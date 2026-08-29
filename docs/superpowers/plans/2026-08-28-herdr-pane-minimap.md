# Herdr Pane Minimap HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Always-on top-right pane-layout HUD in Herdr (Kitty graphics) that shows the unzoomed split map and highlights the focused pane, including while zoomed.

**Architecture:** Linked plugin `herdr/pane-minimap/` runs a detached watcher over Herdr’s Unix socket. It subscribes to `layout.updated` / tab / workspace focus, renders a PNG of `PaneLayoutSnapshot` with the same integer scaling as `tmux/pane-minimap-rs`, and `pane.graphics.set`s layer `minimap` on the visible focused pane. Startup exits after spawning the watcher. Tmux popup HUD is unchanged.

**Tech Stack:** Rust 2021 (`serde`, `serde_json`, `png`, `base64`), Herdr 0.8+ socket API, bash bootstrap, Ghostty/Kitty `experimental.kitty_graphics`.

## Global Constraints

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
- Plugin id `herdr-pane-minimap`; layer id `minimap`; `z_index` `10`; `min_herdr_version` `0.8.0`.
- Default grid 16×10, margin 1 col right / 1 row top; shrink then hide below 8×5.
- Labels are the pane-id suffix (`p3` from `w1:p3`).

## File map

| File | Responsibility |
|---|---|
| `herdr/pane-minimap/src/layout.rs` | Snapshot types, hide, scale, placement |
| `herdr/pane-minimap/src/render.rs` | RGBA map + PNG encode |
| `herdr/pane-minimap/src/herdr.rs` | Unix socket JSON-RPC |
| `herdr/pane-minimap/src/main.rs` | `watch` loop, pidfile, apply/clear |
| `herdr/pane-minimap/Cargo.toml` | crate deps |
| `herdr/pane-minimap/herdr-plugin.toml` | manifest |
| `herdr/pane-minimap/build.sh` | `cargo build --release` + copy binary to plugin root |
| `herdr/pane-minimap/startup.sh` | replace watcher pid, `nohup` watch, exit |
| `bootstrap.sh` | build + `herdr plugin link` |
| `.gitignore` | `target/` and copied binary |
| `README.md`, `AGENTS.md`, CWS `reference.md` | discoverability |

---

### Task 1: Layout mapping and HUD placement

**Files:**
- Create: `herdr/pane-minimap/Cargo.toml`
- Create: `herdr/pane-minimap/src/lib.rs`
- Create: `herdr/pane-minimap/src/layout.rs`
- Create: `herdr/pane-minimap/src/main.rs` (stub so the package builds)

**Interfaces:**
- Consumes: spec scale formulas and hide/placement rules
- Produces: `layout::{Rect, Pane, Snapshot, HudPlacement, scaled_start, scaled_end, should_hide, host_size, placement, pane_label}`

- [ ] **Step 1: Write the failing crate skeleton**

Create `herdr/pane-minimap/Cargo.toml`:

```toml
[package]
name = "herdr-pane-minimap"
version = "0.1.0"
edition = "2021"

[lib]
name = "herdr_pane_minimap"
path = "src/lib.rs"

[[bin]]
name = "herdr-pane-minimap"
path = "src/main.rs"

[dependencies]
base64 = "0.22"
png = "0.17"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

Create `herdr/pane-minimap/src/lib.rs`:

```rust
pub mod layout;
```

Create `herdr/pane-minimap/src/main.rs`:

```rust
fn main() {
    eprintln!("herdr-pane-minimap: watch not implemented");
    std::process::exit(1);
}
```

Create `herdr/pane-minimap/src/layout.rs` with **only** the tests at the bottom and empty `todo!()` bodies for the functions those tests call (or omit the functions so compile fails). Preferred: put the tests in the same file and leave functions unimplemented so `cargo test` fails on assertion / missing items.

Run:

```bash
cd herdr/pane-minimap && cargo test --lib layout::tests::scales_bounds_like_tmux_helper
```

Expected: FAIL (module or test not found, or assertion).

- [ ] **Step 2: Implement layout.rs**

Replace `herdr/pane-minimap/src/layout.rs` with:

```rust
use serde::Deserialize;

