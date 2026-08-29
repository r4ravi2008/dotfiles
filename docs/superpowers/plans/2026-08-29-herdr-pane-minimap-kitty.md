# Herdr Pane Minimap Kitty Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Herdr Spaces sidebar ASCII minimap with a Kitty-graphics overlay (layer `minimap`, z_index 10) that matches tmux `pane-minimap` character-grid semantics, anchored top-left of the visible host pane.

**Architecture:** The existing `herdr/pane-minimap/` watcher keeps its Unix-socket subscribe loop but stops publishing `$minimap*` sidebar tokens. On each layout/focus event it refreshes via `pane.layout` with empty params, builds a 16×10 character grid using tmux-style `scaled_start`/`scaled_end` and interior-only fills with `+`/`-`/`|` borders, rasterizes that grid to PNG (one pixel block per character cell), and calls `pane.graphics.set` on the focused pane. Sidebar token rows are cleared so the Spaces column returns to its default two-row layout.

**Tech Stack:** Rust 2021 (`serde`, `serde_json`, `png`, `base64`), Herdr 0.8+ Unix socket RPC, Kitty graphics (`experimental.kitty_graphics = true`), bash `build.sh` / `startup.sh`.

## Global Constraints

- Visual reference: `tmux/pane-minimap-rs/src/main.rs` lines 696–798 (character grid, interior fill, perimeter borders). Do **not** port nvim inner-split overlays (`/tmp/nvim_layout_*`).
- Delivery: PNG via `pane.graphics.set`, layer `minimap`, `z_index` 10 (already in `herdr/pane-minimap/src/herdr.rs`).
- Placement: top-left of visible host — zoomed uses `area`; unzoomed uses focused pane `rect`. Default grid 16×10, margin 1 col / 1 row; shrink then hide below 8×5.
- Viewport anchor: **top-left** — `viewport_col = 1`, `viewport_row = 1` (change from current top-right in `layout.rs`).
- Hide when `<2` panes; clear graphics on all snapshot panes when hiding.
- Subscribe: `layout.updated`, `tab.focused`, `workspace.focused`, `pane.focused`. Socket events may use underscores (`pane_focused`, `layout_updated`); `matches_event` in `herdr.rs` already normalizes dots/underscores. Always refresh via `pane.layout()` with `{}` (UI-focused layout).
- Do not steal keys. Do not change tmux files. Do not run `herdr server stop`.
- `[experimental] kitty_graphics = true` already enabled in `herdr/config.toml`.
- On apply: CLEAR workspace minimap tokens (null all `minimap*` + `minimap_title`); REMOVE `[ui.sidebar.spaces]` extra minimap rows from `herdr/config.toml` (keep default `state_icon`/`workspace` and `branch`/`git_status` rows only).
- Time-based `seq` in `main.rs` for metadata reporting — keep when clearing tokens.
- Watcher must stay alive: `startup.sh` uses `nohup`; live verify must start watcher detached (agent shells kill process groups).
- Labels: pane-id suffix only (e.g. `p3` from `w1:p3`), drawn in pane interior with LABEL color.
- Every task below ends with **skip commit** (no git commits during execution).

## File map

| File | Change |
|---|---|
| `herdr/pane-minimap/src/layout.rs` | Top-left viewport; update/remove sidebar-only tests |
| `herdr/pane-minimap/src/render.rs` | Character-grid builder + cell-block PNG rasterizer |
| `herdr/pane-minimap/src/tokens.rs` | `cleared_minimap_tokens()` (moved from `ascii.rs`) |
| `herdr/pane-minimap/src/lib.rs` | Export `tokens`; stop exporting `ascii` (or delete `ascii.rs`) |
| `herdr/pane-minimap/src/main.rs` | `graphics_set` apply path; stop `sidebar_tokens`; always clear tokens |
| `herdr/pane-minimap/src/herdr.rs` | Unchanged RPC; existing subscribe tests stay |
| `herdr/pane-minimap/src/ascii.rs` | Delete after Task 2/3 (or leave dead code removed from `lib.rs`) |
| `herdr/config.toml` | Remove minimap sidebar rows; comment HUD is Kitty overlay |
| `herdr/pane-minimap/herdr-plugin.toml` | Update description |
| `AGENTS.md`, `README.md` | One-line sidebar → Kitty overlay wording |

