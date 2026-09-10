# CWS control plane

The laptop Cursor in this pane is the control plane. Implementation runs as a worker on the Cloud Workspace Herdr server. After attach, that worker is a local mirror pane. Drive it with this pane's `herdr` CLI.

`creating-cws-from-devstack-fork` owns provision, SSH wait (`hostname`), and Herdr Mirror attach. This file is the loop after `herdr workspace list` shows `<prefix>: <remote-name>`.

## SSH vs local `herdr`

| Job | Path |
|---|---|
| Box up, bootstrap checklist, OAuth tunnel | SSH (`hostname`, `reference.md` wait/checklist). Not Herdr drive. |
| List / split / start / prompt CWS agents | Local `herdr` on Herdr Mirror panes |

CWS sshd does not forward unix sockets. Native `herdr machine` does not retarget this pane's CLI. Nested `herdr --remote` is disabled.

## Drive an existing worker

Mirror pane foreground is `herdr-mirror`, not `cursor-agent`. `herdr agent get <local-pane-id>` can still show the remote agent. `herdr agent prompt` returns `agent_not_ready` ("no longer the pane foreground process").

Target the local pane ID (`wK:p4`). Remote live names (`say-hi`) are not in this pane's agent namespace.

```bash
herdr pane send-text <local-mirror-pane-id> "<prompt>"
herdr pane send-keys <local-mirror-pane-id> enter
herdr pane wait-output <local-mirror-pane-id> --match "<unique>" \
  --source recent-unwrapped --timeout 120000
herdr pane read <local-mirror-pane-id> --source recent-unwrapped
```

On `blocked`, `send-keys` to that same pane. Do not MCP-edit. Name the ticket, branch, and CWS-scaffolded skills in the prompt (Go: `go-foundations`, then `go-code-review` / `go-pr-review` plus matching chapters).

## Start a worker

Do not `herdr agent start` on a mirror pane. That starts locally and kills the stream.

Use a mirrored shell whose remote cwd is `/workspace/<repo>` (`herdr-mirror remote-split down` if you need a new one). Discover the remote pane ID from that shell, then start there:

```bash
herdr pane run <local-shell-pane-id> "herdr pane current --current"
herdr pane read <local-shell-pane-id> --source recent-unwrapped
herdr pane run <local-shell-pane-id> \
  "herdr agent start <jira-id>-impl --kind cursor --pane <remote-pane-id>"
```

Kind is `cursor` unless the user named another. `<remote-pane-id>` looks like `w1:p2`, never `wK:p3`.

Tests and git may use `herdr pane run` on a different mirrored CWS shell. They are not a substitute for the worker.

## Done when

- Local `herdr agent list` includes the mirrored worker in the repo workspace
- The worker produced the commits / PR updates
- `/resume` in that repo folder on the CWS has a trace