pub const DEFAULT_GRID_COLS: i32 = 16;
pub const DEFAULT_GRID_ROWS: i32 = 10;
pub const MIN_GRID_COLS: i32 = 8;
pub const MIN_GRID_ROWS: i32 = 5;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub struct Rect {
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Pane {
    pub pane_id: String,
    #[serde(default)]
    pub focused: bool,
    pub rect: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Snapshot {
    pub workspace_id: String,
    pub tab_id: String,
    pub zoomed: bool,
    pub area: Rect,
    pub focused_pane_id: String,
    pub panes: Vec<Pane>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HudPlacement {
    pub grid_cols: u16,
    pub grid_rows: u16,
    pub viewport_col: u16,
    pub viewport_row: u16,
}

pub fn scaled_start(v: i32, min: i32, canvas: i32, span: i32) -> i32 {
    let num = i64::from(v - min) * i64::from(canvas);
    (num / i64::from(span)) as i32
}

pub fn scaled_end(v: i32, min: i32, canvas: i32, span: i32) -> i32 {
    let num = i64::from(v - min) * i64::from(canvas);
    ((num + i64::from(span) - 1) / i64::from(span) - 1) as i32
}

pub fn should_hide(snapshot: &Snapshot) -> bool {
    snapshot.panes.len() < 2 || host_size(snapshot).is_none() || placement_for(snapshot).is_none()
}

pub fn host_size(snapshot: &Snapshot) -> Option<(i32, i32)> {
    if snapshot.zoomed {
        return Some((i32::from(snapshot.area.width), i32::from(snapshot.area.height)));
    }
    snapshot
        .panes
        .iter()
        .find(|pane| pane.pane_id == snapshot.focused_pane_id)
        .map(|pane| (i32::from(pane.rect.width), i32::from(pane.rect.height)))
}

pub fn placement_for(snapshot: &Snapshot) -> Option<HudPlacement> {
    let (host_w, host_h) = host_size(snapshot)?;
    placement(host_w, host_h)
}

pub fn placement(host_w: i32, host_h: i32) -> Option<HudPlacement> {
    let mut cols = DEFAULT_GRID_COLS;
    let mut rows = DEFAULT_GRID_ROWS;
    if cols + 2 > host_w || rows + 2 > host_h {
        cols = (host_w - 2).min(DEFAULT_GRID_COLS);
        rows = (host_h - 2).min(DEFAULT_GRID_ROWS);
    }
    if cols < MIN_GRID_COLS || rows < MIN_GRID_ROWS {
        return None;
    }
    let viewport_col = (host_w - cols - 1).max(0) as u16;
    let viewport_row = 1_i32.min((host_h - rows).max(0)) as u16;
    Some(HudPlacement {
        grid_cols: cols as u16,
        grid_rows: rows as u16,
        viewport_col,
        viewport_row,
    })
}

pub fn pane_label(pane_id: &str) -> &str {
    pane_id.rsplit(':').next().unwrap_or(pane_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn two_pane(zoomed: bool, area: Rect, left: Rect, right: Rect) -> Snapshot {
        Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed,
            area,
            focused_pane_id: "w1:p2".into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: false,
                    rect: left,
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: true,
                    rect: right,
                },
            ],
        }
    }

    #[test]
    fn scales_bounds_like_tmux_helper() {
        let min = 0;
        let span = 238;
        assert_eq!(scaled_start(0, min, 46, span), 0);
        assert_eq!(scaled_end(238, min, 46, span), 45);
    }

    #[test]
    fn hides_single_pane() {
        let snap = Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect {
                x: 0,
                y: 0,
                width: 80,
                height: 24,
            },
            focused_pane_id: "w1:p1".into(),
            panes: vec![Pane {
                pane_id: "w1:p1".into(),
                focused: true,
                rect: Rect {
                    x: 0,
                    y: 0,
                    width: 80,
                    height: 24,
                },
            }],
        };
        assert!(should_hide(&snap));
    }

    #[test]
    fn zoomed_placement_uses_area() {
        let area = Rect {
            x: 0,
            y: 0,
            width: 120,
            height: 40,
        };
        let left = Rect {
            x: 0,
            y: 0,
            width: 20,
            height: 10,
        };
        let right = Rect {
            x: 20,
            y: 0,
            width: 20,
            height: 10,
        };
        let snap = two_pane(true, area, left, right);
        let place = placement_for(&snap).expect("fits");
        assert_eq!(place.grid_cols, 16);
        assert_eq!(place.grid_rows, 10);
        assert_eq!(place.viewport_col, 120 - 16 - 1);
        assert_eq!(place.viewport_row, 1);
    }

    #[test]
    fn unzoomed_placement_uses_focused_rect() {
        let area = Rect {
            x: 0,
            y: 0,
            width: 120,
            height: 40,
        };
        let left = Rect {
            x: 0,
            y: 0,
            width: 60,
            height: 40,
        };
        let right = Rect {
            x: 60,
            y: 0,
            width: 60,
            height: 40,
        };
        let snap = two_pane(false, area, left, right);
        let place = placement_for(&snap).expect("fits");
        assert_eq!(place.viewport_col, 60 - 16 - 1);
    }

    #[test]
    fn hides_when_host_smaller_than_minimum_grid() {
        assert!(placement(9, 6).is_none());
        assert!(placement(80, 24).is_some());
    }

    #[test]
    fn pane_label_uses_suffix() {
        assert_eq!(pane_label("w1:p3"), "p3");
        assert_eq!(pane_label("p3"), "p3");
    }
}
```

- [ ] **Step 3: Run the layout tests**

```bash
cd herdr/pane-minimap && cargo test --lib
```

Expected: PASS (layout tests only; lib has no other modules yet).

- [ ] **Step 4: Commit**

```bash
git add herdr/pane-minimap/Cargo.toml herdr/pane-minimap/src/lib.rs herdr/pane-minimap/src/layout.rs herdr/pane-minimap/src/main.rs
git commit -m "$(cat <<'EOF'
feat(herdr): add pane minimap layout mapping

