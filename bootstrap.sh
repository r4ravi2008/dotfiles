#!/usr/bin/env bash
# =============================================================================
# Dotfiles Bootstrap Script
# Creates symlinks and installs dependencies for dotfiles
# =============================================================================

set -e

DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Backup existing file/directory
# -----------------------------------------------------------------------------
backup_if_exists() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        mv "$target" "$BACKUP_DIR/"
        log_warn "Backed up existing $(basename "$target") to $BACKUP_DIR/"
    fi
}

# -----------------------------------------------------------------------------
# Create symlink
# -----------------------------------------------------------------------------
create_symlink() {
    local source="$1"
    local target="$2"
    
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log_info "Symlink already exists: $target -> $source"
        return
    fi
    
    backup_if_exists "$target"
    ln -s "$source" "$target"
    log_success "Created symlink: $target -> $source"
}

# -----------------------------------------------------------------------------
# Install gpakosz/.tmux
# -----------------------------------------------------------------------------
install_tmux_framework() {
    if [[ -d "$HOME/.tmux" ]]; then
        log_info "gpakosz/.tmux already installed"
    else
        log_info "Installing gpakosz/.tmux..."
        git clone https://github.com/gpakosz/.tmux.git "$HOME/.tmux"
        log_success "Installed gpakosz/.tmux"
    fi
    
    # Create symlink for .tmux.conf
    create_symlink "$HOME/.tmux/.tmux.conf" "$HOME/.tmux.conf"
}

# -----------------------------------------------------------------------------
# Install oh-my-zsh plugins
# -----------------------------------------------------------------------------
install_zsh_plugins() {
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    
    # Ensure oh-my-zsh is installed (for plugin directory structure)
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Installing oh-my-zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Installed oh-my-zsh"
    fi
    
    mkdir -p "$ZSH_CUSTOM/plugins"
    
    # zsh-autosuggestions
    if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
        log_info "Installing zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        log_success "Installed zsh-autosuggestions"
    else
        log_info "zsh-autosuggestions already installed"
    fi
    
    # zsh-syntax-highlighting
    if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
        log_info "Installing zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        log_success "Installed zsh-syntax-highlighting"
    else
        log_info "zsh-syntax-highlighting already installed"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "========================================"
    echo "       Dotfiles Bootstrap Script        "
    echo "========================================"
    echo ""
    
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found at $DOTFILES_DIR"
        exit 1
    fi
    
    # Neovim config
    log_info "Setting up Neovim configuration..."
    mkdir -p "$HOME/.config"
    create_symlink "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
    
    # Zsh config
    log_info "Setting up Zsh configuration..."
    create_symlink "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
    create_symlink "$DOTFILES_DIR/zsh/zshenv" "$HOME/.zshenv"
    
    # Tmux config
    log_info "Setting up Tmux configuration..."
    install_tmux_framework
    create_symlink "$DOTFILES_DIR/tmux/tmux.conf.local" "$HOME/.tmux/.tmux.conf.local"
    
    # Install zsh plugins
    log_info "Setting up Zsh plugins..."
    install_zsh_plugins
    
    echo ""
    echo "========================================"
    log_success "Bootstrap complete!"
    echo "========================================"
    echo ""
    log_info "Next steps:"
    echo "  1. Restart your shell or run: source ~/.zshrc"
    echo "  2. Open nvim to let Lazy install plugins"
    echo "  3. Start a new tmux session"
    echo ""
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log_warn "Backups saved to: $BACKUP_DIR"
    fi
}

main "$@"
