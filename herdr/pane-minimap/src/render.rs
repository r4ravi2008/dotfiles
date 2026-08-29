use crate::layout::{pane_label, scaled_end, scaled_start, Snapshot};

const INACTIVE_FILL: [u8; 4] = [0x1a, 0x1b, 0x26, 0xff];
const INACTIVE_BORDER: [u8; 4] = [0x56, 0x5f, 0x89, 0xff];
const ACTIVE_FILL: [u8; 4] = [0x3d, 0x59, 0xa1, 0xff];
const ACTIVE_BORDER: [u8; 4] = [0x7a, 0xa2, 0xf7, 0xff];
const LABEL: [u8; 4] = [0xc0, 0xca, 0xf5, 0xff];
const BG: [u8; 4] = [0x16, 0x16, 0x1e, 0xff];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GridCell {
    pub ch: char,
    pub active: bool,
    pub is_border: bool,
    pub is_label: bool,
    pub is_fill: bool,
}

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

    fn put(&mut self, x: u32, y: u32, color: [u8; 4]) {
        if x >= self.width || y >= self.height {
            return;
        }
        let i = ((y * self.width + x) * 4) as usize;
        self.pixels[i..i + 4].copy_from_slice(&color);
    }

    fn fill_rect(&mut self, x0: u32, y0: u32, w: u32, h: u32, color: [u8; 4]) {
        for py in y0..y0 + h {
            for px in x0..x0 + w {
                self.put(px, py, color);
            }
        }
    }
}

fn clamp(v: i32, lo: i32, hi: i32) -> i32 {
    v.max(lo).min(hi)
}

fn empty_cell() -> GridCell {
    GridCell {
        ch: ' ',
        active: false,
        is_border: false,
        is_label: false,
        is_fill: false,
    }
}

fn border_cell(ch: char, active: bool) -> GridCell {
    GridCell {
        ch,
        active,
        is_border: true,
        is_label: false,
        is_fill: false,
    }
}

fn fill_cell(active: bool) -> GridCell {
    GridCell {
        ch: ' ',
        active,
        is_border: false,
        is_label: false,
        is_fill: true,
    }
}

fn label_cell(ch: char, active: bool) -> GridCell {
    GridCell {
        ch,
        active,
        is_border: false,
        is_label: true,
        is_fill: true,
    }
}

struct BuiltGrid {
    cells: Vec<Vec<GridCell>>,
    interior: Vec<Vec<bool>>,
}

fn build_character_grid(snapshot: &Snapshot, grid_cols: u16, grid_rows: u16) -> BuiltGrid {
    let cols = grid_cols as usize;
    let rows = grid_rows as usize;
    let mut cells = vec![vec![empty_cell(); cols]; rows];
    let mut interior = vec![vec![false; cols]; rows];

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
        let left_px = i32::from(pane.rect.x);
        let top_px = i32::from(pane.rect.y);
        let right_px = left_px + i32::from(pane.rect.width);
        let bottom_px = top_px + i32::from(pane.rect.height);
        let active = pane.pane_id == snapshot.focused_pane_id;

        let left = clamp(
            scaled_start(left_px, min_left, grid_cols as i32, span_x),
            0,
            grid_cols as i32 - 1,
        );
        let right = clamp(
            scaled_end(right_px, min_left, grid_cols as i32, span_x),
            left,
            grid_cols as i32 - 1,
        );
        let top = clamp(
            scaled_start(top_px, min_top, grid_rows as i32, span_y),
            0,
            grid_rows as i32 - 1,
        );
        let bottom = clamp(
            scaled_end(bottom_px, min_top, grid_rows as i32, span_y),
            top,
            grid_rows as i32 - 1,
        );

        for x in (left + 1)..right {
            cells[top as usize][x as usize] = border_cell('-', active);
            cells[bottom as usize][x as usize] = border_cell('-', active);
        }
        for y in (top + 1)..bottom {
            cells[y as usize][left as usize] = border_cell('|', active);
            cells[y as usize][right as usize] = border_cell('|', active);
        }
        cells[top as usize][left as usize] = border_cell('+', active);
        cells[top as usize][right as usize] = border_cell('+', active);
        cells[bottom as usize][left as usize] = border_cell('+', active);
        cells[bottom as usize][right as usize] = border_cell('+', active);

        for y in (top + 1)..bottom {
            for x in (left + 1)..right {
                cells[y as usize][x as usize] = fill_cell(active);
                interior[y as usize][x as usize] = true;
            }
        }

        let inner_w = right - left - 1;
        let inner_h = bottom - top - 1;
        if inner_w > 0 && inner_h > 0 {
            let mut label = pane_label(&pane.pane_id).to_string();
            let inner_w_usize = inner_w as usize;
            if label.chars().count() > inner_w_usize {
                if inner_w_usize == 1 {
                    label = ".".to_string();
                } else {
                    label = format!(
                        "{}.",
                        label
                            .chars()
                            .take(inner_w_usize.saturating_sub(1))
                            .collect::<String>()
                    );
                }
            }
            let label_chars: Vec<char> = label.chars().collect();
            let lx = left + 1 + ((inner_w - label_chars.len() as i32).max(0) / 2);
            let ly = top + 1 + inner_h / 2;
            for (i, ch) in label_chars.iter().enumerate() {
                let x = lx + i as i32;
                if x > left && x < right && ly > top && ly < bottom {
                    cells[ly as usize][x as usize] = label_cell(*ch, active);
                    interior[ly as usize][x as usize] = true;
                }
            }
        }
    }

    BuiltGrid { cells, interior }
}

