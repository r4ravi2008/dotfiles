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

Host block example: `Host cws.devstack-<id>`, `ProxyCommand` via `bastion.cws.cwsppdusw2.iks2.a.intuit.com`, user `coder`, key `~/.ssh/cws_id_rsa`. Laptop `Include` of `ssh/cws-mcp-forwards.conf` merges IPv4+IPv6 `LocalForward` for 8787 / 3118 / 19432 onto every `cws.*`.

## Attach

```bash
herdr --remote cws.devstack-<id>
```

Wrapper (`zsh/zshrc`):

- `_herdr_ensure_cws_forwards`: if `127.0.0.1:8787` is not owned by `ssh`, run `ssh -fN -n -o ControlMaster=no -o ControlPath=none cws.devstack-<id>`.
- Injects `--remote-keybindings server` so `herdr-nvim-nav` Alt+hjkl works.

`herdr/config.toml`: `[remote] manage_ssh_config = false` so Herdr reuses the laptop ControlMaster / SSH config.

Isolated probe (does not steal laptop 8787):

```bash
ssh -o ClearAllForwardings=yes -o ControlMaster=no -o ControlPath=none coder@cws.devstack-<id> '…'
```

If you must test callbacks without fighting Cursor on `::1:8787`, use unique laptop ports in a **throwaway** ssh config (`28787→8787`, `23118→3118`, `29432→19432`) bound on both `127.0.0.1` and `[::1]`. Do not kill Cursor.

Chrome resolves `localhost` to `::1` first. IPv4-only forwards leave Atlassian/Slack to a local Cursor helper (`ERR_CONNECTION_RESET`). Forwards in `cws-mcp-forwards.conf` bind both.

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
| Remote UI | CWS zsh: `PLANNOTATOR_REMOTE=1` `PLANNOTATOR_PORT=19432`. This is the SSH tunnel, not a public share. Agent terminal stays off unless `PLANNOTATOR_AGENT_TERMINAL_REMOTE=1` (do not enable). |
| Matt Pocock | `setup-matt-pocock-skills`, `tdd`, `grill-me`, … in `~/.agents/skills` (git clone; not `npx skills`) |
| `commit` | `~/.cursor/skills/commit` (Jira-prefixed conventional commit) |
| go-style-guide | `/workspace/go-style-guide` and `go-*` skills unless `DEVSTACK_SETUP_GO_STYLE_GUIDE=0` |
| Tunnels | `ssh -G cws.devstack-<id>` lists IPv4 and `::1` LocalForwards for 8787, 3118, 19432 |
| Herdr plugins | `dleen.herdr-agents` @ `74f8550a1008156f811b0bc8663ac251d9f3fcd6`; `official.browser` @ `be6888b71cf4eb5939ee79a746bd1a1c22ade046` (last commit with `herdr-plugin.toml`; HEAD is deprecated); `official.plannotator` @ `e10b969ea1655dbfce25d1464eef6f27c790bb79` (or documented skip/warn) |
| `herdr-pane-minimap` | plugin linked; binary `herdr-pane-minimap` exists in the plugin dir **or** bootstrap warn `Could not build herdr-pane-minimap` / `Could not link` |
| `kitty_graphics` | `true` in `~/.config/herdr/config.toml` |
| Agent keys | `previous_agent`/`next_agent`/`focus_agent` as above; `dleen.herdr-agents.open` on `prefix+a` |
| Presenter deps | `bun` and Chrome/Chromium **or** bootstrap warn naming the missing one |
| Configure | After `herdr server` is `status: running`, `official.plannotator` configure succeeded **or** documented skip (missing bun/chromium/plugin) |
| Share after configure | `PLANNOTATOR_SHARE=disabled` and `jq -e '.share == "disabled"' ~/.plannotator/config.json` |

## OAuth callbacks

Start Atlassian/Slack auth inside the workspace. The browser hits `localhost:8787` / `3118` because `cws-mcp-forwards.conf` is on every `cws.*` SSH. If Cursor owns `::1:8787`, use `http://127.0.0.1:8787/...`.

## Cleanup

Keep one good Running workspace. `delete_workspace` only when the user asks. Do not delete the workspace you just verified.

## Files

Canonical files live in `~/.dotfiles/.agents/skills`. Home `~/.agents/skills/<name>` (and Claude/Cursor) are symlinks to that tree.
