---
name: developing-in-cws
description: >-
  Use when starting Jira-ticket implementation in an Intuit Cloud Workspace,
  or when tempted to code on a local clone, Open in Cursor, IDDA,
  cloudworkspaces-run_workspace_command, cloudworkspaces-edit_workspace_file,
  skip tags, skip herdr-mirror, drive CWS with SSH herdr, herdr agent prompt
  on a mirror pane, herdr machine as CWS attach, or inline create_workspace
  instead of creating-cws-from-devstack-fork.
---

# Developing in CWS

Read the Jira ticket. Let `creating-cws-from-devstack-fork` get a tagged fork CWS and a Herdr Mirror of it on this client. Then create `<jira-id>-<concise-name>` branches in that workspace. This laptop session is the control plane. A Cursor (or requested-kind) agent on the Cloud Workspace does the implementation. Drive that worker with local `herdr pane send-text` as in `control-plane.md`.

**REQUIRED SUB-SKILL:** Use `creating-cws-from-devstack-fork` for every provision, start, tag, wait, and Herdr Mirror attach. Do not inline those steps here. Do not use IDDA or Computer Use.

**REQUIRED SUB-SKILL:** Use `herdr` after Mirror has copied CWS workspaces into this client.

`cws.*` SSH already forwards 8787, 3118, and 19432. Do not bounce to another Cursor chat for tunnels.

For E2E proof, use `validating-aap-features-e2e`. If there is no Jira ticket, use `creating-cws-from-devstack-fork` alone. Local `kit up` is not prod CWS.

## Workflow

1. Read the Jira ticket. You need the issue key. Derive `concise-name` as 2 to 4 kebab-case words from the summary. Associated repos are the GitHub links, development/PRs, and repos named in the description. Branch only those.
2. Invoke `creating-cws-from-devstack-fork` with `tags` `[<jira-id>, cws-dev]` (primary tag is the Jira key). If you are already on that tagged workspace, skip attach and go to step 3.
3. For each associated repo, clone if missing, then `git checkout -b <jira-id>-<concise-name>` (or check that branch out if it already exists). Example: `CWS-6343-activity-detection`. Do this in the Cloud Workspace repos, not a clone under `~/projects`.
4. Follow `control-plane.md`. Start a worker on the box in the associated-repo cwd. Send the implementation prompt with `herdr pane send-text`. The worker invokes CWS-scaffolded skills (`go-style-guide` / `go-*`, and whatever else the ticket needs). Do not apply those skills from the laptop over MCP file edits.

## Ready contract

Start implementation only when the Jira key is read, `creating-cws-from-devstack-fork` finished (`provisioned_via=cloudworkspaces-mcp`, `attached_with_herdr=true` or already on that box, tags include the Jira key and `cws-dev`), every associated repo is on `<jira-id>-<concise-name>` in the CWS, local `herdr workspace list` shows `<prefix>: ...` for that host, and a worker agent is live in that mirrored repo pane. `/resume` in `/workspace` or the repo folder on the box must be able to see that worker. Empty resume means no worker ran.

Leave the tagged workspace in place. Do not `delete_workspace`.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Local clone ready; standup in twenty" | Time pressure is why the tagged CWS exists. Invoke the sub-skill. |
| "I'll just call create_workspace myself; faster than another skill" | Duplication is the failure. `creating-cws-from-devstack-fork` owns provision and attach. |
| "creating-cws is still IDDA" | It is cloudworkspaces MCP. Invoke it. |
| "Staff said skip Herdr / tags / the fork" | Those skips are the failure. |
| "run_workspace_command is git without a hung TUI" | That is not Mirror and not the worker. |
| "edit_workspace_file is coding on the CWS" | MCP writes leave no agent on the box. Prompt the worker. |
| "Local herdr agent list is empty for the CWS" | Mirror is not attached. `herdr-mirror start`, then target local pane IDs. |
| "Staff already proved SSH herdr; attach is machine plus SSH pane list" | Proven SSH is wait/tunnels. Drive is local `herdr` on Mirror panes. |
| "agent prompt is the agent surface; pane send-text is only for raw terminals" | Mirror foreground is `herdr-mirror`. `agent prompt` returns `agent_not_ready`. `pane send-text` is the drive path. |
| "I invoked go-* from the laptop; the skills are in context" | CWS-scaffolded skills run in the CWS worker so `/resume` has a trace. |
| "Open in Cursor is one click" | Skips wrapper tunnels and remote keybindings. |
| "Reuse the running aap-e2e box" | Wrong ticket. Tag must be this Jira key. |
| "Need a Mac Cursor chat for 8787" | Forwards are on every `cws.*` SSH. Stay put. |
| "I'll branch locally and move to CWS after standup" | The branch is created in the CWS. |

## Red flags

Stop if any of these show up:

- Coding or `git checkout -b` on a local clone
- Inlined `create_workspace` / `start_workspace` / `herdr-mirror` hosts.toml in this skill
- IDDA, Computer Use, or Open in Cursor
- `cloudworkspaces-run_workspace_command` as the attach, branch, or implementation path
- `cloudworkspaces-edit_workspace_file` / `write_workspace_file` as the implementation path
- Tests or commits via `herdr pane run` with no CWS worker agent
- SSH `herdr` to split, start, or prompt CWS agents
- `herdr agent prompt` or `herdr agent start` on a mirror pane
- `herdr machine add` as CWS attach
- `herdr-mirror teardown`
- A second workspace created when `tagName=<jira-id>` already matches
- Branch name lacks the Jira key or uses `feature/`
