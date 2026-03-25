#!/usr/bin/env python3
"""tmux pane minimap popup.

Draws the full pane layout for a specific window and highlights a specific pane.
IDs are passed from the hook to avoid race conditions when focus changes.
"""

import argparse
import math
import os
import signal
import subprocess
import sys
import time

DISPLAY_SECONDS = 0.12
PIDFILE = "/tmp/tmux-minimap.pid"

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"

ACT_BG = "\033[44m"
ACT_FG = "\033[97m"
ACT_BORDER = "\033[94m"

INA_BG = "\033[48;5;236m"
INA_FG = "\033[37m"
INA_BORDER = "\033[90m"


def tmux(*args):
    return subprocess.check_output(["tmux"] + list(args), text=True).strip()


def parse_args():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--window-id", default="")
    parser.add_argument("--active-pane-id", default="")
    return parser.parse_args()


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def kill_existing():
    try:
        with open(PIDFILE, encoding="utf-8") as f:
            old_pid = int(f.read().strip())
        os.kill(old_pid, signal.SIGTERM)
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        pass


def write_pid():
    with open(PIDFILE, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))


def cleanup(*_):
    try:
        os.unlink(PIDFILE)
    except FileNotFoundError:
        pass
    sys.exit(0)


def _parse_num(layout: str, i: int):
    j = i
    while j < len(layout) and layout[j].isdigit():
        j += 1
    if j == i:
        raise ValueError(f"expected number at position {i}")
    return int(layout[i:j]), j


def _parse_layout_node(layout: str, i: int):
    width, i = _parse_num(layout, i)
    if layout[i] != "x":
        raise ValueError("invalid layout: missing x")
    i += 1
    height, i = _parse_num(layout, i)
    if layout[i] != ",":
        raise ValueError("invalid layout: missing comma after height")
    i += 1
    left, i = _parse_num(layout, i)
    if layout[i] != ",":
        raise ValueError("invalid layout: missing comma after left")
    i += 1
    top, i = _parse_num(layout, i)

    if i < len(layout) and layout[i] in "[{":
        open_ch = layout[i]
        close_ch = "]" if open_ch == "[" else "}"
        i += 1
        children = []
        while True:
            child, i = _parse_layout_node(layout, i)
            children.append(child)
            if i >= len(layout):
                raise ValueError("invalid layout: unterminated container")
            if layout[i] == ",":
                i += 1
                continue
            if layout[i] == close_ch:
                i += 1
                break
            raise ValueError("invalid layout: unexpected separator")
        return (
            {
                "type": "container",
                "left": left,
                "top": top,
                "width": width,
                "height": height,
                "children": children,
            },
            i,
        )

    if i < len(layout) and layout[i] == ",":
        i += 1
        pane_num, i = _parse_num(layout, i)
        return (
            {
                "type": "pane",
                "pane_num": str(pane_num),
                "left": left,
                "top": top,
                "width": width,
                "height": height,
            },
            i,
        )

    raise ValueError("invalid layout: expected container or pane id")


def _collect_layout_panes(node, out):
    if node["type"] == "pane":
        out.append(node)
        return
    for child in node["children"]:
        _collect_layout_panes(child, out)


