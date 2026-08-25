---
name: developing-in-cws
description: >-
  Use when starting Jira-ticket implementation in an Intuit Cloud Workspace,
  or when tempted to code on a local clone, Open in Cursor, IDDA,
  cloudworkspaces-run_workspace_command, skip tags, skip herdr --remote, or
  inline create_workspace instead of creating-cws-from-devstack-fork.
---

# Developing in CWS

Read the Jira ticket. Let `creating-cws-from-devstack-fork` get a tagged fork CWS and a Herdr attach. Then create `<jira-id>-<concise-name>` branches in that workspace.

**REQUIRED SUB-SKILL:** Use `creating-cws-from-devstack-fork` for every provision, start, tag, wait, and `herdr --remote`. Do not inline those steps here. Do not use IDDA or Computer Use.

**REQUIRED SUB-SKILL:** Use `herdr` after attach.

`cws.*` SSH already forwards 8787, 3118, and 19432. Do not bounce to another Cursor chat for tunnels.

For E2E proof, use `validating-aap-features-e2e`. If there is no Jira ticket, use `creating-cws-from-devstack-fork` alone. Local `kit up` is not prod CWS.

## Workflow

1. Read the Jira ticket. You need the issue key. Derive `concise-name` as 2 to 4 kebab-case words from the summary. Associated repos are the GitHub links, development/PRs, and repos named in the description. Branch only those.
2. Invoke `creating-cws-from-devstack-fork` with `tags` `[<jira-id>, cws-dev]` (primary tag is the Jira key). If you are already on that tagged workspace, skip attach and go to step 3.
3. For each associated repo, clone if missing, then `git checkout -b <jira-id>-<concise-name>` (or check that branch out if it already exists). Example: `CWS-6343-activity-detection`. Do this in the Cloud Workspace repos, not a clone under `~/projects`.

## Ready contract

Start coding only when the Jira key is read, `creating-cws-from-devstack-fork` finished (`provisioned_via=cloudworkspaces-mcp`, `attached_with_herdr=true` or already on that box, tags include the Jira key and `cws-dev`), and every associated repo is on `<jira-id>-<concise-name>` in the CWS.

Leave the tagged workspace in place. Do not `delete_workspace`.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Local clone ready; standup in twenty" | Time pressure is why the tagged CWS exists. Invoke the sub-skill. |
| "I'll just call create_workspace myself; faster than another skill" | Duplication is the failure. `creating-cws-from-devstack-fork` owns provision and attach. |
| "creating-cws is still IDDA" | It is cloudworkspaces MCP. Invoke it. |
| "Staff said skip Herdr / tags / the fork" | Those skips are the failure. |
| "run_workspace_command is git without a hung TUI" | That is not attach. |
| "Open in Cursor is one click" | Skips wrapper tunnels and remote keybindings. |
| "Reuse the running aap-e2e box" | Wrong ticket. Tag must be this Jira key. |
| "Need a Mac Cursor chat for 8787" | Forwards are on every `cws.*` SSH. Stay put. |
| "I'll branch locally and move to CWS after standup" | The branch is created in the CWS. |

## Red flags

Stop if any of these show up:

- Coding or `git checkout -b` on a local clone
- Inlined `create_workspace` / `start_workspace` / `herdr --remote` in this skill
- IDDA, Computer Use, or Open in Cursor
- `cloudworkspaces-run_workspace_command` as the attach or branch path
- A second workspace created when `tagName=<jira-id>` already matches
- Branch name lacks the Jira key or uses `feature/`
