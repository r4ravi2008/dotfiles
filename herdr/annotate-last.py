#!/usr/bin/env python3
"""Plan annotate.last: Cursor transcripts, known tui hosts, or pane dump."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

TUI_HOSTS = {
    "claude",
    "claude-code",
    "claude_code",
    "codex",
    "copilot",
    "copilot-cli",
    "copilot_cli",
    "droid",
    "factory",
    "pi",
    "omp",
    "oh-my-pi",
    "ohmypi",
    "hermes",
    "hermes-cli",
    "hermes_cli",
    "opencode",
    "open-code",
    "open_code",
}
CURSOR_HOSTS = {"cursor", "cursor-agent", "cursor-cli"}
MAX_CHARS = 1_500_000
MAX_TURNS = 8


def load_context():
    raw = os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or "{}"
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def herdr_json(bin_path, args):
    try:
        proc = subprocess.run(
            [bin_path, *args],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return {}
    if proc.returncode != 0:
        return {}
    try:
        value = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def pane_agent(bin_path, pane):
    data = herdr_json(bin_path, ["pane", "get", pane])
    pane_info = ((data.get("result") or {}).get("pane") or {})
    agent = pane_info.get("agent")
    cwd = pane_info.get("cwd") or pane_info.get("foreground_cwd")
    return (
        agent.strip() if isinstance(agent, str) else "",
        cwd if isinstance(cwd, str) and cwd else "",
    )


def process_looks_like_cursor(bin_path, pane):
    data = herdr_json(bin_path, ["pane", "process-info", "--pane", pane])
    info = (data.get("result") or {}).get("process_info") or {}
    processes = info.get("foreground_processes") or []
    needles = ("cursor-agent", "cursor-agent/", "share/cursor-agent")
    for process in processes:
        blob = " ".join(
            [
                str(process.get("name") or ""),
                str(process.get("argv0") or ""),
                str(process.get("cmdline") or ""),
                " ".join(str(x) for x in (process.get("argv") or [])),
            ]
        ).lower()
        if any(needle in blob for needle in needles):
            return True
    return False


def extract_text(message):
    if isinstance(message, str):
        return message
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts = []
    for item in content:
        if isinstance(item, str):
            if item.strip():
                parts.append(item)
            continue
        if not isinstance(item, dict):
            continue
        kind = item.get("type")
        if kind in {"tool_use", "tool_result", "thinking"}:
            continue
        text = item.get("text")
        if kind in {"text", "output_text"} and isinstance(text, str) and text.strip():
            parts.append(text)
        elif kind is None and isinstance(text, str) and text.strip():
            parts.append(text)
    return "\n".join(parts)


def is_user_turn(record):
    if record.get("role") != "user":
        return False
    message = record.get("message")
    if isinstance(message, dict) and isinstance(message.get("content"), list):
        kinds = [
            item.get("type")
            for item in message["content"]
            if isinstance(item, dict)
        ]
        if kinds and all(kind in {"tool_result", "tool_use"} for kind in kinds):
            return False
    return bool(extract_text(message).strip())


def assistant_turns(path: Path):
    turns = []
    current = []

    def flush():
        text = "\n\n".join(part for part in current if part).strip()
        if text:
            turns.append(text)

    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(record, dict):
                continue
            if is_user_turn(record):
                flush()
                current = []
                continue
            if record.get("role") != "assistant":
                continue
            text = extract_text(record.get("message")).strip()
            if text:
                current.append(text)
    flush()
    return turns


def path_slug_variants(cwd: Path):
    paths = [cwd]
    posix = cwd.as_posix()
    if posix.startswith("/private/tmp/"):
        paths.append(Path("/tmp") / cwd.relative_to("/private/tmp"))
    elif posix.startswith("/tmp/"):
        paths.append(Path("/private/tmp") / posix[len("/tmp/") :])
    slugs = []
    for path in paths:
        parts = [part.lstrip(".") for part in path.as_posix().split("/") if part]
        slugs.append("-".join(parts))
        slugs.append(path.as_posix().lstrip("/").replace("/", "-"))
    unique = []
    seen = set()
    for slug in slugs:
        if slug and slug not in seen:
            seen.add(slug)
            unique.append(slug)
    return unique


def cursor_project(cwd: Path):
    projects = Path.home() / ".cursor" / "projects"
    if not projects.is_dir():
        return None
    for slug in path_slug_variants(cwd):
        direct = projects / slug
        if (direct / "agent-transcripts").is_dir():
            return direct
        matches = [
            child
            for child in projects.iterdir()
            if child.is_dir()
            and (child.name == slug or child.name.startswith(slug + "-"))
            and (child / "agent-transcripts").is_dir()
        ]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            return max(
                matches,
                key=lambda child: (child / "agent-transcripts").stat().st_mtime,
            )
    return None


def newest_transcript(project: Path):
    root = project / "agent-transcripts"
    files = [
        path
        for path in root.rglob("*.jsonl")
        if path.is_file() and "subagents" not in path.parts
    ]
    if not files:
        return None
    return max(files, key=lambda path: path.stat().st_mtime)


def write_markdown(host: str, turns: list, pane: str) -> Path:
    chosen = turns[-MAX_TURNS:]
    chunks = []
    if len(chosen) == 1:
        chunks.append(f"# {host} · last reply")
        chunks.append(chosen[0].rstrip())
    else:
        chunks.append(f"# {host} · last replies")
        for index, text in enumerate(chosen, start=len(turns) - len(chosen) + 1):
            label = "Latest" if index == len(turns) else f"Reply {index}"
            chunks.append(f"## {label}")
            chunks.append(text.rstrip())
    body = "\n\n".join(chunks).strip() + "\n"
    if len(body) > MAX_CHARS:
        body = body[-MAX_CHARS:]
        body = "# …truncated…\n" + body[body.find("\n") + 1 :]
    directory = Path(tempfile.gettempdir()) / "herdr-annotate-last"
    directory.mkdir(parents=True, exist_ok=True)
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in (pane or "pane"))
    path = directory / f"{safe}.md"
    path.write_text(body, encoding="utf-8")
    return path


def pane_transcript(bin_path, pane: str) -> str:
    try:
        proc = subprocess.run(
            [
                bin_path,
                "pane",
                "read",
                pane,
                "--source",
                "recent-unwrapped",
                "--lines",
                "120",
                "--format",
                "text",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return ""
    if proc.returncode != 0:
        return ""
    return proc.stdout


def fail(message):
    print(json.dumps({"action": "error", "message": message}))
    raise SystemExit(0)


def main():
    bin_path = sys.argv[1] if len(sys.argv) > 1 else "herdr"
    ctx = load_context()
    pane = ctx.get("focused_pane_id") or os.environ.get("HERDR_PANE_ID") or ""
    if not isinstance(pane, str):
        pane = ""
    cwd_raw = ctx.get("focused_pane_cwd") or ctx.get("workspace_cwd") or os.getcwd()
    agent = ctx.get("focused_pane_agent") if isinstance(ctx.get("focused_pane_agent"), str) else ""
    if pane:
        fetched_agent, fetched_cwd = pane_agent(bin_path, pane)
        agent = agent or fetched_agent
        if not cwd_raw and fetched_cwd:
            cwd_raw = fetched_cwd
    agent = (agent or "").strip().lower()
    cwd = Path(cwd_raw).expanduser()
    try:
        cwd = cwd.resolve()
    except OSError:
        pass

    if not pane:
        fail("no focused pane to read")

    looks_cursor = agent in CURSOR_HOSTS or process_looks_like_cursor(bin_path, pane)
    if agent in TUI_HOSTS and not looks_cursor:
        print(json.dumps({"action": "last"}))
        return

    if looks_cursor:
        project = cursor_project(cwd)
        transcript = newest_transcript(project) if project else None
        if transcript:
            turns = assistant_turns(transcript)
            if turns:
                path = write_markdown("cursor", turns, pane)
                print(json.dumps({"action": "open", "file": str(path)}))
                return
        fail(f"no Cursor transcript under {cwd}")

    dump = pane_transcript(bin_path, pane)
    if dump.strip():
        path = write_markdown(agent or "agent", [dump.strip()], pane)
        print(json.dumps({"action": "open", "file": str(path)}))
        return

    fail(f"{agent or 'this pane'} is not a supported last-message host")


if __name__ == "__main__":
    main()
