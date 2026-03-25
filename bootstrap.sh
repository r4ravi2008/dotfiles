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

# =============================================================================
# Cross-platform package installer engine
# =============================================================================
# Reads packages.conf (declarative registry) and installs missing tools.
# See packages.conf for the file format.
# =============================================================================

PACKAGES_CONF="$DOTFILES_DIR/packages.conf"

# --- Linux package manager detection ----------------------------------------

_LINUX_PKG_MGR=""
_APT_UPDATED=false

detect_linux_pkg_mgr() {
	if [[ -n "$_LINUX_PKG_MGR" ]]; then return; fi
	if   command -v apt-get >/dev/null 2>&1; then _LINUX_PKG_MGR="apt"
	elif command -v dnf     >/dev/null 2>&1; then _LINUX_PKG_MGR="dnf"
	elif command -v pacman  >/dev/null 2>&1; then _LINUX_PKG_MGR="pacman"
	elif command -v zypper  >/dev/null 2>&1; then _LINUX_PKG_MGR="zypper"
	else _LINUX_PKG_MGR="unknown"
	fi
}

# Install packages using the detected Linux package manager.
linux_pkg_install() {
	detect_linux_pkg_mgr
	case "$_LINUX_PKG_MGR" in
	apt)
		if ! $_APT_UPDATED; then
			sudo apt-get update -qq
			_APT_UPDATED=true
		fi
		sudo apt-get install -y "$@"
		;;
	dnf)    sudo dnf install -y "$@" ;;
	pacman) sudo pacman -S --noconfirm --needed "$@" ;;
	zypper) sudo zypper install -y "$@" ;;
	*)
		log_warn "No supported Linux package manager found (tried apt, dnf, pacman, zypper)."
		log_warn "Please install manually: $*"
		return 1
		;;
	esac
}

# --- Fallback installers -----------------------------------------------------
# Each function is named _fallback_<name>, matching the "fallback" column in
# packages.conf.  They are only called when brew / the system package manager
# cannot provide the tool.

_fallback_zoxide() {
	log_info "Installing zoxide via official installer..."
	curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
	log_success "Installed zoxide"
}

_fallback_fzf() {
	if [[ -d "$HOME/.fzf" ]]; then
		log_info "fzf directory exists, updating..."
		git -C "$HOME/.fzf" pull --ff-only 2>/dev/null || true
	else
		log_info "Installing fzf via git..."
		git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
	fi
	"$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
	log_success "Installed fzf"
}

_fallback_lazygit() {
	local version tag url arch
	arch="$(uname -m)"
	# Normalise arch names to match GitHub release artifacts
	case "$arch" in
	x86_64)  arch="x86_64" ;;
	aarch64|arm64) arch="arm64" ;;
	*)
		log_warn "lazygit: unsupported architecture ($arch). Install manually."
		return 1
		;;
	esac

	log_info "Installing lazygit via GitHub release..."
	version="$(curl -sSf https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')"
	if [[ -z "$version" ]]; then
		log_warn "Could not determine latest lazygit version. Install manually."
		return 1
	fi

	local os
	os="$(uname -s)"
	url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_${os}_${arch}.tar.gz"
	local tmp
	tmp="$(mktemp -d)"
	curl -sSfL "$url" -o "$tmp/lazygit.tar.gz"
	tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp"
	sudo install "$tmp/lazygit" /usr/local/bin/lazygit
	rm -rf "$tmp"
	log_success "Installed lazygit v${version}"
}

_fallback_podman_compose() {
	if command -v pipx >/dev/null 2>&1; then
		log_info "Installing podman-compose via pipx..."
		pipx install podman-compose
		log_success "Installed podman-compose via pipx"
	elif command -v pip3 >/dev/null 2>&1; then
		log_info "Installing podman-compose via pip3..."
		pip3 install --user podman-compose
		log_success "Installed podman-compose via pip3"
	else
		log_warn "podman-compose: no pipx or pip3 found. Install manually."
		return 1
	fi
}

_fallback_skhd_zig() {
	if [[ "$(uname)" == "Darwin" ]]; then
		log_info "Installing skhd (Zig rewrite) from jackielii/tap..."
		if ! brew tap | grep -q "^jackielii/tap"; then
			log_info "Tapping jackielii/tap..."
			brew tap jackielii/tap
		fi
		brew install jackielii/tap/skhd-zig
		log_success "Installed skhd"
		log_info "skhd requires accessibility permissions. Grant them in System Settings > Privacy & Security > Accessibility"
		log_info "To start skhd: skhd --start-service"
	else
		log_warn "skhd is macOS-only. Skipping."
		return 1
	fi
}

