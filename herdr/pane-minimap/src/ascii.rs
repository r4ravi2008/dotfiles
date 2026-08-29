use crate::layout::Snapshot;

pub const MAP_COLS: i32 = 16;
pub const MAP_ROWS: i32 = 6;
pub const LINE_TOKEN_COUNT: usize = 6;
pub const TITLE_TOKEN: &str = "minimap_title";
pub const TITLE_VALUE: &str = "layout";

const ACTIVE: char = '█';
const INACTIVE: char = ' ';
const EMPTY: char = ' ';
const H: char = '─';
const V: char = '│';
const TL: char = '┌';
const TR: char = '┐';
const BL: char = '└';
const BR: char = '┘';

const N: u8 = 1;
const E: u8 = 2;
const S: u8 = 4;
const W: u8 = 8;

fn clamp(v: i32, lo: i32, hi: i32) -> i32 {
    v.max(lo).min(hi)
}

fn border_mask(c: char) -> u8 {
    match c {
        '─' => E | W,
        '│' => N | S,
        '┌' => E | S,
        '┐' => W | S,
        '└' => E | N,
        '┘' => W | N,
        '├' => N | E | S,
        '┤' => N | W | S,
        '┬' => E | S | W,
        '┴' => N | E | W,
        '┼' => N | E | S | W,
        _ => 0,
    }
}

fn char_from_mask(mask: u8) -> char {
    match mask {
        m if m == (E | W) => H,
        m if m == (N | S) => V,
        m if m == (E | S) => TL,
        m if m == (W | S) => TR,
        m if m == (E | N) => BL,
        m if m == (W | N) => BR,
        m if m == (N | E | S) => '├',
        m if m == (N | W | S) => '┤',
        m if m == (E | S | W) => '┬',
        m if m == (N | E | W) => '┴',
        _ => '┼',
    }
}

fn put_border(grid: &mut [Vec<char>], x: i32, y: i32, ch: char) {
    if x < 0 || y < 0 {
        return;
    }
    let (x, y) = (x as usize, y as usize);
    if y >= grid.len() || x >= grid[0].len() {
        return;
    }
    let merged = border_mask(grid[y][x]) | border_mask(ch);
    grid[y][x] = if merged == 0 {
        ch
    } else {
        char_from_mask(merged)
    };
}

fn line_token_name(i: usize) -> String {
    format!("minimap{i}")
}

/// Compact character map of the unzoomed pane layout. Focused pane is `█`.
pub fn ascii_lines(snapshot: &Snapshot) -> Vec<String> {
    let mut grid = vec![vec![EMPTY; MAP_COLS as usize]; MAP_ROWS as usize];

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

    let cells: Vec<(i32, i32, i32, i32, bool)> = panes
        .iter()
        .map(|pane| {
            let left = i32::from(pane.rect.x);
            let top = i32::from(pane.rect.y);
            let right = left + i32::from(pane.rect.width);
            let bottom = top + i32::from(pane.rect.height);
            let x0 = clamp(
                crate::layout::scaled_start(left, min_left, MAP_COLS, span_x),
                0,
                MAP_COLS - 1,
            );
            let mut x1 = crate::layout::scaled_start(right, min_left, MAP_COLS, span_x);
            if x1 >= MAP_COLS {
                x1 = MAP_COLS - 1;
            }
            if x1 < x0 {
                x1 = x0;
            }
            let y0 = clamp(
                crate::layout::scaled_start(top, min_top, MAP_ROWS, span_y),
                0,
                MAP_ROWS - 1,
            );
            let mut y1 = crate::layout::scaled_start(bottom, min_top, MAP_ROWS, span_y);
            if y1 >= MAP_ROWS {
                y1 = MAP_ROWS - 1;
            }
            if y1 < y0 {
                y1 = y0;
            }
            (
                x0,
                x1,
                y0,
                y1,
                pane.pane_id == snapshot.focused_pane_id,
            )
        })
        .collect();

    for &(x0, x1, y0, y1, active) in &cells {
        let fill = if active { ACTIVE } else { INACTIVE };
        for y in y0..=y1 {
            for x in x0..=x1 {
                grid[y as usize][x as usize] = fill;
            }
        }
    }

    for &(x0, x1, y0, y1, _) in &cells {
        if x0 == x1 && y0 == y1 {
            put_border(&mut grid, x0, y0, '┼');
            continue;
        }
        for x in x0..=x1 {
            let top = if x == x0 {
                TL
            } else if x == x1 {
                TR
            } else {
                H
            };
            let bot = if x == x0 {
                BL
            } else if x == x1 {
                BR
            } else {
                H
            };
            put_border(&mut grid, x, y0, top);
            put_border(&mut grid, x, y1, bot);
        }
        for y in (y0 + 1)..y1 {
            put_border(&mut grid, x0, y, V);
            put_border(&mut grid, x1, y, V);
        }
    }

    grid.into_iter()
        .map(|row| row.into_iter().collect())
        .collect()
}

