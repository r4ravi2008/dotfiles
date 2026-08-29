---
name: force-pushing-ghes-default
description: >-
  Use when GitHub Enterprise Server rejects a force-push with GH003,
  "Sorry, force-pushing to master/main is not allowed", or pre-receive hook
  declined on a github.intuit.com personal fork default branch; when rebasing
  or rewriting fork/master, cws-dotfiles, or intuit remotes onto origin; when
  tempted to merge, open a PR, rename master to main, delete and recreate the
  default branch, or drive Chrome/Computer Use to change Settings. Do not use
  to push origin or other upstream protected repos.
allowed-tools:
  - Bash
---

# Force-pushing a GHES default branch

GH003 applies to **whatever branch is the repo default right now**, not classic branch protection (`gh api .../protection` 404 is normal). Merge commits, PRs, renaming `master`→`main`, and deleting the default branch are not the fix.

**Never push `origin` / upstream.** Personal remotes only (`fork`, `cws`, `intuit`).

## Recipe

`OWNER/REPO` = the personal repo (example: `rkommineni/devstack`). `REMOTE` = that clone's personal remote. `GH_HOST=github.intuit.com`. Local `HEAD` must already be the linear tip you want on `$DEFAULT` (rebase unique commits onto origin; do not merge).

```bash
DEFAULT=$(GH_HOST=github.intuit.com gh api "repos/$OWNER/$REPO" --jq .default_branch)
git push "$REMOTE" "HEAD:tmp/default-swap"
GH_HOST=github.intuit.com gh api -X PATCH "repos/$OWNER/$REPO" -f default_branch=tmp/default-swap
git push --force-with-lease "$REMOTE" "HEAD:$DEFAULT"
GH_HOST=github.intuit.com gh api -X PATCH "repos/$OWNER/$REPO" -f default_branch="$DEFAULT"
git push "$REMOTE" :tmp/default-swap
```

If any step after the first PATCH fails, PATCH `default_branch` back to `$DEFAULT` before stopping.

Verify: default is still `$DEFAULT`; `git log --merges --oneline origin/master..$REMOTE/$DEFAULT` is empty (or `origin/main` for repos that use `main`); nothing pushed to `origin`.

## When not to use

- Fast-forward already works (`git push` with no force)
- Rewriting a non-default feature branch (plain `--force-with-lease`)
- Upstream `cloud-workspaces/*` or any repo you must not force-push

## Rationalizations

| Excuse | Reality |
|--------|---------|
| "Merge is the only non-force push" | Merge pollutes history. Swap default, then force-push. |
| "Protection API 404, so rename/delete master" | Org pre-receive, not classic protection. Keep the same default name. |
| "Delete remote master and re-push isn't a force-push" | Default branch cannot be deleted; CWS clones `master`. |
| "New default `main` is linear enough" | Leave default on `master`/`main` as it already is. |
| "Open a PR / rebase-merge" | Does not remove an existing merge commit. |
| "Chrome/Computer Use like last time" | `gh api` PATCH is the path. Chrome only if API fails. |

## Red flags — STOP

- `git merge` to "update the fork"
- `git push origin`
- Default left on `tmp/*` or a new `main`
- Branch rename as the rewrite
- Driving Settings in a browser while `gh` works

**All of these mean: restore the original default branch name, then follow the recipe.**
