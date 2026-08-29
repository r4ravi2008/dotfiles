# Herdr Agent Selection and Plannotator Plugin Design

**Date:** 2026-08-28  
**Status:** Approved for implementation planning  
**Repo:** `~/.dotfiles`

## Problem

Herdr already has pane/workspace keys and two plugins (`herdr-nvim-nav`, `herdr-splits`). It does not bind native agent cycle/focus, and it does not install an agent picker. The Plannotator **CLI** and extras already install on laptop and CWS via `packages.conf` + `bootstrap.sh`. Reviews still happen in an external browser (laptop SSH tunnel on 19432). The official Herdr Plannotator **plugin** is not installed, so reviews cannot open inside a Herdr Browser pane.

## Goals

1. Bind native Herdr agent navigation and a `dleen/herdr-agents` picker.
2. Install `ogulcancelik/herdr-browser` and `plannotator/herdr-plannotator` on laptop **and** CWS during bootstrap, then `configure` when Chrome/Chromium and Bun are present.
3. Keep sharing disabled and keep the 19432 tunnel. Do not fail bootstrap if presenter deps are missing.

## Non-goals

- Binding `dleen.herdr-agents.fork-right`.
- Vendoring plugin source under `herdr/` (except existing `nvim-nav`).
- Changing SSH `LocalForward` 19432, `PLANNOTATOR_REMOTE`, `PLANNOTATOR_SHARE`, or `PLANNOTATOR_JINA`.
- Setting `agents = "alt"` (conflicts with `alt+1..9` tab switching).
- Exporting `PLANNOTATOR_PRESENTER` (empty would disable the file-based presenter).
- Failing the entire bootstrap when Chromium, Bun, or a plugin install fails.

## Architecture

After Herdr is on `PATH`, bootstrap uses the same pin-and-install pattern as `herdr-splits`:

1. Link or copy `herdr/config.toml` (CWS still copies the file and appends `new_cwd = "/workspace"`).
2. Keep `herdr-nvim-nav` link + `herdr-splits` pin-install as today.
3. Pin-install `dleen/herdr-agents`, `ogulcancelik/herdr-browser`, `plannotator/herdr-plannotator` with `--yes` and `--ref <sha>`. Reinstall only when `herdr plugin list --plugin <id> --json` does not show that `resolved_commit`.
4. If `google-chrome` or `chromium` **and** `bun` exist: `herdr plugin action invoke configure --plugin official.plannotator`, then poll `herdr plugin log list --plugin official.plannotator --limit 1` until `succeeded`, `failed`, or timeout. On skip/fail/timeout: warn and continue.
5. Existing `configure_plannotator_local_only` still forces `"share":"disabled"` and must run after configure so share cannot be left enabled.

Keys and `kitty_graphics` live in `herdr/config.toml` so every profile gets them, including the CWS copied file.

## Components

| Unit | Responsibility |
|---|---|
| `herdr/config.toml` | Native agent keys, picker `plugin_action`, `[experimental] kitty_graphics = true` |
| `bootstrap.sh` Herdr plugin block | Pin-install three GitHub plugins; wait on configure logs |
| `packages.conf` | `chromium` and `bun` in `cli` so CWS Linux can get presenter deps |
| `_fallback_bun` | Install Bun when brew/apt cannot |
| Docs (`README.md`, `AGENTS.md`, CWS reference) | Keys, plugins, skip conditions |

Plugin IDs (from upstream docs):

| Repo | Plugin id | Action |
|---|---|---|
| `dleen/herdr-agents` | `dleen.herdr-agents` | `dleen.herdr-agents.open` |
| `ogulcancelik/herdr-browser` | `official.browser` | none bound |
| `plannotator/herdr-plannotator` | `official.plannotator` | `configure` (bootstrap only) |

After the first `herdr plugin install ogulcancelik/herdr-browser --yes`, read the plugin id from `herdr plugin list --json` and use that exact id in the pin-check. If the id is not `official.browser`, keep the JSON id and document it in the bootstrap comment. Do not guess.

Pin SHAs: resolve each repo’s default-branch tip at implement time (`git ls-remote`) and store them as named variables next to `herdr_splits_ref`.

## Keybindings

Prefix remains `ctrl+a`.

| Action | Binding | Mechanism |
|---|---|---|
| Agent picker | `prefix+a` | `[[keys.command]]` `type = "plugin_action"` `command = "dleen.herdr-agents.open"` |
| Previous agent | `alt+shift+[` | `[keys] previous_agent` |
| Next agent | `alt+shift+]` | `[keys] next_agent` |
| Focus agent 1–9 | `prefix+alt+1..9` | `[keys] focus_agent` |

