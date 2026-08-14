# CWS create + attach — laptop reference

Companion to `creating-cws-from-devstack-fork`. Laptop only.

## Remotes

| Repo | Remote | Push to | Never |
|---|---|---|---|
| `~/.dotfiles` | `cws` → `github.intuit.com:rkommineni/cws-dotfiles.git` | `git push cws HEAD:main` | `origin` (`github.com:r4ravi2008/dotfiles`) |
| DevStack worktree | `fork` → `github.intuit.com:rkommineni/devstack.git` | `fork/master` | `origin` (`cloud-workspaces/devstack`) |

CWS create clones `CWS_USER_DOTFILES_REPO=https://github.intuit.com/rkommineni/cws-dotfiles.git` **once**. Existing workspaces do not pull new commits.

Confirm tips before Create:

```bash
git -C ~/.dotfiles ls-remote cws refs/heads/main
git -C <devstack-worktree> ls-remote fork refs/heads/master
```

## IDDA Computer Use

App: `com.wails.IntuitDeveloperDesktopApp`. Start each turn with `get_app_state`. Prefer `element_index` + `click_method: accessibility` on the URL combo.

### Create dialog

1. Cloud Workspaces list → **Create**.
2. Close any Shared endpoints side panel first (it steals clicks).
3. Source: Repository URL (on).
4. Expand **Advanced options** first if needed: **medium** (8 core / 32 GB), **us-west**.
5. Click the Main repository combo (accessibility) so it is `expanded`.
6. `set_value` on the combo: `https://github.intuit.com/rkommineni/devstack`.
7. Create enables only after a full `org/repo` URL. Click **Create**.
8. Button reads **Loading** while submitting — do not click again.
9. List shows `devstack-<8 hex>` **Pending**, then **Running**.

`set_value` without expanding the combo often leaves `https://github.intuit.com/` and Create stays disabled. Clicking Advanced while the combo is in a bad state can dismiss the dialog and land on an existing workspace.

### Details vs Open in

- Open Config / logs: click the **workspace name** (left of the row).
- **Open in** opens an editor and is not the create/verify path.
- Delete: Config tab → **Delete workspace**.
- Shared endpoints: Plannotator `19432` should stay **Private** (Intuit network share, not `share.plannotator.ai`).

## Wait

1. `~/.ssh/prd.cws.devstack-<id>.conf` appears (IDDA writes it).
2. `ssh -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ClearAllForwardings=yes coder@cws.devstack-<id> 'hostname'` works.
3. `pgrep -f 'bash /home/coder/.dotfiles/bootstrap.sh'` is empty.
4. `git -C ~/.dotfiles log -1 --oneline` on the box matches the `cws/main` tip you pushed.

Host block example: `Host cws.devstack-<id>`, `ProxyCommand` via `bastion.cws.cwsppdusw2.iks2.a.intuit.com`, user `coder`, key `~/.ssh/cws_id_rsa`. Laptop `Include` of `ssh/cws-mcp-forwards.conf` merges IPv4+IPv6 `LocalForward` for 8787 / 3118 / 19432 onto every `cws.*`.

## Attach

```bash
herdr --remote cws.devstack-<id>
```

Wrapper (`zsh/zshrc`):

- `_herdr_ensure_cws_forwards`: if `127.0.0.1:8787` is not owned by `ssh`, run `ssh -fN -n -o ControlMaster=no -o ControlPath=none cws.devstack-<id>`.
- Injects `--remote-keybindings server` so `herdr-nvim-nav` Alt+hjkl works.

`herdr/config.toml`: `[remote] manage_ssh_config = false` so Herdr reuses the laptop ControlMaster / IDDA config.

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
| Laptop-only skill | `creating-cws-from-devstack-fork` is **absent** from `~/.agents/skills` and `~/.cursor/skills` on CWS |

## OAuth callbacks

Start Atlassian/Slack auth **inside the workspace**. Laptop browser hits `localhost:8787` / `3118`. If Cursor owns `::1:8787`, use `http://127.0.0.1:8787/...`.

## Cleanup

Keep one good Running workspace. Delete extras from IDDA Config → Delete. Do not delete the workspace you just verified unless the user asks.

## This skill on CWS

Bootstrap copies `ai-agents/laptop-skills/` only when **not** a Cloud Workspace, and removes these names from agent skill dirs on CWS. The files may exist under `~/.dotfiles/ai-agents/laptop-skills` on the box; do not invoke them there.