Port tmux minimap integer scaling and HUD placement so zoomed Herdr panes can show the unzoomed split map.
EOF
)"
```

---

### Task 2: PNG renderer

**Files:**
- Modify: `herdr/pane-minimap/src/lib.rs`
- Create: `herdr/pane-minimap/src/render.rs`

**Interfaces:**
- Consumes: `layout::{Snapshot, scaled_start, scaled_end, pane_label}`
- Produces: `render::png_for_snapshot(snapshot, cell_width_px, cell_height_px, grid_cols, grid_rows) -> Vec<u8>`

- [ ] **Step 1: Write the failing PNG magic test**

Add to `src/lib.rs`:

```rust
pub mod layout;
pub mod render;
```

Create `src/render.rs` with a stub:

```rust
use crate::layout::Snapshot;

pub fn png_for_snapshot(
    _snapshot: &Snapshot,
    _cell_width_px: u32,
    _cell_height_px: u32,
    _grid_cols: u16,
    _grid_rows: u16,
) -> Vec<u8> {
    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::{Pane, Rect, Snapshot};

    #[test]
    fn encodes_png_signature() {
        let snap = Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect {
                x: 0,
                y: 0,
                width: 80,
                height: 24,
            },
            focused_pane_id: "w1:p2".into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: false,
                    rect: Rect {
                        x: 0,
                        y: 0,
                        width: 40,
                        height: 24,
                    },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: true,
                    rect: Rect {
                        x: 40,
                        y: 0,
                        width: 40,
                        height: 24,
                    },
                },
            ],
        };
        let png = png_for_snapshot(&snap, 8, 16, 16, 10);
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
    }
}
```

Run:

```bash
cd herdr/pane-minimap && cargo test --lib render::tests::encodes_png_signature
```

Expected: FAIL (`assert_eq` on empty/short buffer).

- [ ] **Step 2: Implement the renderer**

Replace `png_for_snapshot` and add drawing helpers in `src/render.rs`:

```rust
use std::io::Cursor;

use crate::layout::{scaled_end, scaled_start, pane_label, Snapshot};

const INACTIVE_FILL: [u8; 4] = [0x1a, 0x1b, 0x26, 0xff];
const INACTIVE_BORDER: [u8; 4] = [0x56, 0x5f, 0x89, 0xff];
const ACTIVE_FILL: [u8; 4] = [0x3d, 0x59, 0xa1, 0xff];
const ACTIVE_BORDER: [u8; 4] = [0x7a, 0xa2, 0xf7, 0xff];
const LABEL: [u8; 4] = [0xc0, 0xca, 0xf5, 0xff];
const BG: [u8; 4] = [0x16, 0x16, 0x1e, 0xff];

struct Canvas {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

impl Canvas {
    fn new(width: u32, height: u32) -> Self {
        let mut pixels = vec![0; (width * height * 4) as usize];
        for chunk in pixels.chunks_exact_mut(4) {
            chunk.copy_from_slice(&BG);
        }
        Self {
            width,
            height,
            pixels,
        }
    }