---

### Task 1: Top-left HUD placement

**Files:**
- Modify: `herdr/pane-minimap/src/layout.rs:77-94` (`placement` viewport math)
- Modify: `herdr/pane-minimap/src/layout.rs:162-213` (existing placement tests)
- Test: `herdr/pane-minimap/src/layout.rs` (`layout::tests`)

**Interfaces:**
- Consumes: existing `placement(host_w, host_h) -> Option<HudPlacement>`
- Produces: `HudPlacement { viewport_col: 1, viewport_row: 1, ... }` for hosts that fit the grid

- [ ] **Step 1: Write the failing test**

Add to `herdr/pane-minimap/src/layout.rs` inside `mod tests`:

```rust
#[test]
fn placement_anchors_top_left_with_one_cell_margin() {
    let place = placement(120, 40).expect("host fits default grid");
    assert_eq!(place.viewport_col, 1);
    assert_eq!(place.viewport_row, 1);
    assert_eq!(place.grid_cols, 16);
    assert_eq!(place.grid_rows, 10);
}
```

Update `zoomed_placement_uses_area` expected viewport:

```rust
assert_eq!(place.viewport_col, 1);
assert_eq!(place.viewport_row, 1);
```

Update `unzoomed_placement_uses_focused_rect` expected viewport:

```rust
assert_eq!(place.viewport_col, 1);
assert_eq!(place.viewport_row, 1);
```

Remove or rewrite `sidebar_still_shows_when_focused_host_too_small_for_overlay` — sidebar HUD is gone; replace with:

```rust
#[test]
fn hides_overlay_when_focused_host_too_small() {
    let area = Rect { x: 0, y: 0, width: 80, height: 24 };
    let left = Rect { x: 0, y: 0, width: 40, height: 24 };
    let right = Rect { x: 40, y: 0, width: 9, height: 6 };
    let snap = two_pane(false, area, left, right);
    assert!(should_hide(&snap));
}
```

Remove `should_hide_sidebar` and its test-only usages from `layout.rs` (function at lines 56–59).

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib layout::tests::placement_anchors_top_left_with_one_cell_margin layout::tests::zoomed_placement_uses_area layout::tests::unzoomed_placement_uses_focused_rect -q
```

Expected: FAIL — `placement_anchors_top_left_with_one_cell_margin` assertion `left: 1, right: 103` (current top-right `viewport_col = 103` for 120-wide host).

- [ ] **Step 3: Implement top-left placement**

In `herdr/pane-minimap/src/layout.rs`, replace the viewport lines inside `placement`:

```rust
let viewport_col = 1_u16;
let viewport_row = 1_u16;
```

Delete `should_hide_sidebar` entirely.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib layout::tests -q
```

Expected: PASS — all `layout::tests` green (including updated zoomed/unzoomed cases).

- [ ] **Step 5: skip commit**

---

### Task 2: Character-grid tmux-style renderer and PNG rasterizer

**Files:**
- Modify: `herdr/pane-minimap/src/render.rs` (rewrite)
- Test: `herdr/pane-minimap/src/render.rs` (`render::tests`)

**Interfaces:**
- Consumes: `layout::{Snapshot, scaled_start, scaled_end, pane_label}`
- Produces:
  - `pub struct GridCell { pub ch: char, pub active: bool, pub is_border: bool, pub is_label: bool }`
  - `pub fn character_grid(snapshot: &Snapshot, grid_cols: u16, grid_rows: u16) -> Vec<Vec<GridCell>>`
  - `pub fn png_for_snapshot(snapshot: &Snapshot, cell_width_px: u32, cell_height_px: u32, grid_cols: u16, grid_rows: u16) -> Vec<u8>` — builds grid then stamps each cell as a `cell_width_px × cell_height_px` RGBA block

