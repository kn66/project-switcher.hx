(require "helix/static.scm")
(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/components.scm")
(require (prefix-in keymaps. "helix/keymaps.scm"))
(require (prefix-in helix. "helix/commands.scm"))
(require-builtin steel/filesystem)

(provide PROJECT-SWITCHER
         PROJECT-SWITCHER-KEYBINDINGS
         *project-switcher-max-projects*
         project-switcher-config!
         project-switcher-set-max-projects!
         project-switcher-history-path
         project-switcher-projects
         project-switcher-init
         project-switcher-install-keybindings
         project-switcher
         project-switcher-refresh
         project-switcher-open
         project-switcher-add-current
         project-switcher-remove
         project-switcher-clear-missing)

(define PROJECT-SWITCHER "helix-project-switcher")

(define PROJECT-SWITCHER-KEYBINDINGS
  (hash "normal"
        (hash "ret" ':project-switcher-open
              "g" ':project-switcher-refresh
              "a" ':project-switcher-add-current
              "d" ':project-switcher-remove
              "D" ':project-switcher-clear-missing
              "q" ':buffer-close!)))

(define *project-switcher-max-projects* 100)
(define *project-switcher-buffer-path* "/tmp/helix-project-switcher")
(define *project-switcher-line-paths* '())
(define *project-switcher-rendered-text* "")
(define *project-switcher-keybindings-installed?* #false)
(define *project-switcher-hooks-installed?* #false)

(define (path-join . parts)
  (cond
    [(null? parts) ""]
    [(null? (cdr parts)) (car parts)]
    [else
     (let ([left (trim-end-matches (car parts) "/")]
           [right (trim-start-matches (apply path-join (cdr parts)) "/")])
       (cond
         [(equal? left "") right]
         [(equal? left "/") (string-append "/" right)]
         [else (string-append left "/" right)]))]))

(define (config-root)
  (parent-name (get-init-scm-path)))

(define (project-switcher-root)
  (path-join (config-root) "steel" "project-switcher"))

;;@doc
;; File where project history is stored.
(define (project-switcher-history-path)
  (path-join (project-switcher-root) "projects.scm"))

(define (ensure-project-switcher-root!)
  (unless (path-exists? (project-switcher-root))
    (create-directory! (project-switcher-root))))

(define (write-lines path lines)
  (let ([port (open-output-file path #:exists 'truncate)])
    (display (string-join lines "\n") port)
    (display "\n" port)
    (close-port port)))

(define (lines->text lines)
  (string-append (string-join lines "\n") "\n"))

(define (save-projects! projects)
  (ensure-project-switcher-root!)
  (let ([port (open-output-file (project-switcher-history-path) #:exists 'truncate)])
    (write (take-projects projects *project-switcher-max-projects*) port)
    (display "\n" port)
    (close-port port)))

(define (sanitize-projects projects)
  (cond
    [(null? projects) '()]
    [(string? (car projects)) (cons (car projects) (sanitize-projects (cdr projects)))]
    [else (sanitize-projects (cdr projects))]))

;;@doc
;; Return the recorded project roots, most recent first.
(define (project-switcher-projects)
  (let ([path (project-switcher-history-path)])
    (with-handler
      (lambda (_) '())
      (if (path-exists? path)
          (let* ([port (open-input-file path)]
                 [projects (read port)])
            (close-port port)
            (if (list? projects)
                (sanitize-projects projects)
                '()))
          '()))))

(define (take-projects projects count)
  (cond
    [(or (<= count 0) (null? projects)) '()]
    [else (cons (car projects) (take-projects (cdr projects) (- count 1)))]))

(define (path-member? path paths)
  (cond
    [(null? paths) #false]
    [(equal? path (car paths)) #true]
    [else (path-member? path (cdr paths))]))

(define (remove-path path paths)
  (cond
    [(null? paths) '()]
    [(equal? path (car paths)) (remove-path path (cdr paths))]
    [else (cons (car paths) (remove-path path (cdr paths)))]))

(define (upsert-project path projects)
  (take-projects
    (cons path (remove-path path projects))
    *project-switcher-max-projects*))

(define (record-project! path)
  (when (and path (path-exists? path) (is-dir? path))
    (save-projects! (upsert-project path (project-switcher-projects)))))

(define (marker-path? dir marker)
  (path-exists? (path-join dir marker)))

(define (project-marker? dir)
  (or (marker-path? dir ".git")
      (marker-path? dir ".jj")
      (marker-path? dir ".svn")
      (marker-path? dir ".helix")))

(define (find-project-root dir)
  (let loop ([current dir])
    (cond
      [(project-marker? current) current]
      [else
       (let ([parent (parent-name current)])
         (if (or (not parent) (equal? parent current))
             dir
             (loop parent)))])))

(define (path->project-root path)
  (let ([dir (if (and (path-exists? path) (is-dir? path))
                 path
                 (parent-name path))])
    (and dir (find-project-root dir))))

(define (project-switcher-buffer-path? path)
  (equal? path *project-switcher-buffer-path*))

(define (current-project-switcher-buffer?)
  (let ([file (current-file-path)])
    (and file (project-switcher-buffer-path? file))))

(define (current-file-path)
  (with-handler
    (lambda (_) #false)
    (cx->current-file)))

(define (current-project-root)
  (let ([file (current-file-path)])
    (cond
      [(and file (not (project-switcher-buffer-path? file))) (path->project-root file)]
      [else (find-project-root (get-helix-cwd))])))

(define (record-current-project!)
  (let ([root (current-project-root)])
    (when root (record-project! root))
    root))

(define (record-cwd-project!)
  (let ([root (find-project-root (get-helix-cwd))])
    (when root (record-project! root))
    root))

(define (record-document-project! doc-id)
  (with-handler
    (lambda (_) #false)
    (let ([path (editor-document->path doc-id)])
      (when (and path (not (project-switcher-buffer-path? path)))
        (record-project! (path->project-root path))))))

(define (record-cwd-command? command-name)
  (or (equal? command-name "change-current-directory")
      (equal? command-name "cd")
      (equal? command-name "push-directory")
      (equal? command-name "pushd")
      (equal? command-name "pop-directory")
      (equal? command-name "popd")))

;;@doc
;; Configure project switcher. Example: (project-switcher-config! #:max-projects 200)
(define (project-switcher-config! #:max-projects [max-projects #false])
  (when max-projects
    (project-switcher-set-max-projects! max-projects))
  (project-switcher-init))

;;@doc
;; Set the maximum number of project roots retained in history.
(define (project-switcher-set-max-projects! count)
  (let ([value (if (string? count) (string->number count) count)])
    (unless (and value (number? value) (> value 0))
      (error "project-switcher max projects must be a positive number"))
    (set! *project-switcher-max-projects* value)
    (save-projects! (project-switcher-projects))
    (set-status!
      (string-append "project-switcher max projects: " (to-string value)))))

;;@doc
;; Install project-switcher keybindings for the generated project list buffer.
(define (project-switcher-install-keybindings)
  (unless *project-switcher-keybindings-installed?*
    (let ([base (keymaps.deep-copy-global-keybindings)])
      (keymaps.merge-keybindings base PROJECT-SWITCHER-KEYBINDINGS)
      (keymaps.set-global-buffer-or-extension-keymap (hash PROJECT-SWITCHER base))
      (set! *project-switcher-keybindings-installed?* #true)
      "installed helix-project-switcher keybindings")))

;;@doc
;; Install hooks that automatically record opened projects.
(define (project-switcher-init)
  (unless *project-switcher-hooks-installed?*
    (register-hook 'document-opened
                   (lambda (doc-id)
                     (record-document-project! doc-id)))
    (register-hook 'post-command
                   (lambda (command-name)
                     (when (record-cwd-command? command-name)
                       (record-cwd-project!))))
    (set! *project-switcher-hooks-installed?* #true))
  (project-switcher-install-keybindings)
  (record-cwd-project!)
  "helix-project-switcher initialized")

(define (project-line path)
  (let ([prefix (if (and (path-exists? path) (is-dir? path)) "  " "! ")])
    (string-append prefix path)))

(define (render-lines projects)
  (append
    (list "helix-project-switcher"
          "RET switch  a add current  d remove  D prune missing  g refresh  q close"
          "")
    (if (null? projects)
        (list "No projects recorded yet.")
        (map project-line projects))))

(define (line-map projects)
  (append (list #false #false #false)
          (if (null? projects) (list #false) projects)))

(define (render-project-switcher!)
  (let* ([projects (project-switcher-projects)]
         [lines (render-lines projects)])
    (set! *project-switcher-line-paths* (line-map projects))
    (set! *project-switcher-rendered-text* (lines->text lines))
    (write-lines *project-switcher-buffer-path* lines)))

(define (current-doc-id)
  (editor->doc-id (editor-focus)))

(define (map-current-project-switcher-buffer!)
  (with-handler
    (lambda (_) #false)
    (let ([doc-id (current-doc-id)])
      (set-scratch-buffer-name! PROJECT-SWITCHER)
      (keymaps.*reverse-buffer-map-insert* (doc-id->usize doc-id) PROJECT-SWITCHER))))

(define (open-project-switcher-buffer!)
  (helix.open *project-switcher-buffer-path*)
  (map-current-project-switcher-buffer!))

(define (reload-project-switcher-buffer!)
  (with-handler
    (lambda (_) (open-project-switcher-buffer!))
    (editor-document-reload (current-doc-id))
    (map-current-project-switcher-buffer!)))

(define (replace-current-project-switcher-buffer!)
  (with-handler
    (lambda (_) (reload-project-switcher-buffer!))
    (let ([line (+ (get-current-line-number) 1)])
      (select_all)
      (replace-selection-with *project-switcher-rendered-text*)
      (helix.goto-line line)
      (normal_mode)
      (map-current-project-switcher-buffer!))))

(define PROJECT-SWITCHER-MODAL-MAX-WIDTH 80)
(define PROJECT-SWITCHER-MODAL-MAX-ROWS 12)

;; Modal state slots: projects, selected index, scroll offset, visible rows.
(define (project-switcher-modal-state projects)
  (vector projects 0 0 1))

(define (modal-projects state) (vector-ref state 0))
(define (modal-selected state) (vector-ref state 1))
(define (modal-offset state) (vector-ref state 2))
(define (modal-visible-rows state) (vector-ref state 3))

(define (modal-set-projects! state projects) (vector-set! state 0 projects))
(define (modal-set-selected! state selected) (vector-set! state 1 selected))
(define (modal-set-offset! state offset) (vector-set! state 2 offset))
(define (modal-set-visible-rows! state rows) (vector-set! state 3 rows))

(define (modal-project-count state)
  (length (modal-projects state)))

(define (modal-selected-path state)
  (let ([projects (modal-projects state)]
        [selected (modal-selected state)])
    (if (and (not (null? projects))
             (>= selected 0)
             (< selected (length projects)))
        (list-ref projects selected)
        #false)))

(define (modal-clamp-selection! state selected)
  (let ([count (modal-project-count state)])
    (modal-set-selected!
      state
      (if (= count 0)
          0
          (max 0 (min selected (- count 1)))))))

(define (modal-ensure-selection-visible! state)
  (let ([selected (modal-selected state)]
        [offset (modal-offset state)]
        [rows (max 1 (modal-visible-rows state))])
    (cond
      [(< selected offset) (modal-set-offset! state selected)]
      [(>= selected (+ offset rows))
       (modal-set-offset! state (+ 1 (- selected rows)))])))

(define (modal-move-selection! state amount)
  (modal-clamp-selection! state (+ (modal-selected state) amount))
  (modal-ensure-selection-visible! state))

(define (modal-lines state start count)
  (let ([projects (modal-projects state)]
        [selected (modal-selected state)])
    (let loop ([index start] [remaining count])
      (if (or (<= remaining 0) (>= index (length projects)))
          '()
          (let* ([path (list-ref projects index)]
                 [missing? (not (and (path-exists? path) (is-dir? path)))]
                 [prefix (if (= index selected) "> " "  ")]
                 [marker (if missing? "! " "")])
            (cons (string-append prefix marker path)
                  (loop (+ index 1) (- remaining 1))))))))

(define (project-switcher-modal-render state viewport frame)
  (let* ([viewport-width (area-width viewport)]
         [viewport-height (area-height viewport)]
         [width (max 4 (min PROJECT-SWITCHER-MODAL-MAX-WIDTH
                            (- viewport-width 2)))]
         [desired-rows (max 1 (min PROJECT-SWITCHER-MODAL-MAX-ROWS
                                   (modal-project-count state)))]
         [height (max 5 (min (+ desired-rows 4) (- viewport-height 2)))]
         [x (+ (area-x viewport) (quotient (- viewport-width width) 2))]
         [y (+ (area-y viewport) (quotient (- viewport-height height) 2))]
         [modal-area (area x y width height)]
         [rows (max 1 (- height 4))]
         [list-area (area (+ x 1) (+ y 2) (- width 2) rows)]
         [footer-row (+ y (- height 2))])
    (modal-set-visible-rows! state rows)
    (modal-ensure-selection-visible! state)
    (buffer/clear frame modal-area)
    (block/render frame modal-area (block))
    (frame-set-string! frame (+ x 2) (+ y 1) "Projects" (style))
    (widget/list/render
      frame
      list-area
      (widget/list
        (if (= (modal-project-count state) 0)
            (list "  No projects recorded yet.")
            (modal-lines state (modal-offset state) rows))))
    (frame-set-string!
      frame
      (+ x 2)
      footer-row
      "Up/Down select  Enter switch  Esc close"
      (style))))

(define (modal-switch-project! state)
  (let ([path (modal-selected-path state)])
    (cond
      [(not path)
       (set-error! "no project selected")
       #false]
      [(not (path-exists? path))
       (set-error! (string-append "project does not exist: " path))
       #false]
      [(not (is-dir? path))
       (set-error! (string-append "project is not a directory: " path))
       #false]
      [else
       (record-project! path)
       (helix.change-current-directory path)
       (set-status! (string-append "project switched to " path))
       #true])))

(define (modal-remove-project! state)
  (let ([path (modal-selected-path state)])
    (when path
      (let ([projects (remove-path path (modal-projects state))])
        (save-projects! projects)
        (modal-set-projects! state projects)
        (modal-clamp-selection! state (modal-selected state))
        (modal-ensure-selection-visible! state)
        (set-status! (string-append "project removed " path))))))

(define (project-switcher-modal-handle-event state event)
  (cond
    [(key-event-escape? event) event-result/close]
    [(key-event-up? event)
     (modal-move-selection! state -1)
     event-result/consume]
    [(key-event-down? event)
     (modal-move-selection! state 1)
     event-result/consume]
    [(key-event-page-up? event)
     (modal-move-selection! state (- (modal-visible-rows state)))
     event-result/consume]
    [(key-event-page-down? event)
     (modal-move-selection! state (modal-visible-rows state))
     event-result/consume]
    [(key-event-home? event)
     (modal-clamp-selection! state 0)
     (modal-ensure-selection-visible! state)
     event-result/consume]
    [(key-event-end? event)
     (modal-clamp-selection! state (- (modal-project-count state) 1))
     (modal-ensure-selection-visible! state)
     event-result/consume]
    [(key-event-delete? event)
     (modal-remove-project! state)
     event-result/consume]
    [(key-event-enter? event)
     (if (modal-switch-project! state)
         event-result/close
         event-result/consume)]
    [else event-result/consume-without-rerender]))

(define (open-project-switcher-modal!)
  (let ([state (project-switcher-modal-state (project-switcher-projects))])
    (push-component!
      (new-component!
        PROJECT-SWITCHER
        state
        project-switcher-modal-render
        (hash "handle_event" project-switcher-modal-handle-event)))))

;;@doc
;; Open the recent project switcher in a modal window.
(define (project-switcher)
  (open-project-switcher-modal!)
  (set-status! "project-switcher"))

;;@doc
;; Refresh the project switcher buffer from history.
(define (project-switcher-refresh)
  (render-project-switcher!)
  (when (current-project-switcher-buffer?)
    (replace-current-project-switcher-buffer!))
  (set-status! "project-switcher refreshed"))

(define (path-at-line line)
  (if (and (>= line 0) (< line (length *project-switcher-line-paths*)))
      (list-ref *project-switcher-line-paths* line)
      #false))

(define (current-project-switcher-path)
  (when (null? *project-switcher-line-paths*)
    (render-project-switcher!))
  (let* ([line (get-current-line-number)]
         [exact (path-at-line line)])
    (cond
      [exact exact]
      [(path-at-line (- line 1)) (path-at-line (- line 1))]
      [(path-at-line (+ line 1)) (path-at-line (+ line 1))]
      [else #false])))

;;@doc
;; Switch to the project at the current line.
(define (project-switcher-open)
  (let ([path (current-project-switcher-path)])
    (cond
      [(not path) (set-error! "no project on this line")]
      [(not (path-exists? path)) (set-error! (string-append "project does not exist: " path))]
      [(not (is-dir? path)) (set-error! (string-append "project is not a directory: " path))]
      [else
       (record-project! path)
       (helix.change-current-directory path)
       (project-switcher-refresh)
       (set-status! (string-append "project switched to " path))])))

;;@doc
;; Add the current workspace root to project history.
(define (project-switcher-add-current)
  (let ([root (record-current-project!)])
    (if root
        (begin
          (project-switcher-refresh)
          (set-status! (string-append "project added " root)))
        (set-error! "could not determine current project"))))

;;@doc
;; Remove the project at the current line from history.
(define (project-switcher-remove)
  (let ([path (current-project-switcher-path)])
    (if path
        (begin
          (save-projects! (remove-path path (project-switcher-projects)))
          (project-switcher-refresh)
          (set-status! (string-append "project removed " path)))
        (set-error! "no project on this line"))))

;;@doc
;; Remove history entries whose directories no longer exist.
(define (project-switcher-clear-missing)
  (let* ([projects (project-switcher-projects)]
         [kept (filter (lambda (path) (and (path-exists? path) (is-dir? path))) projects)]
         [removed (- (length projects) (length kept))])
    (save-projects! kept)
    (project-switcher-refresh)
    (set-status!
      (string-append "project-switcher pruned "
                     (to-string removed)
                     " missing project(s)"))))

(project-switcher-init)
