use crate::layout::Snapshot;

/// Tmux `DISPLAY_SECONDS` is 0.15s; keep it ~20% longer so the popup is readable.
pub const FLASH_MS: u64 = 180;

#[derive(Debug, PartialEq, Eq)]
pub enum ApplyMode {
    Hide,
    Flash,
}

/// Tmux `after-select-pane` + `window_zoomed_flag`: flash only while zoomed
/// with a split to map. Unzoomed tabs stay empty.
pub fn apply_mode(snapshot: &Snapshot) -> ApplyMode {
    if snapshot.zoomed && snapshot.panes.len() >= 2 {
        ApplyMode::Flash
    } else {
        ApplyMode::Hide
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::{Pane, Rect, Snapshot};

    fn two_pane(zoomed: bool) -> Snapshot {
        Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed,
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
        }
    }

    #[test]
    fn hides_single_pane_tabs() {
        let snap = Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: true,
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
        assert_eq!(apply_mode(&snap), ApplyMode::Hide);
    }

    #[test]
    fn hides_unzoomed_splits_like_tmux() {
        assert_eq!(apply_mode(&two_pane(false)), ApplyMode::Hide);
    }

    #[test]
    fn flashes_when_zoomed_with_splits() {
        assert_eq!(apply_mode(&two_pane(true)), ApplyMode::Flash);
    }
}
