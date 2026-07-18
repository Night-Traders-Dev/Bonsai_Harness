---
name: shell-safety
description: Run shell and bash commands safely without destructive side effects. Use whenever executing terminal commands, especially anything that deletes, moves, or overwrites files or changes system state.
---

# Shell Safety

Treat every command as potentially destructive. Verify before you run.

1. **Read before write/delete.** Inspect the target with `ls`, `list_dir`, or `read_file` before modifying or removing anything.
2. **Quote paths** that may contain spaces: `rm "my file.txt"`, not `rm my file.txt`.
3. **Prefer specific over broad.** Never run `rm -rf /`, `rm -rf ~`, or wildcard deletes without confirming exactly what matches first.
4. **Avoid irreversible operations** unless explicitly requested: `rm -rf`, `git reset --hard`, `git push --force`, `dd`, overwriting files with `>`.
5. **Do not pipe untrusted input** into a shell (`curl ... | sh`).
6. **Check the working directory** before running path-relative commands.

## Guidelines

- For deletes, list what will be removed first, then delete.
- Use dedicated tools (read/write/grep/glob) instead of shell equivalents when available.
- Never expose or echo secrets, tokens, or credentials.
- If a command changes system state, briefly explain what it does before running it.