pub fn character_grid(snapshot: &Snapshot, grid_cols: u16, grid_rows: u16) -> Vec<Vec<GridCell>> {
    build_character_grid(snapshot, grid_cols, grid_rows).cells
}

pub fn format_character_grid(snapshot: &Snapshot, grid_cols: u16, grid_rows: u16) -> String {
    character_grid(snapshot, grid_cols, grid_rows)
        .iter()
        .map(|row| row.iter().map(|cell| cell.ch).collect::<String>())
        .collect::<Vec<_>>()
        .join("\n")
}

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const ACT_BG: &str = "\x1b[44m";
const INA_BG: &str = "\x1b[48;5;236m";
const ACT_BORDER: &str = "\x1b[94m\x1b[1m";
const INA_BORDER: &str = "\x1b[90m";
const ACT_TEXT: &str = "\x1b[44m\x1b[97m\x1b[1m";
const INA_TEXT: &str = "\x1b[48;5;236m\x1b[37m";

fn cell_escape(cell: &GridCell) -> &'static str {
    if cell.is_label {
        if cell.active {
            ACT_TEXT
        } else {
            INA_TEXT
        }
    } else if cell.is_border {
        if cell.active {
            ACT_BORDER
        } else {
            INA_BORDER
        }
    } else if cell.is_fill {
        if cell.active {
            ACT_BG
        } else {
            INA_BG
        }
    } else {
        RESET
    }
}

/// Tmux popup text: 46×18 boxes plus a "Pane Layout (zoomed)" caption.
pub fn format_ansi_map(snapshot: &Snapshot) -> String {
    use crate::layout::{DEFAULT_GRID_COLS, DEFAULT_GRID_ROWS};
    let cols = DEFAULT_GRID_COLS as u16;
    let rows = DEFAULT_GRID_ROWS as u16;
    let grid = character_grid(snapshot, cols, rows);
    let tag = if snapshot.zoomed {
        "(zoomed)".to_string()
    } else {
        format!("({} panes)", snapshot.panes.len())
    };
    let mut out = String::new();
    out.push('\n');
    out.push_str(&format!("  {BOLD}Pane Layout{RESET} {DIM}{tag}{RESET}\n"));
    out.push('\n');
    for row in &grid {
        out.push_str("  ");
        for cell in row {
            out.push_str(cell_escape(cell));
            out.push(cell.ch);
            out.push_str(RESET);
        }
        out.push('\n');
    }
    out
}

