---
description: Comprehensive code review for quality, security, and maintainability
targets: ["*"]
---

# Code Review

Perform a thorough code review focusing on the following areas:

## Current Changes
!`git diff --cached --stat 2>/dev/null || git diff --stat 2>/dev/null || echo "No git changes detected"`

## Review Checklist

### Functionality
- [ ] Code does what it's supposed to do
- [ ] Edge cases are handled appropriately
- [ ] Error handling is comprehensive and informative
- [ ] No obvious bugs or logic errors
- [ ] Input validation is present where needed

### Code Quality
- [ ] Code is readable and well-structured
- [ ] Functions/methods are small and focused (single responsibility)
- [ ] Variable and function names are descriptive
- [ ] No code duplication (DRY principle)
- [ ] Follows project conventions and style guide
- [ ] Comments explain "why" not "what" where needed

### Performance
- [ ] No obvious performance bottlenecks
- [ ] Efficient data structures and algorithms used
- [ ] No unnecessary computations or iterations
- [ ] Database queries are optimized (if applicable)
- [ ] Memory usage is reasonable

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input is properly sanitized
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities (for web code)
- [ ] Authentication/authorization is correct
- [ ] Sensitive data is handled properly

### Testing
- [ ] Unit tests cover the new code
- [ ] Edge cases are tested
- [ ] Tests are readable and maintainable
- [ ] No flaky tests introduced

### Maintainability
- [ ] Code is easy to understand for future developers
- [ ] Dependencies are appropriate and up-to-date
- [ ] No technical debt introduced unnecessarily
- [ ] Breaking changes are documented

$ARGUMENTS

Please provide:
1. A summary of the changes
2. Issues found (categorized by severity: critical, major, minor, suggestion)
3. Specific line-by-line feedback where relevant
4. Recommendations for improvement
