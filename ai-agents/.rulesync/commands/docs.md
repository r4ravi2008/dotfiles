---
description: Generate documentation for code
targets: ["*"]
agent: build
---

# Generate Documentation

Create comprehensive documentation for the specified code.

## Documentation Types

### 1. Function/Method Documentation
```
/**
 * Brief description of what the function does.
 *
 * @param paramName - Description of the parameter
 * @returns Description of return value
 * @throws Description of errors that may be thrown
 * @example
 * ```
 * const result = functionName(arg);
 * ```
 */
```

### 2. Class/Module Documentation
- Purpose and responsibility
- Usage examples
- Public API reference
- Dependencies and relationships

### 3. README Documentation
```markdown
# Project Name

Brief description.

## Installation
## Usage
## API Reference
## Configuration
## Contributing
## License
```

### 4. Inline Comments
- Explain "why" not "what"
- Document complex algorithms
- Note edge cases and gotchas
- Reference related issues/PRs

## Documentation Standards

### JSDoc/TSDoc (JavaScript/TypeScript)
- `@param` - Document parameters
- `@returns` - Document return value
- `@throws` - Document exceptions
- `@example` - Provide usage examples
- `@deprecated` - Mark deprecated items
- `@see` - Reference related items

### Docstrings (Python)
```python
def function_name(param: Type) -> ReturnType:
    """Brief description.
    
    Longer description if needed.
    
    Args:
        param: Description of parameter.
        
    Returns:
        Description of return value.
        
    Raises:
        ErrorType: When this error occurs.
        
    Example:
        >>> function_name(value)
        expected_result
    """
```

### Rustdoc (Rust)
```rust
/// Brief description.
///
/// # Arguments
/// * `param` - Description
///
/// # Returns
/// Description of return value
///
/// # Examples
/// ```
/// let result = function_name(arg);
/// ```
```

$ARGUMENTS

## Instructions
1. Analyze the code structure
2. Identify public APIs that need documentation
3. Generate appropriate documentation format
4. Include usage examples where helpful
5. Document edge cases and important behaviors

## Output
Provide complete documentation in the appropriate format for the codebase.