- [ ] **Step 1: Write the failing tests**

Replace the test module in `herdr/pane-minimap/src/render.rs` with:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::{Pane, Rect, Snapshot};

    fn two_pane_horizontal(focused: &str) -> Snapshot {
        Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect { x: 0, y: 0, width: 80, height: 24 },
            focused_pane_id: focused.into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: focused == "w1:p1",
                    rect: Rect { x: 0, y: 0, width: 40, height: 24 },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: focused == "w1:p2",
                    rect: Rect { x: 40, y: 0, width: 40, height: 24 },
                },
            ],
        }
    }

    fn pane_map_bounds(grid: &[Vec<GridCell>], pane_active: bool) -> Option<(usize, usize, usize, usize)> {
        let mut min_x = grid[0].len();
        let mut min_y = grid.len();
        let mut max_x = 0;
        let mut max_y = 0;
        let mut found = false;
        for (y, row) in grid.iter().enumerate() {
            for (x, cell) in row.iter().enumerate() {
                if cell.is_border && cell.active == pane_active {
                    found = true;
                    min_x = min_x.min(x);
                    min_y = min_y.min(y);
                    max_x = max_x.max(x);
                    max_y = max_y.max(y);
                }
            }
        }
        if found {
            Some((min_x, min_y, max_x, max_y))
        } else {
            None
        }
    }

    fn interior_fill_cells(grid: &[Vec<GridCell>], left: usize, top: usize, right: usize, bottom: usize, active: bool) -> usize {
        let mut count = 0;
        for y in (top + 1)..bottom {
            for x in (left + 1)..right {
                let cell = &grid[y][x];
                if !cell.is_border && !cell.is_label && cell.active == active && cell.ch == ' ' {
                    count += 1;
                }
            }
        }
        count
    }

    #[test]
    fn two_pane_side_by_side_active_interior_and_shared_border() {
        let snap = two_pane_horizontal("w1:p2");
        let grid = character_grid(&snap, 16, 10);
        assert_eq!(grid.len(), 10);
        assert_eq!(grid[0].len(), 16);

        let inactive = pane_map_bounds(&grid, false).expect("inactive pane border");
        let active = pane_map_bounds(&grid, true).expect("active pane border");
        assert!(active.0 > inactive.2 - 1, "panes should abut horizontally");

        let active_fills = interior_fill_cells(&grid, active.0, active.1, active.2, active.3, true);
        assert!(active_fills >= 1, "focused pane must have interior fill cells");

        let inactive_fills = interior_fill_cells(&grid, inactive.0, inactive.1, inactive.2, inactive.3, false);
        assert!(inactive_fills >= 1, "inactive pane must have interior fill cells");

        // Perimeter uses tmux border chars
        assert_eq!(grid[active.1][active.0].ch, '+');
        assert_eq!(grid[active.1][active.2].ch, '+');
        assert!(grid[active.1][(active.0 + active.2) / 2].ch == '-');
        assert!(grid[(active.1 + active.3) / 2][active.0].ch == '|');
    }

    #[test]
    fn four_by_three_map_cells_has_interior_fill() {
        // One pane occupies ~half width → ~8 cols; use tall narrow layout so one pane is ~4x3 cells.
        let snap = Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect { x: 0, y: 0, width: 80, height: 24 },
            focused_pane_id: "w1:p2".into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: false,
                    rect: Rect { x: 0, y: 0, width: 60, height: 24 },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: true,
                    rect: Rect { x: 60, y: 0, width: 20, height: 24 },
                },
            ],
        };
        let grid = character_grid(&snap, 16, 10);
        let active = pane_map_bounds(&grid, true).expect("active bounds");
        let width_cells = active.2 - active.0 + 1;
        let height_cells = active.3 - active.1 + 1;
        assert!(width_cells >= 3 && height_cells >= 2, "pane maps to at least 3x2 cells, got {width_cells}x{height_cells}");
        let fills = interior_fill_cells(&grid, active.0, active.1, active.2, active.3, true);
        assert!(fills >= 1, "4x3-class pane must have >=1 interior fill cell");
    }

    #[test]
    fn png_stamps_cell_blocks_with_expected_dimensions() {
        let snap = two_pane_horizontal("w1:p2");
        let png = png_for_snapshot(&snap, 8, 16, 16, 10);
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
        // PNG header encodes width=128 height=160 (16*8 x 10*16)
        assert_eq!(png[16], 0); // IHDR width byte 1 (128 = 0x0080)
        assert_eq!(png[20], 0); // IHDR height byte 1 (160 = 0x00A0)
    }

    #[test]
    fn encodes_png_signature() {
        let snap = two_pane_horizontal("w1:p2");
        let png = png_for_snapshot(&snap, 8, 16, 16, 10);
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
    }
}
```

Add stub at top of `render.rs` so tests compile-fail on behavior, not missing symbols:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GridCell {
    pub ch: char,
    pub active: bool,
    pub is_border: bool,
    pub is_label: bool,
}

pub fn character_grid(_snapshot: &Snapshot, _grid_cols: u16, _grid_rows: u16) -> Vec<Vec<GridCell>> {
    vec![]
}

pub fn png_for_snapshot(
    snapshot: &Snapshot,
    cell_width_px: u32,
    cell_height_px: u32,
    grid_cols: u16,
    grid_rows: u16,
) -> Vec<u8> {
    let _ = character_grid(snapshot, grid_cols, grid_rows);
    let _ = (cell_width_px, cell_height_px);
    vec![]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib render::tests::two_pane_side_by_side_active_interior_and_shared_border -q
```

