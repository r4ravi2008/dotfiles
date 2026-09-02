#!/usr/bin/env bash
# annotate.open / open-link: if Herdr has a terminal selection, open the matching
# Markdown file. Otherwise fall through to folder / file:// click handling.
set -euo pipefail
root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tui="$root/scripts/plannotator-tui.sh"

target="$(
	python3 - <<'PY'
import json, os, re, subprocess
from pathlib import Path

def load_context():
    raw = os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or "{}"
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}

ctx = load_context()
if isinstance(ctx.get("clicked_url"), str) and ctx["clicked_url"].strip():
    raise SystemExit(0)

text = ctx.get("selected_text")
if not isinstance(text, str) or not text.strip():
    raise SystemExit(0)
text = text.strip()

cwd_raw = ctx.get("focused_pane_cwd") or ctx.get("workspace_cwd") or os.getcwd()
if not isinstance(cwd_raw, str) or not cwd_raw:
    cwd_raw = os.getcwd()
cwd = Path(cwd_raw).expanduser().resolve()

def existing_md(path):
    if path.is_file() and path.suffix.lower() in {".md", ".mdx", ".markdown"}:
        return path
    return None

path_re = re.compile(
    r"(?:file://[^\s]+|(?:\.?/)?[\w./-]+\.(?:md|mdx|markdown))(?::\d+\b)?",
    re.IGNORECASE,
)
for match in path_re.findall(text):
    raw = re.sub(r":\d+$", "", match)
    if raw.startswith("file://"):
        raw = re.sub(r"^file://(localhost)?", "", raw, flags=re.IGNORECASE)
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = cwd / path
    found = existing_md(path.resolve())
    if found:
        print(found)
        raise SystemExit(0)

needles = [line.strip() for line in text.splitlines() if len(line.strip()) >= 16]
if not needles:
    if len(text) >= 16:
        needles = [text[:240]]
    else:
        raise SystemExit(0)
needle = max(needles, key=len)[:240]

rg = subprocess.run(
    [
        "rg",
        "-l",
        "-F",
        "--glob",
        "*.md",
        "--glob",
        "*.mdx",
        "--glob",
        "*.markdown",
        "--glob",
        "!**/node_modules/**",
        "--glob",
        "!**/.git/**",
        "--glob",
        "!**/dist/**",
        "--glob",
        "!**/target/**",
        needle,
        str(cwd),
    ],
    check=False,
    capture_output=True,
    text=True,
)
if rg.returncode not in (0, 1):
    raise SystemExit(0)
hits = [Path(line).resolve() for line in rg.stdout.splitlines() if line.strip()]
hits = [path for path in hits if path.is_file()]
if not hits:
    raise SystemExit(0)
if len(hits) == 1:
    print(hits[0])
    raise SystemExit(0)

named = []
try:
    named = [
        path
        for path in hits
        if path.name in text or str(path.relative_to(cwd)) in text
    ]
except ValueError:
    named = [path for path in hits if path.name in text]
choice = named[0] if named else min(hits, key=lambda p: (len(p.parts), len(str(p))))
print(choice)
PY
)"

if [[ -n "${target}" ]]; then
	exec bash "$tui" herdr open "$target"
fi
exec bash "$tui" herdr open "$@"