    fn put(&mut self, x: i32, y: i32, color: [u8; 4]) {
        if x < 0 || y < 0 {
            return;
        }
        let (x, y) = (x as u32, y as u32);
        if x >= self.width || y >= self.height {
            return;
        }
        let i = ((y * self.width + x) * 4) as usize;
        self.pixels[i..i + 4].copy_from_slice(&color);
    }
}

fn clamp(v: i32, lo: i32, hi: i32) -> i32 {
    v.max(lo).min(hi)
}

pub fn png_for_snapshot(
    snapshot: &Snapshot,
    cell_width_px: u32,
    cell_height_px: u32,
    grid_cols: u16,
    grid_rows: u16,
) -> Vec<u8> {
    let canvas_w = (u32::from(grid_cols) * cell_width_px.max(1)) as i32;
    let canvas_h = (u32::from(grid_rows) * cell_height_px.max(1)) as i32;
    let mut canvas = Canvas::new(canvas_w as u32, canvas_h as u32);

    let min_left = snapshot
        .panes
        .iter()
        .map(|p| i32::from(p.rect.x))
        .min()
        .unwrap_or(0);
    let min_top = snapshot
        .panes
        .iter()
        .map(|p| i32::from(p.rect.y))
        .min()
        .unwrap_or(0);
    let max_right = snapshot
        .panes
        .iter()
        .map(|p| i32::from(p.rect.x) + i32::from(p.rect.width))
        .max()
        .unwrap_or(1);
    let max_bottom = snapshot
        .panes
        .iter()
        .map(|p| i32::from(p.rect.y) + i32::from(p.rect.height))
        .max()
        .unwrap_or(1);
    let span_x = (max_right - min_left).max(1);
    let span_y = (max_bottom - min_top).max(1);

    let mut panes = snapshot.panes.clone();
    panes.sort_by_key(|p| p.pane_id == snapshot.focused_pane_id);

    for pane in &panes {
        let left = i32::from(pane.rect.x);
        let top = i32::from(pane.rect.y);
        let right = left + i32::from(pane.rect.width);
        let bottom = top + i32::from(pane.rect.height);
        let x0 = clamp(scaled_start(left, min_left, canvas_w, span_x), 0, canvas_w - 1);
        let x1 = clamp(scaled_end(right, min_left, canvas_w, span_x), x0, canvas_w - 1);
        let y0 = clamp(scaled_start(top, min_top, canvas_h, span_y), 0, canvas_h - 1);
        let y1 = clamp(scaled_end(bottom, min_top, canvas_h, span_y), y0, canvas_h - 1);
        let active = pane.pane_id == snapshot.focused_pane_id;
        let fill = if active { ACTIVE_FILL } else { INACTIVE_FILL };
        let border = if active {
            ACTIVE_BORDER
        } else {
            INACTIVE_BORDER
        };
        for y in y0..=y1 {
            for x in x0..=x1 {
                let on_border = x == x0 || x == x1 || y == y0 || y == y1;
                canvas.put(x, y, if on_border { border } else { fill });
            }
        }
        let label = pane_label(&pane.pane_id);
        let lx = x0 + 2;
        let ly = y0 + ((y1 - y0).max(1) / 2);
        for (i, _) in label.chars().enumerate() {
            canvas.put(lx + i as i32 * 2, ly, LABEL);
        }
    }

    let mut out = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut out, canvas.width, canvas.height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("png header");
        writer
            .write_image_data(&canvas.pixels)
            .expect("png data");
    }
    let _ = Cursor::new(&out);
    out
}
```

Keep the existing `encodes_png_signature` test in the same file (move it under `mod tests` as in Step 1). Remove the unused `Cursor` import if clippy complains — delete the `let _ = Cursor::new(&out);` line and the `use std::io::Cursor`.

- [ ] **Step 3: Run renderer tests**

```bash
cd herdr/pane-minimap && cargo test --lib
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add herdr/pane-minimap/src/lib.rs herdr/pane-minimap/src/render.rs herdr/pane-minimap/Cargo.lock
git commit -m "$(cat <<'EOF'
feat(herdr): render pane minimap PNG

Draw the unzoomed split map with Tokyo Night fills so the HUD can be stamped via Kitty graphics.
EOF
)"
```

---

### Task 3: Herdr socket client

**Files:**
- Modify: `herdr/pane-minimap/src/lib.rs`
- Create: `herdr/pane-minimap/src/herdr.rs`

**Interfaces:**
- Consumes: `HERDR_SOCKET_PATH` (else `$HOME/.config/herdr/herdr.sock`)
- Produces: `herdr::{Client, GraphicsInfo, subscribe_events}` where `Client` can `pane_layout`, `graphics_info`, `graphics_set`, `graphics_clear`

- [ ] **Step 1: Write a unit test for layout JSON extraction**

Add `pub mod herdr;` to `src/lib.rs`.

In `src/herdr.rs` start with parsers and tests (no live socket):

```rust
use serde::Deserialize;

use crate::layout::Snapshot;

#[derive(Debug, Deserialize)]
struct RpcOk {
    #[serde(default)]
    result: serde_json::Value,
}

pub fn snapshot_from_layout_result(value: &serde_json::Value) -> Option<Snapshot> {
    let layout = if value.get("panes").is_some() {
        value.clone()
    } else {
        value.get("layout")?.clone()
    };
    serde_json::from_value(layout).ok()
}

