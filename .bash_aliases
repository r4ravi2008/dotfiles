# Sourced by Cloud Workspaces default ~/.bashrc (do not replace .bashrc/.profile).
# https://devportal.intuit.com docs: developing/workspace-customization-dotfiles.md

export PATH="$HOME/.local/bin:$PATH"

# Safe extras only. CWS owns credential.helper / insteadOf / useHttpPath.
if command -v git >/dev/null 2>&1; then
	git config --global core.editor nvim 2>/dev/null || true
	git config --global push.default current 2>/dev/null || true
fi

# Interactive shells: use zsh when present. Set CWS_KEEP_BASH=1 to stay on bash.
if [ -n "${PS1-}" ] && [ -z "${ZSH_VERSION-}" ] && [ "${CWS_KEEP_BASH:-}" != "1" ]; then
	case $- in
	*i*)
		if command -v zsh >/dev/null 2>&1; then
			exec zsh
		fi
		;;
	esac
fi
