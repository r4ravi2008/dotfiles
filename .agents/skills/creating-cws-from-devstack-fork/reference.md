# CWS create + attach

Companion to `creating-cws-from-devstack-fork`. No IDDA.

## Remotes

| Repo | Remote | Push to | Never |
|---|---|---|---|
| `~/.dotfiles` | `cws` → `github.intuit.com:rkommineni/cws-dotfiles.git` | `git push cws HEAD:main` | `origin` (`github.com:r4ravi2008/dotfiles`) |
| DevStack worktree | `fork` → `github.intuit.com:rkommineni/devstack.git` | `fork/master` | `origin` (`cloud-workspaces/devstack`) |

CWS create clones `CWS_USER_DOTFILES_REPO=https://github.intuit.com/rkommineni/cws-dotfiles.git` **once** (MCP or otherwise). Existing workspaces do not pull new commits.

Confirm tips before create:

```bash
git -C ~/.dotfiles ls-remote cws refs/heads/main
git -C <devstack-worktree> ls-remote fork refs/heads/master
```

## cloudworkspaces MCP

Tools (names may be prefixed by the client): `get_user_onboarding_status`, `list_workspaces`, `get_workspace`, `get_workspace_by_name`, `get_workspace_info`, `start_workspace`, `create_workspace`, `add_workspace_tags`, `delete_workspace`.

Create args:

- `gitRepoUrl`: `https://github.intuit.com/rkommineni/devstack`
- `region`: `us-west`
- `tags`: caller list, or omit when standalone with no reuse identity

`list_workspaces` `tagName` is one exact tag (the primary / first caller tag). Match `gitRepoUrl` on the fork after listing.

Do not use IDDA, Computer Use, or `use-computer-mcp` for create. `delete_workspace` only if the user asks.

## Wait

1. `get_workspace` status is `RUNNING`.
2. `get_workspace_info` shows bootstrap complete (checked-out repos / git status).
3. `~/.ssh/prd.cws.<name>.conf` (or equivalent `Host cws.<name>`) exists.
4. `ssh -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ClearAllForwardings=yes coder@cws.<name> 'hostname'` works.
5. `pgrep -f 'bash /home/coder/.dotfiles/bootstrap.sh'` is empty on the box.
6. `git -C ~/.dotfiles log -1 --oneline` on the box matches the `cws/main` tip you pushed.

Host block example: `Host cws.devstack-<id>`, `ProxyCommand` via `bastion.cws.cwsppdusw2.iks2.a.intuit.com`, user `coder`, key `~/.ssh/cws_id_rsa`. Do not Include `ssh/cws-mcp-forwards.conf`. Do not LocalForward 8787, 3118, or 19432 onto `cws.*`.

## Attach

Keep `HERDR_ENV=1`. Do not unset it. Do not run `herdr --remote`.

```bash
herdr machine list --json
herdr machine add cws.devstack-<id> --label '<primary-tag-or-workspace-name>'
herdr machine list --json
ssh -o BatchMode=yes cws.devstack-<id> 'herdr workspace list'
# no workspace:
ssh -o BatchMode=yes cws.devstack-<id> 'herdr workspace create --cwd /workspace --label devstack-<id> --no-focus'
# workspace exists: pane list, then pane split <id> --cwd /workspace/<repo> --no-focus
```

Local `herdr pane` / `herdr workspace` talk to Local. Remote IDs come from `ssh cws.devstack-<id> herdr …`. `attached_with_herdr` is true when `machine list` has this host enabled and that host has a pane.

CWS `nohup herdr server` is not a saved-machine daemon (`detached_server_daemon` false). `machine add` may ask to restart so the server survives SSH loss. On a box you just provisioned, answer **y**. If add fails with `not ready for saved machines` and no prompt, `herdr pane run` the same `machine add` in a sibling TTY (still `HERDR_ENV=1`) and send `y`. Do not restart over the user's live remote agents unless they asked.

Wrapper (`zsh/zshrc`): leftover `--remote` still gets `--remote-keybindings server` so `herdr-nvim-nav` Alt+hjkl works. Attach itself is `machine add`. The wrapper must not `ssh -fN` MCP/Plannotator ports.

