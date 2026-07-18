# `tests/` — Test Suites

The harness ships with three self-test suites that run **without touching the
network** (except one deliberate `web_fetch` against the local Ollama port).
They cover the tool system, the skills system, and the benchmark's structure and
scorers. Run them all with:

```bash
./sagemake test
# or individually:
sage tests/test_tools.sage
sage tests/test_skills.sage
sage tests/test_benchmark.sage
```

## Coverage summary

| Suite | Covers | Tests |
|-------|--------|-------|
| `tests/test_tools.sage` | tool registration, dispatch, every tool's happy path + missing-argument errors, unknown-tool handling | 23 |
| `tests/test_skills.sage` | skill loading, frontmatter parsing, subdir `SKILL.md`, shipped-skill validation | 15 |
| `tests/test_benchmark.sage` | benchmark task structure and every scoring matcher | 17 |

**Total: 55 tests.**

## The test harness pattern

Each suite defines a tiny in-file framework:

```sage
var passed = 0
var failed = 0

proc run_test(name, fn):
    print "  " + name + " ... "
    let ok = fn()
    if ok:
        print "    PASS"
        passed = passed + 1
    else:
        print "    FAIL"
        failed = failed + 1
```

with assertion helpers that print a diff on failure and return a bool:

| Helper | Checks |
|--------|--------|
| `expect_eq(actual, expected)` | equality |
| `expect_contains(actual, substr)` | substring presence |
| `expect_startswith(actual, prefix)` | prefix |
| `expect_nil(val)` | value is `nil` |

At the end each suite prints a results block and, if any test failed,
`raise`s — which makes the process exit non-zero so `sagemake test` can detect
failures.

## `tests/test_tools.sage`

Exercises `lib/tools.sage`:

- **Registry:** `get_tool_list()` returns 7 tools; each entry has `name`,
  `description`, `parameters`; all seven expected names are present.
- **Per tool:** a happy-path call and its missing-argument error message, for
  `bash`, `write_file`, `read_file`, `grep`, `glob`, `list_dir`, and `web_fetch`.
  (`write_file`/`read_file` round-trip through a real temp file at
  `/tmp/bonsai_test_write.txt`, cleaned up at the end.)
- **Unknown tool:** `execute_tool("nonexistent_tool_xyz", {})` returns an
  `Error: Unknown tool` string.

> Note: `test_web_fetch_ollama` fetches `http://localhost:11434` and expects the
> string "Ollama", so Ollama must be running for that one test to pass.

## `tests/test_skills.sage`

Exercises `lib/skills.sage`: frontmatter parsing (with and without a block, name
derivation from filename/folder), loading from subdirectory `SKILL.md` files,
that raw YAML is stripped from the injected content, `get_skills_count` /
`get_skills_meta` correctness, and that the eight shipped skills are present and
well-formed.

## `tests/test_benchmark.sage`

Exercises `lib/benchmark.sage` **without calling the model**: it validates that
each `_tasks_*` provider returns well-formed tasks (required keys, valid `kind`),
that `get_categories`/`get_tasks` behave, and that `score` returns the correct
result for every matcher (`number`, `choice` including the `accept` value path,
`contains`, `exact_word`) across passing and failing inputs.

## Writing a new test

1. Add a nullary `proc test_xxx():` that returns a bool (use the `expect_*`
   helpers).
2. Register it with `run_test("description", test_xxx)`.
3. If it creates files, clean them up before the results block.
4. Keep tests **network-free** where possible so they run fast and
   deterministically in CI.

## Adding a whole suite

1. Create `tests/test_<area>.sage` following the framework pattern above.
2. Add its path to the `test_suites` list in `sagemake`'s `cmd_test`.
3. It will then run as part of `./sagemake test`.

## Related

- [tools.md](tools.md) / [skills.md](skills.md) / [benchmark.md](benchmark.md) —
  the modules under test.
- [sagemake.md](sagemake.md) — the `test` command that runs these suites.
