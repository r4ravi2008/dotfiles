# Herdr Agent Picker and Plannotator Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind native Herdr agent cycle/focus plus `dleen/herdr-agents` on `prefix+a`, and bootstrap-pin Herdr Browser + official Plannotator presenter on laptop and CWS without breaking share-disabled or 19432.

**Architecture:** Keys and `kitty_graphics` live in `herdr/config.toml`. Bootstrap extends the existing `herdr-splits` pin-install block with three more GitHub plugins and a configure-wait helper. Chromium and Bun join `packages.conf` `cli`. `configure_plannotator_local_only` stays later in `setup_ai_agents` so share is forced after configure.

**Tech Stack:** bash (`bootstrap.sh`), Herdr 0.8.2 TOML config, `packages.conf` pipe registry.

## Global Constraints

- Native previous/next/focus **and** `dleen/herdr-agents` picker.
- Keys: picker `prefix+a`; previous/next `alt+shift+[` / `alt+shift+]`; focus `prefix+alt+1..9`.
- Do not set `agents = "alt"`. Do not bind `fork-right`.
- Pin refs (default-branch HEAD 2026-08-28):
  - `dleen/herdr-agents` → `74f8550a1008156f811b0bc8663ac251d9f3fcd6` (plugin id `dleen.herdr-agents`)
  - `ogulcancelik/herdr-browser` → `ab5c60b1e15521ff4ac4a168ccd80b5b0133edc8` (plugin id `official.browser`; if `herdr plugin list --json` reports another id after first install, use that id and comment it)
  - `plannotator/herdr-plannotator` → `e10b969ea1655dbfce25d1464eef6f27c790bb79` (plugin id `official.plannotator`)
- `[experimental] kitty_graphics = true`
- Install plugins on laptop and CWS; `configure` only when Bun and Chrome/Chromium exist.
- Configure wait: 60s, poll every 2s; missing log = still running until timeout.
- Warn and continue on install/configure failure; do not `exit` bootstrap.
- Do not change 19432, `PLANNOTATOR_REMOTE`, `PLANNOTATOR_SHARE`, `PLANNOTATOR_JINA`. Do not export `PLANNOTATOR_PRESENTER`.
- Do not vendor those three plugin trees under `herdr/`.
- `configure_plannotator_local_only` must still run after configure (existing `setup_ai_agents` order).
- Herdr pin stays `0.8.2`.

---

### Task 1: Herdr keys and kitty graphics

**Files:**
- Modify: `herdr/config.toml`
- Test: `herdr config check` (repo file is the live symlink target) plus `grep`

**Interfaces:**
- Consumes: existing `[keys]` prefix `ctrl+a`; unused `prefix+a`
- Produces: `previous_agent`, `next_agent`, `focus_agent`; `[[keys.command]]` `dleen.herdr-agents.open`; `[experimental] kitty_graphics = true`

- [ ] **Step 1: Write the failing check**

From repo root:

```bash
herdr config check
test -n "$(grep -E '^previous_agent' herdr/config.toml)" || echo FAIL_no_previous
```

Expected: `herdr config check` may pass today; `FAIL_no_previous` prints because the keys are absent.

- [ ] **Step 2: Confirm keys are absent**

```bash
grep -n 'previous_agent\|dleen.herdr-agents\|kitty_graphics' herdr/config.toml || true
```

Expected: no matches.

- [ ] **Step 3: Add keys and experimental graphics**

Insert after `toggle_sidebar = "prefix+b"` (before the herdr-nvim-nav comment):

```toml
previous_agent = "alt+shift+["
next_agent = "alt+shift+]"
focus_agent = "prefix+alt+1..9"
```

After the last `[[keys.command]]` resize-right block, add:

```toml
[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "dleen.herdr-agents.open"
description = "pick an agent"
```

After `[theme]` (or at file end before `[remote]`), add:

```toml
[experimental]
kitty_graphics = true
```

Do not add `agents = "alt"`. Do not add `fork-right`.

- [ ] **Step 4: Verify**

```bash
herdr config check
grep -E '^previous_agent = "alt\+shift\+\["$' herdr/config.toml
grep -E '^next_agent = "alt\+shift\+\]"$' herdr/config.toml
grep -E '^focus_agent = "prefix\+alt\+1\.\.9"$' herdr/config.toml
grep -F 'command = "dleen.herdr-agents.open"' herdr/config.toml
grep -F 'kitty_graphics = true' herdr/config.toml
! grep -E '^agents\s*=' herdr/config.toml
! grep -F 'fork-right' herdr/config.toml
```

Expected: `herdr config check` exits 0; greps match; last two greps find nothing (exit 0 because of `!`).