_fallback_aws() {
	if [[ "$(uname)" == "Darwin" ]]; then
		log_info "Installing AWS CLI via official macOS installer..."
		local tmp
		tmp="$(mktemp -d)"
		curl -sSfL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$tmp/AWSCLIV2.pkg"
		sudo installer -pkg "$tmp/AWSCLIV2.pkg" -target /
		rm -rf "$tmp"
		log_success "Installed AWS CLI"
	elif [[ "$(uname)" == "Linux" ]]; then
		local arch
		arch="$(uname -m)"
		local url
		case "$arch" in
		x86_64)  url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
		aarch64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
		*)
			log_warn "AWS CLI: unsupported architecture ($arch). Install manually."
			return 1
			;;
		esac
		log_info "Installing AWS CLI via official Linux installer ($arch)..."
		if ! command -v unzip >/dev/null 2>&1; then
			log_info "unzip not found, installing it first..."
			linux_pkg_install unzip || { log_warn "Cannot install unzip; skipping AWS CLI."; return 1; }
		fi
		local tmp
		tmp="$(mktemp -d)"
		curl -sSfL "$url" -o "$tmp/awscliv2.zip"
		(cd "$tmp" && unzip -q awscliv2.zip && sudo ./aws/install)
		rm -rf "$tmp"
		log_success "Installed AWS CLI"
	else
		log_warn "AWS CLI: unsupported OS. Install manually: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
		return 1
	fi
}

# --- Registry parser ---------------------------------------------------------

