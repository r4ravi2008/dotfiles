# Dotfiles Agent Instructions

This repository contains dotfiles for LazyVim (Neovim), zsh, tmux, Ghostty, lazygit, and AI agent configurations.

## Repository Structure

```
.dotfiles/
├── nvim/               # LazyVim/Neovim configuration
│   ├── init.lua        # Main entry point
│   └── lua/
│       ├── config/     # Core config (options, keymaps, autocmds, lazy)
│       └── plugins/    # Plugin configurations
├── zsh/
│   ├── zshrc           # Main zsh configuration (ultra-fast, no oh-my-zsh overhead)
│   └── zshenv          # Environment variables loaded before zshrc
├── tmux/
│   └── tmux.conf.local # Local tmux customizations (gpakosz/.tmux framework)
├── ghostty/
│   └── config          # Ghostty terminal configuration
├── lazygit/
│   └── config.yml      # Lazygit configuration
├── opencode/           # OpenCode application configuration
│   ├── ocx.jsonc       # OCX registry settings
│   ├── package.json    # Plugin dependencies
│   ├── command/        # Slash commands (*.md)
│   └── plugins/        # Custom plugins
├── ai-agents/          # Rulesync-managed AI agent rules
│   ├── .rulesync/      # Source files (edit here)
│   │   ├── rules/      # Rules → generates AGENTS.md
│   │   ├── commands/   # Slash commands
│   │   ├── subagents/  # Subagents
│   │   ├── skills/     # Personal skills (symlinked into ~/.agents/skills)
│   │   └── mcp.json    # MCP server configurations
│   ├── rulesync.jsonc  # Rulesync configuration
│   └── ...             # Generated per-tool outputs (.cursor/, .claude/, etc.)
├── cursor/             # Cursor remote settings (MCP OAuth port forwards)
├── ssh/                # Laptop SSH includes (CWS MCP OAuth LocalForwards)
├── bootstrap.sh        # Installation script
└── AGENTS.md           # This file
```

## Key Features

### Neovim (LazyVim)
- LazyVim base configuration
- Plugins: oil.nvim, obsidian, copilot-chat, tmux-navigator, octo, snacks, opencode
- Custom keymaps and autocmds
- Neovide and VSCode compatibility

### Zsh
- Ultra-fast startup (<200ms target)
- Vi-mode with cursor shape changes
- Lazy-loaded tools: kubectl, pyenv, cargo/rust, bun
- FZF integration with fd
- Zoxide for smart directory navigation
- Custom functions: mkcd, cdl, f, r, ask (opencode)
- No oh-my-zsh runtime (direct plugin sourcing)

### Tmux
- Based on gpakosz/.tmux framework
- Custom local configuration

### Ghostty
- Ghostty terminal emulator configuration
- TokyoNight theme with custom background
- Symlinked to `~/.config/ghostty/config`

### Lazygit
- Custom GUI settings (side panel width, expanded focus)
- Tmux-compatible keybindings (Ctrl+l/j/k disabled to pass through to tmux)
- Config symlinked to `~/Library/Application Support/lazygit/config.yml`

