use crate::layout::{pane_label, scaled_end, scaled_start, Snapshot};

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
    out
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