pub fn event_name(value: &serde_json::Value) -> Option<String> {
    value
        .get("event")
        .and_then(|e| e.as_str())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_nested_layout_result() {
        let raw = serde_json::json!({
            "type": "pane_layout",
            "layout": {
                "workspace_id": "w1",
                "tab_id": "w1:t1",
                "zoomed": true,
                "area": {"x": 0, "y": 0, "width": 80, "height": 24},
                "focused_pane_id": "w1:p1",
                "panes": [
                    {
                        "pane_id": "w1:p1",
                        "focused": true,
                        "rect": {"x": 0, "y": 0, "width": 40, "height": 24}
                    },
                    {
                        "pane_id": "w1:p2",
                        "focused": false,
                        "rect": {"x": 40, "y": 0, "width": 40, "height": 24}
                    }
                ]
            }
        });
        let snap = snapshot_from_layout_result(&raw).expect("parse");
        assert!(snap.zoomed);
        assert_eq!(snap.panes.len(), 2);
    }

    #[test]
    fn reads_layout_updated_event_name() {
        let raw = serde_json::json!({"event": "layout.updated", "data": {}});
        assert_eq!(event_name(&raw).as_deref(), Some("layout.updated"));
    }
}
```

Run:

```bash
cd herdr/pane-minimap && cargo test --lib herdr::tests
```

Expected: FAIL until the module exists, then PASS after Step 1 file is complete (these tests do not need the socket yet). Write the file so these two tests pass before adding `Client`.

- [ ] **Step 2: Add the Unix-socket client**

Append to `src/herdr.rs` (keep the parsers/tests):

```rust
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

use base64::Engine;

pub struct GraphicsInfo {
    pub cell_width_px: u32,
    pub cell_height_px: u32,
    pub pane_visible: bool,
}

pub struct Client {
    path: PathBuf,
}

impl Client {
    pub fn connect() -> std::io::Result<Self> {
        Ok(Self { path: socket_path()? })
    }

    fn rpc(&self, method: &str, params: serde_json::Value) -> std::io::Result<serde_json::Value> {
        let mut stream = UnixStream::connect(&self.path)?;
        stream.set_read_timeout(Some(Duration::from_secs(2)))?;
        stream.set_write_timeout(Some(Duration::from_secs(2)))?;
        let id = format!("minimap-{method}");
        let req = serde_json::json!({"id": id, "method": method, "params": params});
        stream.write_all(req.to_string().as_bytes())?;
        stream.write_all(b"\n")?;
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line)?;
        let parsed: RpcOk = serde_json::from_str(&line).map_err(std::io::Error::other)?;
        Ok(parsed.result)
    }

    pub fn pane_layout(&self) -> std::io::Result<Snapshot> {
        let result = self.rpc("pane.layout", serde_json::json!({}))?;
        snapshot_from_layout_result(&result).ok_or_else(|| {
            std::io::Error::other(format!("unexpected pane.layout result: {result}"))
        })
    }

    pub fn graphics_info(&self, pane_id: &str) -> std::io::Result<GraphicsInfo> {
        let result = self.rpc(
            "pane.graphics.info",
            serde_json::json!({ "pane_id": pane_id }),
        )?;
        if result.get("code").is_some() {
            return Err(std::io::Error::other(result.to_string()));
        }
        Ok(GraphicsInfo {
            cell_width_px: result
                .get("cell_width_px")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as u32,
            cell_height_px: result
                .get("cell_height_px")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as u32,
            pane_visible: result
                .get("pane_visible")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        })
    }

    pub fn graphics_set(
        &self,
        pane_id: &str,
        png: &[u8],
        image_width: u32,
        image_height: u32,
        viewport_col: u16,
        viewport_row: u16,
        grid_cols: u16,
        grid_rows: u16,
    ) -> std::io::Result<()> {
        let data_base64 = base64::engine::general_purpose::STANDARD.encode(png);
        let result = self.rpc(
            "pane.graphics.set",
            serde_json::json!({
                "pane_id": pane_id,
                "layer_id": "minimap",
                "z_index": 10,
                "format": "png",
                "image_width": image_width,
                "image_height": image_height,
                "data_base64": data_base64,
                "placement": {
                    "viewport_col": viewport_col,
                    "viewport_row": viewport_row,
                    "grid_cols": grid_cols,
                    "grid_rows": grid_rows
                }
            }),
        )?;
        if result.get("code").is_some() {
            return Err(std::io::Error::other(result.to_string()));
        }
        Ok(())
    }

    pub fn graphics_clear(&self, pane_id: &str) -> std::io::Result<()> {
        let result = self.rpc(
            "pane.graphics.clear",
            serde_json::json!({
                "pane_id": pane_id,
                "layer_id": "minimap"
            }),
        )?;
        if result.get("code").is_some() {
            return Err(std::io::Error::other(result.to_string()));
        }
        Ok(())
    }
}

pub fn subscribe_stream() -> std::io::Result<BufReader<UnixStream>> {
    let path = socket_path()?;
    let mut stream = UnixStream::connect(path)?;
    stream.set_read_timeout(None)?;
    let req = serde_json::json!({
        "id": "minimap-sub",
        "method": "events.subscribe",
        "params": {
            "subscriptions": [
                {"type": "layout.updated"},
                {"type": "tab.focused"},
                {"type": "workspace.focused"}
            ]
        }
    });
    stream.write_all(req.to_string().as_bytes())?;
    stream.write_all(b"\n")?;
    Ok(BufReader::new(stream))
}

