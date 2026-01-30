---
description: Run tests and systematically fix failures
targets: ["*"]
agent: build
---

# Run Tests and Fix Failures

Execute the test suite and systematically fix any failures.

## Detect Test Framework
!`ls -la package.json Cargo.toml pyproject.toml setup.py Makefile go.mod 2>/dev/null | head -5`

## Instructions

### Step 1: Identify the test command
Based on the project type, determine the appropriate test command:
- **Node.js**: `npm test`, `yarn test`, `pnpm test`, or `bun test`
- **Python**: `pytest`, `python -m pytest`, or `python -m unittest`
- **Rust**: `cargo test`
- **Go**: `go test ./...`
- **Ruby**: `bundle exec rspec` or `rake test`
- **Other**: Check `Makefile` or project docs

### Step 2: Run the full test suite
Execute the test command and capture the output.

### Step 3: Analyze failures
For each failure:
1. Identify the test file and test name
2. Understand what the test is checking
3. Determine if it's a:
   - **Code bug**: The implementation is wrong
   - **Test bug**: The test expectation is wrong
   - **Flaky test**: Race condition or timing issue
   - **Environment issue**: Missing setup or dependencies

### Step 4: Fix systematically
1. Start with the simplest failures first
2. Fix one issue at a time
3. Re-run the specific test after each fix
4. Once individual tests pass, run the full suite again

### Step 5: Verify
- All tests should pass
- No new failures introduced
- Coverage hasn't decreased significantly

$ARGUMENTS

## Output
After fixing, provide:
1. Summary of what was broken
2. What fixes were applied
3. Final test results