Expected: FAIL — `panicked at 'inactive pane border'` or `assertion failed: active_fills >= 1` because stub returns empty grid.

- [ ] **Step 3: Implement character grid (tmux semantics)**

Rewrite `herdr/pane-minimap/src/render.rs` core logic:

1. Initialize `grid` as `grid_rows × grid_cols` of empty `GridCell { ch: ' ', active: false, is_border: false, is_label: false }`.
2. Compute `min_left`, `min_top`, `max_right`, `max_bottom`, `span_x`, `span_y` from snapshot panes (same as today).
3. Sort panes with focused last (draw on top).
4. For each pane, compute tmux bounds on the **character grid** (not pixels):

```rust
let left = clamp(scaled_start(left_px, min_left, grid_cols as i32, span_x), 0, grid_cols as i32 - 1);
let right = clamp(scaled_end(right_px, min_left, grid_cols as i32, span_x), left, grid_cols as i32 - 1);
let top = clamp(scaled_start(top_px, min_top, grid_rows as i32, span_y), 0, grid_rows as i32 - 1);
let bottom = clamp(scaled_end(bottom_px, min_top, grid_rows as i32, span_y), top, grid_rows as i32 - 1);
```

5. Draw borders exactly like tmux (lines 732–744 reference):
   - Horizontals: `for x in (left + 1)..right { grid[top][x] = border; grid[bottom][x] = border }` with `ch='-'`, `is_border=true`
   - Verticals: `for y in (top + 1)..bottom { grid[y][left] = border; grid[y][right] = border }` with `ch='|'`
   - Corners: `'+'` at `(left,top)`, `(right,top)`, `(left,bottom)`, `(right,bottom)`
6. Interior fill: `for y in (top+1)..bottom { for x in (left+1)..right { grid[y][x] = fill cell with ch=' ', is_border=false, active=pane.focused } }`
7. Label: `pane_label(&pane.pane_id)` centered in interior row `ly = top + 1 + inner_h/2`, `lx = left + 1 + (inner_w - label.len)/2`; set `is_label=true`, `active=pane.focused`, `ch` per char. Use pixel dots in PNG for labels if no bitmap; optional 3×5 bitmap for `0-9` and `p` is acceptable enhancement.