fn socket_path() -> std::io::Result<PathBuf> {
    if let Ok(path) = std::env::var("HERDR_SOCKET_PATH") {
        if !path.is_empty() {
            return Ok(PathBuf::from(path));
        }
    }
    let home = std::env::var("HOME").map_err(std::io::Error::other)?;
    Ok(PathBuf::from(home).join(".config/herdr/herdr.sock"))
}
```

If `RpcOk` cannot see `error` objects, also accept a sibling `error` field: add `#[serde(default)] error: Option<serde_json::Value>` and return `Err` when it is `Some`.

Handle RPC errors: Herdr error replies are `{"id","error":{...}}` with no `result`. `serde` default empty `result` would look like success. After `from_str`, if the line contains `"error"`, return `Err`.

Add a small helper used by `rpc`:

```rust
fn parse_rpc_line(line: &str) -> std::io::Result<serde_json::Value> {
    let value: serde_json::Value =
        serde_json::from_str(line).map_err(std::io::Error::other)?;
    if let Some(err) = value.get("error") {
        return Err(std::io::Error::other(err.to_string()));
    }
    Ok(value.get("result").cloned().unwrap_or(serde_json::Value::Null))
}
```

Use `parse_rpc_line` instead of `RpcOk` in `rpc`.

- [ ] **Step 3: Run unit tests**

```bash
cd herdr/pane-minimap && cargo test --lib
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add herdr/pane-minimap/src/lib.rs herdr/pane-minimap/src/herdr.rs
git commit -m "$(cat <<'EOF'
feat(herdr): talk to pane graphics over the control socket

Subscribe-ready client for layout snapshots and the minimap Kitty layer.
EOF
)"
```

---

### Task 4: Watcher binary and plugin manifest

**Files:**
- Modify: `herdr/pane-minimap/src/main.rs`
- Create: `herdr/pane-minimap/herdr-plugin.toml`
- Create: `herdr/pane-minimap/build.sh`
- Create: `herdr/pane-minimap/startup.sh`

**Interfaces:**
- Consumes: `Client`, `png_for_snapshot`, `should_hide`, `placement_for`
- Produces: `herdr-pane-minimap watch`; plugin id `herdr-pane-minimap`; detached watcher via `startup.sh`

- [ ] **Step 1: Implement `watch`**

Replace `src/main.rs` with:

```rust
use std::fs;
use std::io::BufRead;
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::Duration;

use herdr_pane_minimap::herdr::{self, Client};
use herdr_pane_minimap::layout::{self, Snapshot};
use herdr_pane_minimap::render::png_for_snapshot;

fn state_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("HERDR_PLUGIN_STATE_DIR") {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
        .join(".config/herdr/plugin-state/herdr-pane-minimap")
}

fn pidfile() -> PathBuf {
    state_dir().join("watch.pid")
}

fn kill_existing() {
    let path = pidfile();
    let Ok(raw) = fs::read_to_string(&path) else {
        return;
    };
    let Ok(pid) = raw.trim().parse::<u32>() else {
        return;
    };
    if pid == std::process::id() {
        return;
    }
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "command="])
        .output();
    let cmdline = output
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default();
    if !cmdline.contains("herdr-pane-minimap") {
        return;
    }
    let _ = Command::new("kill").args(["-TERM", &pid.to_string()]).status();
    thread::sleep(Duration::from_millis(200));
    let _ = Command::new("kill").args(["-KILL", &pid.to_string()]).status();
}

fn write_pid() {
    let _ = fs::create_dir_all(state_dir());
    let _ = fs::write(pidfile(), std::process::id().to_string());
}

struct ApplyState {
    focused_tab: String,
    last_pane: Option<String>,
    logged_disabled: bool,
}

fn apply(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    if snapshot.tab_id != state.focused_tab && !state.focused_tab.is_empty() {
        return;
    }
    state.focused_tab = snapshot.tab_id.clone();
    if layout::should_hide(snapshot) {
        if let Some(pane) = state.last_pane.take() {
            let _ = client.graphics_clear(&pane);
        }
        return;
    }
    let Some(place) = layout::placement_for(snapshot) else {
        return;
    };
    let info = match client.graphics_info(&snapshot.focused_pane_id) {
        Ok(info) => info,
        Err(err) => {
            let msg = err.to_string();
            if msg.contains("feature_disabled") && !state.logged_disabled {
                eprintln!("herdr-pane-minimap: kitty graphics disabled: {msg}");
                state.logged_disabled = true;
            }
            return;
        }
    };
    if info.cell_width_px == 0 || info.cell_height_px == 0 || !info.pane_visible {
        return;
    }
    let png = png_for_snapshot(
        snapshot,
        info.cell_width_px,
        info.cell_height_px,
        place.grid_cols,
        place.grid_rows,
    );
    let image_width = u32::from(place.grid_cols) * info.cell_width_px;
    let image_height = u32::from(place.grid_rows) * info.cell_height_px;
    if state.last_pane.as_deref() != Some(snapshot.focused_pane_id.as_str()) {
        if let Some(old) = state.last_pane.take() {
            let _ = client.graphics_clear(&old);
        }
    }
    if client
        .graphics_set(
            &snapshot.focused_pane_id,
            &png,
            image_width,
            image_height,
            place.viewport_col,
            place.viewport_row,
            place.grid_cols,
            place.grid_rows,
        )
        .is_ok()
    {
        state.last_pane = Some(snapshot.focused_pane_id.clone());
    }
}

fn watch() -> std::io::Result<()> {
    kill_existing();
    write_pid();
    loop {
        match Client::connect() {
            Ok(client) => {
                if let Ok(snap) = client.pane_layout() {
                    let mut state = ApplyState {
                        focused_tab: snap.tab_id.clone(),
                        last_pane: None,
                        logged_disabled: false,
                    };
                    apply(&client, &mut state, &snap);
                    match herdr::subscribe_stream() {
                        Ok(mut reader) => {
                            let mut line = String::new();
                            while reader.read_line(&mut line)? > 0 {
                                if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) {
                                    match herdr::event_name(&value).as_deref() {
                                        Some("layout.updated") => {
                                            if let Some(snap) = value
                                                .pointer("/data/layout")
                                                .and_then(herdr::snapshot_from_layout_result)
                                                .or_else(|| {
                                                    value
                                                        .get("data")
                                                        .and_then(herdr::snapshot_from_layout_result)
                                                })
                                            {
                                                apply(&client, &mut state, &snap);
                                            }
                                        }
                                        Some("tab.focused") | Some("workspace.focused") => {
                                            if let Ok(snap) = client.pane_layout() {
                                                state.focused_tab = snap.tab_id.clone();
                                                apply(&client, &mut state, &snap);
                                            }
                                        }
                                        _ => {}
                                    }
                                }
                                line.clear();
                            }
                        }
                        Err(_) => thread::sleep(Duration::from_secs(2)),
                    }
                }
            }
            Err(_) => thread::sleep(Duration::from_secs(2)),
        }
        thread::sleep(Duration::from_secs(2));
    }
}

fn main() {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        Some("watch") => {
            if let Err(err) = watch() {
                eprintln!("herdr-pane-minimap watch: {err}");
                std::process::exit(1);
            }
        }
        _ => {
            eprintln!("usage: herdr-pane-minimap watch");
            std::process::exit(2);
        }
    }
}
```

