---
name: test-writing
description: Write effective, maintainable automated tests. Use when the user asks to add tests, improve coverage, or verify that code works correctly.
---

# Test Writing

Write tests that are fast, deterministic, and focused on behavior.

1. Identify the **unit under test** and its observable behavior (inputs → outputs, side effects, errors).
2. Find and follow the project's existing test framework and conventions before writing new tests.
3. Cover the important cases:
   - **Happy path** — typical valid input.
   - **Edge cases** — empty, zero, one, many, maximum, boundary values.
   - **Error cases** — invalid input, failures, exceptions.
4. Keep each test focused on one behavior with a descriptive name that states what it verifies.
5. Use the Arrange–Act–Assert structure: set up inputs, run the code, assert on results.
6. Run the suite and confirm the new tests pass and the rest still pass.

## Guidelines

- Prefer many small, specific tests over one large test.
- Tests must be deterministic — no reliance on timing, network, or ordering unless explicitly testing that.
- Assert on behavior and outputs, not on internal implementation details.
- A test that never fails is worthless; make sure it can actually fail if the code breaks.
