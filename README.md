# Dotfiles

Personal dotfiles for:

- Neovim (LazyVim): `nvim/` -> `~/.config/nvim`
- Zsh: `zsh/zshrc`, `zsh/zshenv` -> `~/.zshrc`, `~/.zshenv`
- Tmux (gpakosz/.tmux framework): `tmux/tmux.conf.local` -> `~/.tmux/.tmux.conf.local`
- Herdr: `herdr/config.toml` -> `~/.config/herdr/config.toml`
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
- Links Herdr keys (agent picker `prefix+a`, previous/next `alt+shift+[` / `]`, focus `prefix+alt+1..9`, annotate `prefix+shift+a` / `p` / `y`), builds `herdr-nvim-nav` and `herdr-pane-minimap`, and installs `herdr-splits`, `dleen/herdr-agents`, and `plannotator/herdr-annotate` when Herdr is available
- Installs zsh plugin repos (autosuggestions + syntax-highlighting) into the oh-my-zsh custom plugin dir
- Sets up OpenCode config and plugin directories under `~/.config/opencode/`
- Links rulesync-generated AI agent outputs when present (OpenCode MCP config + `~/AGENTS.md`)

If you change the repo layout or add new dotfiles, update `bootstrap.sh` so installs stay consistent.

## Cloud Workspaces

CWS does **not** clone into `~/.dotfiles`. During workspace create it copies this repo onto `/home/coder` and runs **only** an executable `~/.config/yadm/bootstrap` (see `cws-runner/prebuild/set-up-user.sh`). It will not overwrite CWS-managed `.bashrc`, `.profile`, or `.gitconfig`; put Bash extras in `.bash_aliases`.

Repeatable setup:

1. Push these changes (branch is `main`).
2. In [Cloud Workspace preferences](https://devportal.intuit.com/app/dp/cloudWorkspaces), set Dotfiles to the GitHub URL **with the branch**:
   `https://github.intuit.com/rkommineni/cws-dotfiles/tree/main`
   (a URL with no `/tree/<ref>` falls back to `master`, which this repo does not use).
3. Create a **new** workspace (existing ones are not retrofitted).

That bootstrap relocates the copied tree to `~/.dotfiles`, links configs, installs CLI tools including Herdr, and starts `herdr server` in `/workspace`.

### Herdr attach (from the laptop)

SSH host aliases are written on the **laptop** by the CWS CLI, not inside the workspace. For the workspace used in the earlier thread that was `coder@cws.devstack-a0758f6a`.

```bash
cws login
cws config-ssh
ssh coder@cws.<workspace-name>          # confirm SSH first
herdr --remote cws.<workspace-name>
```

If `Host cws.<name>` already sets `User coder`, `herdr --remote cws.<name>` is enough. The zsh `herdr` wrapper opens the same SSH mux (and `LocalForward`s) as `ssh` before attaching. Detach with `ctrl+b q`.

CWS profile skips Ghostty, skhd, Podman, AWS CLI, and Rust (the image already has Docker and awscli). Interactive Bash `exec`s zsh via `.bash_aliases` unless `CWS_KEEP_BASH=1`.

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
- `herdr/`: tmux-aligned Herdr keys and the Neovim bridge action bindings
- `opencode/`: OpenCode app config, custom plugins, and slash commands
- `ai-agents/`: rulesync inputs + generated outputs for AI coding tools
- `cursor/`: Cursor remote settings (MCP OAuth + Plannotator auto-forward)
- `ssh/cws-mcp-forwards.conf`: LocalForward 8787 (Atlassian), 3118 (Slack), and 19432 (Plannotator) on every `cws.*` host

## Making changes

- Edit files in `~/.dotfiles/` (not the symlinked locations in `~/` or `~/.config/*`).
- Re-run `./bootstrap.sh` after structural changes (new symlinks, new tool configs, etc.).
- For AI agent changes, run `npx rulesync generate` after editing `ai-agents/.rulesync/`.

## Prereqs / optional tools

- Required: `git`, `zsh`, `tmux`, `nvim`, `node` (for rulesync and OpenCode plugin deps)
- Recommended: `fzf`, `fd`, `ripgrep`, `zoxide`
- Optional: `herdr` 0.8.0+ for agent workspaces and Neovim pane navigation
- Optional: `hunk` (diff review TUI) and `plannotator` (web plan review, extras, sharing disabled). 19432 is the CWS SSH tunnel, not a public share.
- Bootstrap installs Bun so `plannotator/herdr-annotate` can fetch plannotator-tui. `plannotator annotate` still opens a browser.
- Bootstrap also installs [Matt Pocock's skills](https://github.com/mattpocock/skills) (engineering + productivity) into `~/.agents/skills`

## Uninstall / rollback

Bootstrap moves any replaced config into `~/.dotfiles_backup/<timestamp>/`.

- Remove symlinks created by bootstrap
- Restore files from the backup directory
