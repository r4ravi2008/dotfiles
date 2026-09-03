#!/usr/bin/env bash
# =============================================================================
# Dotfiles Bootstrap Script
# Creates symlinks and installs dependencies for dotfiles
# =============================================================================

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
DOTFILES_PROFILE="${DOTFILES_PROFILE:-}"
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

# Merge Cursor/VS Code settings so MCP OAuth callback ports are always forwarded.
# Arrays are unioned by remotePort; other keys deep-merge.
merge_json_settings() {
	local dest="$1"
	local src="$2"

	if [[ ! -f "$src" ]]; then
		return 1
	fi
	if ! command -v jq >/dev/null 2>&1; then
		log_warn "jq not found; cannot merge $dest"
		return 1
	fi

	mkdir -p "$(dirname "$dest")"
	if [[ ! -s "$dest" ]]; then
		printf '%s\n' '{}' > "$dest"
	fi

	local tmp
	tmp="$(mktemp)"
	if jq --slurpfile add "$src" '
		. as $base
		| $add[0] as $extra
		| ($base * ($extra | del(."remote.SSH.defaultForwardedPorts", ."remote.portsAttributes")))
		| ."remote.portsAttributes" = ((."remote.portsAttributes" // {}) + ($extra."remote.portsAttributes" // {}))
		| ."remote.SSH.defaultForwardedPorts" = (
			((."remote.SSH.defaultForwardedPorts" // []) + ($extra."remote.SSH.defaultForwardedPorts" // []))
			| unique_by(.remotePort)
		)
	' "$dest" > "$tmp"; then
		mv "$tmp" "$dest"
		return 0
	fi
	rm -f "$tmp"
	log_warn "Failed to merge settings into $dest"
	return 1
}

# Laptop: Include Host cws.* LocalForwards so herdr --remote / ssh / Desktop App
# tunnel Atlassian (8787), Slack (3118), and Plannotator (19432) without a manual ssh -L.
ensure_cws_mcp_ssh_forwards() {
	local snippet="$DOTFILES_DIR/ssh/cws-mcp-forwards.conf"
	local ssh_config="$HOME/.ssh/config"
	local include_line="Include $snippet"

	if [[ ! -f "$snippet" ]]; then
		log_warn "Missing $snippet; skipping CWS MCP SSH forwards"
		return
	fi

	mkdir -p "$HOME/.ssh"
	if [[ -f "$ssh_config" ]] && grep -Fq "$snippet" "$ssh_config"; then
		log_info "SSH already includes CWS MCP OAuth forwards"
		return
	fi

	local tmp
	tmp="$(mktemp)"
	{
		echo "# dotfiles: CWS forwards (8787 Atlassian, 3118 Slack, 19432 Plannotator)"
		echo "$include_line"
		echo ""
		[[ -f "$ssh_config" ]] && cat "$ssh_config"
	} > "$tmp"
	mv "$tmp" "$ssh_config"
	chmod 600 "$ssh_config" 2>/dev/null || true
	log_success "Added CWS MCP OAuth SSH forwards to ~/.ssh/config"
}

# CWS: merge into remote IDE machine settings (written before user bootstrap).
merge_cws_ide_machine_settings() {
	local dest
	local merged=0
	local src

	for dest in \
		"$HOME/.cursor-server/data/Machine/settings.json" \
		"$HOME/.vscode-server/data/Machine/settings.json"
	do
		for src in \
			"$DOTFILES_DIR/cursor/cws-remote-settings.json" \
			"$DOTFILES_DIR/cursor/cws-workspace-trust.json"
		do
			[[ -f "$src" ]] || continue
			if merge_json_settings "$dest" "$src"; then
				log_success "Merged $(basename "$src") into $dest"
				merged=1
			fi
		done
	done

	if [[ "$merged" -eq 0 ]]; then
		log_warn "Could not merge Cursor/VS Code machine settings"
	fi
}

# Laptop: Cursor Remote-SSH user settings so Desktop Cursor also forwards the callbacks.
merge_laptop_cursor_forward_settings() {
	local src="$DOTFILES_DIR/cursor/cws-remote-settings.json"
	local dest="$HOME/Library/Application Support/Cursor/User/settings.json"

	if [[ "$(uname)" != "Darwin" ]]; then
		return
	fi
	if [[ ! -f "$src" ]]; then
		return
	fi
	if [[ ! -d "$(dirname "$dest")" ]]; then
		log_info "Cursor user settings directory missing; skip laptop Cursor port-forward merge"
		return
	fi
	if merge_json_settings "$dest" "$src"; then
		log_success "Merged MCP port-forward settings into Cursor user settings"
	fi
}

# =============================================================================
# Cross-platform package installer engine
# =============================================================================
# Reads packages.conf (declarative registry) and installs missing tools.
# See packages.conf for the file format.
# =============================================================================

PACKAGES_CONF=""

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

_fallback_herdr() {
	local os arch asset dest tmp url
	os="$(uname -s)"
	arch="$(uname -m)"
	case "$os/$arch" in
	Linux/x86_64) asset="herdr-linux-x86_64" ;;
	Linux/aarch64|Linux/arm64) asset="herdr-linux-aarch64" ;;
	Darwin/arm64) asset="herdr-macos-aarch64" ;;
	Darwin/x86_64) asset="herdr-macos-x86_64" ;;
	*)
		log_warn "herdr: unsupported platform ($os/$arch). Install manually."
		return 1
		;;
	esac

	url="https://github.com/herdrdev/herdr/releases/download/v${HERDR_PINNED_VERSION}/${asset}"
	dest="$HOME/.local/bin/herdr"
	tmp="$(mktemp -d)"
	log_info "Installing herdr ${HERDR_PINNED_VERSION} from GitHub ($asset)..."
	if ! curl -fsSL "$url" -o "$tmp/herdr"; then
		log_warn "Failed to download $url"
		rm -rf "$tmp"
		return 1
	fi
	mkdir -p "$HOME/.local/bin"
	chmod +x "$tmp/herdr"
	mv "$tmp/herdr" "$dest"
	rm -rf "$tmp"
	export PATH="$HOME/.local/bin:$PATH"
	hash -r 2>/dev/null || true
	if herdr_is_pinned_version; then
		log_success "Installed herdr ${HERDR_PINNED_VERSION} -> $dest"
	else
		log_warn "herdr installed but version is not ${HERDR_PINNED_VERSION}"
		return 1
	fi
}

