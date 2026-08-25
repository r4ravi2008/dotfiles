---
name: developing-in-cws
description: >-
  Use when starting Jira-ticket implementation in an Intuit Cloud Workspace,
  or when tempted to code on a laptop clone, Open in Cursor, IDDA,
  cloudworkspaces-run_workspace_command, skip tags, skip herdr --remote,
  inline create_workspace instead of creating-cws-from-devstack-fork, or
  provision from inside a CWS.
---

# Developing in CWS

Read the Jira ticket on the laptop. Let `creating-cws-from-devstack-fork` get you a tagged fork CWS and a Herdr attach. Then create `<jira-id>-<concise-name>` branches inside that box.

**REQUIRED SUB-SKILL:** Use `creating-cws-from-devstack-fork` for every provision, start, tag, wait, and `herdr --remote`. Do not inline those steps here. Do not use IDDA or Computer Use.

**REQUIRED SUB-SKILL:** Use `herdr` after attach.

Laptop only. If `/.cws` exists, `CWS_WORKSPACE_ID` is set, or `id -un` is `coder` with `/workspace`, stop. Do not create, start, tag, run `herdr --remote`, or branch from this session.

Handoff, this shape only:

1. This session is inside a Cloud Workspace. Stop.
2. Open a laptop Cursor session.
3. From that laptop session, run `creating-cws-from-devstack-fork` with tags `[<jira-id>, cws-dev]`, then create `<jira-id>-<concise-name>` branches inside that CWS.

Do not offer IDDA, Open in Cursor, `run_workspace_command`, inlined `create_workspace`, or laptop clones as a substitute.

For E2E proof, use `validating-aap-features-e2e`. If there is no Jira ticket, use `creating-cws-from-devstack-fork` alone. Local `kit up` is not prod CWS.

## Workflow

Run from the laptop.

1. Read the Jira ticket. You need the issue key. Derive `concise-name` as 2 to 4 kebab-case words from the summary. Associated repos are the GitHub links, development/PRs, and repos named in the description. Branch only those.
2. Invoke `creating-cws-from-devstack-fork` with `tags` `[<jira-id>, cws-dev]` (primary tag is the Jira key). That skill reuses a matching tagged box or creates from `https://github.intuit.com/rkommineni/devstack`, waits until `RUNNING`, and attaches with Shell `herdr --remote`. Stay in that remote session.
3. For each associated repo, clone if missing, then `git checkout -b <jira-id>-<concise-name>` (or check that branch out if it already exists). Example: `CWS-6343-activity-detection`.

## Ready contract

Start coding only when the Jira key is read, `creating-cws-from-devstack-fork` finished (`provisioned_via=cloudworkspaces-mcp`, `attached_with_herdr=true`, tags include the Jira key and `cws-dev`), and every associated repo is on `<jira-id>-<concise-name>` inside the CWS.

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
| "I'm already on CWS, MCP talks to the API anyway" | Stop. Open a laptop Cursor session. |
| "Correct policy is stop with no progress" | Handoff is the progress. |
| "Handoff can mention IDDA or laptop clones as or" | Handoff is the sub-skill plus in-CWS branches only. |
| "I'll branch locally and move to CWS after standup" | The branch is created inside the CWS. |

## Red flags

Stop if any of these show up:

- Coding or `git checkout -b` on a laptop clone
- Inlined `create_workspace` / `start_workspace` / `herdr --remote` in this skill
- IDDA, Computer Use, or Open in Cursor
- `cloudworkspaces-run_workspace_command` as the attach or branch path
- A second workspace created when `tagName=<jira-id>` already matches
- `/.cws` / `coder` session creating, attaching, or "good enough" branching
- Branch name lacks the Jira key or uses `feature/`
