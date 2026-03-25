#!/usr/bin/env bash
# =============================================================================
# Dotfiles Bootstrap Script
# Creates symlinks and installs dependencies for dotfiles
# =============================================================================

set -e

DOTFILES_DIR="$HOME/.dotfiles"
# Lazy backup dir: only computed/created when actually needed (see backup_if_exists)
BACKUP_DIR=""

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
		if [[ -z "$BACKUP_DIR" ]]; then
			BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"
		fi
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
		# KEEP_ZSHRC=yes prevents the installer from clobbering our symlinked .zshrc
		KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
		log_success "Installed oh-my-zsh"
	else
		log_info "oh-my-zsh already installed"
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
# Install CLI tools (zoxide, fzf, fd, ripgrep, etc.)
# -----------------------------------------------------------------------------
install_cli_tools() {
	local tools=(zoxide fzf fd rg lazygit)
	local brew_names=(zoxide fzf fd ripgrep lazygit)
	local missing=()
	local missing_brew=()

	for i in "${!tools[@]}"; do
		if ! command -v "${tools[$i]}" >/dev/null 2>&1; then
			missing+=("${tools[$i]}")
			missing_brew+=("${brew_names[$i]}")
		else
			log_info "${tools[$i]} already installed"
		fi
	done

	if [[ ${#missing[@]} -eq 0 ]]; then
		log_success "All CLI tools already installed"
		return
	fi

	log_info "Missing CLI tools: ${missing[*]}"

	if command -v brew >/dev/null 2>&1; then
		log_info "Installing missing tools via Homebrew: ${missing_brew[*]}"
		brew install "${missing_brew[@]}"
		log_success "Installed CLI tools via Homebrew"
	else
		# Fallback: install individually via official methods
		for tool in "${missing[@]}"; do
			case "$tool" in
			zoxide)
				log_info "Installing zoxide via curl..."
				curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
				log_success "Installed zoxide"
				;;
			fzf)
				if [[ -d "$HOME/.fzf" ]]; then
					log_info "fzf directory exists, updating..."
					git -C "$HOME/.fzf" pull --ff-only 2>/dev/null || true
				else
					log_info "Installing fzf via git..."
					git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
				fi
				"$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
				log_success "Installed fzf"
				;;
			*)
				log_warn "$tool not installed. Install manually (e.g. via your package manager)."
				;;
			esac
		done
	fi
}

# -----------------------------------------------------------------------------
# Install Rust toolchain
# -----------------------------------------------------------------------------
install_rust() {
	if command -v cargo >/dev/null 2>&1; then
		log_info "Rust (cargo) already installed"
		return
	fi

	if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
		log_info "Rust is installed at ~/.cargo/bin (not in current PATH yet)"
		return
	fi

	if ! command -v curl >/dev/null 2>&1; then
		log_warn "curl not found. Install Rust manually from https://rustup.rs"
		return
	fi

	log_info "Installing Rust via rustup..."
	if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
		if [[ -r "$HOME/.cargo/env" ]]; then
			# shellcheck disable=SC1090
			source "$HOME/.cargo/env"
		fi
		if command -v cargo >/dev/null 2>&1 || [[ -x "$HOME/.cargo/bin/cargo" ]]; then
			log_success "Installed Rust toolchain"
		else
			log_warn "Rust installer completed, but cargo is not available yet in this shell"
		fi
	else
		log_warn "Rust installation failed; continuing bootstrap"
	fi
}