If `/data/layout` is wrong for the live event, dump one `layout.updated` line from `watch.log` during Task 5 verification and adjust the pointer; also try `value["data"]` as a `Snapshot` directly. Keep both `pointer` and `get("data")` as above.

- [ ] **Step 2: Add plugin scripts and manifest**

`herdr/pane-minimap/build.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release
cp -f target/release/herdr-pane-minimap ./herdr-pane-minimap
chmod +x ./herdr-pane-minimap
```

`herdr/pane-minimap/startup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
STATE="${HERDR_PLUGIN_STATE_DIR:-$HOME/.config/herdr/plugin-state/herdr-pane-minimap}"
ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
BIN="$ROOT/herdr-pane-minimap"
mkdir -p "$STATE"
PIDFILE="$STATE/watch.pid"
if [[ -f "$PIDFILE" ]]; then
  old="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "${old}" ]] && ps -p "$old" -o command= 2>/dev/null | grep -q herdr-pane-minimap; then
    kill -TERM "$old" 2>/dev/null || true
    sleep 0.2
    kill -KILL "$old" 2>/dev/null || true
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "herdr-pane-minimap binary missing at $BIN" >&2
  exit 0
fi
nohup "$BIN" watch >>"$STATE/watch.log" 2>&1 &
echo $! >"$PIDFILE"
```

`herdr/pane-minimap/herdr-plugin.toml`:

```toml
id = "herdr-pane-minimap"
name = "Pane Minimap"
version = "0.1.0"
min_herdr_version = "0.8.0"
description = "Always-on top-right pane layout HUD via Kitty graphics"
platforms = ["macos", "linux"]

[[build]]
command = ["bash", "build.sh"]
platforms = ["macos", "linux"]

[[startup]]
command = ["bash", "startup.sh"]
platforms = ["macos", "linux"]
```

```bash
chmod +x herdr/pane-minimap/build.sh herdr/pane-minimap/startup.sh
```

- [ ] **Step 3: Build and run unit tests**

```bash
cd herdr/pane-minimap && bash build.sh && cargo test --lib
./herdr-pane-minimap; echo exit:$?
```

Expected: tests PASS; binary without args exits 2 and prints `usage: herdr-pane-minimap watch`.

- [ ] **Step 4: Commit**

