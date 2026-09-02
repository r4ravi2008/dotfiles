# Herdr agent picker and annotate plugin

**Date:** 2026-08-28  
**Corrected:** 2026-08-29  
**Status:** Shipped  
**Repo:** `~/.dotfiles`

## Problem

Herdr had pane keys and `herdr-nvim-nav` / `herdr-splits`, but no agent cycle, no picker, and no in-terminal plan review. The Plannotator CLI already installs on laptop and CWS. `plannotator annotate` opens a browser. That is fine. In Herdr, review should stay in a pane.

The first pass installed `ogulcancelik/herdr-browser` plus `plannotator/herdr-plannotator` and tried to open Chrome inside a Herdr pane. The CLI never honors that. The plugin that reviews inside Herdr is [`plannotator/herdr-annotate`](https://github.com/plannotator/herdr-annotate).

## Goals

1. Bind native agent previous/next/focus and a `dleen/herdr-agents` picker.
2. Pin-install full `plannotator/herdr-annotate` on laptop and CWS (needs Bun). Keep `prefix+a` as the picker and `prefix+o` as cycle pane.
3. Leave share disabled and leave the 19432 tunnel for the web CLI. Warn and continue if Bun or a plugin install fails.

## Non-goals

- `dleen.herdr-agents.fork-right`
- `agents = "alt"` (clashes with `alt+1..9` tabs)
- Vendoring those plugin trees under `herdr/`
- Changing 19432, `PLANNOTATOR_REMOTE`, `PLANNOTATOR_SHARE`, or `PLANNOTATOR_JINA`
- Making `plannotator annotate` open the Herdr overlay
- Failing bootstrap when a plugin or Bun install fails

## How it is wired

Bootstrap pin-installs like `herdr-splits`: `--yes --ref <sha>`, skip when `herdr plugin list --plugin <id> --json` already shows that `resolved_commit`. Bootstrap uninstalls leftover `official.browser` / `official.plannotator`.

Keys live in `herdr/config.toml`. CWS copies that file, then appends `new_cwd = "/workspace"` and `[ui] copy_on_select = false`. `configure_plannotator_local_only` still forces `"share":"disabled"`.

| Repo | Plugin id | Bound actions |
|---|---|---|
| `dleen/herdr-agents` | `dleen.herdr-agents` | `open` on `prefix+a` |
| `plannotator/herdr-annotate` | `annotate` | capture, copy-context, manage, open, last |

Pins:

- `dleen/herdr-agents` `74f8550a1008156f811b0bc8663ac251d9f3fcd6`
- `plannotator/herdr-annotate` `fb93a1318f960792452cef6cde72a2c4f4591241`

Herdr pin is `0.8.2` (annotate wants ≥0.8.0). `packages.conf` `cli` has `bun` (`_fallback_bun` if brew/apt cannot). No Chromium.

## Keys

Prefix is `ctrl+a`.

| Action | Binding |
|---|---|
| Agent picker | `prefix+a` |
| Previous / next agent | `alt+shift+[` / `alt+shift+]` |
| Focus agent 1–9 | `prefix+alt+1..9` |
| Annotate capture | `prefix+u` / `prefix+ctrl+u` |
| Copy annotations | `prefix+ctrl+e` |
| Manage annotations | `prefix+m` |
| Folder review | `prefix+f` / `prefix+ctrl+p` |
| Last agent reply | `prefix+ctrl+y` |

Upstream annotate uses `prefix+a` / `prefix+o` / `prefix+shift+o`. Those are already picker, cycle pane, and notifications here.

Visual `<leader>a` in Neovim copies the selection and invokes `annotate.capture` when `HERDR_ENV=1`.

Remote attach already passes `--remote-keybindings server` via the zsh `herdr` wrapper. CWS `copy_on_select = false` keeps the mouse selection so capture can read it.

## Review flow

`prefix+f` / `prefix+ctrl+p` or `prefix+ctrl+y` opens plannotator-tui as a Herdr overlay. Send or `E` posts the review as the agent's next message. `q` closes. `plannotator annotate --gate` is a different program and still opens a browser. `prefix+shift+p` stays Herdr's pane rename.

## Failure

| Failure | Behavior |
|---|---|
| Plugin install fails | Warn, continue. Unbound keys do nothing. |
| Bun missing | Warn, continue. Skip the annotate pin. |
| `herdr` missing | Existing warn. Skip Herdr plugins. |
