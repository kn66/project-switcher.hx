# Helix Project Switcher

Recent project switcher for Helix Steel/Scheme.

The plugin records project roots automatically when documents are opened and
when the current working directory is changed. It keeps the most recent 100
projects by default.

## Requirements

- Helix built with Steel support
- A Steel setup that loads `helix.scm`

## Installation

With `helix-steel-plugin-manager`:

```scheme
(plugin-ensure "kn66/helix-project-switcher")
```

For a manual local install, expose the commands from your Helix `helix.scm`:

```scheme
(require (only-in "path/to/helix-project-switcher/helix.scm"
                  project-switcher
                  project-switcher-config!
                  project-switcher-set-max-projects!
                  project-switcher-init
                  project-switcher-refresh
                  project-switcher-open
                  project-switcher-add-current
                  project-switcher-remove
                  project-switcher-clear-missing))

(provide project-switcher
         project-switcher-config!
         project-switcher-set-max-projects!
         project-switcher-init
         project-switcher-refresh
         project-switcher-open
         project-switcher-add-current
         project-switcher-remove
         project-switcher-clear-missing)
```

The plugin calls `project-switcher-init` when loaded, so automatic recording is
enabled after the module is required.

## Usage

Open the switcher:

```text
:project-switcher
```

Inside the switcher buffer:

| Key | Action |
| --- | --- |
| `ret` | Switch to the selected project |
| `a` | Add the current project |
| `d` | Remove the selected project |
| `D` | Remove missing directories |
| `g` | Refresh |
| `q` | Close the switcher buffer |

## Configuration

Change the number of retained projects from your Steel config:

```scheme
(project-switcher-set-max-projects! 200)
```

Or use the keyword config helper:

```scheme
(project-switcher-config! #:max-projects 200)
```

History is stored under:

```text
<helix-steel-config-dir>/steel/project-switcher/projects.scm
```