Colors (keep existing constants): `INACTIVE_FILL`, `INACTIVE_BORDER`, `ACTIVE_FILL`, `ACTIVE_BORDER`, `LABEL`, `BG`.

8. **PNG rasterizer:** For each grid cell `(gx, gy)`, fill pixel rectangle `[gx*cw .. (gx+1)*cw) × [gy*ch .. (gy+1)*ch)`:
   - Empty `' '`: `BG`
   - Border `'+'|'-'|'|'`: `ACTIVE_BORDER` or `INACTIVE_BORDER` by `cell.active`; draw glyph shape within block (horizontal bar, vertical bar, or cross at corners)
   - Interior fill `' '`: full block `ACTIVE_FILL` / `INACTIVE_FILL`
   - Label char: `LABEL` pixels (center dot or 3×5 glyph)

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib render::tests -q
```

Expected: PASS — all four render tests green.

- [ ] **Step 5: skip commit**

---

### Task 3: Watcher apply — Kitty overlay, clear sidebar tokens, hide rules

**Files:**
- Create: `herdr/pane-minimap/src/tokens.rs`
- Modify: `herdr/pane-minimap/src/lib.rs` — add `pub mod tokens;`, remove `pub mod ascii;`
- Modify: `herdr/pane-minimap/src/main.rs` — replace sidebar reporting with graphics + token clear
- Delete: `herdr/pane-minimap/src/ascii.rs` (after porting token clear helper)
- Test: `herdr/pane-minimap/src/tokens.rs`, `herdr/pane-minimap/src/herdr.rs` (subscribe test unchanged)

**Interfaces:**
- Consumes: `layout::{should_hide, placement_for, host_size}`, `render::png_for_snapshot`, `tokens::cleared_minimap_tokens`, `herdr::Client::{pane_layout, graphics_info, graphics_set, graphics_clear, workspace_report_tokens}`
- Produces: `apply()` that logs `set wN:pN col=1 row=1` on success; `hide` path clears all pane layers and nulls minimap tokens

- [ ] **Step 1: Write the failing tests**

Create `herdr/pane-minimap/src/tokens.rs`:

```rust
pub const TITLE_TOKEN: &str = "minimap_title";
pub const LINE_TOKEN_COUNT: usize = 6;

pub fn cleared_minimap_tokens() -> serde_json::Map<String, serde_json::Value> {
    let mut out = serde_json::Map::new();
    out.insert(TITLE_TOKEN.into(), serde_json::Value::Null);
    for i in 0..LINE_TOKEN_COUNT {
        out.insert(format!("minimap{i}"), serde_json::Value::Null);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleared_tokens_null_all_minimap_keys() {
        let tokens = cleared_minimap_tokens();
        assert_eq!(tokens.get(TITLE_TOKEN), Some(&serde_json::Value::Null));
        for i in 0..LINE_TOKEN_COUNT {
            assert_eq!(
                tokens.get(&format!("minimap{i}")),
                Some(&serde_json::Value::Null)
            );
        }
        assert_eq!(tokens.len(), LINE_TOKEN_COUNT + 1);
    }
}
```

Update `herdr/pane-minimap/src/lib.rs`:

```rust
pub mod herdr;
pub mod layout;
pub mod render;
pub mod tokens;
```

Add to `herdr/pane-minimap/src/main.rs` a small pure helper (testable from lib — move to `apply.rs` if preferred):

Create `herdr/pane-minimap/src/apply.rs`:

```rust
use crate::layout::{self, Snapshot};

#[derive(Debug, PartialEq, Eq)]
pub enum ApplyMode {
    Hide,
    Show,
}

pub fn apply_mode(snapshot: &Snapshot) -> ApplyMode {
    if layout::should_hide(snapshot) {
        ApplyMode::Hide
    } else {
        ApplyMode::Show
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::{Pane, Rect, Snapshot};

    #[test]
    fn hides_single_pane_tabs() {
        let snap = Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect { x: 0, y: 0, width: 80, height: 24 },
            focused_pane_id: "w1:p1".into(),
            panes: vec![Pane {
                pane_id: "w1:p1".into(),
                focused: true,
                rect: Rect { x: 0, y: 0, width: 80, height: 24 },
            }],
        };
        assert_eq!(apply_mode(&snap), ApplyMode::Hide);
    }

    #[test]
    fn shows_two_pane_tab_when_host_fits() {
        let snap = Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect { x: 0, y: 0, width: 80, height: 24 },
            focused_pane_id: "w1:p2".into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: false,
                    rect: Rect { x: 0, y: 0, width: 40, height: 24 },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: true,
                    rect: Rect { x: 40, y: 0, width: 40, height: 24 },
                },
            ],
        };
        assert_eq!(apply_mode(&snap), ApplyMode::Show);
    }
}
```

Add `pub mod apply;` to `lib.rs`.

Temporarily leave `main.rs` calling `ascii::sidebar_tokens` so `apply_mode` tests can be added without fixing main yet.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib tokens::tests::cleared_tokens_null_all_minimap_keys apply::tests -q
```