# -----------------------------------------------------------------------------
# Setup tmux pane minimap helper (Rust build + wrapper permissions)
# -----------------------------------------------------------------------------
setup_tmux_pane_minimap() {
	local wrapper="$DOTFILES_DIR/tmux/pane-minimap"
	local manifest="$DOTFILES_DIR/tmux/pane-minimap-rs/Cargo.toml"
	local src="$DOTFILES_DIR/tmux/pane-minimap-rs/src/main.rs"
	local bin="$DOTFILES_DIR/tmux/pane-minimap-rs/target/release/pane-minimap"
	local cargo_cmd="cargo"

	if [[ ! -f "$wrapper" ]]; then
		log_warn "tmux/pane-minimap wrapper not found; skipping pane minimap setup"
		return
	fi

	chmod +x "$wrapper"

	if command -v cargo >/dev/null 2>&1; then
		cargo_cmd="cargo"
	elif [[ -x "$HOME/.cargo/bin/cargo" ]]; then
		cargo_cmd="$HOME/.cargo/bin/cargo"
	else
		log_warn "cargo not found; pane-minimap will use Python fallback"
		return
	fi

	if [[ ! -f "$manifest" || ! -f "$src" ]]; then
		log_warn "pane-minimap Rust sources not found; skipping binary build"
		return
	fi

	if [[ -x "$bin" && "$manifest" -ot "$bin" && "$src" -ot "$bin" ]]; then
		log_info "tmux pane-minimap Rust binary already up-to-date"
		return
	fi

	log_info "Building tmux pane-minimap Rust binary..."
	if "$cargo_cmd" build --release --manifest-path "$manifest" >/dev/null 2>&1; then
		log_success "Built tmux pane-minimap Rust binary"
	else
		log_warn "Failed to build pane-minimap Rust binary; Python fallback will be used"
	fi
}

