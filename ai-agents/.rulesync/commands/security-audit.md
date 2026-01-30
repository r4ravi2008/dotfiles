---
description: Comprehensive security audit for vulnerabilities
targets: ["*"]
agent: plan
---

# Security Audit

Perform a comprehensive security review of the codebase.

## Current Files
!`git ls-files | head -50`

## Check for Secrets
!`git diff --cached 2>/dev/null || git diff HEAD~1 2>/dev/null | grep -iE "(password|secret|api_key|apikey|token|credential|private_key)" | head -20 || echo "No obvious secrets in recent changes"`

## Security Checklist

### 1. Secrets & Credentials
- [ ] No hardcoded passwords, API keys, or tokens
- [ ] No private keys or certificates in code
- [ ] Environment variables used for sensitive config
- [ ] `.env` files are in `.gitignore`
- [ ] No secrets in commit history

### 2. Input Validation
- [ ] All user input is validated
- [ ] Input length limits are enforced
- [ ] Special characters are escaped/sanitized
- [ ] File uploads are restricted by type and size

### 3. Authentication & Authorization
- [ ] Authentication is properly implemented
- [ ] Session management is secure
- [ ] Password hashing uses strong algorithms (bcrypt, argon2)
- [ ] Authorization checks on all protected routes
- [ ] No privilege escalation vulnerabilities

### 4. Injection Vulnerabilities
- [ ] SQL queries use parameterized statements
- [ ] No command injection possibilities
- [ ] No LDAP injection vulnerabilities
- [ ] Template injection is prevented

### 5. Cross-Site Scripting (XSS)
- [ ] Output is properly encoded/escaped
- [ ] Content Security Policy headers set
- [ ] User input not directly rendered as HTML

### 6. Cross-Site Request Forgery (CSRF)
- [ ] CSRF tokens on state-changing operations
- [ ] SameSite cookie attribute set

### 7. Dependencies
- [ ] Dependencies are up-to-date
- [ ] No known vulnerable packages
- [ ] Lock files are committed

### 8. Data Protection
- [ ] Sensitive data encrypted at rest
- [ ] HTTPS enforced for data in transit
- [ ] PII handled according to regulations
- [ ] Proper data retention policies

### 9. Error Handling
- [ ] No sensitive info in error messages
- [ ] Stack traces not exposed to users
- [ ] Proper logging without sensitive data

### 10. Infrastructure
- [ ] Security headers configured
- [ ] Rate limiting implemented
- [ ] CORS properly configured

$ARGUMENTS

## Output
Provide:
1. **Critical Issues**: Must fix immediately
2. **High Priority**: Should fix before deployment
3. **Medium Priority**: Fix in next sprint
4. **Low Priority**: Improvements to consider
5. **Recommendations**: Best practices to adopt