# Parse packages.conf and return lines matching the requested group(s).
# Usage: _parse_packages group1 [group2 ...]
# Each output line: command|brew|apt|dnf|pacman|zypper|fallback
_parse_packages() {
	local groups=("$@")
	if [[ ! -f "$PACKAGES_CONF" ]]; then
		log_error "Package registry not found at $PACKAGES_CONF"
		return 1
	fi

	while IFS='|' read -r cmd group brew apt dnf pacman zypper fallback; do
		# Trim leading/trailing whitespace
		cmd="${cmd#"${cmd%%[![:space:]]*}"}";             cmd="${cmd%"${cmd##*[![:space:]]}"}"
		group="${group#"${group%%[![:space:]]*}"}";       group="${group%"${group##*[![:space:]]}"}"
		brew="${brew#"${brew%%[![:space:]]*}"}";           brew="${brew%"${brew##*[![:space:]]}"}"
		apt="${apt#"${apt%%[![:space:]]*}"}";             apt="${apt%"${apt##*[![:space:]]}"}"
		dnf="${dnf#"${dnf%%[![:space:]]*}"}";             dnf="${dnf%"${dnf##*[![:space:]]}"}"
		pacman="${pacman#"${pacman%%[![:space:]]*}"}";     pacman="${pacman%"${pacman##*[![:space:]]}"}"
		zypper="${zypper#"${zypper%%[![:space:]]*}"}";     zypper="${zypper%"${zypper##*[![:space:]]}"}"
		fallback="${fallback#"${fallback%%[![:space:]]*}"}"; fallback="${fallback%"${fallback##*[![:space:]]}"}"

		# Skip comments and blank lines
		[[ -z "$cmd" || "$cmd" == \#* ]] && continue

		# Filter by group
		local match=false
		for g in "${groups[@]}"; do
			[[ "$group" == "$g" ]] && match=true && break
		done
		$match || continue

		echo "${cmd}|${brew}|${apt}|${dnf}|${pacman}|${zypper}|${fallback}"
	done < "$PACKAGES_CONF"
}

# --- Main installer ----------------------------------------------------------

# Install all packages from the given group(s).
# Usage: install_packages group1 [group2 ...]
#
# Strategy:
#   1. Collect missing packages
#   2. Batch-install via brew (macOS) or system pkg mgr (Linux)
#   3. For anything that fails or has no distro package, run the fallback
install_packages() {
	local groups=("$@")
	local label="${groups[*]}"

	# Collect missing packages
	local -a missing_cmds=()    # command names
	local -a missing_brew=()    # brew formula names
	local -a missing_distro=()  # distro package names (for detected pkg mgr)
	local -a missing_fallback=() # fallback function names (parallel to missing_cmds)

	detect_linux_pkg_mgr

	while IFS='|' read -r cmd brew apt dnf pacman zypper fallback; do
		if command -v "$cmd" >/dev/null 2>&1; then
			log_info "$cmd already installed"
			continue
		fi

		missing_cmds+=("$cmd")
		missing_brew+=("$brew")
		missing_fallback+=("$fallback")

		# Pick the right distro package name
		local distro_pkg="-"
		case "$_LINUX_PKG_MGR" in
		apt)    distro_pkg="$apt" ;;
		dnf)    distro_pkg="$dnf" ;;
		pacman) distro_pkg="$pacman" ;;
		zypper) distro_pkg="$zypper" ;;
		esac
		missing_distro+=("$distro_pkg")
	done < <(_parse_packages "${groups[@]}")

	if [[ ${#missing_cmds[@]} -eq 0 ]]; then
		log_success "All $label tools already installed"
		return
	fi

	log_info "Missing $label tools: ${missing_cmds[*]}"

	# --- macOS: prefer Homebrew batch install --------------------------------
	if command -v brew >/dev/null 2>&1; then
		local -a brew_batch=()
		for i in "${!missing_cmds[@]}"; do
			[[ "${missing_brew[$i]}" != "-" ]] && brew_batch+=("${missing_brew[$i]}")
		done
		if [[ ${#brew_batch[@]} -gt 0 ]]; then
			log_info "Installing via Homebrew: ${brew_batch[*]}"
			if brew install "${brew_batch[@]}"; then
				log_success "Installed ${brew_batch[*]} via Homebrew"
				# Re-check which ones are still missing and need fallback
				local -a still_missing_idx=()
				for i in "${!missing_cmds[@]}"; do
					command -v "${missing_cmds[$i]}" >/dev/null 2>&1 || still_missing_idx+=("$i")
				done
				# Run fallbacks only for tools brew didn't satisfy
				for i in "${still_missing_idx[@]}"; do
					local fb="${missing_fallback[$i]}"
					local fb_func="_fallback_${fb//-/_}"
					if [[ "$fb" != "-" ]] && declare -f "$fb_func" >/dev/null 2>&1; then
						log_info "${missing_cmds[$i]}: brew didn't provide it, trying fallback..."
						"$fb_func" || log_warn "${missing_cmds[$i]}: fallback install failed"
					else
						log_warn "${missing_cmds[$i]}: not installed by Homebrew and no fallback available"
					fi
				done
				return
			else
				log_warn "Homebrew batch install failed; falling back to individual installs"
			fi
		fi
	fi

	# --- Linux / no-brew: try system package manager, then fallbacks ---------
	if [[ "$(uname)" == "Linux" && "$_LINUX_PKG_MGR" != "unknown" ]]; then
		# Batch all packages that have a distro package name
		local -a distro_batch=()
		local -a distro_batch_idx=()
		for i in "${!missing_cmds[@]}"; do
			if [[ "${missing_distro[$i]}" != "-" ]]; then
				distro_batch+=("${missing_distro[$i]}")
				distro_batch_idx+=("$i")
			fi
		done
		if [[ ${#distro_batch[@]} -gt 0 ]]; then
			log_info "Installing via $_LINUX_PKG_MGR: ${distro_batch[*]}"
			linux_pkg_install "${distro_batch[@]}" || true
		fi
	fi

	# Run fallbacks for anything still missing
	for i in "${!missing_cmds[@]}"; do
		local cmd="${missing_cmds[$i]}"
		local fb="${missing_fallback[$i]}"
		if command -v "$cmd" >/dev/null 2>&1; then
			log_success "$cmd installed"
			continue
		fi
		if [[ "$fb" != "-" ]]; then
			local fb_func="_fallback_${fb//-/_}"
			if declare -f "$fb_func" >/dev/null 2>&1; then
				log_info "$cmd: trying fallback installer..."
				"$fb_func" || log_warn "$cmd: fallback install failed"
			else
				log_warn "$cmd: fallback '$fb' referenced but _fallback_${fb//-/_} not defined"
			fi
		else
			log_warn "$cmd: not installed. No package or fallback available for this platform."
		fi
	done
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
				# OpenCode discovers skills from ~/.agents/skills/ (synced by bootstrap below),
				# so remove the redundant rulesync-generated copy to avoid confusion.
				rm -rf "$DOTFILES_DIR/ai-agents/.opencode/skill"
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

	# Sync skills to ~/.agents/skills (single source of truth: ai-agents/.rulesync/skills)
	if [[ -d "$DOTFILES_DIR/ai-agents/.rulesync/skills" ]]; then
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.rulesync/skills" "$HOME/.agents/skills" "agent skills (~/.agents/skills)"
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

	# skhd config (hotkey daemon - Zig rewrite)
	log_info "Setting up skhd configuration..."
	mkdir -p "$HOME/.config/skhd"
	create_symlink "$DOTFILES_DIR/skhd/skhdrc" "$HOME/.config/skhd/skhdrc"
	# Also symlink to ~/.skhdrc for backwards compatibility
	create_symlink "$DOTFILES_DIR/skhd/skhdrc" "$HOME/.skhdrc"

	# Lazygit config
	log_info "Setting up Lazygit configuration..."
	local lazygit_conf_dir
	if [[ "$(uname)" == "Darwin" ]]; then
		lazygit_conf_dir="$HOME/Library/Application Support/lazygit"
	else
		lazygit_conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit"
	fi
	mkdir -p "$lazygit_conf_dir"
	create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$lazygit_conf_dir/config.yml"

	# Install zsh plugins
	log_info "Setting up Zsh plugins..."
	install_zsh_plugins

	# Install CLI tools (zoxide, fzf, fd, ripgrep, lazygit)
	log_info "Installing CLI tools..."
	install_packages cli

	# Install window management tools (skhd)
	log_info "Installing window management tools..."
	install_packages wm

	# Install container & cloud tools (podman, podman-compose, aws-cli)
	log_info "Installing container & cloud tools..."
	install_packages container cloud

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
