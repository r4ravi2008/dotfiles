---
name: creating-cws-from-devstack-fork
description: >-
  Use when creating, recreating, starting, or attaching a production Intuit
  Cloud Workspace using the rkommineni/devstack fork, or when tempted to use
  IDDA, use-computer-mcp, Computer Use, herdr --remote, HERDR_ENV unset,
  cloud-workspaces/devstack, kit up, Open in, or to install tools inside the
  workspace.
---

# Creating a CWS from the DevStack fork

Create with the cloudworkspaces MCP. Attach with `herdr machine add`, then open a pane on that machine.

Do not SSH-forward laptop ports 8787, 3118, or 19432. Cursor owns those locally. If you are already on the target workspace, skip attach.

**REQUIRED SUB-SKILL:** Use `herdr` after attach.

Callers such as `developing-in-cws` pass `tags`. This skill does not read Jira or create feature branches.

## When to use

- New prod CWS that must pick up `cws-dotfiles` (cloned only at create time)
- Recreate after a bootstrap miss. Do not patch the live box.
- Start a stopped box, or attach to an existing `cws.*` host
- Another skill needs a fork-seeded CWS plus a Herdr saved machine and a pane on it

Skip this skill if you are about to `kit up` a local kind DevStack, pointing at `cloud-workspaces/devstack`, or reaching for IDDA.

## Caller contract

Pass `tags` when the caller has a reuse identity. The first tag is `list_workspaces` `tagName`. Example: `[CWS-6343, cws-dev]`.

With no tags, create from the fork. Do not grab a random tagged box.

If the user named a workspace, `get_workspace_by_name`, start it if Stopped, then attach.

Record `provisioned_via: cloudworkspaces-mcp` and `attached_with_herdr: true`. Leave tagged workspaces in place.

## Preconditions

1. Dotfiles tip is on `cws`, not `origin`:
   `git -C ~/.dotfiles push cws HEAD:main`
   `origin` is public `github.com:r4ravi2008/dotfiles`. Do not push it (hook + leak).
2. Fork tip is on `fork/master`:
   `https://github.intuit.com/rkommineni/devstack`
   Do not `git push origin master`. That is `cloud-workspaces/devstack`.

Remotes, wait probes, tunnels, and the bootstrap checklist are in `reference.md`.

## Workflow

1. `get_user_onboarding_status`. If they are not onboarded, give the URL and wait.
2. If there are tags, `list_workspaces` with `tagName=<primary tag>`. Prefer `gitRepoUrl` `https://github.intuit.com/rkommineni/devstack`.
   - Stopped: `start_workspace`.
   - RUNNING: reuse it. `add_workspace_tags` for any missing caller tags.
   - Missing, or no tags: `create_workspace` with that fork URL, `region` `us-west`, and caller `tags` when provided. Use the current fork if this session is already on one.
3. Poll `get_workspace` until `RUNNING`, then confirm SSH from the wait section in `reference.md` (`get_workspace_info` plus `hostname`). Do **not** wait for user `bootstrap.sh` to exit. Record `provisioned_via: cloudworkspaces-mcp`.
4. If this environment is already that workspace (`/.cws` exists), skip this step. Otherwise attach from the local Herdr pane (`HERDR_ENV=1` stays set). Host is `cws.<workspace-name>` from `get_workspace`.

   ```bash
   herdr machine list --json
   herdr machine add cws.<workspace-name> --label '<primary-tag-or-workspace-name>'
   herdr machine list --json
   ```

   Skip `add` when that SSH target is already saved and enabled. `add` must persist a profile. CWS bootstrap `nohup herdr server` is not a saved-machine daemon; if add asks to restart the remote server so it survives SSH loss, answer **y** on a box you just provisioned. If it prints `not ready for saved machines` with no prompt, run the same `machine add` via `herdr pane run` in a sibling TTY and send `y`. Do not restart when the remote already has the user's live agents unless they asked. Do not approve experimental handoff.

   Local `herdr pane` talks to Local. Open a pane **on that machine**:

   ```bash
   ssh -o BatchMode=yes cws.<workspace-name> 'herdr workspace list'
   ```

   No workspace: `herdr workspace create --cwd /workspace --label <workspace-name> --no-focus`. Workspace exists: `herdr pane list` then `herdr pane split <pane-id> --cwd /workspace/<repo> --no-focus` (or use the root pane). Read IDs from JSON. Follow `herdr` (remote IDs from the host CLI). Record `attached_with_herdr: true`.

If the verify checklist fails, fix `cws-dotfiles`, `git push cws HEAD:main`, and create a new workspace. Do not `brew`, `npm`, or `npx skills` on the box. CWS Node is 18, and `npx skills` dies on `util.styleText`.

`delete_workspace` only when the user asks. Never delete the tagged box you just attached.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Skill still requires IDDA / use-computer-mcp" | Old path. This skill is cloudworkspaces MCP plus `herdr machine add`. |
| "MCP skips fork/dotfiles bootstrap" | Create still clones `cws-dotfiles` once. Seed the fork URL. |
| "Staff says click IDDA, MCP is unofficial" | MCP is the create path. IDDA is a red flag. |
| "developing-in-cws already inlines create_workspace" | Callers invoke this skill. Do not duplicate it there. |
| "Official cloud-workspaces/devstack is what everyone uses" | Fork `master` has go-style-guide. Upstream does not. |
| "Push origin/main so CWS sees it" | CWS clones `cws-dotfiles` on GHES. `origin` is public GitHub. |
| "Install hunk/plannotator on the box tonight" | Create-time bootstrap only. Patching the box proves nothing. |
| "npx skills add. Node is there" | Node 18. Bundle extras in dotfiles instead. |
| "Need a Mac Cursor chat for 8787" | Laptop Cursor owns 8787/3118. Do not SSH-forward them. |
| "kit up / make is faster" | Local kind, not prod CWS. |
| "Open in Cursor if herdr is slow" | Skips remote keybindings. Use `herdr machine add`. |
| "Wait for pgrep bootstrap.sh before machine add" | Attach as soon as SSH works. Unanchored `pgrep -f bootstrap.sh` matches the probe's own `bash -l -c` and never returns. |
| "run_workspace_command is attach enough" | Attach is `herdr machine add` plus a pane on that machine. |
| "`herdr --remote` is attach" | Nested TUI. Saved machine plus a pane on that host. |
| "Unset HERDR_ENV so nested herdr can attach" | Stay in local Herdr. `machine add` is a CLI. |
| "LocalForward 8787/3118/19432 so CWS OAuth works" | Steals Cursor's laptop ports. Leave them local. |
| "Enable share.plannotator.ai for the phone" | Keep `PLANNOTATOR_SHARE=disabled`. |
| "Set PLANNOTATOR_REMOTE=0 for local-only" | CWS zsh still uses 19432 on the box. That is not a laptop LocalForward. |

## Red flags

Stop if any of these show up:

- IDDA, `use-computer-mcp`, or Computer Use to create or attach
- `gitRepoUrl` contains `cloud-workspaces/devstack`
- `git push origin` from `~/.dotfiles` or DevStack
- `kit up`, `make` in devstack, or `ssh devstack` on port 32222
- `brew` / `npm i -g` / `npx skills` inside the workspace
- Open in Cursor
- `herdr --remote`
- Unsetting `HERDR_ENV` (`HERDR_ENV=`, `env -u HERDR_ENV`)
- Unanchored `pgrep -f bootstrap.sh` as an attach gate
- `cloudworkspaces-run_workspace_command` as attach
- `PLANNOTATOR_SHARE` not `disabled`
- `LocalForward` 8787, 3118, or 19432 on `cws.*`
