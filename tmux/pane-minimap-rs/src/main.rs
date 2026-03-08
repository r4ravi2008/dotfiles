use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::process::Command;
use std::thread;
use std::time::Duration;

const DISPLAY_SECONDS: f64 = 0.07;
const PIDFILE: &str = "/tmp/tmux-minimap.pid";

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";

const ACT_BG: &str = "\x1b[44m";
const INA_BG: &str = "\x1b[48;5;236m";
const INA_BORDER: &str = "\x1b[90m";

const CANVAS_W: i32 = 46;
const CANVAS_H: i32 = 18;

#[derive(Default)]
struct Args {
    window_id: String,
    active_pane_id: String,
}

#[derive(Clone)]
enum LayoutNode {
    Container {
        children: Vec<LayoutNode>,
    },
    Pane {
        pane_num: String,
        left: i32,
        top: i32,
        width: i32,
        height: i32,
    },
}

#[derive(Clone)]
struct LayoutPane {
    pane_num: String,
    left: i32,
    top: i32,
    width: i32,
    height: i32,
}

#[derive(Clone)]
struct PaneMeta {
    pane_id: String,
    idx: i32,
    cmd: String,
}

#[derive(Clone)]
struct Pane {
    idx: i32,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    cmd: String,
    active: bool,
}

#[derive(Clone, Copy)]
enum Color {
    Reset,
    ActiveBorder,
    ActiveFill,
    ActiveText,
    InactiveBorder,
    InactiveFill,
    InactiveText,
}

impl Color {
    fn escape(self) -> &'static str {
        match self {
            Self::Reset => RESET,
            Self::ActiveBorder => "\x1b[94m\x1b[1m",
            Self::ActiveFill => ACT_BG,
            Self::ActiveText => "\x1b[44m\x1b[97m\x1b[1m",
            Self::InactiveBorder => INA_BORDER,
            Self::InactiveFill => INA_BG,
            Self::InactiveText => "\x1b[48;5;236m\x1b[37m",
        }
    }
}

#[derive(Clone, Copy)]
struct Cell {
    ch: char,
    color: Color,
}

#[derive(Clone, Copy)]
struct Style {
    border: Color,
    fill: Color,
    text: Color,
}

fn tmux(args: &[&str]) -> io::Result<String> {
    let output = Command::new("tmux").args(args).output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(io::Error::other(format!(
            "tmux command failed: {}",
            stderr.trim()
        )));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn parse_args() -> Args {
    let mut parsed = Args::default();
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--window-id" => {
                if let Some(v) = args.next() {
                    parsed.window_id = v;
                }
            }
            "--active-pane-id" => {
                if let Some(v) = args.next() {
                    parsed.active_pane_id = v;
                }
            }
            _ => {}
        }
    }
    parsed
}

fn clamp(v: i32, lo: i32, hi: i32) -> i32 {
    v.max(lo).min(hi)
}

fn is_expected_minimap_process(pid: u32) -> bool {
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "command="])
        .output();
    let Ok(output) = output else {
        return false;
    };
    if !output.status.success() {
        return false;
    }
    let cmdline = String::from_utf8_lossy(&output.stdout);
    cmdline.contains("pane-minimap")
}

fn kill_existing() {
    let Ok(raw) = fs::read_to_string(PIDFILE) else {
        return;
    };
    let Ok(old_pid) = raw.trim().parse::<u32>() else {
        return;
    };
    if old_pid == std::process::id() || !is_expected_minimap_process(old_pid) {
        return;
    }
    let _ = Command::new("kill")
        .args(["-TERM", &old_pid.to_string()])
        .status();
}

fn write_pid() -> io::Result<()> {
    fs::write(PIDFILE, std::process::id().to_string())
}

fn cleanup() {
    let _ = fs::remove_file(PIDFILE);
}

struct PidGuard;

impl Drop for PidGuard {
    fn drop(&mut self) {
        cleanup();
    }
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn new(layout: &'a str) -> Self {
        Self {
            bytes: layout.as_bytes(),
            pos: 0,
        }
    }

    fn at_end(&self) -> bool {
        self.pos >= self.bytes.len()
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn parse_num(&mut self) -> Result<i32, String> {
        let start = self.pos;
        while let Some(ch) = self.peek() {
            if ch.is_ascii_digit() {
                self.pos += 1;
            } else {
                break;
            }
        }
        if self.pos == start {
            return Err(format!("expected number at position {start}"));
        }
        std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "invalid utf-8 in number".to_string())?
            .parse::<i32>()
            .map_err(|_| "invalid integer in layout".to_string())
    }

    fn expect(&mut self, expected: u8, message: &str) -> Result<(), String> {
        if self.peek() == Some(expected) {
            self.pos += 1;
            Ok(())
        } else {
            Err(message.to_string())
        }
    }

