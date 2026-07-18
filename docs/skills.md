# `lib/skills.sage` + `skills/` — Skills System

Skills teach the agent *how* to do a task well. Each skill is a Markdown file
(`SKILL.md`) with YAML frontmatter and a concise, step-by-step body. On startup
(and on `:ingest-skills`) all skills are loaded, their frontmatter is stripped,
and their bodies are injected into the system prompt. This lets you extend the
agent's know-how without changing code or retraining the model.

## The `SKILL.md` format

Skills follow the open `SKILL.md` convention: **YAML frontmatter** (a `name` and
a `description` with clear triggers) followed by atomic instructions.

```markdown
---
name: code-review
description: Review code for bugs and security issues. Use when the user asks for a code review.
---

# Code Review
1. Read the changed files fully.
2. Check correctness, security, error handling, performance, clarity.
3. Group findings by severity: Critical, Warning, Suggestion.
```

- **`name`** — a short identifier. If omitted, the loader derives it from the
  filename/folder.
- **`description`** — what the skill does **and when to use it**. This is the
  trigger guidance the model reads to decide whether the skill applies, so make
  the triggers explicit ("Use when the user asks to…").
- **Body** — concise, ordered, atomic steps. Keep it actionable.

## Directory layouts

Two layouts are supported:

```
skills/
├── code-review/
│   └── SKILL.md      # folder-based skill (recommended)
└── quick-note.md     # single-file skill
```

`_collect_md_files` picks up a `SKILL.md` inside each subdirectory **and** any
loose `*.md` file directly under `skills/`.

## How loading works

### `load_skills(dir) -> string`
The main entry point (called by `main.sage`). It:

1. Resets the module state (`skills_content`, `skills_count`, `skills_meta`).
2. Returns `""` early if `dir` doesn't exist or isn't a directory.
3. Collects skill files via `_collect_md_files`.
4. For each file: reads it, parses frontmatter, derives a name (frontmatter
   `name`, else the filename/folder), records metadata, and builds a prompt entry:

   ```
   ===== Skill: <name> =====
   <description>
   <body>
   ```

5. Joins all entries with blank lines into `skills_content` and returns it.

The **raw YAML never leaks** into the prompt — only the human-readable name,
description, and body are injected.

### `_parse_frontmatter(content) -> dict`
Parses a leading `---` … `---` YAML block. Returns:

```
{ "name": <string>, "description": <string>, "body": <string>, "has_frontmatter": bool }
```

If the content doesn't start with `---` or has no closing `---`, it returns the
whole content as `body` with `has_frontmatter = false`. Inside the block it reads
simple `key: value` lines, picking out `name` and `description`.

### `_collect_md_files(dir, out) -> list`
Appends every `<dir>/<sub>/SKILL.md` and every loose `<dir>/*.md` path to `out`.

### `_last_index(s, sub) -> int`
Helper that returns the index of the **last** occurrence of `sub` in `s`
(SageLang's `indexof` finds the first). Used to derive a name from a path.

## Public accessors

| Proc | Returns |
|------|---------|
| `get_skills_content()` | The concatenated prompt-ready skills string. |
| `get_skills_count()` | How many skill files were loaded. |
| `get_skills_meta()` | A list of `{name, description, path}` for each skill. |
| `parse_frontmatter(content)` | Public wrapper over `_parse_frontmatter` (used by tests). |

## Injection into the prompt

`main.sage` passes `get_skills_content()` (or the return of `load_skills`) to
`agent.init_history_with_skills`, which wraps it:

```
<SYSTEM_PROMPT>

=== Loaded Skills ===
<all skills>
=== End Skills ===
```

## Runtime reload

The `:ingest-skills` command re-runs `load_skills` and rebuilds the history, so
you can edit or add skills and apply them **without restarting** the harness. Note
this resets the current conversation to the fresh (updated) system prompt.

## Shipped skills

| Skill | Triggers on |
|-------|-------------|
| `code-review` | reviewing code for bugs, security, best practices |
| `debugging` | diagnosing errors, crashes, failing tests |
| `git-commit` | writing conventional commit messages, committing safely |
| `test-writing` | adding tests, improving coverage |
| `refactoring` | cleaning up / restructuring code without changing behavior |
| `shell-safety` | running shell commands without destructive side effects |
| `web-research` | gathering accurate up-to-date info from the web |
| `documentation` | writing READMEs, docstrings, code comments |

Each lives at `skills/<name>/SKILL.md`.

## Authoring a new skill

1. Create `skills/<your-skill>/SKILL.md`.
2. Add frontmatter with a clear `name` and a `description` that states **what**
   and **when**.
3. Write a short, ordered list of concrete steps. Optionally add an
   "Output format" section.
4. Run `:ingest-skills` (or restart) to load it.
5. Consider adding a validation case to `tests/test_skills.sage`.

### Tips
- Put the strongest trigger phrases in `description` — that's what the model
  matches against.
- Prefer imperative, atomic steps over prose.
- Keep skills focused; one skill per task type.

## Related

- [agent.md](agent.md) — `init_history_with_skills` injection.
- [main.md](main.md) — startup loading and `:ingest-skills`.
- [testing.md](testing.md) — `tests/test_skills.sage`.
