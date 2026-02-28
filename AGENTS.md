# Dotfiles Agent Instructions

This repository contains dotfiles for LazyVim (Neovim), zsh, tmux, and AI agent configurations.

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
│   │   └── mcp.json    # MCP server configurations
│   ├── rulesync.jsonc  # Rulesync configuration
│   └── AGENTS.md       # Generated output (symlinked to ~/)
├── cursor/             # Cursor-specific configuration
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

### AI Agents (OpenCode, Cursor, Windsurf, etc.)
- Unified rules via rulesync → generates AGENTS.md
- Supported tools: OpenCode, Cursor, Windsurf, Codex CLI
- OpenCode MCP config: generated at `ai-agents/opencode.json` (symlinked to `~/.config/opencode/opencode.json`)
- Windsurf: generates `.codeiumignore` (project-level ignore file) and uses AGENTS.md for rules
- Shared commands and subagents across all AI coding tools
- Symlinked to `~/AGENTS.md` for global use

#### Rulesync (Source of Truth)

For AI agents, treat rulesync as the source of truth for rules, commands, subagents/agents, MCP servers, and any tool-specific manifests (including hooks/config where applicable).

- Make changes in `ai-agents/.rulesync/` (for example `ai-agents/.rulesync/mcp.json` for MCP servers)
- Do not hand-edit generated outputs (for example `ai-agents/opencode.json`, `ai-agents/AGENTS.md`, or tool-specific config files created from generation)
- Legacy note: older setups used `opencode/config.json` / `~/.config/opencode/config.json`; MCP is now managed via rulesync and generated into `ai-agents/opencode.json`
- Regenerate manifests after edits: `cd ~/.dotfiles/ai-agents && npx rulesync generate`
- Mental model: edit rulesync inputs → sync/generate → rulesync writes the per-tool config files for each managed tool

## Bootstrap Process

The `bootstrap.sh` script:
1. Creates symlinks from home directory to dotfiles
2. Installs gpakosz/.tmux if not present
3. Installs oh-my-zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting)
4. Sets up AI agent configurations (OpenCode, AGENTS.md)
5. Backs up existing configs before overwriting

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
- Node.js (for rulesync and OpenCode plugins)