# -----------------------------------------------------------------------------
# Setup AI Agents (OpenCode, Cursor, etc.)
# -----------------------------------------------------------------------------
setup_ai_agents() {
	log_info "Setting up AI agent configurations..."

	# Ensure config directories exist
	mkdir -p "$HOME/.config/opencode"
	mkdir -p "$HOME/.cursor"

    # Generate rulesync outputs (source of truth lives in ai-agents/.rulesync)
	# This keeps Cursor/OpenCode configs and commands in sync even if they already exist locally.
	if [[ -d "$DOTFILES_DIR/ai-agents/.rulesync" ]]; then
		if command -v npx >/dev/null 2>&1; then
			log_info "Generating rulesync outputs (OpenCode/Cursor/etc.)..."
			if (cd "$DOTFILES_DIR/ai-agents" && npx rulesync generate); then
				log_success "Generated rulesync outputs"
			else
				log_warn "rulesync generate failed; some agent configs may be stale"
			fi
		else
			log_warn "npx not found; install Node.js to run rulesync generate"
		fi
	fi

	# Sync a directory's contents without replacing the directory itself.
	# This avoids breaking Cursor's ability to manage other local files.
	sync_dir_contents() {
		local source_dir="$1"
		local target_dir="$2"
		local label="$3"

		if [[ ! -d "$source_dir" ]]; then
			return
		fi

		mkdir -p "$target_dir"
		if command -v rsync >/dev/null 2>&1; then
			rsync -a "$source_dir/" "$target_dir/"
		else
			cp -R -p "$source_dir/." "$target_dir/"
		fi
		log_success "Synced ${label}"
	}

	if [[ -f "$DOTFILES_DIR/ai-agents/opencode.json" ]]; then
		# Respect existing user config if it's not already managed by this repo.
		if [[ -e "$HOME/.config/opencode/opencode.json" && ! -L "$HOME/.config/opencode/opencode.json" ]]; then
			log_warn "OpenCode config exists at ~/.config/opencode/opencode.json; skipping symlink (to avoid overwriting your local config)."
			log_warn "If you want rulesync-managed MCP in OpenCode, replace it with a symlink to ~/.dotfiles/ai-agents/opencode.json."
		else
			create_symlink "$DOTFILES_DIR/ai-agents/opencode.json" "$HOME/.config/opencode/opencode.json"
		fi
	else
		log_warn "OpenCode MCP config not generated yet. Run 'cd ~/.dotfiles/ai-agents && npx rulesync generate' to create ai-agents/opencode.json."
	fi
	create_symlink "$DOTFILES_DIR/opencode/ocx.jsonc" "$HOME/.config/opencode/ocx.jsonc"
	create_symlink "$DOTFILES_DIR/opencode/package.json" "$HOME/.config/opencode/package.json"
	create_symlink "$DOTFILES_DIR/ai-agents/.rulesync/commands" "$HOME/.config/opencode/command"
	create_symlink "$DOTFILES_DIR/opencode/plugins" "$HOME/.config/opencode/plugins"

	# Global AGENTS.md (generated by rulesync)
	if [[ -f "$DOTFILES_DIR/ai-agents/AGENTS.md" ]]; then
		create_symlink "$DOTFILES_DIR/ai-agents/AGENTS.md" "$HOME/AGENTS.md"
	else
		log_warn "AGENTS.md not found. Run 'cd ~/.dotfiles/ai-agents && npx rulesync generate' first."
	fi

	# Cursor MCP config (rulesync source of truth)
	if [[ -f "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" ]]; then
		create_symlink "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" "$HOME/.cursor/mcp.json"
	elif [[ -f "$DOTFILES_DIR/cursor/mcp.json" ]]; then
		create_symlink "$DOTFILES_DIR/cursor/mcp.json" "$HOME/.cursor/mcp.json"
	fi

	# Cursor commands/agents/rules/skills are generated by rulesync into ai-agents/.cursor.
	# Cursor may already have its own ~/.cursor/{commands,agents,...} directories, so we sync
	# contents instead of symlinking the whole directory.
	if [[ -d "$DOTFILES_DIR/ai-agents/.cursor" ]]; then
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/commands" "$HOME/.cursor/commands" "Cursor commands"
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/agents" "$HOME/.cursor/agents" "Cursor agents"
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/rules" "$HOME/.cursor/rules" "Cursor rules"
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/skills" "$HOME/.cursor/skills" "Cursor skills"
	else
		log_warn "rulesync Cursor outputs not found at ai-agents/.cursor; run 'cd ~/.dotfiles/ai-agents && npx rulesync generate'"
	fi

	# Sync ~/.agents directory (lock file + all skills in one place)
	if [[ -d "$DOTFILES_DIR/agents" ]]; then
		sync_dir_contents "$DOTFILES_DIR/agents" "$HOME/.agents" "agents config (~/.agents)"
	fi

	# Install OpenCode plugin dependencies (skip if node_modules is up-to-date)
	if [[ -f "$DOTFILES_DIR/opencode/package.json" ]]; then
		local oc_dir="$HOME/.config/opencode"
		if [[ ! -d "$oc_dir/node_modules" || "$oc_dir/package.json" -nt "$oc_dir/node_modules" ]]; then
			log_info "Installing OpenCode plugin dependencies..."
			(cd "$oc_dir" && npm install --silent 2>/dev/null) || log_warn "npm install failed, continuing..."
		else
			log_info "OpenCode plugin dependencies already up-to-date"
		fi
	fi

	log_success "AI agent configurations set up"
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
	create_symlink "$DOTFILES_DIR/tmux/tmux.conf.local" "$HOME/.tmux.conf.local"

	# Ghostty config
	log_info "Setting up Ghostty configuration..."
	mkdir -p "$HOME/.config/ghostty"
	create_symlink "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"

	# Lazygit config
	log_info "Setting up Lazygit configuration..."
	mkdir -p "$HOME/Library/Application Support/lazygit"
	create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$HOME/Library/Application Support/lazygit/config.yml"

	# Install zsh plugins
	log_info "Setting up Zsh plugins..."
	install_zsh_plugins

	# Install CLI tools (zoxide, fzf, fd, ripgrep)
	log_info "Installing CLI tools..."
	install_cli_tools

	# Install Rust toolchain
	log_info "Installing Rust toolchain..."
	install_rust

	# Build tmux pane minimap helper
	log_info "Setting up tmux pane minimap..."
	setup_tmux_pane_minimap

	# AI Agents configuration (OpenCode, Cursor, etc.)
	log_info "Setting up AI Agents configuration..."
	setup_ai_agents

	echo ""
	echo "========================================"
	log_success "Bootstrap complete!"
	echo "========================================"
	echo ""
	log_info "Next steps:"
	echo "  1. Restart your shell or run: source ~/.zshrc"
	echo "  2. Open nvim to let Lazy install plugins"
	echo "  3. Start a new tmux session"
	echo "  4. If you edit ai-agent rules, run: cd ~/.dotfiles/ai-agents && npx rulesync generate"
	echo ""

	if [[ -d "$BACKUP_DIR" ]]; then
		log_warn "Backups saved to: $BACKUP_DIR"
	fi
}

main "$@"
