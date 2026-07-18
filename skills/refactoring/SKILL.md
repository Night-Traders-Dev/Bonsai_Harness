---
name: refactoring
description: Improve code structure without changing behavior. Use when the user asks to clean up, simplify, restructure, or reduce duplication in code.
---

# Refactoring

Refactoring changes structure while preserving behavior. Safety comes first.

1. **Establish a safety net.** Ensure tests exist and pass before you start. If none exist, add characterization tests that capture current behavior.
2. **Make small, reversible steps.** Refactor in tiny increments, running tests after each one.
3. **Change one concern at a time.** Do not mix refactoring with new features or bug fixes in the same edit.
4. **Preserve the public interface** unless the task is explicitly to change it.

## Common refactorings

- Extract a well-named function from a long block.
- Remove duplication by unifying repeated logic.
- Replace magic numbers/strings with named constants.
- Simplify nested conditionals with early returns or guard clauses.
- Rename unclear identifiers to reveal intent.
- Split large functions/modules by responsibility.

## Rules

- Behavior must be identical before and after; tests are the proof.
- Keep diffs reviewable — smaller is better.
- Do not "improve" code the task did not ask you to touch.