```bash
git add herdr/pane-minimap/src/main.rs herdr/pane-minimap/herdr-plugin.toml herdr/pane-minimap/build.sh herdr/pane-minimap/startup.sh
git commit -m "$(cat <<'EOF'
feat(herdr): watch layout events and stamp the pane HUD

Detach a socket subscriber from plugin startup so zoomed navigation can keep a non-modal map.
EOF
)"
```

---

### Task 5: Bootstrap, ignore rules, and docs

**Files:**
- Modify: `.gitignore`
- Modify: `bootstrap.sh` (Herdr plugin block after `herdr-nvim-nav` link)
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `.agents/skills/creating-cws-from-devstack-fork/reference.md`

**Interfaces:**
- Consumes: `herdr/pane-minimap/` tree from Tasks 1–4
- Produces: linked plugin on laptop and CWS; documented skip if cargo/herdr missing

- [ ] **Step 1: Ignore build artifacts**

Append to `.gitignore` under the existing Rust section:

```
herdr/pane-minimap/target/
herdr/pane-minimap/herdr-pane-minimap
```

- [ ] **Step 2: Link from bootstrap**

In `bootstrap.sh`, immediately after the `herdr-nvim-nav` `plugin link` success/warn block (still inside `if command -v herdr`), insert:

```bash
		local herdr_minimap_dir="$DOTFILES_DIR/herdr/pane-minimap"
		if [[ -d "$herdr_minimap_dir" ]]; then
			if (cd "$herdr_minimap_dir" && bash build.sh >/dev/null 2>&1); then
				herdr plugin uninstall herdr-pane-minimap >/dev/null 2>&1 || true
				if herdr plugin link "$herdr_minimap_dir" >/dev/null 2>&1; then
					log_success "Linked herdr-pane-minimap (zoom HUD)"
				else
					log_warn "Could not link herdr-pane-minimap; pane HUD unavailable"
				fi
			else
				log_warn "Could not build herdr-pane-minimap (need cargo); pane HUD unavailable"
			fi
		fi
```

Do not `exit` on failure.

- [ ] **Step 3: Docs**

`README.md` bootstrap bullet — extend the Herdr sentence so it also says it builds/links `herdr-pane-minimap`.

`AGENTS.md` Herdr/plugins sentence — add: always-on pane HUD plugin `herdr-pane-minimap` (Kitty layer, not a popup). Tmux `pane-minimap` popup is unchanged.

CWS `reference.md` E2E table — add a row:

| `herdr-pane-minimap` | plugin linked; binary `herdr-pane-minimap` exists in the plugin dir **or** bootstrap warn `Could not build herdr-pane-minimap` / `Could not link` |

- [ ] **Step 4: Verify locally**

```bash
cd herdr/pane-minimap && cargo test --lib && bash build.sh
herdr config check
herdr plugin uninstall herdr-pane-minimap >/dev/null 2>&1 || true
herdr plugin link "$PWD"
herdr plugin list --plugin herdr-pane-minimap --json
```

Expected: tests pass; `herdr config check` 0; list JSON contains `"plugin_id": "herdr-pane-minimap"`.

Manual (Ghostty/Kitty, `kitty_graphics` already on, restart Herdr client if graphics were just enabled):

1. Two panes, not zoomed: HUD top-right of focused pane; Alt+hjkl still moves; highlight follows.
2. `alt+z`: HUD remains; full layout still drawn; hop panes; highlight updates; no tmux-style popup.
3. Close to one pane: HUD clears.

If `layout.updated` never redraws, read `$HOME/.config/herdr/plugin-state/herdr-pane-minimap/watch.log` and fix `event_name` / `data.layout` path from the real JSON.

- [ ] **Step 5: Commit**

```bash
git add .gitignore bootstrap.sh README.md AGENTS.md .agents/skills/creating-cws-from-devstack-fork/reference.md
git commit -m "$(cat <<'EOF'
feat(herdr): bootstrap the pane minimap HUD plugin

Link the Kitty-graphics layout map on laptop and CWS without failing install when cargo is missing.
EOF
)"
```

---

## Spec coverage

| Spec requirement | Task |
|---|---|
| Always-on top-right HUD, ≥2 panes | 1 (hide/placement), 4 (apply) |
| Unzoomed geometry + focused highlight | 1, 2 |
| Zoom uses `area` for placement | 1 |
| `pane.graphics.set` layer `minimap` | 3, 4 |
| No keys / no popup / tmux unchanged | 4 (no bindings), 5 (docs) |
| No nvim inner splits | not implemented |
| Socket `layout.updated`, not manifest hook | 3, 4 |
| Startup detaches watcher | 4 `startup.sh` |
| Bootstrap warn-and-continue | 5 |

## Self-review

- No TBD/TODO placeholders in task steps.
- `HudPlacement` / `Snapshot` / `Client` names are consistent across tasks.
- PNG image size is `grid * cell_px`, matching `graphics_set` args in Task 4.
- `viewport_row` is `1` clamped, matching the spec.
