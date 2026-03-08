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
	local tools=(zoxide fzf fd rg)
	local brew_names=(zoxide fzf fd ripgrep)
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
# Setup AI Agents (OpenCode, Cursor, etc.)
# -----------------------------------------------------------------------------
setup_ai_agents() {
	log_info "Setting up AI agent configurations..."

	# Ensure config directories exist
	mkdir -p "$HOME/.config/opencode"
	mkdir -p "$HOME/.cursor"

	# OpenCode legacy cleanup: older versions of this dotfiles repo created a
	# ~/.config/opencode/config.json symlink, but OpenCode's canonical global
	# config is ~/.config/opencode/opencode.json.
	if [[ -L "$HOME/.config/opencode/config.json" && "$(readlink "$HOME/.config/opencode/config.json")" == "$DOTFILES_DIR/opencode/config.json" ]]; then
		rm -f "$HOME/.config/opencode/config.json"
		log_info "Removed legacy OpenCode config.json symlink"
	fi

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

	# OpenCode skills (symlink generated skills to ~/.opencode/skills/)
	if [[ -d "$DOTFILES_DIR/ai-agents/.opencode/skill" ]]; then
		mkdir -p "$HOME/.opencode/skills"
		for skill_dir in "$DOTFILES_DIR/ai-agents/.opencode/skill"/*; do
			if [[ -d "$skill_dir" ]]; then
				skill_name="$(basename "$skill_dir")"
				create_symlink "$skill_dir" "$HOME/.opencode/skills/$skill_name"
			fi
		done
		log_success "Linked OpenCode skills"
	fi

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

	# Sync skills to ~/.agents/skills for OpenCode (rulesync global mode doesn't fully support skills yet)
	if [[ -d "$DOTFILES_DIR/ai-agents/.opencode/skill" ]]; then
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.opencode/skill" "$HOME/.agents/skills" "OpenCode skills (~/.agents/skills)"
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

	# Install zsh plugins
	log_info "Setting up Zsh plugins..."
	install_zsh_plugins

	# Install CLI tools (zoxide, fzf, fd, ripgrep)
	log_info "Installing CLI tools..."
	install_cli_tools

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