Expected: FAIL — module not found until files are created.

After creating stubs, re-run; `apply::tests` should PASS once implemented; if `main.rs` still imports `ascii`, compile may fail until Step 3.

- [ ] **Step 3: Rewrite `main.rs` apply path**

Replace `apply` in `herdr/pane-minimap/src/main.rs`:

```rust
use herdr_pane_minimap::apply::ApplyMode;
use herdr_pane_minimap::layout;
use herdr_pane_minimap::render::png_for_snapshot;
use herdr_pane_minimap::tokens::cleared_minimap_tokens;
// remove: use herdr_pane_minimap::ascii;
```

Core `apply` body:

```rust
fn apply(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    if snapshot.tab_id != state.focused_tab && !state.focused_tab.is_empty() {
        return;
    }
    state.focused_tab = snapshot.tab_id.clone();

    // Clear previous overlay host
    if let Some(old) = state.last_pane.take() {
        let _ = client.graphics_clear(&old);
    }
    for pane in &snapshot.panes {
        let _ = client.graphics_clear(&pane.pane_id);
    }

    // Always clear sidebar minimap tokens on the active workspace
    let cleared = cleared_minimap_tokens();
    if report_tokens(client, state, &snapshot.workspace_id, &cleared) {
        log_line(&format!(
            "cleared sidebar tokens on {}",
            snapshot.workspace_id
        ));
    }
    // Also clear when switching away from a previous workspace
    if let Some(old) = state.last_workspace.clone() {
        if old != snapshot.workspace_id {
            let _ = report_tokens(client, state, &old, &cleared);
            log_line(&format!("cleared sidebar tokens on {old}"));
        }
    }
    state.last_workspace = Some(snapshot.workspace_id.clone());

    match herdr_pane_minimap::apply::apply_mode(snapshot) {
        ApplyMode::Hide => {
            log_line(&format!(
                "hide {} focus={} panes={}",
                snapshot.workspace_id,
                snapshot.focused_pane_id,
                snapshot.panes.len()
            ));
            return;
        }
        ApplyMode::Show => {}
    }

    let place = match layout::placement_for(snapshot) {
        Some(p) => p,
        None => return,
    };
    let host_pane = snapshot.focused_pane_id.clone();
    let info = match client.graphics_info(&host_pane) {
        Ok(i) if i.cell_width_px > 0 && i.cell_height_px > 0 => i,
        Ok(_) | Err(_) => return,
    };
    let png = png_for_snapshot(
        snapshot,
        info.cell_width_px,
        info.cell_height_px,
        place.grid_cols,
        place.grid_rows,
    );
    let img_w = u32::from(place.grid_cols) * info.cell_width_px;
    let img_h = u32::from(place.grid_rows) * info.cell_height_px;
    if client
        .graphics_set(
            &host_pane,
            &png,
            img_w,
            img_h,
            place.viewport_col,
            place.viewport_row,
            place.grid_cols,
            place.grid_rows,
        )
        .is_ok()
    {
        log_line(&format!(
            "set {} col={} row={} grid={}x{} focus={} panes={}",
            host_pane,
            place.viewport_col,
            place.viewport_row,
            place.grid_cols,
            place.grid_rows,
            snapshot.focused_pane_id,
            snapshot.panes.len()
        ));
        state.last_pane = Some(host_pane);
    }
}
```