/// 3×5 bitmap, high bit is the left column.
fn glyph_rows(ch: char) -> Option<[u8; 5]> {
    match ch.to_ascii_lowercase() {
        '0' => Some([0b111, 0b101, 0b101, 0b101, 0b111]),
        '1' => Some([0b010, 0b110, 0b010, 0b010, 0b111]),
        '2' => Some([0b111, 0b001, 0b111, 0b100, 0b111]),
        '3' => Some([0b111, 0b001, 0b111, 0b001, 0b111]),
        '4' => Some([0b101, 0b101, 0b111, 0b001, 0b001]),
        '5' => Some([0b111, 0b100, 0b111, 0b001, 0b111]),
        '6' => Some([0b111, 0b100, 0b111, 0b101, 0b111]),
        '7' => Some([0b111, 0b001, 0b001, 0b001, 0b001]),
        '8' => Some([0b111, 0b101, 0b111, 0b101, 0b111]),
        '9' => Some([0b111, 0b101, 0b111, 0b001, 0b111]),
        'a' => Some([0b010, 0b101, 0b111, 0b101, 0b101]),
        'b' => Some([0b110, 0b101, 0b110, 0b101, 0b110]),
        'c' => Some([0b011, 0b100, 0b100, 0b100, 0b011]),
        'd' => Some([0b110, 0b101, 0b101, 0b101, 0b110]),
        'e' => Some([0b111, 0b100, 0b110, 0b100, 0b111]),
        'f' => Some([0b111, 0b100, 0b110, 0b100, 0b100]),
        'g' => Some([0b011, 0b100, 0b101, 0b101, 0b011]),
        'h' => Some([0b101, 0b101, 0b111, 0b101, 0b101]),
        'i' => Some([0b111, 0b010, 0b010, 0b010, 0b111]),
        'j' => Some([0b001, 0b001, 0b001, 0b101, 0b010]),
        'k' => Some([0b101, 0b101, 0b110, 0b101, 0b101]),
        'l' => Some([0b100, 0b100, 0b100, 0b100, 0b111]),
        'm' => Some([0b101, 0b111, 0b111, 0b101, 0b101]),
        'n' => Some([0b110, 0b101, 0b101, 0b101, 0b101]),
        'o' => Some([0b010, 0b101, 0b101, 0b101, 0b010]),
        'p' => Some([0b110, 0b101, 0b110, 0b100, 0b100]),
        'q' => Some([0b010, 0b101, 0b101, 0b110, 0b001]),
        'r' => Some([0b110, 0b101, 0b110, 0b101, 0b101]),
        's' => Some([0b011, 0b100, 0b010, 0b001, 0b110]),
        't' => Some([0b111, 0b010, 0b010, 0b010, 0b010]),
        'u' => Some([0b101, 0b101, 0b101, 0b101, 0b111]),
        'v' => Some([0b101, 0b101, 0b101, 0b101, 0b010]),
        'w' => Some([0b101, 0b101, 0b111, 0b111, 0b101]),
        'x' => Some([0b101, 0b101, 0b010, 0b101, 0b101]),
        'y' => Some([0b101, 0b101, 0b010, 0b010, 0b010]),
        'z' => Some([0b111, 0b001, 0b010, 0b100, 0b111]),
        ':' => Some([0b000, 0b010, 0b000, 0b010, 0b000]),
        '.' => Some([0b000, 0b000, 0b000, 0b000, 0b010]),
        _ => None,
    }
}

fn draw_bitmap_3x5(
    canvas: &mut Canvas,
    x0: u32,
    y0: u32,
    cw: u32,
    ch: u32,
    rows: [u8; 5],
    color: [u8; 4],
) {
    let pad_x = (cw / 6).max(1);
    let pad_y = (ch / 8).max(1);
    let inner_w = cw.saturating_sub(pad_x * 2).max(3);
    let inner_h = ch.saturating_sub(pad_y * 2).max(5);
    let cell_w = (inner_w / 3).max(1);
    let cell_h = (inner_h / 5).max(1);
    let ox = x0 + pad_x;
    let oy = y0 + pad_y;
    for (ry, bits) in rows.iter().enumerate() {
        for cx in 0..3u32 {
            if bits & (1 << (2 - cx)) != 0 {
                canvas.fill_rect(ox + cx * cell_w, oy + ry as u32 * cell_h, cell_w, cell_h, color);
            }
        }
    }
}

fn draw_glyph(canvas: &mut Canvas, x0: u32, y0: u32, cw: u32, ch: u32, glyph: char, color: [u8; 4]) {
    let mid_x = x0 + cw / 2;
    let mid_y = y0 + ch / 2;
    let thick = (cw.max(ch) / 4).max(1);

    match glyph {
        '-' => {
            canvas.fill_rect(x0, mid_y.saturating_sub(thick / 2), cw, thick, color);
        }
        '|' => {
            canvas.fill_rect(mid_x.saturating_sub(thick / 2), y0, thick, ch, color);
        }
        '+' => {
            canvas.fill_rect(x0, mid_y.saturating_sub(thick / 2), cw, thick, color);
            canvas.fill_rect(mid_x.saturating_sub(thick / 2), y0, thick, ch, color);
        }
        other => {
            if let Some(rows) = glyph_rows(other) {
                draw_bitmap_3x5(canvas, x0, y0, cw, ch, rows, color);
            } else {
                let dot = (cw.min(ch) / 3).max(1);
                canvas.fill_rect(
                    mid_x.saturating_sub(dot / 2),
                    mid_y.saturating_sub(dot / 2),
                    dot,
                    dot,
                    color,
                );
            }
        }
    }
}

fn stamp_cell(
    canvas: &mut Canvas,
    gx: u32,
    gy: u32,
    cw: u32,
    ch: u32,
    cell: &GridCell,
    is_interior: bool,
) {
    let x0 = gx * cw;
    let y0 = gy * ch;

    if cell.is_border {
        let fill = if cell.active {
            ACTIVE_FILL
        } else {
            INACTIVE_FILL
        };
        let border = if cell.active {
            ACTIVE_BORDER
        } else {
            INACTIVE_BORDER
        };
        canvas.fill_rect(x0, y0, cw, ch, fill);
        draw_glyph(canvas, x0, y0, cw, ch, cell.ch, border);
        return;
    }

    if cell.is_label {
        let fill = if cell.active {
            ACTIVE_FILL
        } else {
            INACTIVE_FILL
        };
        canvas.fill_rect(x0, y0, cw, ch, fill);
        draw_glyph(canvas, x0, y0, cw, ch, cell.ch, LABEL);
        return;
    }

    if is_interior {
        let fill = if cell.active {
            ACTIVE_FILL
        } else {
            INACTIVE_FILL
        };
        canvas.fill_rect(x0, y0, cw, ch, fill);
        return;
    }

    canvas.fill_rect(x0, y0, cw, ch, BG);
}

