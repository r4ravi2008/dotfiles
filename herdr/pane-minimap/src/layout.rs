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