- [ ] **Step 5: Commit**

```bash
git add herdr/config.toml
git commit -m "$(cat <<'EOF'
feat(herdr): bind agent picker and enable kitty graphics

Add native previous/next/focus plus prefix+a for dleen.herdr-agents,
and turn on kitty_graphics for Herdr Browser panes.
EOF
)"
```

---

### Task 2: Chromium and Bun packages

**Files:**
- Modify: `packages.conf`
- Modify: `bootstrap.sh` (add `_fallback_bun` only; do not touch the Herdr plugin block yet)
- Test: `bash -n bootstrap.sh`; `grep` package rows

**Interfaces:**
- Consumes: `install_packages` `_fallback_${fb//-/_}` naming
- Produces: `_fallback_bun`; `packages.conf` rows `chromium` and `bun` in group `cli`

- [ ] **Step 1: Write the failing check**

```bash
grep -E '^chromium[[:space:]]*\|' packages.conf || echo FAIL_no_chromium
grep -E '^bun[[:space:]]*\|' packages.conf || echo FAIL_no_bun
grep -n '_fallback_bun' bootstrap.sh || echo FAIL_no_fallback
```

Expected: three FAIL lines.

- [ ] **Step 2: Confirm they fail**

Re-run Step 1. Expected: same FAIL lines.

- [ ] **Step 3: Add package rows and fallback**

Append under the CLI tools section in `packages.conf` (after `plannotator`):

```
chromium     | cli   | -        | chromium  | chromium  | chromium | chromium | -
bun          | cli   | bun      | -         | -         | -        | -        | bun
```

Insert `_fallback_bun` immediately before `_fallback_plannotator`:

```bash
_fallback_bun() {
	export PATH="$HOME/.local/bin:$PATH"
	if command -v bun >/dev/null 2>&1; then
		log_success "bun already installed"
		return 0
	fi
	log_info "Installing bun via official installer..."
	if curl -fsSL https://bun.sh/install | BUN_INSTALL="$HOME/.local" bash; then
		hash -r 2>/dev/null || true
		export PATH="$HOME/.local/bin:$PATH"
		if command -v bun >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/bun" ]]; then
			log_success "Installed bun"
			return 0
		fi
	fi
	log_warn "bun install failed"
	return 1
}
```

- [ ] **Step 4: Verify**

```bash
bash -n bootstrap.sh
grep -E '^chromium[[:space:]]*\|[[:space:]]*cli' packages.conf
grep -E '^bun[[:space:]]*\|[[:space:]]*cli' packages.conf
grep -n '^_fallback_bun' bootstrap.sh
```

Expected: `bash -n` silent exit 0; greps match.

- [ ] **Step 5: Commit**

```bash
git add packages.conf bootstrap.sh
git commit -m "$(cat <<'EOF'
feat(bootstrap): install bun and chromium for Plannotator presenter

CWS Linux needs Chromium; Bun is required to configure herdr-plannotator.
EOF
)"
```

---

### Task 3: Pin Herdr plugins and configure presenter

**Files:**
- Modify: `bootstrap.sh` (Herdr plugin block in `main`, plus helpers near other herdr functions)
- Test: `bash -n bootstrap.sh`; `grep` pins and helper names

**Interfaces:**
- Consumes: Task 1 keys (no file change); Task 2 `bun`/`chromium` on PATH when install succeeds
- Produces:
  - `herdr_plugin_at_ref <plugin_id> <sha>` — returns 0 if JSON list shows both id and `resolved_commit`
  - `install_herdr_github_plugin <plugin_id> <owner/repo> <sha> <success_msg> <warn_msg>`
  - `plannotator_presenter_deps_ready` — 0 if bun and a Chrome/Chromium exist
  - `wait_herdr_plugin_action <plugin_id> <action_name> <timeout_sec>` — polls logs; 0 on succeeded, 1 on failed/timeout
  - `configure_herdr_plannotator` — invoke configure or warn with missing dep name

- [ ] **Step 1: Write the failing check**

```bash
grep -n 'herdr_plugin_at_ref' bootstrap.sh || echo FAIL_no_helper
grep -F '74f8550a1008156f811b0bc8663ac251d9f3fcd6' bootstrap.sh || echo FAIL_no_agents_pin
```

Expected: FAIL lines.

- [ ] **Step 2: Confirm they fail**

Re-run Step 1.

- [ ] **Step 3: Add helpers and call them after herdr-splits**

Place helpers just before `start_herdr_server`:

```bash
herdr_plugin_at_ref() {
	local plugin_id="$1"
	local sha="$2"
	local state
	state="$(herdr plugin list --plugin "$plugin_id" --json 2>/dev/null || true)"
	grep -Eq '"plugin_id"[[:space:]]*:[[:space:]]*"'"$plugin_id"'"' <<<"$state" \
		&& grep -Eq '"resolved_commit"[[:space:]]*:[[:space:]]*"'"$sha"'"' <<<"$state"
}

install_herdr_github_plugin() {
	local plugin_id="$1"
	local repo="$2"
	local sha="$3"
	local ok_msg="$4"
	local warn_msg="$5"
	if herdr_plugin_at_ref "$plugin_id" "$sha"; then
		log_info "Herdr plugin $plugin_id already installed at $sha"
		return 0
	fi
	if herdr plugin install "$repo" --ref "$sha" --yes; then
		log_success "$ok_msg"
		return 0
	fi
	log_warn "$warn_msg"
	return 1
}

plannotator_presenter_deps_ready() {
	if ! command -v bun >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/bun" ]]; then
		echo "bun"
		return 1
	fi
	if command -v google-chrome >/dev/null 2>&1 \
		|| command -v chromium >/dev/null 2>&1 \
		|| command -v chromium-browser >/dev/null 2>&1 \
		|| [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
		return 0
	fi
	echo "chrome/chromium"
	return 1
}

wait_herdr_plugin_action() {
	local plugin_id="$1"
	local action_name="$2"
	local timeout_sec="${3:-60}"
	local elapsed=0
	local log
	while (( elapsed < timeout_sec )); do
		log="$(herdr plugin log list --plugin "$plugin_id" --limit 1 2>/dev/null || true)"
		if grep -Eq 'succeeded' <<<"$log"; then
			return 0
		fi
		if grep -Eq 'failed' <<<"$log"; then
			return 1
		fi
		sleep 2
		elapsed=$((elapsed + 2))
	done
	return 1
}

configure_herdr_plannotator() {
	local missing
	if ! missing="$(plannotator_presenter_deps_ready)"; then
		log_warn "Skipping official.plannotator configure (missing $missing)"
		return 0
	fi
	if ! herdr plugin action invoke configure --plugin official.plannotator; then
		log_warn "Could not invoke official.plannotator configure"
		return 0
	fi
	if wait_herdr_plugin_action official.plannotator configure 60; then
		log_success "Configured official.plannotator presenter"
		return 0
	fi
	log_warn "official.plannotator configure failed or timed out"
	return 0
}
```

In `main`, after the herdr-splits.conf seed block and still inside `if command -v herdr`, add:

```bash
		local herdr_agents_ref="74f8550a1008156f811b0bc8663ac251d9f3fcd6"
		local herdr_browser_ref="ab5c60b1e15521ff4ac4a168ccd80b5b0133edc8"
		local herdr_plannotator_ref="e10b969ea1655dbfce25d1464eef6f27c790bb79"
		install_herdr_github_plugin dleen.herdr-agents dleen/herdr-agents \
			"$herdr_agents_ref" \
			"Installed Herdr agents picker" \
			"Could not install dleen/herdr-agents; prefix+a picker unavailable" || true
		install_herdr_github_plugin official.browser ogulcancelik/herdr-browser \
			"$herdr_browser_ref" \
			"Installed Herdr Browser" \
			"Could not install ogulcancelik/herdr-browser; in-Herdr Plannotator UI unavailable" || true
		install_herdr_github_plugin official.plannotator plannotator/herdr-plannotator \
			"$herdr_plannotator_ref" \
			"Installed Herdr Plannotator plugin" \
			"Could not install plannotator/herdr-plannotator" || true
		configure_herdr_plannotator || true
```

Do not refactor the existing splits install to use the helper unless it is a one-line swap that preserves `--ref` `107273e004e4f7ef07f13c83164d2cb2c51df65d`. Prefer leaving splits as-is.

If Browser install succeeds and `herdr plugin list --plugin official.browser --json` is empty, run `herdr plugin list --json`, find the installed id, and use that id in `install_herdr_github_plugin` plus a comment. Do not guess a third id.

Do not call `configure_plannotator_local_only` here.

- [ ] **Step 4: Verify**

```bash
bash -n bootstrap.sh
grep -F '74f8550a1008156f811b0bc8663ac251d9f3fcd6' bootstrap.sh
grep -F 'ab5c60b1e15521ff4ac4a168ccd80b5b0133edc8' bootstrap.sh
grep -F 'e10b969ea1655dbfce25d1464eef6f27c790bb79' bootstrap.sh
grep -n '^herdr_plugin_at_ref\|^install_herdr_github_plugin\|^configure_herdr_plannotator' bootstrap.sh
grep -n 'configure_herdr_plannotator' bootstrap.sh
```

