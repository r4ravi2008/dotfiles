---
description: Generate semantic commit message based on staged changes
targets: ["*"]
---

# Generate Commit Message

Analyze the staged changes and create a well-crafted commit message.

## Staged Changes
!`git diff --cached --stat`
!`git diff --cached`

## Recent Commit Style
!`git log --oneline -10`

## Commit Message Guidelines

### Format
```
<type>(<scope>): <subject>

<body>

<footer>
```

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
1. Subject line: max 50 characters, imperative mood ("add" not "added")
2. Body: wrap at 72 characters, explain what and why (not how)
3. Separate subject from body with blank line
4. Reference issues at the bottom

### Examples
```
feat(auth): add OAuth2 login support

Implement Google and GitHub OAuth providers to allow
users to sign in without creating a password.

- Add OAuth middleware
- Create provider configuration
- Update user model for external auth

Closes #123
```

```
fix(api): handle null response in user lookup

The API was crashing when looking up users that don't exist.
Now returns a proper 404 response.

Fixes #456
```

$ARGUMENTS

## Instructions
1. Analyze the staged changes thoroughly
2. Determine the appropriate commit type and scope
3. Write a clear, concise subject line
4. If changes are significant, include a body explaining the context
5. Execute: `git commit -m "message"`
