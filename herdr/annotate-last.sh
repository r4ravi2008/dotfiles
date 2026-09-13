#!/usr/bin/env bash
# annotate.last: review the focused pane's agent, not whatever plannotator-tui
# guesses. Upstream herdr last names the pane process and unknown names (Cursor's
# node) fall through to Claude.
set -euo pipefail
root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
here="$(cd "$(dirname "$0")" && pwd)"
tui="$root/scripts/plannotator-tui.sh"
planner="$here/annotate-last.py"
herdr_bin="${HERDR_BIN_PATH:-herdr}"

notify() {
	local title="$1" body="$2"
	"$herdr_bin" notification show "$title" --body "$body" >/dev/null 2>&1 || true
	echo "$title: $body" >&2
}

if [[ ! -f "$planner" ]]; then
	notify "Annotate: last reply" "annotate-last.py is missing; re-run bootstrap"
	exit 1
fi

plan="$(python3 "$planner" "$herdr_bin")"
action="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("action",""))' "$plan")"
case "$action" in
	last)
		exec bash "$tui" herdr last "$@"
		;;
	open)
		file="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("file",""))' "$plan")"
		if [[ -z "$file" ]]; then
			notify "Annotate: last reply" "could not write a review file"
			exit 1
		fi
		exec bash "$tui" herdr open "$file"
		;;
	error)
		msg="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("message",""))' "$plan")"
		notify "Annotate: last reply" "${msg:-could not open the last agent message}"
		exit 1
		;;
	*)
		notify "Annotate: last reply" "could not decide how to open the last message"
		exit 1
		;;
esac
