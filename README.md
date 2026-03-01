# claude-launcher

A small zsh function that presents a numbered menu of your `~/projects` subdirectories and launches [Claude Code](https://claude.ai/code) in the selected one.

## Usage

Run `lc` in any shell to open the menu:

```
   0)  terminal
   1)  projects (root)
   2)  my-app
   3)  dotfiles
   4)  scripts

  Pick a project [0-4]:
```

Press a single key to select:

| Choice | Action |
|--------|--------|
| `0` | `cd` to `~/projects` (no Claude) |
| `1` | `cd` to `~/projects` and launch Claude |
| `2`+ | `cd` to that subdirectory and launch Claude |

## Installation

1. Clone the repo:
   ```sh
   git clone git@github.com:ericfaris/claude-launcher.git ~/projects/claude-launcher
   ```

2. Source the script in your `~/.zshrc`:
   ```sh
   source ~/projects/claude-launcher/claude-launcher.sh
   ```

3. Optionally auto-launch when opening a shell in `~/projects`:
   ```sh
   [[ "$(pwd)" == "$HOME/projects" ]] && lc
   ```

## Requirements

- zsh
- [Claude Code](https://claude.ai/code) (`claude` on your PATH)
