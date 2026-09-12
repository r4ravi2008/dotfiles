---
name: git-commit-flow
description: >-
  Use when committing, grouping unstaged work, or splitting a dirty tree into
  focused commits. Inventory changes, drop generated artifacts, map each group
  to its owning work item or repository exception, then commit. Do not use for GH003
  force-push (force-pushing-ghes-default).
---

# Git commit flow

Five steps. Each step's output is the next step's input. Do not skip a step.
Do not start Nest, a workflow engine, or a second commit skill.

## 1. Inventory

Run `git status`, `git diff`, `git diff --cached`, and `git log --oneline -10`.

Done when every path in the working tree and index is listed, including
untracked files.

## 2. Exclude

Drop generated and temporary artifacts (lockfiles you did not mean to pin,
`node_modules`, build output, secrets, MCP OAuth churn unless that is the work).

Done when the remaining paths are what should land in git.

## 3. Own

Map each remaining path to the work item that owns its observable outcome.
Compare the diff to the issue's scope, not the filename. Branch name
`[A-Z]+-[0-9]+` is a Jira id when present. GitHub issues use `#n`.

Repository-local `AGENTS.md` instructions may explicitly allow a scoped
exception for direct user-requested maintenance without a work item. Apply that
exception only in the repository that defines it. Otherwise, if a change has no
owner, stop and report it. Do not invent a ticket or commit unowned work.

Done when every remaining path has an owner or explicit repository exception,
or you have stopped.

## 4. Group

Split the owned paths into the smallest set of commits that a reviewer can
revert independently. One concern per commit.

Done when each group has a type (`feat`, `fix`, `docs`, `test`, `refactor`,
`chore`, `ci`, `build`), an owner or repository exception, and a file list.

## 5. Commit

For each group, in dependency order: `git add` only those paths, then
`git commit` with:

```text
[type #issue-id] imperative summary
```

If the owner is a Jira id from the branch, use `JIRA-ID type(scope): summary`
instead, matching this repo's recent log. When a repository exception applies,
use the commit format specified by that repository's `AGENTS.md`. Subject max
72 characters. Body wraps at 72 and says why, not how. No Co-Authored-By trailer
unless the user asked.

Done when `git status` has no leftover paths from step 2, or the leftovers are
the unowned work you already reported.

Push only when the user asked.
