---
name: git-commit
description: Write clear conventional git commit messages and commit safely. Use when the user asks to commit changes, write a commit message, or prepare a pull request.
---

# Git Commit

Before committing, always inspect the working tree so you commit only what is intended.

1. Run `git status` and `git diff` to review staged and unstaged changes.
2. Stage only the intended files. Never blindly `git add -A` if unrelated changes are present.
3. Never commit secrets, credentials, large binaries, or build artifacts.
4. Write the commit message, then commit.

## Message format (Conventional Commits)

```
<type>(<optional scope>): <short summary in imperative mood>

<optional body: what changed and why, wrapped at ~72 chars>
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `build`.

## Rules

- Summary line: imperative mood ("add", not "added"), under ~50 chars, no trailing period.
- Explain **why** in the body when the change is not obvious; the diff already shows **what**.
- One logical change per commit. Split unrelated changes into separate commits.
- Match the existing style of the repository's history (`git log --oneline -10`).
- Only commit, amend, or push when the user explicitly asks.
