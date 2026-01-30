---
description: Create a well-structured pull request
agent: build
---

# Create Pull Request

Create a well-structured pull request based on the current branch changes.

## Current State
!`git branch --show-current`
!`git log --oneline -5`
!`git diff main...HEAD --stat 2>/dev/null || git diff master...HEAD --stat 2>/dev/null || git diff --stat HEAD~5`

## Instructions

1. **Analyze all commits** on this branch since it diverged from main/master
2. **Summarize the changes** comprehensively - look at ALL commits, not just the latest
3. **Create the PR** using the `gh` CLI with the following structure:

### PR Title Format
Use conventional commit style:
- `feat: description` for new features
- `fix: description` for bug fixes
- `docs: description` for documentation
- `refactor: description` for refactoring
- `test: description` for tests
- `chore: description` for maintenance

### PR Body Structure
```markdown
## Summary
Brief description of what this PR does and why.

## Changes
- Bullet point list of key changes
- Include file names where helpful

## Testing
- How was this tested?
- What should reviewers verify?

## Related Issues
Closes #issue_number (if applicable)
```

$ARGUMENTS

## Steps to Execute
1. First, check if we need to push: `git status`
2. Push if needed: `git push -u origin $(git branch --show-current)`
3. Create PR: `gh pr create --title "..." --body "..."`
4. Return the PR URL when done