Remove `clear_overlay` function and `cleared_overlay` field from `ApplyState` (always clear per apply). Keep `refresh_from_layout` calling `client.pane_layout()` with `{}`. Keep event loop:

```rust
if herdr::matches_event(&value, "layout.updated")
    || herdr::matches_event(&value, "tab.focused")
    || herdr::matches_event(&value, "workspace.focused")
    || herdr::matches_event(&value, "pane.focused")
{
    refresh_from_layout(&client, &mut state);
}
```

Delete `herdr/pane-minimap/src/ascii.rs`. Remove any remaining `ascii` imports.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib -q
```

Expected: PASS — all lib tests including `herdr::tests::subscribe_includes_pane_focused`, `tokens::tests`, `apply::tests`, `layout::tests`, `render::tests`.

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo build --bin herdr-pane-minimap -q
```

Expected: build succeeds; no references to `ascii`.

- [ ] **Step 5: skip commit**

---

### Task 4: Config and documentation — remove sidebar rows, update descriptions

**Files:**
- Modify: `herdr/config.toml:156-177`
- Modify: `herdr/pane-minimap/herdr-plugin.toml:5`
- Modify: `AGENTS.md:86`
- Modify: `README.md:36`

**Interfaces:**
- Consumes: Task 3 watcher that clears tokens (sidebar rows become dead UI if left configured)
- Produces: default two-row Spaces sidebar; docs describe Kitty overlay HUD

- [ ] **Step 1: Update Herdr config**

In `herdr/config.toml`, replace lines 156–177 with:

```toml
# Kitty graphics HUD: herdr-pane-minimap draws the pane layout map as a
# top-left overlay (layer minimap) on the focused pane — not in the sidebar.
# Plugin is linked from ~/.dotfiles/herdr/pane-minimap; the watcher starts on
# server restore. After a live `plugin link`, run that plugin's startup.sh once
# (or restart the Herdr server) so the HUD appears without a reboot.
[experimental]
kitty_graphics = true

[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  ["branch", "git_status"],
]
```

- [ ] **Step 2: Update plugin manifest**

In `herdr/pane-minimap/herdr-plugin.toml`, change description:

```toml
description = "Always-on top-left pane layout HUD via Kitty graphics (layer minimap)"
```

- [ ] **Step 3: Update AGENTS.md one-liner**

In `AGENTS.md`, replace the `herdr-pane-minimap` parenthetical:

```markdown
- Bootstrap pins `dleen.herdr-agents` (`prefix+a` picker, previous/next `alt+shift+[` / `alt+shift+]`, focus `prefix+alt+1..9`) and builds/links `herdr-pane-minimap` (Kitty overlay pane layout HUD on the focused pane). Tmux `pane-minimap` popup is unchanged.
```

- [ ] **Step 4: Update README.md one-liner**

In `README.md`, extend the Herdr bootstrap bullet — change `herdr-pane-minimap` wording to:

```markdown
builds `herdr-nvim-nav` and `herdr-pane-minimap` (Kitty overlay HUD, not sidebar tokens)
```

- [ ] **Step 5: Verify config parses**

Run:

```bash
herdr config check
```

Expected: exit code `0`.

- [ ] **Step 6: skip commit**

---

### Task 5: End-to-end verify — tests, build, detached watcher, live HUD

**Files:**
- No code changes unless verify fails (fix in place, then re-run)

