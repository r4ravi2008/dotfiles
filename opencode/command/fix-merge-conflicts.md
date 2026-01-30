---
description: Analyze and resolve git merge conflicts
agent: build
---

# Fix Merge Conflicts

Analyze and resolve git merge conflicts in the current branch.

## Conflict Status
!`git status`
!`git diff --name-only --diff-filter=U 2>/dev/null || echo "No conflicts detected"`

## Instructions

### Step 1: Identify conflicted files
List all files with merge conflicts using `git status` or `git diff --name-only --diff-filter=U`.

### Step 2: For each conflicted file
1. Read the entire file to understand the context
2. Identify the conflict markers:
   ```
   <<<<<<< HEAD
   (your changes)
   =======
   (their changes)
   >>>>>>> branch-name
   ```
3. Understand both versions:
   - **HEAD/ours**: Your current branch changes
   - **theirs**: Changes from the branch being merged

### Step 3: Resolve conflicts intelligently
For each conflict, determine the best resolution:
- **Keep ours**: If our changes are correct
- **Keep theirs**: If their changes are correct
- **Merge both**: If both changes should be combined
- **Rewrite**: If neither version is ideal

### Step 4: Resolution strategies by file type
- **Code files**: Ensure logic is correct, no duplicate imports, proper formatting
- **Package files** (package.json, Cargo.toml): Usually merge both dependency changes
- **Config files**: Carefully consider which settings should win
- **Generated files**: Often best to regenerate

### Step 5: After resolving
1. Remove ALL conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
2. Ensure the file is syntactically valid
3. Stage the resolved file: `git add <file>`
4. Repeat for all conflicted files

### Step 6: Complete the merge
```bash
git add .
git commit -m "resolve: merge conflicts from <branch>"
```

$ARGUMENTS

## Output
Provide:
1. List of conflicted files found
2. Summary of how each conflict was resolved
3. Any potential issues to watch for after merge
