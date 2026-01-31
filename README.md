# Dotfiles

Personal dotfiles for:

- Neovim (LazyVim): `nvim/` -> `~/.config/nvim`
- Zsh: `zsh/zshrc`, `zsh/zshenv` -> `~/.zshrc`, `~/.zshenv`
- Tmux (gpakosz/.tmux framework): `tmux/tmux.conf.local` -> `~/.tmux/.tmux.conf.local`
- OpenCode config + plugins: `opencode/` -> `~/.config/opencode/*`
- Shared AI agent rules (rulesync): `ai-agents/` (generates `AGENTS.md`, MCP configs, etc.)

This repo is meant to be cloned to `~/.dotfiles` and installed via the bootstrap script.

## Quick Start

```bash
git clone <your-fork-or-repo-url> ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh
```

After bootstrap:

- Restart your shell (or `source ~/.zshrc`)
- Open `nvim` once to let LazyVim install plugins
- Start a new `tmux` session
- Generate AI agent outputs (see below)

## What bootstrap.sh does

`bootstrap.sh` is the entry point for setting up this repo on a new machine.

- Creates symlinks from your home directory into `~/.dotfiles/`
- Backs up any existing files it would replace to `~/.dotfiles_backup/<timestamp>/`
- Installs `gpakosz/.tmux` to `~/.tmux` (if missing) and links `~/.tmux.conf`
- Installs zsh plugin repos (autosuggestions + syntax-highlighting) into the oh-my-zsh custom plugin dir
- Sets up OpenCode config and plugin directories under `~/.config/opencode/`
- Links rulesync-generated AI agent outputs when present (OpenCode MCP config + `~/AGENTS.md`)

If you change the repo layout or add new dotfiles, update `bootstrap.sh` so installs stay consistent.

## AI agent rules (rulesync)

Rulesync is the source of truth for shared AI agent rules/commands/subagents and MCP server config.

- Edit source files under `ai-agents/.rulesync/`
- Regenerate tool-specific outputs:

```bash
cd ~/.dotfiles/ai-agents
npx rulesync generate
```

Notes:

- Do not hand-edit generated files like `ai-agents/AGENTS.md` or `ai-agents/opencode.json`.
- `bootstrap.sh` will symlink `ai-agents/opencode.json` to `~/.config/opencode/opencode.json` when it exists.

## Repo layout

- `nvim/`: LazyVim config (entry: `nvim/init.lua`)
- `zsh/`: zsh runtime config
- `tmux/`: tmux local overrides for the gpakosz framework
- `opencode/`: OpenCode app config, custom plugins, and slash commands
- `ai-agents/`: rulesync inputs + generated outputs for AI coding tools
- `cursor/`: Cursor-specific config (e.g. MCP)

## Making changes

- Edit files in `~/.dotfiles/` (not the symlinked locations in `~/` or `~/.config/*`).
- Re-run `./bootstrap.sh` after structural changes (new symlinks, new tool configs, etc.).
- For AI agent changes, run `npx rulesync generate` after editing `ai-agents/.rulesync/`.

## Prereqs / optional tools

- Required: `git`, `zsh`, `tmux`, `nvim`, `node` (for rulesync and OpenCode plugin deps)
- Recommended: `fzf`, `fd`, `ripgrep`, `zoxide`

## Uninstall / rollback

Bootstrap moves any replaced config into `~/.dotfiles_backup/<timestamp>/`.

- Remove symlinks created by bootstrap
- Restore files from the backup directory
