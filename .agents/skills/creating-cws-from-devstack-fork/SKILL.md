---
name: creating-cws-from-devstack-fork
description: >-
  Use when creating, recreating, starting, or attaching a production Intuit
  Cloud Workspace using the rkommineni/devstack fork, or when tempted to use
  IDDA, use-computer-mcp, Computer Use, cloud-workspaces/devstack, kit up,
  Open in, or to install tools inside the workspace.
---

# Creating a CWS from the DevStack fork

Create with the cloudworkspaces MCP. Attach with `herdr --remote` in the Shell.

`cws.*` SSH already forwards 8787, 3118, and 19432. Do not bounce to another Cursor chat for tunnels. If you are already on the target workspace, skip attach.

**REQUIRED SUB-SKILL:** Use `herdr` after attach.

Callers such as `developing-in-cws` pass `tags`. This skill does not read Jira or create feature branches.

## When to use

- New prod CWS that must pick up `cws-dotfiles` (cloned only at create time)
- Recreate after a bootstrap miss. Do not patch the live box.
- Start a stopped box, or attach to an existing `cws.*` host
- Another skill needs a fork-seeded CWS plus `herdr --remote`

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
4. If this environment is already that workspace, skip this step. Otherwise, in the Shell:

   ```bash
   herdr --remote cws.<workspace-name>
   ```

   The name comes from `get_workspace` (host `cws.devstack-<id>`). Stay in that remote session. Follow `herdr`. Record `attached_with_herdr: true`.

If the verify checklist fails, fix `cws-dotfiles`, `git push cws HEAD:main`, and create a new workspace. Do not `brew`, `npm`, or `npx skills` on the box. CWS Node is 18, and `npx skills` dies on `util.styleText`.

`delete_workspace` only when the user asks. Never delete the tagged box you just attached.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Skill still requires IDDA / use-computer-mcp" | Old path. This skill is cloudworkspaces MCP plus Shell `herdr --remote`. |
| "MCP skips fork/dotfiles bootstrap" | Create still clones `cws-dotfiles` once. Seed the fork URL. |
| "Staff says click IDDA, MCP is unofficial" | MCP is the create path. IDDA is a red flag. |
| "developing-in-cws already inlines create_workspace" | Callers invoke this skill. Do not duplicate it there. |
| "Official cloud-workspaces/devstack is what everyone uses" | Fork `master` has go-style-guide. Upstream does not. |
| "Push origin/main so CWS sees it" | CWS clones `cws-dotfiles` on GHES. `origin` is public GitHub. |
| "Install hunk/plannotator on the box tonight" | Create-time bootstrap only. Patching the box proves nothing. |
| "npx skills add. Node is there" | Node 18. Bundle extras in dotfiles instead. |
| "Need a Mac Cursor chat for 8787" | Forwards are on every `cws.*` SSH. Stay put. |
| "kit up / make is faster" | Local kind, not prod CWS. |
| "Open in Cursor if herdr is slow" | Skips wrapper tunnels and remote keybindings. |
| "Wait for pgrep bootstrap.sh before herdr --remote" | Attach as soon as SSH works. Unanchored `pgrep -f bootstrap.sh` matches the probe's own `bash -l -c` and never returns. |
| "run_workspace_command is attach enough" | Attach is Shell `herdr --remote`. |
| "Kill Cursor to free 8787" | Bind IPv4+IPv6 forwards. Do not kill the user's Cursor. |
| "Enable share.plannotator.ai for the phone" | Keep `PLANNOTATOR_SHARE=disabled`. |
| "ClearAllForwardings on the attach session" | Drops 8787/3118/19432. Dedicated `-fN` only. |
| "Set PLANNOTATOR_REMOTE=0 for local-only" | That breaks the 19432 tunnel. REMOTE=1 is not a public share. |

## Red flags

Stop if any of these show up:

- IDDA, `use-computer-mcp`, or Computer Use to create or attach
- `gitRepoUrl` contains `cloud-workspaces/devstack`
- `git push origin` from `~/.dotfiles` or DevStack
- `kit up`, `make` in devstack, or `ssh devstack` on port 32222
- `brew` / `npm i -g` / `npx skills` inside the workspace
- Open in Cursor
- Unanchored `pgrep -f bootstrap.sh` as an attach gate
- `cloudworkspaces-run_workspace_command` as attach
- `PLANNOTATOR_SHARE` not `disabled`
- Killing Cursor to steal port 8787