Do not set `agents = "alt"`. Do not bind `fork-right`. Do not reuse `alt+1..9` (tabs) or `cmd+alt+1..9` (workspaces).

`prefix+a` is currently unused. Herdr default comments use `workspace_picker = "prefix+w"`; this repo already uses `prefix+s` / `alt+p` for workspaces.

## Packages and environments

Add to `packages.conf` `cli` group (installed on laptop and CWS):

- `chromium`: brew `-` (macOS keeps existing Chrome). Linux: apt/dnf/pacman/zypper names that provide a `chromium` binary; if a distro uses `chromium-browser` only, the command-check field must match what `command -v` finds, or bootstrap must treat both names as present for configure.
- `bun`: brew `bun` where available; otherwise `_fallback_bun` (official bun install script into `~/.local/bin`, or skip with warn).

Configure-ready means all of:

- `herdr` on PATH
- `official.plannotator` installed
- `command -v bun`
- `command -v google-chrome` or `command -v chromium` or `command -v chromium-browser` or macOS `/Applications/Google Chrome.app`

CWS already sets `PLANNOTATOR_REMOTE=1` and `PLANNOTATOR_PORT=19432` in `zsh/zshenv`. Leave that. Do not export `PLANNOTATOR_PRESENTER`.

`[experimental] kitty_graphics = true` is required for Herdr Browser. Remote attach already uses `--remote-keybindings server` via the zsh `herdr` wrapper; no change.

Herdr pin stays `0.8.2` (meets herdr-agents ≥0.8 and plannotator plugin ≥0.7.5).

## Data flow (in-Herdr review)

1. Agent runs Plannotator; a page is ready on the local Plannotator URL.
2. If configure succeeded, `~/.plannotator/config.json` has a presenter pointing at the plugin helper (plus `"share":"disabled"`).
3. Presenter asks Herdr to open a focused, zoomed `official.browser` pane at that URL.
4. User approves/comments on the page. Plugin does not interpret feedback.
5. When review ends, helper closes the pane.

If configure was skipped, this path does not run. User uses the existing browser/tunnel.

## Error handling

| Failure | Behavior |
|---|---|
| Plugin install fails | Warn; continue. Missing action keys do nothing. |
| Chromium/Bun install fails | Warn; continue; skip configure. |
| Configure skipped (deps) | Warn naming the missing binary. |
| Configure log `failed` or timeout | Warn; do not uninstall; do not revert share-disabled. |
| `herdr` missing | Existing warn; skip all Herdr plugins including new ones. |

Timeout for configure wait: 60 seconds, poll every 2 seconds. Treat a missing log as still running until timeout.

## Documentation updates

- `README.md`: agent keys; Herdr plugins include browser + plannotator + herdr-agents; CWS may install Chromium/Bun for in-pane review.
- `AGENTS.md`: same facts; share still disabled; 19432 still tunnel-only.
- `.agents/skills/creating-cws-from-devstack-fork/reference.md` E2E table: add rows for the three plugins (pinned refs), `kitty_graphics`, picker action, native agent keys, Chromium/Bun or explicit skip, configure succeeded **or** documented skip, `share` still disabled after configure.

## Verification

No unit test framework in this repo. Manual checks:

1. `herdr config check` succeeds after `config.toml` edits.
2. Laptop: `herdr plugin list` shows the three plugins at pinned refs; `prefix+a` opens the picker when `HERDR_ENV=1` and fzf/python3 exist (already true: fzf is `cli`).
3. With two or more agent panes: `alt+shift+[` / `alt+shift+]` cycle; `prefix+alt+1` focuses the first agent if Herdr reports one.
4. CWS bootstrap: plugins at pins; configure success **or** a warn that names the missing dep.
5. After successful configure: `jq -e '.share == "disabled"' ~/.plannotator/config.json`; presenter field is non-empty.
6. 19432 still in `ssh/cws-mcp-forwards.conf`; `PLANNOTATOR_SHARE=disabled` still in `zsh/zshenv`.

## Constraints (verbatim)

- Native previous/next/focus **and** `dleen/herdr-agents` picker.
- Keys: picker `prefix+a`; previous/next `alt+shift+[` / `alt+shift+]`; focus `prefix+alt+1..9`.
- Install path: extend existing bootstrap Herdr plugin block; pin `--ref`.
- Install `ogulcancelik/herdr-browser` and `plannotator/herdr-plannotator` on laptop and CWS; `configure` when Chrome/Chromium and Bun exist.
- `kitty_graphics = true`.
- Keep `PLANNOTATOR_SHARE=disabled` and 19432 tunnel.
- No `fork-right`; no `agents = "alt"`; no vendored plugin trees for these three.
- Warn and continue on install/configure failure; do not fail bootstrap.
