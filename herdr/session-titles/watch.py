#!/usr/bin/env python3
"""Copy terminal_title_stripped onto pane metadata titles for prefix+g."""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

SOURCE = "plugin:herdr-session-titles"
STATE_DIR = Path(
    os.environ.get(
        "HERDR_PLUGIN_STATE_DIR",
        os.path.expanduser("~/.config/herdr/plugin-state/herdr-session-titles"),
    )
)
SEQ_PATH = STATE_DIR / "seq.json"
HERDR = os.environ.get("HERDR_BIN_PATH") or "herdr"
SOCKET_PATH = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser(
    "~/.config/herdr/herdr.sock"
)

AGENT_KIND_TITLES = {
    "antigravity",
    "claude",
    "codex",
    "copilot",
    "cursor",
    "devin",
    "droid",
    "grok",
    "hermes",
    "kimi",
    "kilo",
    "opencode",
    "pi",
    "qoder",
    "qwen",
}


def log(msg: str) -> None:
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    print(f"{stamp} {msg}", flush=True)


def load_seq() -> dict:
    try:
        return json.loads(SEQ_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return {"seq": 0, "titles": {}}


def save_seq(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    SEQ_PATH.write_text(json.dumps(state))


def herdr_json(*args: str) -> dict:
    result = subprocess.run(
        [HERDR, *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(err or f"herdr {' '.join(args)} failed")
    raw = (result.stdout or "").strip()
    if not raw:
        return {}
    data = json.loads(raw)
    if isinstance(data, dict) and "result" in data and "panes" not in data:
        inner = data["result"]
        if isinstance(inner, dict):
            return inner
    return data if isinstance(data, dict) else {}


def panes_from_list() -> list[dict]:
    data = herdr_json("pane", "list")
    panes = data.get("panes")
    return panes if isinstance(panes, list) else []


def pane_get(pane_id: str) -> dict | None:
    try:
        data = herdr_json("pane", "get", pane_id)
    except RuntimeError:
        return None
    pane = data.get("pane") if isinstance(data.get("pane"), dict) else data
    return pane if isinstance(pane, dict) else None


def useful_title(pane: dict) -> str | None:
    if not pane.get("agent"):
        return None
    title = (pane.get("terminal_title_stripped") or pane.get("terminal_title") or "").strip()
    if not title:
        return None
    title = re.sub(r"\s+[-–—]\s+[✅⏳✗×●○].*$", "", title).strip()
    title = re.sub(
        r"\s+[-–—]\s+(ready|working|idle|done)\b.*$",
        "",
        title,
        flags=re.IGNORECASE,
    ).strip()
    if not title:
        return None
    agent = str(pane.get("agent") or "").strip().lower()
    lowered = title.lower()
    if lowered == agent or lowered in AGENT_KIND_TITLES:
        return None
    if lowered.startswith("pane "):
        return None
    return title


def report_title(state: dict, pane_id: str, title: str | None, agent: str | None) -> None:
    previous = (state.get("titles") or {}).get(pane_id)
    if title == previous:
        return
    state["seq"] = int(state.get("seq") or 0) + 1
    cmd = [
        HERDR,
        "pane",
        "report-metadata",
        pane_id,
        "--source",
        SOURCE,
        "--seq",
        str(state["seq"]),
    ]
    if title:
        cmd.extend(["--title", title])
    else:
        cmd.append("--clear-title")
    if agent:
        cmd.extend(["--agent", agent])
    result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        state["seq"] = int(state["seq"]) - 1
        err = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(err or "report-metadata failed")
    titles = state.setdefault("titles", {})
    if title:
        titles[pane_id] = title
    else:
        titles.pop(pane_id, None)
    save_seq(state)


def sync_pane(state: dict, pane: dict) -> None:
    pane_id = pane.get("pane_id")
    if not pane_id:
        return
    title = useful_title(pane)
    agent = pane.get("agent")
    agent_label = str(agent) if agent else None
    try:
        report_title(state, pane_id, title, agent_label if title else None)
    except RuntimeError as exc:
        log(f"{pane_id}: {exc}")


def sync_all(state: dict) -> None:
    for pane in panes_from_list():
        sync_pane(state, pane)


def pane_id_from_event(event: dict) -> str | None:
    data = event.get("data") or event.get("params") or event
    if not isinstance(data, dict):
        return None
    pane = data.get("pane")
    if isinstance(pane, dict) and pane.get("pane_id"):
        return str(pane["pane_id"])
    for key in ("pane_id", "id"):
        value = data.get(key)
        if value:
            return str(value)
    return None


def event_name(event: dict) -> str:
    name = event.get("event") or event.get("type") or ""
    return str(name).replace("_", ".")


def subscribe() -> socket.socket:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(SOCKET_PATH)
    req = {
        "id": "session-titles-sub",
        "method": "events.subscribe",
        "params": {
            "subscriptions": [
                {"type": "pane.updated"},
                {"type": "pane.created"},
                {"type": "pane.agent_detected"},
                {"type": "pane.closed"},
            ]
        },
    }
    sock.sendall((json.dumps(req) + "\n").encode())
    return sock


def handle_event(state: dict, event: dict) -> None:
    name = event_name(event)
    pane_id = pane_id_from_event(event)
    if name == "pane.closed":
        if pane_id:
            titles = state.setdefault("titles", {})
            titles.pop(pane_id, None)
            save_seq(state)
        return
    if not pane_id:
        return
    pane = pane_get(pane_id)
    if pane:
        sync_pane(state, pane)


def watch() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state = load_seq()
    log("watch started")
    while True:
        try:
            sync_all(state)
            sock = subscribe()
            buf = b""
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    raise ConnectionError("socket closed")
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if not line.strip():
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if event.get("id") == "session-titles-sub" or (
                        "result" in event and "event" not in event
                    ):
                        continue
                    handle_event(state, event)
        except Exception as exc:
            log(f"reconnect: {exc}")
            time.sleep(1)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--once":
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        sync_all(load_seq())
        raise SystemExit(0)
    watch()