### AI Agents (OpenCode, Cursor, Claude Code, Windsurf, etc.)
- Unified rules via rulesync
- Supported tools: OpenCode, Cursor, Claude Code, Windsurf, Codex CLI, Pi
- OpenCode MCP config: generated at `ai-agents/opencode.json` (symlinked to `~/.config/opencode/opencode.json`)
- Claude Code: commands/agents in `.claude/`, MCP merged into `~/.claude.json` (user-scope) from rulesync `mcp.json`. Skills are not generated into `.claude/skills`; `~/.claude/skills` → `~/.agents/skills`.
- Pi: no built-in MCP; bootstrap installs `pi-mcp-adapter` and links rulesync `mcp.json` to `~/.config/mcp/mcp.json` and `~/.agents/mcp.json`
- Windsurf: generates `.codeiumignore` (project-level ignore file) and uses AGENTS.md for rules
- Personal commands: `/pr`, `/deslop`, `/jira-list`, `/audit-effect-native-impl`
- Personal skills in rulesync: `commit` (Jira-prefixed conventional commits; replacement for the old `git-commit-flow`); `force-pushing-ghes-default` (GH003 on github.intuit.com fork default branches)
- `creating-cws-from-devstack-fork` and `developing-in-cws` sit in `.agents/skills/`, symlinked into `~/.agents/skills`. Not in `.rulesync/skills`.
- Skills live in `~/.agents/skills`. Personal skills (`.rulesync/skills` and `.agents/skills`) are symlinked in; third-party kits come from `npx skills add --global`. `~/.claude/skills` and `~/.cursor/skills` symlink to that dir.
- Hunk (`hunk`) and Plannotator (`plannotator`) are CLI tools from `packages.conf`. Bootstrap also installs Hunk's review skill and Plannotator extras (`compound`, `setup-goal`, `visual-explainer`). Sharing is off (`PLANNOTATOR_SHARE=disabled` and `~/.plannotator/config.json`).
- CWS sets `PLANNOTATOR_REMOTE=1` and `PLANNOTATOR_PORT=19432` so the laptop can SSH-tunnel the Plannotator web UI. That is not a public share. `plannotator annotate` still opens a browser. In Herdr, review with `plannotator/herdr-annotate` (`prefix+shift+p` folder, `prefix+shift+y` last reply, `prefix+shift+a` capture). Needs Bun.
- Bootstrap pins `dleen.herdr-agents` (`prefix+a` picker, previous/next `alt+shift+[` / `alt+shift+]`, focus `prefix+alt+1..9`) and builds/links `herdr-pane-minimap` (tmux-style popup while hopping zoomed panes). Tmux `pane-minimap` popup is unchanged.

#### Rulesync (Source of Truth)

For AI agents, treat rulesync as the source of truth for rules, commands, subagents/agents, MCP servers, and any tool-specific manifests (including hooks/config where applicable).

- Make changes in `ai-agents/.rulesync/` (for example `ai-agents/.rulesync/mcp.json` for MCP servers)
- Do not hand-edit generated outputs (for example `ai-agents/opencode.json` or tool-specific config files created from generation)
- Legacy note: older setups used `opencode/config.json` / `~/.config/opencode/config.json`; MCP is now managed via rulesync and generated into `ai-agents/opencode.json`
- Regenerate manifests after edits: `cd ~/.dotfiles/ai-agents && npx rulesync generate`
- Mental model: edit rulesync inputs → sync/generate → rulesync writes the per-tool config files for each managed tool

## Bootstrap Process

The `bootstrap.sh` script:
1. Creates symlinks from home directory to dotfiles
2. Installs gpakosz/.tmux if not present
3. Installs oh-my-zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting)
4. Installs CLI tools (zoxide, fzf, fd, ripgrep, lazygit) via Homebrew or fallback
5. Symlinks Ghostty and lazygit configurations
6. Sets up AI agent configurations (OpenCode, Cursor, Claude Code)
7. `npx skills add --global` for third-party kits, then symlink personal skills and `~/.claude/skills` / `~/.cursor/skills` into `~/.agents/skills`
8. Backs up existing configs before overwriting
9. Laptop: Includes `ssh/cws-mcp-forwards.conf` from `~/.ssh/config` so every `cws.*` host forwards MCP OAuth callbacks (8787 Atlassian, 3118 Slack) and Plannotator (19432). CWS: merges the same ports into Cursor/VS Code machine settings. Do not put these in a project `devcontainer.json`.

## Development Guidelines

When modifying these dotfiles:
1. Edit files in `~/.dotfiles/`, not the symlinked locations
2. Test changes before committing
3. Keep zshrc startup time under 200ms
4. Document significant plugin additions
5. Use lazy-loading for heavy tools

### AI Agent Rules Workflow
1. Edit source files in `~/.dotfiles/ai-agents/.rulesync/`
2. Run `cd ~/.dotfiles/ai-agents && npx rulesync generate`
3. Symlinked `~/AGENTS.md` updates automatically

## Dependencies

- Neovim >= 0.9.0
- Git
- fzf, fd, ripgrep (optional but recommended)
- fnm (Fast Node Manager)
- zoxide (optional)
- lazygit (optional)
- Node.js (for rulesync and OpenCode plugins)