`herdr/config.toml`: `[remote] manage_ssh_config = false` so Herdr reuses the laptop ControlMaster / SSH config.

Isolated probe:

```bash
ssh -o ClearAllForwardings=yes -o ControlMaster=no -o ControlPath=none coder@cws.devstack-<id> '…'
```

## E2E checklist (bootstrap only)

Run over SSH after bootstrap exits. Do not install anything.

| Check | Expect |
|---|---|
| Dotfiles tip | `cws-dotfiles` `main` SHA you pushed |
| `herdr` | binary + `herdr status` shows `status: running` (match that phrase, not substring `running`) |
| `nvim` | 0.12+; `require('oil')` and `require('herdr-nvim-nav')` succeed |
| Nav maps | `<A-h/j/k/l>` and `<A-z>` in nvim config; herdr plugin actions `herdr-nvim-nav.{left,down,up,right}` |
| `hunk` | CLI present; skill `hunk-review` in `~/.agents/skills` and `~/.cursor/skills` |
| `plannotator` | CLI present; extras `plannotator-compound`, `plannotator-setup-goal`, `plannotator-visual-explainer` |
| Core plannotator skills | `plannotator-review` / `annotate` / `last` land in **Claude** (`~/.claude/skills`). Cursor extras only unless copied. Plan-intercept hook is Claude `ExitPlanMode`, not Cursor. |
| Share | `PLANNOTATOR_SHARE=disabled`, `~/.plannotator/config.json` `{"share":"disabled"}`, `PLANNOTATOR_JINA=0` |
| Remote UI | CWS zsh: `PLANNOTATOR_REMOTE=1` `PLANNOTATOR_PORT=19432` on the box. Not a laptop LocalForward. Agent terminal stays off unless `PLANNOTATOR_AGENT_TERMINAL_REMOTE=1` (do not enable). |
| Matt Pocock | `setup-matt-pocock-skills`, `tdd`, `grill-me`, … in `~/.agents/skills` (git clone; not `npx skills`) |
| `commit` | `~/.cursor/skills/commit` (Jira-prefixed conventional commit) |
| go-style-guide | `/workspace/go-style-guide` and `go-*` skills unless `DEVSTACK_SETUP_GO_STYLE_GUIDE=0` |
| Tunnels | `ssh -G cws.devstack-<id>` has no LocalForward for 8787, 3118, or 19432 |
| Herdr plugins | `dleen.herdr-agents` @ `74f8550a1008156f811b0bc8663ac251d9f3fcd6`; `annotate` (`plannotator/herdr-annotate`) @ `fb93a1318f960792452cef6cde72a2c4f4591241` (or documented skip/warn). `official.browser` and `official.plannotator` absent. |
| `herdr-pane-minimap` | plugin linked; binary `herdr-pane-minimap` exists in the plugin dir **or** bootstrap warn `Could not build herdr-pane-minimap` / `Could not link` |
| `kitty_graphics` | `true` in `~/.config/herdr/config.toml` |
| Agent keys | `previous_agent`/`next_agent`/`focus_agent` as above; `dleen.herdr-agents.open` on `prefix+a` |
| Annotate keys | `annotate.open` `prefix+f`; `annotate.last` `prefix+ctrl+y`; `annotate.capture` `prefix+u`; `copy_on_select = false` in herdr config (and the CWS-copied config) |
| Annotate deps | `bun` on PATH (plugin build fetches plannotator-tui) **or** bootstrap warn |

## OAuth callbacks

Atlassian/Slack OAuth for laptop Cursor stays on the laptop (`localhost:8787` / `3118`). Do not tunnel those ports through `cws.*` SSH.

## Cleanup

Keep one good Running workspace. `delete_workspace` only when the user asks. Do not delete the workspace you just verified.

## Files

Canonical files live in `~/.dotfiles/.agents/skills`. Home `~/.agents/skills/<name>` (and Claude/Cursor) are symlinks to that tree.