# Pin Herdr on CWS (and fallback installs) so `herdr --remote` matches the laptop.
# Do not use https://herdr.dev/install.sh — that always fetches latest.json.
HERDR_PINNED_VERSION="0.8.2"

# LazyVim needs Neovim 0.11+. Debian's neovim package is often 0.10.x.
NVIM_MIN_VERSION="0.11"

herdr_is_pinned_version() {
	command -v herdr >/dev/null 2>&1 || return 1
	local ver
	ver="$(herdr --version 2>/dev/null | sed -n 's/^herdr[[:space:]]*//p' | head -1)"
	[[ "$ver" == "$HERDR_PINNED_VERSION" ]]
}

nvim_meets_min_version() {
	command -v nvim >/dev/null 2>&1 || return 1
	local ver major minor
	ver="$(nvim --version 2>/dev/null | sed -n 's/^NVIM v\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p' | head -1)"
	[[ -n "$ver" ]] || return 1
	major="${ver%% *}"
	minor="${ver#* }"
	(( major > 0 )) || (( major == 0 && minor >= 11 ))
}

_fallback_nvim() {
	local os arch url asset prefix dest tmp
	os="$(uname -s)"
	arch="$(uname -m)"
	case "$os/$arch" in
	Linux/x86_64)  asset="nvim-linux-x86_64.tar.gz"; prefix="nvim-linux-x86_64" ;;
	Linux/aarch64|Linux/arm64) asset="nvim-linux-arm64.tar.gz"; prefix="nvim-linux-arm64" ;;
	Darwin/arm64)  asset="nvim-macos-arm64.tar.gz"; prefix="nvim-macos-arm64" ;;
	Darwin/x86_64) asset="nvim-macos-x86_64.tar.gz"; prefix="nvim-macos-x86_64" ;;
	*)
		log_warn "nvim: unsupported platform ($os/$arch). Install manually from https://github.com/neovim/neovim/releases"
		return 1
		;;
	esac

	url="https://github.com/neovim/neovim/releases/latest/download/${asset}"
	dest="$HOME/.local/opt/${prefix}"
	tmp="$(mktemp -d)"
	log_info "Installing latest Neovim from GitHub ($asset)..."
	if ! curl -fsSL "$url" -o "$tmp/$asset"; then
		log_warn "Failed to download $url"
		rm -rf "$tmp"
		return 1
	fi
	mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
	rm -rf "$dest"
	tar -xzf "$tmp/$asset" -C "$HOME/.local/opt"
	rm -rf "$tmp"
	if [[ ! -x "$dest/bin/nvim" ]]; then
		log_warn "Neovim tarball did not contain $dest/bin/nvim"
		return 1
	fi
	ln -sfn "$dest/bin/nvim" "$HOME/.local/bin/nvim"
	export PATH="$HOME/.local/bin:$PATH"
	hash -r 2>/dev/null || true
	log_success "Installed $(nvim --version | head -1) -> $HOME/.local/bin/nvim"
}

_fallback_open_computer_use() {
	if ! command -v npm >/dev/null 2>&1; then
		log_warn "open-computer-use: npm not found. Install Node.js, then re-run bootstrap."
		return 1
	fi
	log_info "Installing open-computer-use via npm..."
	if npm install -g open-computer-use; then
		export PATH="$(npm root -g 2>/dev/null)/../bin:$HOME/.local/bin:$PATH"
		hash -r 2>/dev/null || true
		if command -v open-computer-use >/dev/null 2>&1; then
			log_success "Installed open-computer-use"
			if [[ "$(uname)" == "Darwin" ]]; then
				log_info "Grant Accessibility and Screen Recording when open-computer-use doctor asks"
			fi
			return 0
		fi
	fi
	log_warn "open-computer-use install finished but binary not found on PATH"
	return 1
}

_ensure_npm() {
	if command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
		return 0
	fi
	local nvm_bin="/usr/local/share/nvm/current/bin"
	if [[ -x "$nvm_bin/npm" ]]; then
		export PATH="$nvm_bin:$PATH"
	elif [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
		# shellcheck disable=SC1091
		. "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
	fi
	command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1
}

_node_major() {
	if ! _ensure_npm; then
		echo 0
		return 0
	fi
	node -p 'parseInt(process.versions.node, 10)' 2>/dev/null || echo 0
}

_run_with_timeout() {
	local secs="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "$secs" "$@"
	else
		"$@"
	fi
}

# Canonical skill dir is ~/.agents/skills (Pi, Codex, OpenCode).
# Claude Code and Cursor read their own dirs, so those become symlinks.
_link_skill_lock() {
	local lock="$DOTFILES_DIR/ai-agents/.skill-lock.json"
	mkdir -p "$HOME/.agents"
	if [[ ! -f "$lock" ]]; then
		printf '%s\n' '{
  "version": 3,
  "skills": {},
  "dismissed": {}
}' > "$lock"
	fi
	create_symlink "$lock" "$HOME/.agents/.skill-lock.json"
}

