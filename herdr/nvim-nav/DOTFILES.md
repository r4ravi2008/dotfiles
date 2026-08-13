# herdr-nvim-nav (dotfiles fork)

Vendored from [aimdevlee/herdr-nvim-nav](https://github.com/aimdevlee/herdr-nvim-nav)
at the commit in `UPSTREAM_COMMIT`.

## Why a fork?

Upstream forwards `ctrl+h/j/k/l` into Neovim. This repo uses tilish-style
`alt+h/j/k/l` for navigation and `ctrl+h/j/k/l` for resize, so the C action and
Neovim defaults are patched to Alt.

The C socket path is ~10ms per keypress vs ~300ms for `herdr-splits`' bash
scripts that fork the `herdr` CLI several times.

## Bootstrap

`bootstrap.sh` runs `make` and `herdr plugin link` on this directory.
