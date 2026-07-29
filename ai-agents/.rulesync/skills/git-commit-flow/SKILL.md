---
name: git-commit-flow
description: Analyze repository changes, exclude generated artifacts, map each logical change to its owning issue, and create focused issue-linked commits. Use when preparing or organizing commits in a repository.
---

# Git Commit Flow

Analyze all files in the current repository, staged and unstaged. Identify generated or temporary artifacts that should not be committed.

Inspect the repository's issue tracker and map every logical change to the issue that owns its observable outcome. Do not infer an issue only from a filename; compare the diff with the issue scope and completion criteria. If no issue owns a change, stop and report the missing work item instead of creating an untraceable commit.

Group related changes into separate logical commits. Format every commit subject as:

```text
[type #issue-id] imperative summary
```

Use a lowercase Conventional Commit-style type such as `feat`, `fix`, `docs`, `test`, `refactor`, or `chore`. Use the provider's canonical issue identifier; for GitHub issues, use `#123`. Keep the summary concise and imperative.

Examples:

```text
[docs #45] define the canonical work-item workflow
[fix #53] preserve deterministic preview naming
```
