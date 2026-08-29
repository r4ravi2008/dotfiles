# Herdr Pane Minimap HUD Design

**Date:** 2026-08-28  
**Status:** Approved for implementation planning  
**Repo:** `~/.dotfiles`

## Problem

In tmux, a Rust helper (`tmux/pane-minimap-rs`) draws a short-lived layout map when switching panes while zoomed. That map is the right idea: stay zoomed, still see where you are in the split tree. The delivery is wrong for Herdr. Tmux `display-popup` steals the client, freezes the pane under the popup, and flashes for 0.15s. Navigation (Alt+hjkl) must stay on the zoomed pane. The map is a representation only.

Herdr can draw Kitty-graphics layers on a pane without taking keys. `pane.layout` still returns every pane rect when the tab is zoomed. That is the VS Code minimap analog: a small always-on map in the corner of what you are looking at.

## Goals

1. Always-on pane layout HUD in the top-right of the focused Herdr pane when the current tab has two or more panes.
2. Same spatial meaning as the tmux minimap: scale the **unzoomed** layout, highlight the focused pane, so zoom does not erase mental layout.
3. Do not handle Alt+hjkl or any other navigation. `herdr-nvim-nav` stays the navigator.
4. Leave the tmux popup HUD unchanged.

## Non-goals

- Changing `tmux/tmux.conf.local`, `tmux/pane-minimap`, or `tmux/pane-minimap-rs` behavior.
- Neovim inner-split overlays (`/tmp/nvim_layout_*`). v1 is Herdr panes only.
- Plugin popup, overlay, or split placement for the map (those steal focus or change layout).
- A toggle keybinding (can add later; v1 is always-on whenever hide rules do not apply).
- Sharing a crate with the tmux binary. Port the scale math; do not parse `#{window_layout}`.
- Supervising the watcher via Herdr plugin command slots (startup must exit).

## Architecture

A linked local plugin `herdr/pane-minimap/` (same bootstrap pattern as `herdr-nvim-nav`).

1. Bootstrap builds the release binary and `herdr plugin link`s the directory.
2. Plugin `[[startup]]` is a short argv command: kill the previous watcher if the pidfile is ours, start `herdr-pane-minimap watch` detached (`nohup`), write the new pid, exit.
3. The watcher opens `HERDR_SOCKET_PATH`, calls `pane.layout` once for the focused tab, then `events.subscribe` for `layout.updated`, `tab.focused`, and `workspace.focused`.
4. On each relevant event it renders a PNG of the unzoomed layout and `pane.graphics.set`s it on the **visible** focused pane, layer id `minimap`. It `pane.graphics.clear`s the previous pane when focus moves.
5. Graphics sit in the top-right of that pane’s **visible** rectangle (full `area` when zoomed; focused pane `rect` when not). Keys still go to the PTY.

`layout.updated` cannot be a manifest `[[events]]` hook (Herdr excludes it as high-volume). The socket subscriber is required so zoom-without-focus-change still refreshes the highlight.

## Components

| Unit | Responsibility |
|---|---|
| `herdr/pane-minimap/src/layout.rs` | `PaneLayoutSnapshot` types, hide rules, scale math, HUD grid placement |
| `herdr/pane-minimap/src/render.rs` | Draw boxes + focused fill into RGBA, encode PNG |
| `herdr/pane-minimap/src/herdr.rs` | Unix-socket JSON-RPC: layout, graphics info/set/clear, event subscribe |
| `herdr/pane-minimap/src/main.rs` | `watch`: pidfile, subscribe loop, apply/clear |
| `herdr/pane-minimap/herdr-plugin.toml` | id, startup, platforms, min version, build |
| `bootstrap.sh` | cargo build + `herdr plugin link` after nvim-nav |
| `.gitignore` | `herdr/pane-minimap/target/` |
| Docs | README, AGENTS.md, CWS reference row |

Plugin id: `herdr-pane-minimap`. Binary name: `herdr-pane-minimap`. Layer id: `minimap`. `z_index`: `10`. `min_herdr_version`: `0.8.0`.

## Mapping (tmux → Herdr)

The tmux tool:

1. Reads `#{window_layout}` and `list-panes`.
2. Collects each pane’s `(left, top, right, bottom)`.
3. Scales onto a 46×18 character canvas with integer `scaled_start` / `scaled_end`.
4. Paints the active pane with a brighter fill; labels `idx:cmd`.
5. Uses zoom only as a caption; geometry is always the full window.

The Herdr HUD:

1. Reads `PaneLayoutSnapshot` (`workspace_id`, `tab_id`, `zoomed`, `area`, `focused_pane_id`, `panes[].rect`).
2. Uses those rects as the unzoomed layout (API uses `tab.layout.panes(area)`, not the zoomed UI list).
3. Scales onto a pixel canvas sized `grid_cols * cell_width_px` by `grid_rows * cell_height_px`.
4. Highlights `focused_pane_id`. Labels the pane-id suffix after `:`, e.g. `p3` from `w1:p3`. No extra `pane.list` round trip in v1.
5. `zoomed` chooses **placement host size** (`area` vs focused `rect`), not which rects are drawn.

Integer scaling must match the tmux helper:

```text
scaled_start(v, min, canvas, span) = (v - min) * canvas / span
scaled_end(v, min, canvas, span)   = ((v - min) * canvas + span - 1) / span - 1
```

with `span = max(1, max_edge - min_edge)`.

## HUD placement

Default grid: **16 columns × 10 rows**. Margin: **1 column from the right, 1 row from the top**.

Visible host rectangle:

- If `zoomed`: `area.width` × `area.height`.
- Else: focused pane’s `rect.width` × `rect.height`.

Placement:

