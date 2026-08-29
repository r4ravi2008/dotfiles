#!/usr/bin/env bash
set -euo pipefail
STATE="${HERDR_PLUGIN_STATE_DIR:-$HOME/.config/herdr/plugin-state/herdr-pane-minimap}"
ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
BIN="$ROOT/herdr-pane-minimap"
mkdir -p "$STATE"
PIDFILE="$STATE/watch.pid"
if [[ -f "$PIDFILE" ]]; then
  old="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "${old}" ]] && ps -p "$old" -o command= 2>/dev/null | grep -q herdr-pane-minimap; then
    kill -TERM "$old" 2>/dev/null || true
    sleep 0.2
    kill -KILL "$old" 2>/dev/null || true
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "herdr-pane-minimap binary missing at $BIN" >&2
  exit 0
fi
nohup "$BIN" watch >>"$STATE/watch.log" 2>&1 &
echo $! >"$PIDFILE"
