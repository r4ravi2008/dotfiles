use std::env;
use std::fs;
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::Duration;

fn log_line(msg: &str) {
    let mut err = std::io::stderr().lock();
    let _ = writeln!(err, "herdr-pane-minimap: {msg}");
    let _ = err.flush();
}

use herdr_pane_minimap::apply::{self, ApplyMode};
use herdr_pane_minimap::herdr::{self, Client};
use herdr_pane_minimap::layout::Snapshot;
use herdr_pane_minimap::render::{format_ansi_map, format_character_grid, png_for_snapshot};
use herdr_pane_minimap::tokens::cleared_minimap_tokens;

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
    if !cmdline.contains("minimap") {
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
    last_graphics_pane: Option<String>,
    last_popup: Option<String>,
    last_workspace: Option<String>,
    seq: u64,
}

fn report_tokens(
    client: &Client,
    state: &mut ApplyState,
    workspace_id: &str,
    tokens: &serde_json::Map<String, serde_json::Value>,
) -> bool {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    state.seq = now.max(state.seq.saturating_add(1));
    match client.workspace_report_tokens(workspace_id, tokens, state.seq) {
        Ok(()) => true,
        Err(err) => {
            log_line(&format!("report-metadata {workspace_id} failed: {err}"));
            false
        }
    }
}

fn clear_tokens_if_needed(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    if state.last_workspace.as_deref() == Some(snapshot.workspace_id.as_str()) {
        return;
    }
    let cleared = cleared_minimap_tokens();
    if report_tokens(client, state, &snapshot.workspace_id, &cleared) {
        log_line(&format!(
            "cleared sidebar tokens on {}",
            snapshot.workspace_id
        ));
    }
    if let Some(old) = state.last_workspace.clone() {
        if old != snapshot.workspace_id {
            let _ = report_tokens(client, state, &old, &cleared);
            log_line(&format!("cleared sidebar tokens on {old}"));
        }
    }
    state.last_workspace = Some(snapshot.workspace_id.clone());
}

fn clear_graphics(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    if let Some(old) = state.last_graphics_pane.take() {
        let _ = client.graphics_clear(&old);
    }
    for pane in &snapshot.panes {
        let _ = client.graphics_clear(&pane.pane_id);
    }
}

fn close_popup(client: &Client, state: &mut ApplyState) {
    if let Some(id) = state.last_popup.take() {
        let _ = client.plugin_pane_close(&id);
        log_line(&format!("closed popup {id}"));
    }
}

fn hide_idle(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    clear_tokens_if_needed(client, state, snapshot);
    clear_graphics(client, state, snapshot);
    close_popup(client, state);
    kill_flash_helpers();
}

fn kill_flash_helpers() {
    let _ = Command::new("pkill")
        .args(["-f", "herdr-pane-minimap flash"])
        .status();
}

fn open_flash_popup(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    close_popup(client, state);
    kill_flash_helpers();
    thread::sleep(Duration::from_millis(40));
    let json = match serde_json::to_string(snapshot) {
        Ok(j) => j,
        Err(err) => {
            log_line(&format!("serialize snapshot failed: {err}"));
            return;
        }
    };
    match client.plugin_pane_open(&json) {
        Ok(pane_id) => {
            log_line(&format!(
                "flash {} focus={} panes={}",
                snapshot.workspace_id,
                snapshot.focused_pane_id,
                snapshot.panes.len()
            ));
            if !pane_id.is_empty() {
                state.last_popup = Some(pane_id);
            }
        }
        Err(err) => {
            let msg = err.to_string();
            if msg.contains("popup already open") {
                log_line("flash coalesced (popup already open)");
            } else {
                log_line(&format!("plugin.pane.open failed: {err}"));
            }
        }
    }
}

fn on_pane_focused(client: &Client, state: &mut ApplyState) {
    let Ok(snapshot) = client.pane_layout() else {
        return;
    };
    clear_tokens_if_needed(client, state, &snapshot);
    clear_graphics(client, state, &snapshot);
    match apply::apply_mode(&snapshot) {
        ApplyMode::Hide => {
            close_popup(client, state);
            log_line(&format!(
                "idle {} focus={} zoomed={} panes={}",
                snapshot.workspace_id,
                snapshot.focused_pane_id,
                snapshot.zoomed,
                snapshot.panes.len()
            ));
        }
        ApplyMode::Flash => open_flash_popup(client, state, &snapshot),
    }
}

