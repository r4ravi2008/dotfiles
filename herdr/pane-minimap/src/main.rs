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

use herdr_pane_minimap::ascii;
use herdr_pane_minimap::herdr::{self, Client};
use herdr_pane_minimap::layout::Snapshot;

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
    last_workspace: Option<String>,
    seq: u64,
    cleared_overlay: bool,
}

fn clear_overlay(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    if let Some(pane) = state.last_pane.take() {
        let _ = client.graphics_clear(&pane);
    }
    if !state.cleared_overlay {
        for pane in &snapshot.panes {
            let _ = client.graphics_clear(&pane.pane_id);
        }
        state.cleared_overlay = true;
    }
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

fn apply(client: &Client, state: &mut ApplyState, snapshot: &Snapshot) {
    if snapshot.tab_id != state.focused_tab && !state.focused_tab.is_empty() {
        return;
    }
    state.focused_tab = snapshot.tab_id.clone();
    clear_overlay(client, state, snapshot);

    if let Some(old) = state.last_workspace.clone() {
        if old != snapshot.workspace_id {
            let cleared = ascii::cleared_sidebar_tokens();
            if report_tokens(client, state, &old, &cleared) {
                log_line(&format!("cleared sidebar tokens on {old}"));
            }
        }
    }

    let tokens = ascii::sidebar_tokens(snapshot);
    if report_tokens(client, state, &snapshot.workspace_id, &tokens) {
        let shown = !tokens
            .get(ascii::TITLE_TOKEN)
            .map(|v| v.is_null())
            .unwrap_or(true);
        log_line(&format!(
            "sidebar {} {} focus={} panes={}",
            if shown { "set" } else { "hide" },
            snapshot.workspace_id,
            snapshot.focused_pane_id,
            snapshot.panes.len()
        ));
        state.last_workspace = Some(snapshot.workspace_id.clone());
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

fn refresh_from_layout(client: &Client, state: &mut ApplyState) {
    if let Ok(snap) = client.pane_layout() {
        state.focused_tab = snap.tab_id.clone();
        apply(client, state, &snap);
    }
}

fn watch() -> std::io::Result<()> {
    kill_existing();
    write_pid();
    log_line("watch started");
    let mut state = ApplyState {
        focused_tab: String::new(),
        last_pane: None,
        last_workspace: None,
        seq: 0,
        cleared_overlay: false,
    };
    loop {
        match Client::connect() {
            Ok(client) => {
                refresh_from_layout(&client, &mut state);
                match herdr::subscribe_stream() {
                    Ok(mut reader) => {
                        let mut line = String::new();
                        while reader.read_line(&mut line)? > 0 {
                            if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) {
                                if is_subscribe_ack(&value) {
                                    line.clear();
                                    continue;
                                }
                                if herdr::matches_event(&value, "layout.updated")
                                    || herdr::matches_event(&value, "tab.focused")
                                    || herdr::matches_event(&value, "workspace.focused")
                                    || herdr::matches_event(&value, "pane.focused")
                                {
                                    refresh_from_layout(&client, &mut state);
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

fn main() {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        Some("watch") => {
            if let Err(err) = watch() {
                log_line(&format!("watch exited: {err}"));
                std::process::exit(1);
            }
        }
        _ => {
            eprintln!("usage: herdr-pane-minimap watch");
            std::process::exit(2);
        }
    }
}
