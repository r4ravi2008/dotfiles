# herdr-nvim-nav

Seamless `Ctrl+h/j/k/l` navigation across [herdr] panes and Neovim splits —
the [vim-tmux-navigator] experience, for herdr.

> **Neovim-only, socket-based, no per-keystroke process.** If you want **Vim**
> support too, or a plain shell implementation, see
> [Prior art](#prior-art) — that project takes a different approach.

Press `Ctrl+h/j/k/l` and the cursor moves to the split in that direction. When
you reach the edge of Neovim's splits, the same keystroke crosses into the
neighbouring herdr pane instead of stopping. It works the other way too: from a
plain pane, the chord moves herdr's focus; from a pane running Neovim, the chord
is handed to Neovim.

[herdr]: https://herdr.dev
[vim-tmux-navigator]: https://github.com/christoomey/vim-tmux-navigator

## How it works

tmux answers "is this pane Neovim?" with a pane option (`@pane-is-vim`) and a
conditional keybinding (`if -F`). herdr has neither, so this plugin reconstructs
the decision:

- **Neovim** writes its PID to a marker file named after the pane
  (`$XDG_CACHE_HOME/herdr/nvim-panes/<pane-id>`) on entry, and removes it on
  exit. A stale PID left by a crash is recognised (via `kill(pid, 0)`) and
  cleaned up.
- The **herdr action** (plugin id `herdr-nvim-nav`) reads that marker on each keystroke. If a live
  Neovim owns the focused pane, it forwards the chord over herdr's control
  socket (`pane.send_keys`); otherwise it moves herdr's pane focus
  (`pane.focus_direction`).

The action is a small C binary, not a shell script, on purpose. herdr must
fork/exec *something* per keystroke (~2.4 ms here); layering `sh` plus the herdr
CLI on top added ~8 ms for 0.3 ms of actual socket work. The C binary does that
work in the one process herdr already had to start. See the comment block at the
top of [`herdr-nvim-nav.c`](herdr-nvim-nav.c) for the measurements.

## Requirements

- **herdr** ≥ 0.7.0
- **Neovim** (0.9+ recommended, for `vim.uv`)
- A C compiler (`cc` / `clang` / `gcc`) — used by the install-time build. GitHub
  `herdr plugin install` runs it for you; only a local `plugin link` needs it on hand.
- **christoomey/vim-tmux-navigator** — only if you run Neovim under tmux
  (`with_tmux`); herdr-only setups don't need it.
- macOS or Linux

## Install

### 1. Install the herdr action

**From GitHub (recommended):**

```sh
herdr plugin install aimdevlee/herdr-nvim-nav
```

The manifest's `[[build]]` command compiles the C binary during install, so
there's no separate build step. Pin a version with `--ref <tag|sha>`.

**From a local checkout** (for development):

```sh
git clone https://github.com/aimdevlee/herdr-nvim-nav
cd herdr-nvim-nav
make                                  # produces ./herdr-nvim-nav
herdr plugin link "$PWD"              # link — build commands are NOT run
```

`herdr plugin link` skips `[[build]]`, so build with `make` yourself first, and
rebuild after any `git pull` that touches `herdr-nvim-nav.c`. The compiled
binary is a build artifact and is not committed. `herdr server reload-config`
re-reads `config.toml`, not plugin manifests.

### 2. Bind the keys in herdr

In `~/.config/herdr/config.toml`, bind the four directions to the plugin
actions:

```toml
[[keys.command]]
key = "ctrl+h"
type = "plugin_action"
command = "herdr-nvim-nav.left"

[[keys.command]]
key = "ctrl+j"
type = "plugin_action"
command = "herdr-nvim-nav.down"

[[keys.command]]
key = "ctrl+k"
type = "plugin_action"
command = "herdr-nvim-nav.up"

[[keys.command]]
key = "ctrl+l"
type = "plugin_action"
command = "herdr-nvim-nav.right"
```

Then reload: `herdr server reload-config`.

### 3. Install the Neovim half

The Neovim side is a plugin-manager-agnostic module
([`lua/herdr-nvim-nav/init.lua`](lua/herdr-nvim-nav/init.lua)). Install it like
any Neovim plugin and call `setup()`. It maintains the pane marker the herdr
action reads, and maps `<C-h/j/k/l>` (plus the arrow variants) to move within
Neovim's splits, falling through to herdr — or to tmux when running under tmux.

**lazy.nvim:**

```lua
{
  'aimdevlee/herdr-nvim-nav',
  dependencies = { 'christoomey/vim-tmux-navigator' }, -- omit if with_tmux = false
  config = function()
    require('herdr-nvim-nav').setup()
  end,
}
```

**packer:**

```lua
use {
  'aimdevlee/herdr-nvim-nav',
  requires = { 'christoomey/vim-tmux-navigator' }, -- omit if with_tmux = false
  config = function() require('herdr-nvim-nav').setup() end,
}
```

**Manual** (any runtimepath): drop `lua/herdr-nvim-nav/` on your runtimepath and
`require('herdr-nvim-nav').setup{ with_tmux = false }` from your init.

#### tmux fallback

`christoomey/vim-tmux-navigator` is used **only** when Neovim runs under tmux
(not herdr). `with_tmux` is auto-detected from `$TMUX`, so tmux users need no
config. If you never run Neovim under tmux, drop the dependency and set
`with_tmux = false` — nothing tmux-related is loaded.

#### Options

```lua
require('herdr-nvim-nav').setup({
  with_tmux = nil,          -- nil = auto-detect $TMUX; true/false to force
  keymaps = {               -- lhs list per direction; {} disables a direction
    left  = { '<C-h>', '<C-Left>' },
    down  = { '<C-j>', '<C-Down>' },
    up    = { '<C-k>', '<C-Up>' },
    right = { '<C-l>', '<C-Right>' },
  },
  socket_path = nil,        -- default: $HERDR_SOCKET_PATH or ~/.config/herdr/herdr.sock
  cache_dir = nil,          -- default: $XDG_CACHE_HOME or ~/.cache
  herdr_bin = nil,          -- default: $HERDR_BIN_PATH or "herdr"
  socket_timeout_ms = 150,
})
```

## Configuration

Both halves honour these environment variables. The Neovim half also takes the
matching `setup()` options above, which win over the environment when set; the C
action reads the environment only.

| Variable | `setup()` option | Used by | Default |
| --- | --- | --- | --- |
| `HERDR_SOCKET_PATH` | `socket_path` | C, lua | `~/.config/herdr/herdr.sock` |
| `XDG_CACHE_HOME` | `cache_dir` | C, lua | `~/.cache` (marker directory root) |
| `HERDR_BIN_PATH` | `herdr_bin` | lua | `herdr` on `$PATH` (CLI fallback) |
| `HERDR_PANE_ID` | — | C, lua | set by herdr per pane |

## Troubleshooting

- **Keys move panes but never reach Neovim.** The marker isn't being written —
  confirm `require('herdr-nvim-nav').setup()` ran and that `HERDR_PANE_ID` is set in the pane
  (`echo $HERDR_PANE_ID`). Check that `$XDG_CACHE_HOME/herdr/nvim-panes/` gets a
  file while Neovim is focused.
- **Nothing happens at all.** herdr records the action's stderr and exit code —
  see `herdr plugin log`. A rejected socket request is reported there.
- **Wrong herdr socket.** Set `HERDR_SOCKET_PATH` explicitly if your herdr
  socket isn't at the default path.

## Prior art

[**paulbkim-dev/vim-herdr-navigation**][prior] solves the same problem and came
first. It's worth using — and it does two things this project doesn't: it
supports **Vim** as well as Neovim, and its herdr side is a portable shell
script with no compile step.

This project makes different trade-offs on purpose:

| | vim-herdr-navigation | herdr-nvim-nav |
| --- | --- | --- |
| "Is this Vim?" check | herdr CLI `pane process-info` + `jq` on the foreground process | marker file Neovim maintains + `kill(pid,0)` |
| herdr side | `navigate.sh` (bash, needs `jq`) | `herdr-nvim-nav` (compiled C, no runtime deps) |
| herdr transport | CLI (`herdr pane …`) | control socket directly |
| Per-keystroke cost | herdr binary load + `jq` process | one process, direct socket (~3 ms) |
| Editors | Vim + Neovim | Neovim |

The short version: reach for **vim-herdr-navigation** if you use Vim or want to
avoid a compiler; reach for **this** if you're Neovim-only and want the chord to
cost as little as possible per press. The design rationale and measurements are
in the header of [`herdr-nvim-nav.c`](herdr-nvim-nav.c).

[prior]: https://github.com/paulbkim-dev/vim-herdr-navigation

## License

[MIT](LICENSE) © aimdevlee