**Interfaces:**
- Consumes: Tasks 1–4 complete
- Produces: passing tests, release binary, live overlay on focused pane, empty sidebar tokens

- [ ] **Step 1: Unit tests**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && cargo test --lib -q
```

Expected: all tests PASS (count ≥ 20 across `layout`, `render`, `herdr`, `tokens`, `apply`).

- [ ] **Step 2: Release build**

Run:

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && bash build.sh
```

Expected: `target/release/herdr-pane-minimap` copied to `herdr/pane-minimap/herdr-pane-minimap`; exit `0`.

- [ ] **Step 3: Start watcher detached (survives agent shell exit)**

Run (do **not** use foreground watch — agent shells kill process groups):

```bash
cd /Users/rkommineni/.dotfiles/herdr/pane-minimap && bash startup.sh
```

Expected: exits immediately; `$HOME/.config/herdr/plugin-state/herdr-pane-minimap/watch.pid` contains a live PID; `watch.log` contains `watch started`.

Optional sanity:

```bash
ps -p "$(cat "$HOME/.config/herdr/plugin-state/herdr-pane-minimap/watch.pid")" -o command=
```

Expected: command line includes `herdr-pane-minimap watch`.

- [ ] **Step 4: Confirm overlay on a multi-pane tab**

Prerequisite: Herdr running with a tab that has ≥2 panes and `[experimental] kitty_graphics = true`.

Run:

```bash
FOCUSED="$(herdr pane list --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['panes'][0]['pane_id'])")"
herdr pane.graphics.info --pane "$FOCUSED" --json
tail -20 "$HOME/.config/herdr/plugin-state/herdr-pane-minimap/watch.log"
```

Expected:
- `pane.graphics.info` JSON includes `"cell_width_px"` > 0 and `"pane_visible": true` for the focused pane.
- `watch.log` contains a line like `set w1:p2 col=1 row=1 grid=16x10 focus=w1:p2 panes=2` (exact ids vary).

- [ ] **Step 5: Confirm sidebar tokens cleared**

Run:

```bash
herdr workspace metadata --workspace "$(herdr workspace list --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['workspaces'][0]['workspace_id'])")" --json | python3 -c "import sys,json; m=json.load(sys.stdin)['result'].get('tokens',{}); assert all(m.get(k) in (None,'',) or m.get(k) is None for k in ['minimap_title','minimap0','minimap1']), m; print('minimap tokens cleared')"
```

Expected: prints `minimap tokens cleared` (or keys absent/null).

Visually: Spaces sidebar shows only workspace + git rows (two rows), no `layout` / ASCII map lines.

- [ ] **Step 6: Trigger refresh via focus event**

Switch pane focus (`prefix + arrow` or Herdr focus command), then:

```bash
tail -5 "$HOME/.config/herdr/plugin-state/herdr-pane-minimap/watch.log"
```

Expected: new `set wN:pN col=1 row=1` line after focus change; no `sidebar set` lines.

- [ ] **Step 7: skip commit**

---

## Self-review checklist

| Spec requirement | Task |
|---|---|
| Top-left viewport col=1 row=1 | Task 1 |
| tmux character grid interior fill + `+`/`-`/`|` borders | Task 2 |
| PNG via cell-block stamping | Task 2 |
| `pane.graphics.set` layer minimap z_index 10 | Task 3 (existing `herdr.rs`) |
| Hide <2 panes; clear all pane graphics | Task 3 |
| Clear minimap sidebar tokens | Task 3, 4 |
| Subscribe layout/tab/workspace/pane.focused | Task 3 (existing) |
| `pane.layout()` empty params refresh | Task 3 |
| Remove sidebar minimap config rows | Task 4 |
| No tmux changes / no key steal / no server stop | Global constraints |
| Detached watcher verify | Task 5 |
| No nvim inner splits | Out of scope (not in plan) |

Placeholder scan: no TBD/TODO placeholders in tasks above.
