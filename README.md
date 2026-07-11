# Helix Project Switcher

Recent project switcher for Helix Steel/Scheme.

The plugin records project roots automatically when documents are opened and
when the current working directory is changed. It keeps the most recent 100
projects by default.

## Requirements

- Helix built with Steel support
- Steel's `forge` package manager
- A Steel setup that loads `helix.scm`

## Installation

Install the plugin with Forge:

```sh
forge pkg install --git https://github.com/kn66/helix-project-switcher.git
```

Forge installs the package under Steel's `cogs` directory. Expose the commands
from your Helix `helix.scm`:

```scheme
(require (only-in "helix-project-switcher/helix.scm"
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

To update the plugin, reinstall it with `--force`:

```sh
forge pkg install --git https://github.com/kn66/helix-project-switcher.git --force
```

For local development, run `forge install /path/to/helix-project-switcher
--force` or require the checkout's `helix.scm` directly.

The plugin calls `project-switcher-init` when loaded, so automatic recording is
enabled after the module is required.

## Usage

Open the switcher:

```text
:project-switcher
```

The project list opens in a modal window over the current editor view:

| Key | Action |
| --- | --- |
| `up` / `down` | Move the selection |
| `pageup` / `pagedown` | Move by one page |
| `home` / `end` | Select the first or last project |
| `ret` | Switch to the selected project |
| `delete` | Remove the selected project from history |
| `esc` | Close the modal |

Missing project directories are marked with `!` and remain in the list until
`project-switcher-clear-missing` is run.

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
