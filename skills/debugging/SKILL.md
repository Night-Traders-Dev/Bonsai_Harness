---
name: debugging
description: Systematically diagnose and fix bugs, crashes, and unexpected behavior. Use when the user reports an error, a stack trace, a failing test, or code that does not behave as expected.
---

# Debugging

Follow a hypothesis-driven process. Do not guess-and-patch.

1. **Reproduce** the problem. Identify the exact command, input, or steps that trigger it. If you cannot reproduce it, gather more detail before changing code.
2. **Read the error** carefully. Note the error type, message, and the top of the stack trace pointing at the failing line.
3. **Locate** the failing code with `read_file` and `grep`. Trace the data flow backward from the failure point to where the bad value originates.
4. **Form a hypothesis** about the root cause. State it explicitly (e.g. "the list is empty because the filter removes all items when X").
5. **Verify** the hypothesis with a minimal check — add a print/log, inspect a value, or write a tiny reproduction — before editing.
6. **Fix the root cause**, not the symptom. Avoid catching and hiding errors just to make them disappear.
7. **Confirm** the fix by re-running the reproduction and the test suite.

## Guidelines

- Change one thing at a time so you know what fixed it.
- Prefer the smallest change that addresses the root cause.
- If the bug reveals a missing test case, add a test that would have caught it.
- When stuck, re-read the assumptions — the bug is often in something you believed was correct.
