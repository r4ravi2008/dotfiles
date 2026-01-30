---
description: Debug issues systematically
agent: build
---

# Debug Issue

Systematically debug and fix the reported issue.

## Debugging Process

### Step 1: Understand the Problem
- What is the expected behavior?
- What is the actual behavior?
- When does it occur? (always, sometimes, specific conditions)
- Where does it occur? (specific file, function, route)

### Step 2: Reproduce the Issue
- Create minimal reproduction steps
- Identify the exact trigger
- Note any error messages or stack traces

### Step 3: Gather Information
!`git log --oneline -10`
!`git diff HEAD~3 --stat 2>/dev/null || echo ""`

Questions to answer:
- Did this work before? When did it break?
- What changed recently?
- Are there related issues or error logs?

### Step 4: Form Hypotheses
Based on the information, list possible causes:
1. Recent code changes
2. Configuration issues
3. Environmental differences
4. Race conditions or timing
5. Data/state corruption
6. External dependency changes

### Step 5: Test Hypotheses
For each hypothesis:
1. Design a quick test
2. Execute the test
3. Interpret results
4. Eliminate or confirm

### Step 6: Identify Root Cause
- Don't just fix symptoms
- Find the underlying cause
- Understand why it happened

### Step 7: Implement Fix
- Make the minimal change needed
- Add tests to prevent regression
- Document the fix if non-obvious

### Step 8: Verify Fix
- Confirm the original issue is resolved
- Check for side effects
- Run related tests
- Test edge cases

## Common Debug Techniques

### Add Logging
```javascript
console.log('DEBUG:', { variable, state, timestamp: Date.now() });
```

### Use Debugger
- Set breakpoints at suspicious locations
- Step through execution
- Inspect variables

### Binary Search
- Find the commit that introduced the bug
- `git bisect` can help automate this

### Rubber Duck Debugging
- Explain the code line by line
- Often reveals the issue

$ARGUMENTS

## Output
Provide:
1. Root cause analysis
2. Steps taken to debug
3. The fix implemented
4. How to prevent similar issues
