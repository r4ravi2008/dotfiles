#!/usr/bin/env python3
"""Regression tests for prefix+g titles."""

from watch import next_seq, pane_display_title


def test_idle_keeps_waiting_for_you():
    pane = {
        "agent": "cursor",
        "agent_status": "idle",
        "terminal_title_stripped": "PR Review Solution - ❓ Waiting for you",
        "pane_id": "w1:p1",
    }
    assert pane_display_title(pane, {}) == "PR Review Solution - ❓ Waiting for you"


def test_working_keeps_osc_status():
    pane = {
        "agent": "cursor",
        "agent_status": "working",
        "terminal_title_stripped": "Agent State Issue - ⏳ Working ...",
        "pane_id": "w1:p2",
    }
    assert pane_display_title(pane, {}) == "Agent State Issue - ⏳ Working ..."


def test_ready_keeps_osc_status():
    pane = {
        "agent": "cursor",
        "agent_status": "idle",
        "terminal_title_stripped": "CWS Script Query - ✅ Ready",
        "pane_id": "w1:p3",
    }
    assert pane_display_title(pane, {}) == "CWS Script Query - ✅ Ready"


def test_shell_title_does_not_append_agent_status():
    pane = {
        "terminal_title_stripped": "nvim",
        "agent_status": "idle",
        "pane_id": "w1:p4",
    }
    assert pane_display_title(pane, {}) == "nvim"


def test_next_seq_jumps_past_stale_file_counter():
    assert next_seq({"seq": 209}) > 1_000_000_000_000


if __name__ == "__main__":
    test_idle_keeps_waiting_for_you()
    test_working_keeps_osc_status()
    test_ready_keeps_osc_status()
    test_shell_title_does_not_append_agent_status()
    test_next_seq_jumps_past_stale_file_counter()
    print("ok")