```text
viewport_col = host_width  - grid_cols - 1
viewport_row = 1
```

Clamp `viewport_col`/`viewport_row` to ≥ 0.

Hide (clear layer, do not set) when any of:

- Fewer than 2 panes in the snapshot.
- Host width < 8 or host height < 5 after trying to shrink.
- `pane.graphics.info` returns `feature_disabled` or `cell_size_unavailable`.
- `pane_visible` is false for the focused pane.

Shrink rule: if the default 16×10 plus margins does not fit, reduce `grid_cols` and `grid_rows` proportionally to fit `host - 2` in each axis, integer, minimum 8×5. Below that, hide.

Only the focused (visible) pane receives the layer. When zoomed, Herdr only allows graphics on that pane; attaching to a hidden pane is a no-op/error.

Ignore `layout.updated` snapshots whose `tab_id` is not the currently focused tab. On `tab.focused` / `workspace.focused`, record the new ids and request `pane.layout` for the focused pane.

Track `last_layer_pane_id`. On apply to a different pane, clear the old pane’s `minimap` layer first.

## Data flow

```text
startup (exits)
  -> nohup herdr-pane-minimap watch
       -> pane.layout (focused)
       -> events.subscribe [layout.updated, tab.focused, workspace.focused]
       -> on event:
            snapshot = event.layout or pane.layout
            if snapshot.tab not focused: return
            if hide: clear last layer; return
            png = render(snapshot, cell size)
            clear previous pane if changed
            pane.graphics.set focused_pane layer=minimap placement=top-right
```

`layout.updated` already includes `PaneLayoutSnapshot`. Prefer that payload over a second `pane.layout` call.

## Watcher lifecycle

Pidfile: `$HERDR_PLUGIN_STATE_DIR/watch.pid` (falls back to `$HOME/.config/herdr/plugin-state/herdr-pane-minimap/watch.pid` if env is missing, same directory Herdr would create).

Before start: if pidfile pid is alive and its command line contains `herdr-pane-minimap`, send SIGTERM, wait up to 1s, then SIGKILL if needed.

Log: append to `$HERDR_PLUGIN_STATE_DIR/watch.log`. Do not write pane contents.

On live Herdr handoff, startup runs again and replaces the watcher. The old socket is dead; the new process reconnects.

Do not register `layout.updated` in `[[events]]`. Do not leave the watcher as the startup process itself (occupies plugin in-flight slots).

## Error handling

| Failure | Behavior |
|---|---|
| `herdr` missing at bootstrap | Existing warn; skip this plugin too (same `if command -v herdr` block). |
| `cargo` missing / build fails | Warn; skip link. No HUD. |
| `plugin link` fails | Warn; continue. |
| Socket missing / server down | Watcher retries connect every 2s, no crash loop faster than that. |
| `feature_disabled` | Log once; stay idle until process restart (config reload of kitty_graphics needs a new client anyway). |
| `cell_size_unavailable` (no attached client yet) | Skip this frame; retry on next event. |
| Graphics set/clear error | Log; keep last successful layer. |
| Single-pane tab | Clear if a layer is showing. |
| Remote attach (`herdr --remote`) | Watcher runs on the server; graphics target the attached client. Same code path. |

## Look

Tokyo Night-adjacent, not a character-cell ASCII popup:

- Inactive: dark gray fill `#1a1b26`, dim border `#565f89`.
- Focused: blue fill `#3d59a1`, bright border `#7aa2f7`, label `#c0caf5`.
- 1px (or 1 cell-pixel) inner padding. Rounded corners are not required.

Opacity is whatever PNG on the Kitty layer does; do not require a separate alpha config in v1. Use opaque fills so the map stays readable over terminal noise.

## Testing

Unit tests in the crate (no live Herdr):

1. Scale: a 238-wide span onto canvas 46 matches the tmux tests (`scaled_start(0)=0`, `scaled_end(238)=45`).
2. Hide when `panes.len() < 2`.
3. Placement: zoomed uses `area`; unzoomed uses focused rect; top-right math as specified.
4. Shrink then hide below 8×5.
5. PNG encoder produces a buffer starting with `89 50 4E 47`.

Manual (needs Herdr + Ghostty/Kitty + `kitty_graphics`):

1. Two-plus panes, not zoomed: map in focused pane top-right; Alt+hjkl still moves panes; highlight follows focus.
2. Zoom (`alt+z`): map stays; still shows the full layout with the zoomed pane highlighted; hopping with Alt+hjkl updates highlight without a popup.
3. One pane: map gone.
4. `herdr config check` still passes (no new keys).

## Documentation

- `README.md` bootstrap bullet: also builds/links `herdr-pane-minimap`.
- `AGENTS.md`: always-on Herdr pane HUD via Kitty graphics; tmux popup unchanged.
- `.agents/skills/creating-cws-from-devstack-fork/reference.md`: plugin linked; HUD visible when zoomed with ≥2 panes **or** documented skip (no cargo / no herdr).

## Constraints (verbatim)

- Always-on top-right HUD on the focused visible pane when the tab has ≥2 panes.
- Unzoomed layout geometry; highlight focused pane; zoom does not change which rects are drawn.
- Kitty `pane.graphics.set` layer `minimap`; no popup; no keybindings.
- Do not handle Alt+hjkl.
- Leave tmux minimap as-is.
- No Neovim inner splits in v1.
- Plugin lives under `herdr/pane-minimap/`; bootstrap cargo build + `herdr plugin link`.
- Startup detaches the watcher and exits; subscribe to socket `layout.updated` (not manifest hooks).
- `kitty_graphics` stays true (already set).
- Warn and continue on build/link failure; do not fail bootstrap.
