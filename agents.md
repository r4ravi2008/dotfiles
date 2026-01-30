# Dotfiles Agent Instructions

This repository contains dotfiles for LazyVim (Neovim), zsh, and tmux configurations.

## Repository Structure

```
.dotfiles/
├── nvim/           # LazyVim/Neovim configuration
│   ├── init.lua    # Main entry point
│   └── lua/
│       ├── config/ # Core config (options, keymaps, autocmds, lazy)
│       └── plugins/# Plugin configurations
├── zsh/
│   ├── zshrc       # Main zsh configuration (ultra-fast, no oh-my-zsh overhead)
│   └── zshenv      # Environment variables loaded before zshrc
├── tmux/
│   └── tmux.conf.local  # Local tmux customizations (gpakosz/.tmux framework)
├── bootstrap.sh    # Installation script
└── agents.md       # This file
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

## Bootstrap Process

The `bootstrap.sh` script:
1. Creates symlinks from home directory to dotfiles
2. Installs gpakosz/.tmux if not present
3. Installs oh-my-zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting)
4. Backs up existing configs before overwriting

## Development Guidelines

When modifying these dotfiles:
1. Edit files in `~/.dotfiles/`, not the symlinked locations
2. Test changes before committing
3. Keep zshrc startup time under 200ms
4. Document significant plugin additions
5. Use lazy-loading for heavy tools

## Dependencies

- Neovim >= 0.9.0
- Git
- fzf, fd, ripgrep (optional but recommended)
- fnm (Fast Node Manager)
- zoxide (optional)
