#!/usr/bin/env bash
set -euo pipefail
STATE="${HERDR_PLUGIN_STATE_DIR:-$HOME/.config/herdr/plugin-state/herdr-session-titles}"
ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
WATCH="$ROOT/watch.py"
mkdir -p "$STATE"
PIDFILE="$STATE/watch.pid"

alive() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q 'herdr/session-titles/watch.py'
}

if [[ -f "$PIDFILE" ]]; then
  old="$(cat "$PIDFILE" 2>/dev/null || true)"
  if alive "$old"; then
    exit 0
  fi
fi

if [[ ! -f "$WATCH" ]]; then
  echo "herdr-session-titles watch.py missing at $WATCH" >&2
  exit 0
fi

nohup python3 "$WATCH" >>"$STATE/watch.log" 2>&1 &
echo $! >"$PIDFILE"