pub fn cleared_sidebar_tokens() -> serde_json::Map<String, serde_json::Value> {
    let mut tokens = serde_json::Map::new();
    tokens.insert(TITLE_TOKEN.to_string(), serde_json::Value::Null);
    for i in 0..LINE_TOKEN_COUNT {
        tokens.insert(line_token_name(i), serde_json::Value::Null);
    }
    tokens
}

/// Workspace metadata token patch. Null values clear a key so empty sidebar rows hide.
pub fn sidebar_tokens(snapshot: &Snapshot) -> serde_json::Map<String, serde_json::Value> {
    if crate::layout::should_hide_sidebar(snapshot) {
        return cleared_sidebar_tokens();
    }
    let mut tokens = serde_json::Map::new();
    tokens.insert(
        TITLE_TOKEN.to_string(),
        serde_json::Value::String(TITLE_VALUE.to_string()),
    );
    let lines = ascii_lines(snapshot);
    for i in 0..LINE_TOKEN_COUNT {
        let value = lines
            .get(i)
            .cloned()
            .map(serde_json::Value::String)
            .unwrap_or(serde_json::Value::Null);
        tokens.insert(line_token_name(i), value);
    }
    tokens
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::{Pane, Rect, Snapshot};

    fn two_pane_horizontal(focused: &str) -> Snapshot {
        Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect {
                x: 0,
                y: 0,
                width: 80,
                height: 24,
            },
            focused_pane_id: focused.into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: focused == "w1:p1",
                    rect: Rect {
                        x: 0,
                        y: 0,
                        width: 40,
                        height: 24,
                    },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: focused == "w1:p2",
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

    fn two_pane_vertical(focused: &str) -> Snapshot {
        Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect {
                x: 0,
                y: 0,
                width: 80,
                height: 24,
            },
            focused_pane_id: focused.into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: focused == "w1:p1",
                    rect: Rect {
                        x: 0,
                        y: 0,
                        width: 80,
                        height: 12,
                    },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: focused == "w1:p2",
                    rect: Rect {
                        x: 0,
                        y: 12,
                        width: 80,
                        height: 12,
                    },
                },
            ],
        }
    }

    #[test]
    fn side_by_side_highlights_the_focused_half() {
        let lines = ascii_lines(&two_pane_horizontal("w1:p2"));
        assert_eq!(lines.len(), MAP_ROWS as usize);
        let mid: Vec<char> = lines[3].chars().collect();
        assert_eq!(mid.len(), MAP_COLS as usize);
        let left = mid[..8].iter().filter(|c| **c == ACTIVE).count();
        let right = mid[8..].iter().filter(|c| **c == ACTIVE).count();
        assert!(right > left, "focused right pane should be █: {lines:?}");
    }

    #[test]
    fn changing_focus_moves_the_highlight() {
        let right = ascii_lines(&two_pane_horizontal("w1:p2"));
        let left = ascii_lines(&two_pane_horizontal("w1:p1"));
        assert_ne!(right, left);
        let mid: Vec<char> = left[3].chars().collect();
        let left_active = mid[..8].iter().filter(|c| **c == ACTIVE).count();
        let right_active = mid[8..].iter().filter(|c| **c == ACTIVE).count();
        assert!(left_active > right_active);
    }

    #[test]
    fn stacked_panes_highlight_the_bottom_when_focused() {
        let lines = ascii_lines(&two_pane_vertical("w1:p2"));
        let top_active = lines[..3]
            .iter()
            .flat_map(|l| l.chars())
            .filter(|c| *c == ACTIVE)
            .count();
        let bottom_active = lines[3..]
            .iter()
            .flat_map(|l| l.chars())
            .filter(|c| *c == ACTIVE)
            .count();
        assert!(
            bottom_active > top_active,
            "focused bottom pane should be █: {lines:?}"
        );
    }

    fn four_pane_grid(focused: &str) -> Snapshot {
        Snapshot {
            workspace_id: "w1".into(),
            tab_id: "w1:t1".into(),
            zoomed: false,
            area: Rect {
                x: 0,
                y: 0,
                width: 80,
                height: 24,
            },
            focused_pane_id: focused.into(),
            panes: vec![
                Pane {
                    pane_id: "w1:p1".into(),
                    focused: focused == "w1:p1",
                    rect: Rect {
                        x: 0,
                        y: 0,
                        width: 40,
                        height: 12,
                    },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: focused == "w1:p2",
                    rect: Rect {
                        x: 40,
                        y: 0,
                        width: 40,
                        height: 12,
                    },
                },
                Pane {
                    pane_id: "w1:p3".into(),
                    focused: focused == "w1:p3",
                    rect: Rect {
                        x: 0,
                        y: 12,
                        width: 40,
                        height: 12,
                    },
                },
                Pane {
                    pane_id: "w1:p4".into(),
                    focused: focused == "w1:p4",
                    rect: Rect {
                        x: 40,
                        y: 12,
                        width: 40,
                        height: 12,
                    },
                },
            ],
        }
    }

    fn is_vertical_border(c: char) -> bool {
        matches!(c, '│' | '┌' | '┐' | '└' | '┘' | '┼' | '├' | '┤' | '┬' | '┴')
    }

    fn is_horizontal_border(c: char) -> bool {
        matches!(c, '─' | '┌' | '┐' | '└' | '┘' | '┼' | '├' | '┤' | '┬' | '┴')
    }

    #[test]
    fn four_pane_grid_draws_split_borders() {
        let lines = ascii_lines(&four_pane_grid("w1:p4"));
        let top: String = lines[..3].join("\n");
        let left: String = lines
            .iter()
            .map(|l| l.chars().take(8).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n");
        assert!(
            top.chars().any(is_vertical_border),
            "two inactive top panes must show a vertical split:\n{top}"
        );
        assert!(
            left.chars().any(is_horizontal_border),
            "two inactive left panes must show a horizontal split:\n{left}"
        );
    }

    #[test]
    fn sidebar_tokens_stay_within_herdr_limits() {
        let tokens = sidebar_tokens(&two_pane_horizontal("w1:p2"));
        assert_eq!(
            tokens.get(TITLE_TOKEN),
            Some(&serde_json::Value::String(TITLE_VALUE.into()))
        );
        assert!(tokens.len() <= 16);
        for (name, value) in &tokens {
            assert!(name.len() <= 32);
            if let Some(s) = value.as_str() {
                assert!(s.len() <= 80, "{name} is {} bytes", s.len());
            }
        }
    }

    #[test]
    fn sidebar_tokens_clear_when_a_single_pane() {
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
        let tokens = sidebar_tokens(&snap);
        assert_eq!(tokens.get(TITLE_TOKEN), Some(&serde_json::Value::Null));
        assert_eq!(tokens.get("minimap0"), Some(&serde_json::Value::Null));
    }
}