fn on_layout_or_tab(client: &Client, state: &mut ApplyState) {
    let Ok(snapshot) = client.pane_layout() else {
        return;
    };
    if apply::apply_mode(&snapshot) == ApplyMode::Hide {
        hide_idle(client, state, &snapshot);
        log_line(&format!(
            "idle {} focus={} zoomed={} panes={}",
            snapshot.workspace_id,
            snapshot.focused_pane_id,
            snapshot.zoomed,
            snapshot.panes.len()
        ));
    }
}

fn is_subscribe_ack(value: &serde_json::Value) -> bool {
    if value.get("event").is_some() {
        return false;
    }
    if value.get("id").and_then(|v| v.as_str()) == Some("minimap-sub") {
        return true;
    }
    value.get("result").is_some()
}

fn watch() -> std::io::Result<()> {
    kill_existing();
    write_pid();
    log_line("watch started");
    let mut state = ApplyState {
        last_graphics_pane: None,
        last_popup: None,
        last_workspace: None,
        seq: 0,
    };
    loop {
        match Client::connect() {
            Ok(client) => {
                if let Ok(snap) = client.pane_layout() {
                    hide_idle(&client, &mut state, &snap);
                }
                match herdr::subscribe_stream() {
                    Ok(mut reader) => {
                        let mut line = String::new();
                        while reader.read_line(&mut line)? > 0 {
                            if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) {
                                if is_subscribe_ack(&value) {
                                    line.clear();
                                    continue;
                                }
                                if herdr::matches_event(&value, "pane.focused") {
                                    on_pane_focused(&client, &mut state);
                                } else if herdr::matches_event(&value, "layout.updated")
                                    || herdr::matches_event(&value, "tab.focused")
                                    || herdr::matches_event(&value, "workspace.focused")
                                {
                                    on_layout_or_tab(&client, &mut state);
                                }
                            }
                            line.clear();
                        }
                    }
                    Err(_) => thread::sleep(Duration::from_secs(2)),
                }
            }
            Err(_) => thread::sleep(Duration::from_secs(2)),
        }
        thread::sleep(Duration::from_secs(2));
    }
}

fn flash_current() -> std::io::Result<()> {
    let snapshot = if let Ok(raw) = env::var("HERDR_MINIMAP_SNAPSHOT") {
        serde_json::from_str::<Snapshot>(&raw)
            .map_err(|err| std::io::Error::other(format!("snapshot env: {err}")))?
    } else {
        Client::connect()?.pane_layout()?
    };
    if apply::apply_mode(&snapshot) != ApplyMode::Flash {
        return Ok(());
    }
    let mut out = std::io::stdout().lock();
    write!(out, "{}", format_ansi_map(&snapshot))?;
    out.flush()?;
    thread::sleep(Duration::from_millis(apply::FLASH_MS));
    Ok(())
}

fn dump_current(path: &str) -> std::io::Result<()> {
    let client = Client::connect()?;
    let snap = client.pane_layout()?;
    let place = layout_or_default(&snap);
    println!("{}", format_character_grid(&snap, place.0, place.1));
    let png = png_for_snapshot(&snap, 8, 16, place.0, place.1);
    fs::write(path, png)?;
    eprintln!(
        "wrote {path} grid={}x{} focus={} panes={}",
        place.0,
        place.1,
        snap.focused_pane_id,
        snap.panes.len()
    );
    Ok(())
}

fn layout_or_default(snap: &Snapshot) -> (u16, u16) {
    herdr_pane_minimap::layout::placement_for(snap)
        .map(|p| (p.grid_cols, p.grid_rows))
        .unwrap_or((
            herdr_pane_minimap::layout::DEFAULT_GRID_COLS as u16,
            herdr_pane_minimap::layout::DEFAULT_GRID_ROWS as u16,
        ))
}

fn main() {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("watch") => {
            if let Err(err) = watch() {
                log_line(&format!("watch exited: {err}"));
                std::process::exit(1);
            }
        }
        Some("flash") => {
            if let Err(err) = flash_current() {
                eprintln!("flash failed: {err}");
                std::process::exit(1);
            }
        }
        Some("dump") => {
            let path = args
                .next()
                .unwrap_or_else(|| "/tmp/herdr-minimap.png".into());
            if let Err(err) = dump_current(&path) {
                eprintln!("dump failed: {err}");
                std::process::exit(1);
            }
        }
        _ => {
            eprintln!("usage: herdr-pane-minimap watch|flash|dump [png]");
            std::process::exit(2);
        }
    }
}