_link_harness_skills() {
	mkdir -p "$HOME/.agents/skills" "$HOME/.claude" "$HOME/.cursor"
	create_symlink "$HOME/.agents/skills" "$HOME/.claude/skills"
	create_symlink "$HOME/.agents/skills" "$HOME/.cursor/skills"
}

# Personal skills stay in the repo. Point ~/.agents/skills/<name> at them.
_link_repo_skills() {
	local src dest name
	mkdir -p "$HOME/.agents/skills"
	for src in \
		"$DOTFILES_DIR/.agents/skills" \
		"$DOTFILES_DIR/ai-agents/.rulesync/skills"
	do
		[[ -d "$src" ]] || continue
		for dest in "$src"/*; do
			[[ -d "$dest" && -f "$dest/SKILL.md" ]] || continue
			name="$(basename "$dest")"
			create_symlink "$dest" "$HOME/.agents/skills/$name"
		done
	done
}

_install_skills_pkg() {
	local pkg="$1"
	if ! _ensure_npm || [[ "$(_node_major)" -lt 20 ]]; then
		log_warn "npx skills needs Node 20+; skipping $pkg"
		return 1
	fi
	log_info "skills.sh add $pkg"
	if _run_with_timeout 600 npx --yes skills add "$pkg" --global --yes --skill '*'; then
		log_success "Installed $pkg"
		return 0
	fi
	log_warn "skills add failed for $pkg"
	return 1
}

_fallback_hunk() {
	export PATH="$HOME/.local/bin:$PATH"
	_ensure_npm || true
	if command -v brew >/dev/null 2>&1; then
		log_info "Installing hunk via Homebrew (modem-dev/tap)..."
		brew tap modem-dev/tap >/dev/null 2>&1 || true
		if brew install modem-dev/tap/hunk; then
			log_success "Installed hunk"
			return 0
		fi
	fi
	if command -v npm >/dev/null 2>&1; then
		log_info "Installing hunk via npm (hunkdiff)..."
		if npm install -g hunkdiff; then
			export PATH="$(npm root -g 2>/dev/null)/../bin:$HOME/.local/bin:$PATH"
			hash -r 2>/dev/null || true
			if command -v hunk >/dev/null 2>&1; then
				log_success "Installed hunk"
				return 0
			fi
		fi
	fi
	log_warn "hunk install failed. See https://github.com/modem-dev/hunk"
	return 1
}

_fallback_bun() {
	export PATH="$HOME/.local/bin:$PATH"
	if command -v bun >/dev/null 2>&1; then
		log_success "bun already installed"
		return 0
	fi
	log_info "Installing bun via official installer..."
	if curl -fsSL https://bun.sh/install | BUN_INSTALL="$HOME/.local" bash; then
		hash -r 2>/dev/null || true
		export PATH="$HOME/.local/bin:$PATH"
		if command -v bun >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/bun" ]]; then
			log_success "Installed bun"
			return 0
		fi
	fi
	log_warn "bun install failed"
	return 1
}

_fallback_uv() {
	export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
	if command -v uv >/dev/null 2>&1; then
		log_success "uv already installed"
		return 0
	fi
	log_info "Installing uv via official installer..."
	if curl -fsSL https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$HOME/.local/bin" sh; then
		hash -r 2>/dev/null || true
		export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
		if command -v uv >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/uv" ]]; then
			log_success "Installed uv"
			return 0
		fi
	fi
	log_warn "uv install failed"
	return 1
}

_fallback_plannotator() {
	export PATH="$HOME/.local/bin:$PATH"
	log_info "Installing plannotator (core skills + extras)..."
	if curl -fsSL https://plannotator.ai/install.sh | bash -s -- --non-interactive --extras; then
		hash -r 2>/dev/null || true
		if command -v plannotator >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/plannotator" ]]; then
			log_success "Installed plannotator"
			return 0
		fi
	fi
	log_warn "plannotator installer finished but binary not found on PATH"
	return 1
}

# Disable public share links (share.plannotator.ai / paste short links).
configure_plannotator_local_only() {
	local dir="${PLANNOTATOR_DATA_DIR:-$HOME/.plannotator}"
	local cfg="$dir/config.json"
	mkdir -p "$dir"
	if [[ -s "$cfg" ]] && command -v jq >/dev/null 2>&1; then
		local tmp
		tmp="$(mktemp)"
		if jq '.share = "disabled"' "$cfg" > "$tmp"; then
			mv "$tmp" "$cfg"
		else
			rm -f "$tmp"
			printf '%s\n' '{"share":"disabled"}' > "$cfg"
		fi
	else
		printf '%s\n' '{"share":"disabled"}' > "$cfg"
	fi
	log_success "Plannotator sharing disabled (local-only)"
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
			if [[ "$cmd" == "nvim" ]] && ! nvim_meets_min_version; then
				log_info "nvim is older than ${NVIM_MIN_VERSION}; will install the GitHub release"
			elif [[ "$cmd" == "herdr" ]] && ! herdr_is_pinned_version; then
				log_info "herdr is not ${HERDR_PINNED_VERSION}; will install the pinned GitHub release"
			else
				log_info "$cmd already installed"
				continue
			fi
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
# Setup AI Agents (OpenCode, Cursor, Claude Code, etc.)
# -----------------------------------------------------------------------------
setup_ai_agents() {
	log_info "Setting up AI agent configurations..."

	# Ensure config directories exist
	mkdir -p "$HOME/.config/opencode"
	mkdir -p "$HOME/.cursor"
	mkdir -p "$HOME/.claude"

    # Generate rulesync outputs (source of truth lives in ai-agents/.rulesync)
	# This keeps Cursor/OpenCode configs and commands in sync even if they already exist locally.
	if [[ -d "$DOTFILES_DIR/ai-agents/.rulesync" ]]; then
		if command -v npx >/dev/null 2>&1; then
			log_info "Generating rulesync outputs (OpenCode/Cursor/Claude Code/etc.)..."
			if (cd "$DOTFILES_DIR/ai-agents" && npx rulesync generate); then
				log_success "Generated rulesync outputs"
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

	# Cursor MCP config (rulesync source of truth)
	if [[ -f "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" ]]; then
		create_symlink "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" "$HOME/.cursor/mcp.json"
	elif [[ -f "$DOTFILES_DIR/cursor/mcp.json" ]]; then
		create_symlink "$DOTFILES_DIR/cursor/mcp.json" "$HOME/.cursor/mcp.json"
	fi

	# Pi has no built-in MCP. pi-mcp-adapter reads the shared user-global files.
	# Do not symlink ~/.pi/agent/mcp.json — the adapter may write overrides there.
	if [[ -f "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" ]]; then
		mkdir -p "$HOME/.config/mcp" "$HOME/.agents"
		create_symlink "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" "$HOME/.config/mcp/mcp.json"
		create_symlink "$DOTFILES_DIR/ai-agents/.rulesync/mcp.json" "$HOME/.agents/mcp.json"
	fi

	if command -v pi >/dev/null 2>&1; then
		local pi_settings="$HOME/.pi/agent/settings.json"
		local pi_mcp_installed=0
		if [[ -f "$pi_settings" ]] && command -v jq >/dev/null 2>&1; then
			if jq -e '
				(.packages // [])
				| map(if type == "string" then . else (.source // "") end)
				| any(test("^npm:pi-mcp-adapter(@|$)") or . == "pi-mcp-adapter")
			' "$pi_settings" >/dev/null 2>&1; then
				pi_mcp_installed=1
			fi
		fi
		if (( pi_mcp_installed )); then
			log_info "pi-mcp-adapter already installed"
		elif pi install npm:pi-mcp-adapter --no-approve; then
			log_success "Installed pi-mcp-adapter (so Pi loads rulesync MCP servers)"
		else
			log_warn "Could not install pi-mcp-adapter; Pi will not load MCP servers"
		fi
	else
		log_warn "pi not found; skipping pi-mcp-adapter install"
	fi

	# Cursor commands/agents/rules/skills are generated by rulesync into ai-agents/.cursor.
	# Cursor may already have its own ~/.cursor/{commands,agents,...} directories, so we sync
	# contents instead of symlinking the whole directory.
	if [[ -d "$DOTFILES_DIR/ai-agents/.cursor" ]]; then
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/commands" "$HOME/.cursor/commands" "Cursor commands"
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/agents" "$HOME/.cursor/agents" "Cursor agents"
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.cursor/rules" "$HOME/.cursor/rules" "Cursor rules"
	else
		log_warn "rulesync Cursor outputs not found at ai-agents/.cursor; run 'cd ~/.dotfiles/ai-agents && npx rulesync generate'"
	fi

	# Claude Code configuration
	# Claude Code uses ~/.claude/ for commands/agents/skills.
	# Global MCP servers live in ~/.claude.json under the top-level "mcpServers" key.
	mkdir -p "$HOME/.claude"
	if [[ -d "$DOTFILES_DIR/ai-agents/.claude" ]]; then
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.claude/commands" "$HOME/.claude/commands" "Claude Code commands"
		sync_dir_contents "$DOTFILES_DIR/ai-agents/.claude/agents" "$HOME/.claude/agents" "Claude Code agents"
	else
		log_warn "rulesync Claude Code outputs not found at ai-agents/.claude; run 'cd ~/.dotfiles/ai-agents && npx rulesync generate'"
	fi

	# Claude Code global MCP servers
	# Use `claude mcp add --scope user` to register servers from rulesync mcp.json.
	# Claude Code stores user-scope MCP in ~/.claude.json under "mcpServers" with a
	# required "type" field that raw JSON merging would miss.
	local mcp_source="$DOTFILES_DIR/ai-agents/.rulesync/mcp.json"
	if [[ -f "$mcp_source" ]] && command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		log_info "Registering MCP servers with Claude Code (user scope)..."
		local server_names
		if ! server_names="$(jq -r '.mcpServers // {} | keys[]' "$mcp_source" 2>/dev/null)"; then
			log_warn "Could not parse $mcp_source; skipping Claude Code MCP registration"
			server_names=""
		fi
		while IFS= read -r name; do
			[[ -z "$name" ]] && continue
			local url cmd
			url="$(jq -r --arg n "$name" '.mcpServers[$n].url // empty' "$mcp_source")"
			cmd="$(jq -r --arg n "$name" '.mcpServers[$n].command // empty' "$mcp_source")"
			if [[ -n "$url" ]]; then
				if claude mcp add --scope user --transport http "$name" "$url" >/dev/null 2>&1; then
					log_success "Registered Claude Code MCP server: $name"
				else
					log_warn "Failed to register Claude Code MCP server: $name"
				fi
			elif [[ -n "$cmd" ]]; then
				local -a stdio_args=()
				while IFS= read -r a; do
					[[ -n "$a" ]] && stdio_args+=("$a")
				done < <(jq -r --arg n "$name" '.mcpServers[$n].args // [] | .[]' "$mcp_source")
				if claude mcp add --scope user --transport stdio "$name" -- "$cmd" "${stdio_args[@]}" >/dev/null 2>&1; then
					log_success "Registered Claude Code MCP server: $name"
				else
					log_warn "Failed to register Claude Code MCP server: $name"
				fi
			else
				log_warn "Skipping Claude Code MCP server '$name': no url or command field"
			fi
		done <<< "$server_names"
	elif [[ -f "$mcp_source" ]]; then
		log_warn "claude CLI or jq not found; cannot register MCP servers for Claude Code"
	fi

	_link_skill_lock

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

	# pstack first; Matt Pocock overwrites tdd/teach.
	_install_skills_pkg "backnotprop/pstack" || true
	_install_skills_pkg "mattpocock/skills" || true
	if command -v hunk >/dev/null 2>&1; then
		_install_skills_pkg "modem-dev/hunk" || true
	fi
	if command -v plannotator >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/plannotator" ]]; then
		_install_skills_pkg "backnotprop/plannotator/apps/skills/extra" || true
	fi
	_link_repo_skills
	_link_harness_skills
	configure_plannotator_local_only || true

	log_success "AI agent configurations set up"
}

is_cloud_workspace() {
	[[ -d /.cws ]] || [[ -n "${CWS_WORKSPACE_ID:-}" ]] || [[ -n "${CWS_USER_DOTFILES_REPO_URL:-}" ]] \
		|| { [[ -d /workspace ]] && [[ "$(id -un 2>/dev/null || true)" == "coder" ]]; }
}

resolve_dotfiles_dir() {
	if [[ -d "$DOTFILES_DIR/nvim" && -f "$DOTFILES_DIR/bootstrap.sh" ]]; then
		return
	fi
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	if [[ -d "$script_dir/nvim" ]]; then
		DOTFILES_DIR="$script_dir"
		return
	fi
	if [[ -d "$HOME/.dotfiles/nvim" ]]; then
		DOTFILES_DIR="$HOME/.dotfiles"
		return
	fi
	if [[ -d "$HOME/nvim" && -f "$HOME/bootstrap.sh" ]]; then
		DOTFILES_DIR="$HOME"
	fi
}

herdr_plugin_at_ref() {
	local plugin_id="$1"
	local sha="$2"
	local state
	state="$(herdr plugin list --plugin "$plugin_id" --json 2>/dev/null || true)"
	grep -Eq '"plugin_id"[[:space:]]*:[[:space:]]*"'"$plugin_id"'"' <<<"$state" \
		&& grep -Eq '"resolved_commit"[[:space:]]*:[[:space:]]*"'"$sha"'"' <<<"$state"
}

install_herdr_github_plugin() {
	local plugin_id="$1"
	local repo="$2"
	local sha="$3"
	local ok_msg="$4"
	local warn_msg="$5"
	if herdr_plugin_at_ref "$plugin_id" "$sha"; then
		log_info "Herdr plugin $plugin_id already installed at $sha"
		return 0
	fi
	if herdr plugin install "$repo" --ref "$sha" --yes; then
		log_success "$ok_msg"
		return 0
	fi
	log_warn "$warn_msg"
	return 1
}

# Keep the agent picker focused on the configured local agents. Pi comes first,
# so it is the default when a folder has no preference.
# The picker inherits FZF_DEFAULT_OPTS=--height 40% --border from the Herdr
# server shell, so the 90% popup shrinks to a few rows and the preview hides
# the rest of the list. Clear those opts and keep the preview on the right.
patch_herdr_agents() {
	local root opener
	root="$(herdr plugin list --plugin dleen.herdr-agents --json 2>/dev/null \
		| python3 -c 'import json,sys; d=json.load(sys.stdin); ps=d.get("result",{}).get("plugins") or []; print(ps[0].get("plugin_root","") if ps else "")' 2>/dev/null || true)"
	local script="$root/herdr-agents"
	if [[ ! -f "$script" ]]; then
		return 0
	fi
	if grep -Fq 'AGENT_KINDS = ("pi", "opencode", "codex")' "$script"; then
		log_info "herdr-agents already defaults to Pi"
	elif grep -Fq 'AGENT_KINDS = ("opencode", "codex")' "$script"; then
		perl -pi -e 's/AGENT_KINDS = \("opencode", "codex"\)/AGENT_KINDS = ("pi", "opencode", "codex")/' "$script"
		log_success "herdr-agents now defaults to Pi"
	elif grep -Fq 'AGENT_KINDS = ("cursor", "claude", "codex", "pi")' "$script"; then
		perl -pi -e 's/AGENT_KINDS = \("cursor", "claude", "codex", "pi"\)/AGENT_KINDS = ("pi", "opencode", "codex")/' "$script"
		log_success "herdr-agents now defaults to Pi"
	elif grep -Fq 'AGENT_KINDS = ("claude", "codex", "pi")' "$script"; then
		perl -pi -e 's/AGENT_KINDS = \("claude", "codex", "pi"\)/AGENT_KINDS = ("pi", "opencode", "codex")/' "$script"
		log_success "herdr-agents now defaults to Pi"
	else
		log_warn "herdr-agents AGENT_KINDS line changed upstream; skipped agent-kind patch"
	fi
	if grep -Fq '--height=100%' "$script"; then
		log_info "herdr-agents fzf already fills the popup"
	elif grep -Fq '"--layout=reverse", "--info=inline", "--pointer=>",' "$script"; then
		perl -pi -e 's/"--layout=reverse", "--info=inline", "--pointer=>",/"--layout=reverse", "--height=100%", "--info=inline", "--pointer=>",/' "$script"
		log_success "herdr-agents fzf now fills the popup"
	else
		log_warn "herdr-agents fzf args changed upstream; skipped height patch"
	fi
	if grep -Fq 'if cols >= 100:' "$script"; then
		log_info "herdr-agents preview already stays on the right"
	elif grep -Fq 'if cols >= 170:' "$script"; then
		perl -pi -e 's/if cols >= 170:/if cols >= 100:/; s/return f"down,\{max\(14, lines \* 3 \/\/ 5\)\},wrap,border-top"/return f"down,{min(8, max(4, lines \/\/ 5))},wrap,border-top"/' "$script"
		log_success "herdr-agents preview stays beside the list"
	else
		log_warn "herdr-agents preview_window changed upstream; skipped preview patch"
	fi
	opener="$root/open-picker.sh"
	if [[ -f "$opener" ]] && grep -Fq 'FZF_DEFAULT_OPTS' "$opener"; then
		log_info "herdr-agents opener already clears FZF_DEFAULT_OPTS"
	elif [[ -f "$opener" ]] && grep -Fq '--entrypoint picker' "$opener"; then
		perl -pi -e 's/--entrypoint picker/--entrypoint picker \\\n\t--env FZF_DEFAULT_OPTS=/' "$opener"
		log_success "herdr-agents opener clears FZF_DEFAULT_OPTS"
	fi
}

# annotate.open ignores terminal selection and always opens the folder. Point it
# at open-from-selection.sh so a unique Markdown quote opens that file instead.
patch_herdr_annotate() {
	local root dest src
	root="$(herdr plugin list --plugin annotate --json 2>/dev/null \
		| python3 -c 'import json,sys; d=json.load(sys.stdin); ps=d.get("result",{}).get("plugins") or []; print(ps[0].get("plugin_root","") if ps else "")' 2>/dev/null || true)"
	if [[ ! -d "$root/scripts" ]]; then
		return 0
	fi
	src="$DOTFILES_DIR/herdr/open-from-selection.sh"
	dest="$root/scripts/open-from-selection.sh"
	if [[ ! -f "$src" ]]; then
		log_warn "herdr/open-from-selection.sh missing; skipped annotate open patch"
		return 0
	fi
	install -m 755 "$src" "$dest"
	python3 - "$root/herdr-plugin.toml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
if "open-from-selection.sh" in text:
    raise SystemExit(0)
old = 'scripts/plannotator-tui.sh\\" herdr open'
new = 'scripts/open-from-selection.sh\\"'
if old not in text:
    raise SystemExit(2)
path.write_text(text.replace(old, new))
PY
	case $? in
		0)
			if grep -Fq 'open-from-selection.sh' "$root/herdr-plugin.toml"; then
				log_success "herdr-annotate open jumps to the selected Markdown file"
			else
				log_info "herdr-annotate open already uses selection matching"
			fi
			;;
		2) log_warn "herdr-annotate open command changed upstream; skipped selection patch" ;;
	esac
}

start_herdr_server() {
	export PATH="$HOME/.local/bin:$PATH"
	if ! command -v herdr >/dev/null 2>&1; then
		log_warn "herdr not on PATH; skipped headless server"
		return
	fi
	mkdir -p "$HOME/.config/herdr"
	if herdr status 2>/dev/null | grep -A5 '^server:' | grep -Eq '^[[:space:]]*status: running$'; then
		if is_cloud_workspace; then
			log_info "Restarting Herdr so new panes use /workspace"
			herdr server stop >/dev/null 2>&1 || true
			sleep 1
		else
			log_info "Herdr server already running"
			return
		fi
	fi
	local cwd="${PWD:-$HOME}"
	[[ -d /workspace ]] && cwd="/workspace"
	log_info "Starting Herdr headless server in $cwd"
	(cd "$cwd" && nohup herdr server >>"$HOME/.config/herdr/server.log" 2>&1 &)
	sleep 1
	if herdr status 2>/dev/null | grep -A5 '^server:' | grep -Eq '^[[:space:]]*status: running$'; then
		log_success "Herdr server running (socket ~/.config/herdr/herdr.sock)"
	else
		log_warn "Herdr server may still be starting; check ~/.config/herdr/server.log"
	fi
}

install_lazyvim_plugins() {
	export PATH="$HOME/.local/bin:$PATH"
	if ! command -v nvim >/dev/null 2>&1; then
		log_warn "nvim not on PATH; skipped LazyVim plugin sync"
		return
	fi
	if [[ ! -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
		log_warn "Neovim config not linked; skipped LazyVim plugin sync"
		return
	fi
	log_info "Installing LazyVim plugins (headless nvim)..."
	if GIT_TERMINAL_PROMPT=0 _run_with_timeout 600 nvim --headless "+Lazy! sync" +qa; then
		log_success "LazyVim plugins installed"
	else
		log_warn "LazyVim plugin sync failed or timed out; open nvim later to finish"
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

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--profile)
			DOTFILES_PROFILE="$2"
			shift 2
			;;
		--profile=*)
			DOTFILES_PROFILE="${1#*=}"
			shift
			;;
		*)
			log_error "Unknown argument: $1"
			exit 1
			;;
		esac
	done

	resolve_dotfiles_dir
	PACKAGES_CONF="$DOTFILES_DIR/packages.conf"

	if [[ -z "$DOTFILES_PROFILE" ]]; then
		if is_cloud_workspace; then
			DOTFILES_PROFILE="cws"
		else
			DOTFILES_PROFILE="laptop"
		fi
	fi
	log_info "Profile: $DOTFILES_PROFILE (DOTFILES_DIR=$DOTFILES_DIR)"

	if [[ ! -d "$DOTFILES_DIR" ]]; then
		log_error "Dotfiles directory not found at $DOTFILES_DIR"
		exit 1
	fi

	export PATH="$HOME/.local/bin:$PATH"

	# CWS default .bashrc sources ~/.bash_aliases; never overwrite .bashrc/.profile/.gitconfig.
	if [[ -f "$DOTFILES_DIR/.bash_aliases" ]]; then
		create_symlink "$DOTFILES_DIR/.bash_aliases" "$HOME/.bash_aliases"
	fi

	log_info "Setting up Neovim configuration..."
	mkdir -p "$HOME/.config"
	create_symlink "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"

	log_info "Setting up Zsh configuration..."
	create_symlink "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
	create_symlink "$DOTFILES_DIR/zsh/zshenv" "$HOME/.zshenv"

	if [[ "$DOTFILES_PROFILE" == "cws" ]] && command -v zsh >/dev/null 2>&1 && command -v chsh >/dev/null 2>&1; then
		chsh -s "$(command -v zsh)" >/dev/null 2>&1 \
			&& log_success "Default shell set to zsh" \
			|| log_info "Could not chsh; interactive bash will exec zsh via ~/.bash_aliases"
	fi

	log_info "Setting up ImageMagick font map (image.nvim identify)..."
	mkdir -p "$HOME/.config/ImageMagick"
	create_symlink "$DOTFILES_DIR/imagemagick/type.xml" "$HOME/.config/ImageMagick/type.xml"

	log_info "Setting up Lazygit configuration..."
	local lazygit_conf_dir
	if [[ "$(uname)" == "Darwin" ]]; then
		lazygit_conf_dir="$HOME/Library/Application Support/lazygit"
	else
		lazygit_conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit"
	fi
	mkdir -p "$lazygit_conf_dir"
	create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$lazygit_conf_dir/config.yml"

	log_info "Setting up Zsh plugins..."
	install_zsh_plugins

	log_info "Installing CLI tools..."
	install_packages cli

	log_info "Installing cloud tools..."
	install_packages cloud

	log_info "Installing Rust toolchain..."
	install_rust

	log_info "Setting up Herdr configuration..."
	if command -v npm >/dev/null 2>&1; then
		if command -v pi >/dev/null 2>&1 || npm install -g --ignore-scripts @earendil-works/pi-coding-agent; then
			log_success "Configured Pi coding agent"
		else
			log_warn "Could not install Pi coding agent"
		fi
	fi
	# The desktop app bundles Codex outside normal shell PATH. Expose it through
	# ~/.local/bin so Herdr panes can start and resume Codex sessions.
	if [[ -x "/Applications/ChatGPT.app/Contents/Resources/codex" ]]; then
		create_symlink "/Applications/ChatGPT.app/Contents/Resources/codex" "$HOME/.local/bin/codex"
		if [[ -x "/Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host" ]]; then
			create_symlink "/Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host" "$HOME/.local/bin/codex-code-mode-host"
		fi
		log_success "Configured Codex CLI for Herdr shells"
	fi
	# Herdr resolves the supported `opencode` kind through PATH. Keep regular
	# OpenCode's database separate from OpenCode2's incompatible schema.
	if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
		chmod +x "$DOTFILES_DIR/opencode/opencode"
		create_symlink "$DOTFILES_DIR/opencode/opencode" "$HOME/.local/bin/opencode"
		mkdir -p "$HOME/.local/share/opencode-v1/opencode"
		if [[ -f "$HOME/.local/share/opencode/auth.json" && ! -e "$HOME/.local/share/opencode-v1/opencode/auth.json" ]]; then
			create_symlink "$HOME/.local/share/opencode/auth.json" "$HOME/.local/share/opencode-v1/opencode/auth.json"
		fi
		log_success "Configured Herdr OpenCode launches"
	else
		log_warn "OpenCode not found at ~/.opencode/bin/opencode; Herdr OpenCode launches may be unavailable"
	fi
	mkdir -p "$HOME/.config/herdr"
	create_symlink "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"
	if is_cloud_workspace && [[ -d /workspace ]]; then
		rm -f "$HOME/.config/herdr/config.toml"
		cp "$DOTFILES_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"
		# Base config already has [ui] copy_on_select = false; do not append a second
		# [ui] table — herdr rejects duplicate table headers on reload-config.
		printf '\n# CWS: new panes start in the workspace mount, not $HOME.\nnew_cwd = "/workspace"\n' >>"$HOME/.config/herdr/config.toml"
	fi
	if command -v herdr >/dev/null 2>&1; then
		mkdir -p "$HOME/.pi/agent/extensions"
		if herdr integration install pi >/dev/null 2>&1; then
			log_success "Installed current Herdr integration for Pi"
		else
			log_warn "Could not install the Herdr Pi integration"
		fi
		if herdr integration install opencode >/dev/null 2>&1; then
			log_success "Installed current Herdr integration for OpenCode"
		else
			log_warn "Could not install the Herdr OpenCode integration"
		fi
		if herdr integration install codex >/dev/null 2>&1; then
			log_success "Installed current Herdr integration for Codex"
		else
			log_warn "Could not install the Herdr Codex integration"
		fi

		local herdr_nav_dir="$DOTFILES_DIR/herdr/nvim-nav"
		if [[ -d "$herdr_nav_dir" ]]; then
			if (cd "$herdr_nav_dir" && make >/dev/null 2>&1); then
				herdr plugin uninstall herdr-nvim-nav >/dev/null 2>&1 || true
				if herdr plugin link "$herdr_nav_dir" >/dev/null 2>&1; then
					log_success "Linked herdr-nvim-nav (fast Alt+hjkl)"
				else
					log_warn "Could not link herdr-nvim-nav; Alt pane navigation may be slow or unavailable"
				fi
			else
				log_warn "Could not build herdr-nvim-nav (need cc); Alt pane navigation may be unavailable"
			fi
		fi

		local herdr_minimap_dir="$DOTFILES_DIR/herdr/pane-minimap"
		if [[ -d "$herdr_minimap_dir" ]]; then
			if (cd "$herdr_minimap_dir" && bash build.sh >/dev/null 2>&1); then
				herdr plugin uninstall herdr-pane-minimap >/dev/null 2>&1 || true
				if herdr plugin link "$herdr_minimap_dir" >/dev/null 2>&1; then
					log_success "Linked herdr-pane-minimap (sidebar layout map)"
				else
					log_warn "Could not link herdr-pane-minimap; sidebar layout map unavailable"
				fi
			else
				log_warn "Could not build herdr-pane-minimap (need cargo); sidebar layout map unavailable"
			fi
		fi

		local herdr_titles_dir="$DOTFILES_DIR/herdr/session-titles"
		if [[ -d "$herdr_titles_dir" ]]; then
			herdr plugin uninstall herdr-session-titles >/dev/null 2>&1 || true
			if herdr plugin link "$herdr_titles_dir" >/dev/null 2>&1; then
				log_success "Linked herdr-session-titles (prefix+g agent session names)"
			else
				log_warn "Could not link herdr-session-titles; prefix+g will keep showing agent kinds"
			fi
		fi

		local herdr_splits_ref="107273e004e4f7ef07f13c83164d2cb2c51df65d"
		local herdr_splits_state
		herdr_splits_state="$(herdr plugin list --plugin herdr-splits --json 2>/dev/null || true)"
		if grep -Eq '"plugin_id"[[:space:]]*:[[:space:]]*"herdr-splits"' <<<"$herdr_splits_state" \
			&& grep -Eq '"resolved_commit"[[:space:]]*:[[:space:]]*"'"$herdr_splits_ref"'"' <<<"$herdr_splits_state"; then
			log_info "Herdr splits plugin already installed at $herdr_splits_ref"
		elif herdr plugin install lmilojevicc/herdr-splits.nvim \
			--ref "$herdr_splits_ref" --yes; then
			log_success "Installed Herdr splits plugin (Ctrl resize)"
		else
			log_warn "Could not install Herdr splits plugin; Ctrl pane resize bindings remain unavailable"
		fi
		local herdr_splits_conf_dir
		herdr_splits_conf_dir="$(herdr plugin config-dir herdr-splits 2>/dev/null || true)"
		if [[ -n "$herdr_splits_conf_dir" && -f "$DOTFILES_DIR/herdr/herdr-splits.conf" ]]; then
			mkdir -p "$herdr_splits_conf_dir"
			cp "$DOTFILES_DIR/herdr/herdr-splits.conf" "$herdr_splits_conf_dir/herdr-splits.conf"
			log_info "Seeded herdr-splits.conf (Ctrl=resize)"
		fi

		local herdr_agents_ref="74f8550a1008156f811b0bc8663ac251d9f3fcd6"
		local herdr_annotate_ref="5d94eadfed96e4064b692718cef143afeb0931d3"
		install_herdr_github_plugin dleen.herdr-agents dleen/herdr-agents \
			"$herdr_agents_ref" \
			"Installed Herdr agents picker" \
			"Could not install dleen/herdr-agents; prefix+a picker unavailable" || true
		patch_herdr_agents || true
		# Prior bootstraps installed the Chrome presenter. Drop it.
		herdr plugin uninstall official.plannotator >/dev/null 2>&1 || true
		herdr plugin uninstall official.browser >/dev/null 2>&1 || true
		install_herdr_github_plugin annotate plannotator/herdr-annotate \
			"$herdr_annotate_ref" \
			"Installed Herdr Annotate (plannotator-tui)" \
			"Could not install plannotator/herdr-annotate" || true
		patch_herdr_annotate || true
	else
		log_warn "Herdr is not installed; skipped Herdr pane-navigation plugins"
	fi

	if [[ "$DOTFILES_PROFILE" == "cws" ]]; then
		start_herdr_server
		log_info "Configuring MCP OAuth port forwards for Cursor/VS Code..."
		merge_cws_ide_machine_settings
	else
		log_info "Setting up CWS MCP OAuth SSH forwards..."
		ensure_cws_mcp_ssh_forwards
		merge_laptop_cursor_forward_settings

		log_info "Setting up Ghostty configuration..."
		mkdir -p "$HOME/.config/ghostty"
		create_symlink "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"

		log_info "Setting up skhd configuration..."
		mkdir -p "$HOME/.config/skhd"
		create_symlink "$DOTFILES_DIR/skhd/skhdrc" "$HOME/.config/skhd/skhdrc"
		create_symlink "$DOTFILES_DIR/skhd/skhdrc" "$HOME/.skhdrc"

		log_info "Installing window management tools..."
		install_packages wm

		log_info "Installing container tools..."
		install_packages container
	fi

	log_info "Setting up AI Agents configuration..."
	setup_ai_agents

	log_info "Installing LazyVim plugins..."
	install_lazyvim_plugins

	echo ""
	echo "========================================"
	log_success "Bootstrap complete!"
	echo "========================================"
	echo ""
	log_info "Next steps:"
	echo "  1. Restart your shell or run: source ~/.zshrc"
	echo "  2. nvim plugins were synced during bootstrap (open nvim if a plugin is still missing)"
	if [[ "$DOTFILES_PROFILE" == "cws" ]]; then
		echo "  3. On your laptop: cws login && cws config-ssh"
		echo "  4. Attach Herdr: herdr --remote coder@cws.<workspace-name>"
	else
		echo "  3. Start a new herdr session"
		echo "  4. If you edit ai-agent rules, run: cd ~/.dotfiles/ai-agents && npx rulesync generate"
	fi
	echo ""

	if [[ -d "$BACKUP_DIR" ]]; then
		log_warn "Backups saved to: $BACKUP_DIR"
	fi
}

main "$@"
