---
name: commit
description: >-
  Use when committing staged changes — analyzes the diff, determines
  conventional commit type and scope, and generates a semantic commit message
  prefixed with the Jira ID from the current branch name.
allowed-tools:
  - Bash
---

# Generate Commit Message

## Tool justification (security review)

- **Bash**: Required to run `git diff --cached`, `git log`, `git branch`, and `git commit` to analyze staged changes and create the commit.

Analyze the staged changes and create a well-crafted commit message prefixed with the Jira ID.

## Step 1: Resolve Jira ID

Run `git branch --show-current` to get the current branch name.

Extract the Jira ID using this pattern: `[A-Z]+-[0-9]+` (e.g. `CGCAKE-5160`, `TAX-123`).

```
branch: feature/CGCAKE-5160-add-tax-engine  →  Jira ID: CGCAKE-5160
branch: CGCAKE-5160-some-work               →  Jira ID: CGCAKE-5160
branch: main                                →  no Jira ID found
```

**If no Jira ID is found in the branch name**, ask the user:
> "No Jira ID found in branch name. What Jira ticket should I prefix this commit with? (e.g. CGCAKE-1234, or 'none' to skip)"

If the user provides an ID, use it. If they say "none" or skip, omit the prefix.

## Step 2: Analyze Staged Changes

Run:
- `git diff --cached --stat`
- `git diff --cached`
- `git log --oneline -10` (for recent commit style)

## Step 3: Compose Commit Message

### Format
```
<jira-id> <type>(<scope>): <subject>

<body>

<footer>
```

**With Jira ID:** `CGCAKE-5160 feat(tax-engine): add withholding calculation`
**Without Jira ID:** `feat(tax-engine): add withholding calculation`

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, missing semicolons, etc (no code change)
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `test`: Adding or correcting tests
- `chore`: Maintenance tasks, dependency updates
- `ci`: CI/CD changes
- `build`: Build system or external dependency changes

### Rules
1. Subject line: max 72 characters total (including Jira prefix), imperative mood ("add" not "added")
2. Body: wrap at 72 characters, explain what and why (not how)
3. Separate subject from body with blank line
4. Reference issues at the bottom

## Step 4: Execute

`git commit -m "<message>"`