    fn parse_node(&mut self) -> Result<LayoutNode, String> {
        let width = self.parse_num()?;
        self.expect(b'x', "invalid layout: missing x")?;
        let height = self.parse_num()?;
        self.expect(b',', "invalid layout: missing comma after height")?;
        let left = self.parse_num()?;
        self.expect(b',', "invalid layout: missing comma after left")?;
        let top = self.parse_num()?;

        if let Some(open) = self.peek() {
            if open == b'[' || open == b'{' {
                let close = if open == b'[' { b']' } else { b'}' };
                self.pos += 1;
                let mut children = Vec::new();
                loop {
                    children.push(self.parse_node()?);
                    let Some(next) = self.peek() else {
                        return Err("invalid layout: unterminated container".to_string());
                    };
                    if next == b',' {
                        self.pos += 1;
                        continue;
                    }
                    if next == close {
                        self.pos += 1;
                        break;
                    }
                    return Err("invalid layout: unexpected separator".to_string());
                }
                return Ok(LayoutNode::Container { children });
            }
        }

        if self.peek() == Some(b',') {
            self.pos += 1;
            let pane_num = self.parse_num()?.to_string();
            return Ok(LayoutNode::Pane {
                pane_num,
                left,
                top,
                width,
                height,
            });
        }

        Err("invalid layout: expected container or pane id".to_string())
    }
}

fn collect_layout_panes(node: &LayoutNode, out: &mut Vec<LayoutPane>) {
    match node {
        LayoutNode::Pane {
            pane_num,
            left,
            top,
            width,
            height,
        } => out.push(LayoutPane {
            pane_num: pane_num.clone(),
            left: *left,
            top: *top,
            width: *width,
            height: *height,
        }),
        LayoutNode::Container { children } => {
            for child in children {
                collect_layout_panes(child, out);
            }
        }
    }
}

fn scaled_start(v: i32, min: i32, canvas: i32, span: i32) -> i32 {
    let num = i64::from(v - min) * i64::from(canvas);
    (num / i64::from(span)) as i32
}

fn scaled_end(v: i32, min: i32, canvas: i32, span: i32) -> i32 {
    let num = i64::from(v - min) * i64::from(canvas);
    ((num + i64::from(span) - 1) / i64::from(span) - 1) as i32
}