Expected: `bash -n` exit 0; pins present; helpers defined; configure called from `main`.

Optional laptop smoke (do not fail the task if plugins already differ locally):

```bash
# only if herdr exists; warn-only
herdr plugin list --plugin dleen.herdr-agents --json | head -c 400 || true
```

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh
git commit -m "$(cat <<'EOF'
feat(bootstrap): pin Herdr agents, Browser, and Plannotator plugins

Install the picker and in-pane presenter on laptop and CWS; configure
only when Bun and Chrome exist, and never fail bootstrap on skip.
EOF
)"
```

---

### Task 4: Document keys, plugins, and CWS checks

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `.agents/skills/creating-cws-from-devstack-fork/reference.md`

**Interfaces:**
- Consumes: Task 1 bindings; Task 2 packages; Task 3 plugin ids and SHAs
- Produces: docs that match those exact values

- [ ] **Step 1: Write the failing check**

```bash
grep -F 'prefix+a' README.md || echo FAIL_readme
grep -F 'dleen.herdr-agents' AGENTS.md || echo FAIL_agents
grep -F 'official.plannotator' .agents/skills/creating-cws-from-devstack-fork/reference.md || echo FAIL_ref
```

Expected: FAIL lines.

- [ ] **Step 2: Confirm they fail**

Re-run Step 1.

- [ ] **Step 3: Update docs**

In `README.md` bootstrap bullet about Herdr, replace the splits-only sentence with:

```
- Links the Herdr keymap (agent previous/next `alt+shift+[` / `]`, focus `prefix+alt+1..9`, picker `prefix+a`), builds/links `herdr-nvim-nav`, installs `herdr-splits`, `dleen/herdr-agents`, `ogulcancelik/herdr-browser`, and `plannotator/herdr-plannotator` when Herdr is available, and enables `kitty_graphics`
```

In Optional tools, add that CWS/bootstrap may install Chromium and Bun so the Herdr Plannotator presenter can `configure`; share stays disabled; 19432 remains the laptop tunnel.

In `AGENTS.md` Hunk/Plannotator paragraph, append:

```
Bootstrap also pins Herdr plugins `dleen.herdr-agents` (`prefix+a`), `official.browser`, and `official.plannotator`, and sets `kitty_graphics`. Native agent keys: previous/next `alt+shift+[` / `alt+shift+]`, focus `prefix+alt+1..9`. Configure runs only when Bun and Chrome/Chromium exist; otherwise bootstrap warns and continues. Sharing stays `PLANNOTATOR_SHARE=disabled`.
```

In `reference.md` E2E table, add rows:

| Check | Expect |
|---|---|
| Herdr plugins | `dleen.herdr-agents` @ `74f8550a1008156f811b0bc8663ac251d9f3fcd6`; `official.browser` @ `ab5c60b1e15521ff4ac4a168ccd80b5b0133edc8`; `official.plannotator` @ `e10b969ea1655dbfce25d1464eef6f27c790bb79` (or documented skip/warn) |
| `kitty_graphics` | `true` in `~/.config/herdr/config.toml` |
| Agent keys | `previous_agent`/`next_agent`/`focus_agent` as above; `dleen.herdr-agents.open` on `prefix+a` |
| Presenter deps | `bun` and Chrome/Chromium **or** bootstrap warn naming the missing one |
| Configure | `official.plannotator` configure succeeded **or** documented skip |
| Share after configure | `PLANNOTATOR_SHARE=disabled` and `jq -e '.share == "disabled"' ~/.plannotator/config.json` |

Do not edit `ssh/cws-mcp-forwards.conf` or `zsh/zshenv`.

- [ ] **Step 4: Verify**

```bash
grep -F 'prefix+a' README.md
grep -F 'dleen.herdr-agents' AGENTS.md
grep -F 'official.plannotator' .agents/skills/creating-cws-from-devstack-fork/reference.md
grep -F '74f8550a1008156f811b0bc8663ac251d9f3fcd6' .agents/skills/creating-cws-from-devstack-fork/reference.md
grep PLANNOTATOR_SHARE=disabled zsh/zshenv
grep 19432 ssh/cws-mcp-forwards.conf
```

Expected: all match; last two unchanged.

- [ ] **Step 5: Commit**

```bash
git add README.md AGENTS.md .agents/skills/creating-cws-from-devstack-fork/reference.md
git commit -m "$(cat <<'EOF'
docs(herdr): document agent keys and Plannotator Herdr plugins

Keep CWS E2E checks aligned with pinned plugin SHAs and share-disabled.
EOF
)"
```
