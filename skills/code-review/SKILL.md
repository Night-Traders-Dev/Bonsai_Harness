---
name: code-review
description: Review code for bugs, security issues, and best practices. Use when the user asks for a code review, mentions reviewing changes, or asks whether code is correct or safe.
---

# Code Review

When asked to review code, work through these steps in order:

1. Read the changed or provided files fully before commenting.
2. Check for **correctness**: logic errors, off-by-one bugs, wrong operators, unhandled edge cases (empty input, nil/null, zero, negative, very large values).
3. Check for **security**: injection (SQL/shell/command), path traversal, unvalidated input, hardcoded secrets, unsafe deserialization, missing auth checks.
4. Check for **error handling**: unchecked return values, swallowed exceptions, missing cleanup of resources (files, sockets, locks).
5. Check for **performance**: unnecessary loops, N+1 queries, repeated allocations, blocking calls on hot paths.
6. Check for **clarity**: unclear names, dead code, missing intent, overly complex branches.

## Output format

Group findings by severity, most serious first:

- **Critical** — bugs or vulnerabilities that must be fixed.
- **Warning** — likely problems or risky patterns.
- **Suggestion** — style, clarity, or minor improvements.

For each finding, cite the location as `file:line`, explain the problem in one sentence, and give a concrete fix (a code snippet when helpful). If the code is solid, say so explicitly rather than inventing issues.
