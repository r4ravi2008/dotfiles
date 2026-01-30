---
description: Refactor code following best practices
agent: build
---

# Refactor Code

Refactor the specified code to improve quality, readability, and maintainability.

## Refactoring Principles

### SOLID Principles
- **S**ingle Responsibility: Each module/class should have one reason to change
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable for base types
- **I**nterface Segregation: Many specific interfaces over one general interface
- **D**ependency Inversion: Depend on abstractions, not concretions

### Clean Code Guidelines
1. **Meaningful names**: Variables and functions should reveal intent
2. **Small functions**: Functions should do one thing well
3. **Minimal arguments**: Prefer fewer function parameters
4. **No side effects**: Functions should be predictable
5. **DRY**: Don't Repeat Yourself
6. **KISS**: Keep It Simple, Stupid
7. **YAGNI**: You Aren't Gonna Need It

## Refactoring Techniques

### Extract Method
Move code into a well-named function when:
- Code is duplicated
- A block of code needs explanation
- A function is too long

### Rename
Improve clarity by renaming:
- Variables that don't describe their content
- Functions that don't describe their action
- Classes that don't describe their purpose

### Simplify Conditionals
- Extract complex conditions into well-named booleans
- Use guard clauses for early returns
- Replace nested conditionals with polymorphism when appropriate

### Remove Code Smells
- Long methods
- Large classes
- Long parameter lists
- Duplicate code
- Dead code
- Comments explaining bad code (fix the code instead)

$ARGUMENTS

## Instructions
1. Analyze the code structure and identify issues
2. Plan the refactoring steps (smallest changes first)
3. Make changes incrementally
4. Ensure tests still pass after each change
5. Keep the same external behavior (no functional changes)

## Output
Provide:
1. Issues identified in the original code
2. Refactoring steps applied
3. Before/after comparison of key improvements
4. Any remaining technical debt to address later
