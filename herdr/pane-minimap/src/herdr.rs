use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

use base64::Engine;

use crate::layout::Snapshot;

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

fn parse_rpc_line(line: &str) -> std::io::Result<serde_json::Value> {
    let value: serde_json::Value =
        serde_json::from_str(line).map_err(std::io::Error::other)?;
    if let Some(err) = value.get("error") {
        return Err(std::io::Error::other(err.to_string()));
    }
    Ok(value.get("result").cloned().unwrap_or(serde_json::Value::Null))
}

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
        Ok(Self {
            path: socket_path()?,
        })
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
        parse_rpc_line(&line)
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

    #[test]
    fn parse_rpc_line_rejects_error_replies() {
        let line = r#"{"id":"minimap-pane.layout","error":{"code":"not_found","message":"no pane"}}"#;
        let err = parse_rpc_line(line).unwrap_err();
        assert!(err.to_string().contains("not_found"));
    }

    #[test]
    fn parse_rpc_line_returns_result_field() {
        let line = r#"{"id":"minimap-pane.layout","result":{"layout":{"panes":[]}}}"#;
        let value = parse_rpc_line(line).expect("ok");
        assert!(value.get("layout").is_some());
    }

    fn sample_snapshot_json() -> serde_json::Value {
        serde_json::json!({
            "workspace_id": "w1",
            "tab_id": "w1:t1",
            "zoomed": false,
            "area": {"x": 0, "y": 0, "width": 80, "height": 24},
            "focused_pane_id": "w1:p2",
            "panes": [
                {
                    "pane_id": "w1:p1",
                    "focused": false,
                    "rect": {"x": 0, "y": 0, "width": 40, "height": 24}
                },
                {
                    "pane_id": "w1:p2",
                    "focused": true,
                    "rect": {"x": 40, "y": 0, "width": 40, "height": 24}
                }
            ]
        })
    }

    #[test]
    fn parses_layout_updated_nested_under_data_layout() {
        let raw = serde_json::json!({
            "event": "layout.updated",
            "data": {
                "layout": sample_snapshot_json()
            }
        });
        let snap = raw
            .pointer("/data/layout")
            .and_then(snapshot_from_layout_result)
            .expect("parse nested layout");
        assert_eq!(snap.panes.len(), 2);
        assert_eq!(snap.focused_pane_id, "w1:p2");
    }

    #[test]
    fn parses_layout_updated_snapshot_fields_at_data() {
        let raw = serde_json::json!({
            "event": "layout.updated",
            "data": sample_snapshot_json()
        });
        let snap = raw
            .get("data")
            .and_then(snapshot_from_layout_result)
            .expect("parse data snapshot");
        assert_eq!(snap.panes.len(), 2);
        assert_eq!(snap.tab_id, "w1:t1");
    }
}
