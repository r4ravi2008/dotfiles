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
    if info.cell_width_px == 0 || info.cell_height_px == 0 {
        return;
    }
    if !info.pane_visible {
        if let Some(pane) = state.last_pane.take() {
            let _ = client.graphics_clear(&pane);
        }
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
    let mut state = ApplyState {
        focused_tab: String::new(),
        last_pane: None,
        logged_disabled: false,
    };
    loop {
        match Client::connect() {
            Ok(client) => {
                if let Ok(snap) = client.pane_layout() {
                    state.focused_tab = snap.tab_id.clone();
                    apply(&client, &mut state, &snap);
                    match herdr::subscribe_stream() {
                        Ok(mut reader) => {
                            let mut line = String::new();
                            while reader.read_line(&mut line)? > 0 {
                                if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) {
                                    if is_subscribe_ack(&value) {
                                        line.clear();
                                        continue;
                                    }
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