def render(window_id: str, active_pane_id: str) -> bool:
    if not window_id:
        window_id = tmux("display", "-p", "#{window_id}")
    if not active_pane_id:
        active_pane_id = tmux("display", "-p", "#{pane_id}")

    zoomed = (
        tmux("display-message", "-p", "-t", window_id, "#{window_zoomed_flag}") == "1"
    )
    pane_meta_raw = tmux(
        "list-panes",
        "-t",
        window_id,
        "-F",
        "#{pane_id}|#{pane_index}|#{pane_current_command}",
    )

    layout_raw = tmux("display-message", "-p", "-t", window_id, "#{window_layout}")
    if "," not in layout_raw:
        return False
    layout = layout_raw.split(",", 1)[1]
    layout_root, end_i = _parse_layout_node(layout, 0)
    if end_i != len(layout):
        return False

    layout_panes = []
    _collect_layout_panes(layout_root, layout_panes)

    pane_meta = {}
    for line in pane_meta_raw.splitlines():
        pane_id, idx, cmd = line.split("|")
        pane_num = pane_id.lstrip("%")
        pane_meta[pane_num] = {"pane_id": pane_id, "idx": int(idx), "cmd": cmd}

    panes = []
    for lp in layout_panes:
        meta = pane_meta.get(lp["pane_num"])
        if not meta:
            continue
        panes.append(
            {
                "pane_id": meta["pane_id"],
                "idx": meta["idx"],
                "left": lp["left"],
                "top": lp["top"],
                "right": lp["left"] + lp["width"],
                "bottom": lp["top"] + lp["height"],
                "cmd": meta["cmd"],
                "active": meta["pane_id"] == active_pane_id,
            }
        )

    if panes and not any(p["active"] for p in panes):
        panes[0]["active"] = True

    if len(panes) < 2:
        return False

    min_left = min(p["left"] for p in panes)
    min_top = min(p["top"] for p in panes)
    max_right = max(p["right"] for p in panes)
    max_bottom = max(p["bottom"] for p in panes)

    span_x = max(1, max_right - min_left)
    span_y = max(1, max_bottom - min_top)

    canvas_w, canvas_h = 46, 18

    def x1(v):
        return int((v - min_left) * canvas_w / span_x)

    def x2(v):
        return int(math.ceil((v - min_left) * canvas_w / span_x)) - 1

    def y1(v):
        return int((v - min_top) * canvas_h / span_y)

    def y2(v):
        return int(math.ceil((v - min_top) * canvas_h / span_y)) - 1

    grid = [[(" ", RESET) for _ in range(canvas_w)] for _ in range(canvas_h)]

    def put(x, y, ch, color):
        if 0 <= x < canvas_w and 0 <= y < canvas_h:
            grid[y][x] = (ch, color)

    draw_order = sorted(panes, key=lambda p: p["active"])

    for p in draw_order:
        left = clamp(x1(p["left"]), 0, canvas_w - 1)
        right = clamp(x2(p["right"]), left, canvas_w - 1)
        top = clamp(y1(p["top"]), 0, canvas_h - 1)
        bottom = clamp(y2(p["bottom"]), top, canvas_h - 1)

        if p["active"]:
            border, fill, text = ACT_BORDER + BOLD, ACT_BG, ACT_BG + ACT_FG + BOLD
        else:
            border, fill, text = INA_BORDER, INA_BG, INA_BG + INA_FG

        for x in range(left + 1, right):
            put(x, top, "-", border)
            put(x, bottom, "-", border)
        for y in range(top + 1, bottom):
            put(left, y, "|", border)
            put(right, y, "|", border)

        put(left, top, "+", border)
        put(right, top, "+", border)
        put(left, bottom, "+", border)
        put(right, bottom, "+", border)

        for y in range(top + 1, bottom):
            for x in range(left + 1, right):
                put(x, y, " ", fill)

        inner_w = right - left - 1
        inner_h = bottom - top - 1
        if inner_w > 0 and inner_h > 0:
            label = f"{p['idx']}:{p['cmd']}"
            if len(label) > inner_w:
                label = label[: inner_w - 1] + "."
            lx = left + 1 + max(0, (inner_w - len(label)) // 2)
            ly = top + 1 + inner_h // 2
            for i, ch in enumerate(label):
                cx = lx + i
                if cx <= right - 1:
                    put(cx, ly, ch, text)

    print()
    tag = "(zoomed)" if zoomed else f"({len(panes)} panes)"
    print(f"  {BOLD}Pane Layout{RESET} {DIM}{tag}{RESET}")
    print()
    for row in grid:
        print("  " + "".join(f"{color}{ch}{RESET}" for ch, color in row))
    sys.stdout.flush()
    return True


def main():
    args = parse_args()
    signal.signal(signal.SIGTERM, cleanup)

    kill_existing()
    write_pid()

    shown = render(args.window_id, args.active_pane_id)
    if shown:
        time.sleep(DISPLAY_SECONDS)

    cleanup()


if __name__ == "__main__":
    main()
