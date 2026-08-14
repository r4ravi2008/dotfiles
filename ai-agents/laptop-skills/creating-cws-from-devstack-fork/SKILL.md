---
name: creating-cws-from-devstack-fork
description: >-
  Use when creating or recreating a production Intuit Cloud Workspace from a
  laptop so it clones the personal DevStack fork and latest cws-dotfiles, or
  when attaching with herdr --remote. Use when tempted to use
  cloud-workspaces/devstack, kit up, Open in, github.com origin, or to install
  tools inside the workspace. Do not use from inside a Cloud Workspace.
---

# Creating a CWS from the DevStack fork

Laptop-only. IDDA (Intuit Builder Desktop App) does not exist in a Cloud Workspace.

**If `/.cws` exists, `CWS_WORKSPACE_ID` is set, or `id -un` is `coder` with `/workspace`: stop.** Tell the user to run this from a laptop Cursor session. Do not drive IDDA, CWS API, kubectl, or `herdr --remote` from inside CWS.

**REQUIRED SUB-SKILL:** Use `use-computer-mcp` for every IDDA click.

## When to use

- New prod CWS that must pick up `cws-dotfiles` (create-time clone only)
- Recreate after a bootstrap miss (do not patch the live box)
- Attach / tunnel / OAuth / Plannotator checks on an existing `cws.*` host

## When not to use

- Already inside a Cloud Workspace
- Local kind DevStack (`kit up` / `make` in `devstack/`) — that is not prod CWS
- Upstream `cloud-workspaces/devstack` (no go-style-guide fork commit)

## Preconditions (laptop)

1. Dotfiles tip is on **`cws`**, not `origin`:
   `git -C ~/.dotfiles push cws HEAD:main`
   `origin` is public `github.com:r4ravi2008/dotfiles` — do not push (hook + leak).
2. Fork tip is on **`fork/master`**:
   `https://github.intuit.com/rkommineni/devstack`
   Do not `git push origin master` (that is `cloud-workspaces/devstack`).
3. IDDA running: `com.wails.IntuitDeveloperDesktopApp` (v0.2.58+).

## Create (IDDA)

Exact clicks: **REQUIRED** `reference.md`.

- Repo: `https://github.intuit.com/rkommineni/devstack` (not `cloud-workspaces/devstack`)
- Size **medium**, region **us-west**
- Expand Advanced **before** filling the URL if Create stays disabled
- Expand the URL combo, then `set_value` the full fork URL
- Click **Create** only when it is enabled (not Loading)
- Open details by the **workspace name**, never **Open in**
- Delete is on the Config tab of the detail page

Poll until **Running** and `~/.ssh/prd.cws.<name>.conf` exists. Then wait until `bootstrap.sh --profile cws` is **not** in `pgrep` before testing.

## Attach

From the **laptop** only:

```bash
herdr --remote cws.<workspace-name>
```

The zsh wrapper adds `--remote-keybindings server` (Alt+hjkl) and opens a dedicated `ssh -fN` so 8787 / 3118 / 19432 survive. Herdr’s own mux sets `ClearAllForwardings` — do not rely on that session for tunnels. `herdr/config.toml` must keep `manage_ssh_config = false`.

Probes: `ssh -o ClearAllForwardings=yes` is OK. Attach tunnels: never.

## Verify (no manual installs)

Checklist: **REQUIRED** `reference.md`.

If anything is missing: fix `cws-dotfiles`, `git push cws HEAD:main`, create a **new** workspace. Do not `brew` / `npm` / `npx skills` on the box (CWS Node is 18; `npx skills` dies on `util.styleText`).

## Rationalizations

| Excuse | Reality |
|---|---|
| "Official cloud-workspaces/devstack is what everyone uses" | Fork `master` has go-style-guide. Upstream does not. |
| "Push origin/main so CWS sees it" | CWS clones `cws-dotfiles` on GHES. `origin` is public GitHub. |
| "Install hunk/plannotator on the box tonight" | Create-time bootstrap only. Patching the box proves nothing. |
| "npx skills add — Node is there" | Node 18. Bundle extras in dotfiles instead. |
| "I'm already on CWS, drive IDDA from here" | IDDA is macOS. This skill is not installed on CWS. Stop. |
| "Computer Use MCP still drives the laptop from this CWS chat" | Stop. Open a laptop-local Cursor session. Do not create from a `coder` shell. |
| "kit up / make is faster" | Local kind, not prod CWS. |
| "Open in Cursor if herdr is slow" | Skips wrapper tunnels and remote keybindings. |
| "Kill Cursor to free 8787" | Bind IPv4+IPv6 forwards; use `127.0.0.1` if `::1` is taken. Do not kill the user's Cursor. |
| "Enable share.plannotator.ai for the phone" | Leaks internal plans. Keep `PLANNOTATOR_SHARE=disabled`. |
| "ClearAllForwardings on the attach session" | Drops 8787/3118/19432. Dedicated `-fN` only. |
| "Set PLANNOTATOR_REMOTE=0 for local-only" | That breaks the 19432 tunnel. REMOTE=1 is not a public share. |

## Red flags — stop

- Repo URL contains `cloud-workspaces/devstack`
- `git push origin` from `~/.dotfiles` or DevStack
- `kit up`, `make` in devstack, or `ssh devstack` on port 32222
- `brew` / `npm i -g` / `npx skills` inside the workspace
- Computer Use / IDDA / `herdr --remote` from a `coder` CWS shell
- `PLANNOTATOR_SHARE` not `disabled`
- Killing Cursor to steal port 8787