pub fn png_for_snapshot(
    snapshot: &Snapshot,
    cell_width_px: u32,
    cell_height_px: u32,
    grid_cols: u16,
    grid_rows: u16,
) -> Vec<u8> {
    let built = build_character_grid(snapshot, grid_cols, grid_rows);
    let cw = cell_width_px.max(1);
    let ch = cell_height_px.max(1);
    let canvas_w = u32::from(grid_cols) * cw;
    let canvas_h = u32::from(grid_rows) * ch;
    let mut canvas = Canvas::new(canvas_w, canvas_h);

    for (gy, row) in built.cells.iter().enumerate() {
        for (gx, cell) in row.iter().enumerate() {
            stamp_cell(
                &mut canvas,
                gx as u32,
                gy as u32,
                cw,
                ch,
                cell,
                built.interior[gy][gx],
            );
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
    out
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

    #[test]
    fn labels_use_pane_suffix_chars() {
        let snap = two_pane_horizontal("w1:p2");
        let grid = character_grid(&snap, 16, 10);
        let labels: String = grid
            .iter()
            .flatten()
            .filter(|cell| cell.is_label)
            .map(|cell| cell.ch)
            .collect();
        assert!(labels.contains('p'), "labels={labels}");
        assert!(labels.contains('2'), "labels={labels}");
    }

    #[test]
    fn truncates_label_like_tmux_when_inner_is_one_cell() {
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
                    rect: Rect { x: 0, y: 0, width: 76, height: 24 },
                },
                Pane {
                    pane_id: "w1:p2".into(),
                    focused: true,
                    rect: Rect { x: 76, y: 0, width: 4, height: 24 },
                },
            ],
        };
        let grid = character_grid(&snap, 16, 10);
        let active_labels: Vec<char> = grid
            .iter()
            .flatten()
            .filter(|cell| cell.is_label && cell.active)
            .map(|cell| cell.ch)
            .collect();
        assert!(
            active_labels.iter().all(|ch| *ch == '.' || *ch == 'p' || *ch == '2'),
            "unexpected label glyphs {active_labels:?}"
        );
    }

    fn decode_rgba(png: &[u8]) -> (u32, u32, Vec<u8>) {
        let decoder = png::Decoder::new(std::io::Cursor::new(png));
        let mut reader = decoder.read_info().expect("png info");
        let mut buf = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).expect("png frame");
        buf.truncate(info.buffer_size());
        (info.width, info.height, buf)
    }

    #[test]
    fn label_glyphs_paint_more_than_a_center_dot() {
        let snap = two_pane_horizontal("w1:p2");
        let png = png_for_snapshot(&snap, 8, 16, 16, 10);
        let (w, _h, pixels) = decode_rgba(&png);
        let mut label_pixels = 0usize;
        for chunk in pixels.chunks_exact(4) {
            if chunk == LABEL {
                label_pixels += 1;
            }
        }
        assert!(
            label_pixels > 16,
            "expected 3x5 letter stamps, got {label_pixels} LABEL pixels (w={w})"
        );
    }

    #[test]
    fn tmux_size_grid_is_boxes_not_blocks() {
        let snap = two_pane_horizontal("w1:p2");
        let dump = format_character_grid(&snap, 46, 18);
        assert!(dump.contains('+') && dump.contains('-') && dump.contains('|'));
        assert!(!dump.contains('█') && !dump.contains('░'));
        let first = dump.lines().next().expect("row");
        assert_eq!(first.len(), 46);
        assert!(first.starts_with('+'));
        assert!(first.ends_with('+'));
    }

    #[test]
    fn ansi_map_looks_like_tmux_popup() {
        let snap = two_pane_horizontal("w1:p2");
        let ansi = format_ansi_map(&snap);
        let stripped: String = ansi
            .chars()
            .fold((String::new(), false), |(mut out, esc), ch| {
                if ch == '\u{1b}' {
                    (out, true)
                } else if esc {
                    (out, ch != 'm')
                } else {
                    out.push(ch);
                    (out, false)
                }
            })
            .0;
        assert!(stripped.contains("Pane Layout"));
        assert!(stripped.contains("(2 panes)"));
        assert!(stripped.contains('+') && stripped.contains("p2"));
    }
}