fn render(window_id_arg: &str, active_pane_id_arg: &str) -> io::Result<bool> {
    let window_id = if window_id_arg.is_empty() {
        tmux(&["display", "-p", "#{window_id}"])?
    } else {
        window_id_arg.to_string()
    };

    let active_pane_id = if active_pane_id_arg.is_empty() {
        tmux(&["display", "-p", "#{pane_id}"])?
    } else {
        active_pane_id_arg.to_string()
    };

    let zoomed = tmux(&[
        "display-message",
        "-p",
        "-t",
        &window_id,
        "#{window_zoomed_flag}",
    ])? == "1";

    let pane_meta_raw = tmux(&[
        "list-panes",
        "-t",
        &window_id,
        "-F",
        "#{pane_id}|#{pane_index}|#{pane_current_command}",
    ])?;

    let layout_raw = tmux(&[
        "display-message",
        "-p",
        "-t",
        &window_id,
        "#{window_layout}",
    ])?;
    let Some((_, layout)) = layout_raw.split_once(',') else {
        return Ok(false);
    };

    let mut parser = Parser::new(layout);
    let layout_root = match parser.parse_node() {
        Ok(node) => node,
        Err(_) => return Ok(false),
    };
    if !parser.at_end() {
        return Ok(false);
    }

    let mut layout_panes = Vec::new();
    collect_layout_panes(&layout_root, &mut layout_panes);

    let mut pane_meta: HashMap<String, PaneMeta> = HashMap::new();
    for line in pane_meta_raw.lines() {
        let mut parts = line.splitn(3, '|');
        let (Some(pane_id), Some(idx), Some(cmd)) = (parts.next(), parts.next(), parts.next())
        else {
            continue;
        };
        pane_meta.insert(
            pane_id.trim_start_matches('%').to_string(),
            PaneMeta {
                pane_id: pane_id.to_string(),
                idx: idx.parse::<i32>().unwrap_or(0),
                cmd: cmd.to_string(),
            },
        );
    }

    let mut panes = Vec::new();
    for lp in layout_panes {
        let Some(meta) = pane_meta.get(&lp.pane_num) else {
            continue;
        };
        panes.push(Pane {
            idx: meta.idx,
            left: lp.left,
            top: lp.top,
            right: lp.left + lp.width,
            bottom: lp.top + lp.height,
            cmd: meta.cmd.clone(),
            active: meta.pane_id == active_pane_id,
        });
    }

    if panes.is_empty() {
        return Ok(false);
    }

    if !panes.iter().any(|p| p.active) {
        panes[0].active = true;
    }

    if panes.len() < 2 {
        return Ok(false);
    }

    let min_left = panes.iter().map(|p| p.left).min().unwrap_or(0);
    let min_top = panes.iter().map(|p| p.top).min().unwrap_or(0);
    let max_right = panes.iter().map(|p| p.right).max().unwrap_or(1);
    let max_bottom = panes.iter().map(|p| p.bottom).max().unwrap_or(1);
    let span_x = (max_right - min_left).max(1);
    let span_y = (max_bottom - min_top).max(1);

    let mut grid = vec![
        Cell {
            ch: ' ',
            color: Color::Reset,
        };
        (CANVAS_W * CANVAS_H) as usize
    ];

    let mut put = |x: i32, y: i32, ch: char, color: Color| {
        if (0..CANVAS_W).contains(&x) && (0..CANVAS_H).contains(&y) {
            grid[(y * CANVAS_W + x) as usize] = Cell { ch, color };
        }
    };

    panes.sort_by_key(|p| p.active);

    for p in &panes {
        let left = clamp(
            scaled_start(p.left, min_left, CANVAS_W, span_x),
            0,
            CANVAS_W - 1,
        );
        let right = clamp(
            scaled_end(p.right, min_left, CANVAS_W, span_x),
            left,
            CANVAS_W - 1,
        );
        let top = clamp(
            scaled_start(p.top, min_top, CANVAS_H, span_y),
            0,
            CANVAS_H - 1,
        );
        let bottom = clamp(
            scaled_end(p.bottom, min_top, CANVAS_H, span_y),
            top,
            CANVAS_H - 1,
        );

        let style = if p.active {
            Style {
                border: Color::ActiveBorder,
                fill: Color::ActiveFill,
                text: Color::ActiveText,
            }
        } else {
            Style {
                border: Color::InactiveBorder,
                fill: Color::InactiveFill,
                text: Color::InactiveText,
            }
        };

        for x in (left + 1)..right {
            put(x, top, '-', style.border);
            put(x, bottom, '-', style.border);
        }
        for y in (top + 1)..bottom {
            put(left, y, '|', style.border);
            put(right, y, '|', style.border);
        }

        put(left, top, '+', style.border);
        put(right, top, '+', style.border);
        put(left, bottom, '+', style.border);
        put(right, bottom, '+', style.border);

        for y in (top + 1)..bottom {
            for x in (left + 1)..right {
                put(x, y, ' ', style.fill);
            }
        }

        let inner_w = right - left - 1;
        let inner_h = bottom - top - 1;
        if inner_w > 0 && inner_h > 0 {
            let mut label = format!("{}:{}", p.idx, p.cmd);
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
                let cx = lx + i as i32;
                if cx <= right - 1 {
                    put(cx, ly, *ch, style.text);
                }
            }
        }
    }

    println!();
    let tag = if zoomed {
        "(zoomed)".to_string()
    } else {
        format!("({} panes)", panes.len())
    };
    println!("  {BOLD}Pane Layout{RESET} {DIM}{tag}{RESET}");
    println!();

    for y in 0..CANVAS_H {
        let mut row = String::from("  ");
        for x in 0..CANVAS_W {
            let cell = grid[(y * CANVAS_W + x) as usize];
            row.push_str(cell.color.escape());
            row.push(cell.ch);
            row.push_str(RESET);
        }
        println!("{row}");
    }

    io::stdout().flush()?;
    Ok(true)
}

fn main() {
    let args = parse_args();

    kill_existing();
    if write_pid().is_err() {
        return;
    }
    let _pid_guard = PidGuard;

    let shown = render(&args.window_id, &args.active_pane_id).unwrap_or(false);
    if shown {
        thread::sleep(Duration::from_secs_f64(DISPLAY_SECONDS));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_simple_layout_tree() {
        let layout = "238x61,0,0[119x61,0,0,1,118x61,120,0,2]";
        let mut parser = Parser::new(layout);
        let root = parser.parse_node().expect("layout should parse");
        assert!(parser.at_end());

        let mut panes = Vec::new();
        collect_layout_panes(&root, &mut panes);

        assert_eq!(panes.len(), 2);
        assert_eq!(panes[0].pane_num, "1");
        assert_eq!(panes[1].pane_num, "2");
    }

    #[test]
    fn rejects_invalid_layout() {
        let mut parser = Parser::new("bad-layout");
        assert!(parser.parse_node().is_err());
    }

    #[test]
    fn scales_bounds_like_python_logic() {
        let min = 0;
        let span = 238;
        assert_eq!(scaled_start(0, min, CANVAS_W, span), 0);
        assert_eq!(scaled_end(238, min, CANVAS_W, span), CANVAS_W - 1);
    }
}
