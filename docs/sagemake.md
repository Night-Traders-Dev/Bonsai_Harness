# `sagemake` — Build System

`sagemake` is a Python 3 script that drives the whole developer workflow for the
harness: syntax checking, compiling, running, testing, benchmarking, installing,
and cleaning. It is the recommended way to interact with the project.

```bash
./sagemake <command> [args...]
```

## Commands

| Command | What it does |
|---------|--------------|
| `build` | Check dependencies, then lint every `*.sage` file for syntax errors. |
| `compile` | Build a JIT-packaged native binary (falls back to a run script). |
| `run` | Launch the harness with the JIT runtime. |
| `test` | Run the three self-test suites. |
| `bench` | Run the model benchmark suite with per-category process isolation. |
| `install` | Copy the built binary to `/usr/local/bin`. |
| `clean` | Remove build artifacts. |
| `all` | `build` then `test`. |

Run with no (or an unknown) command to see the usage summary.

## Key paths & config

| Name | Value |
|------|-------|
| `ROOT` | the repo root (script's parent directory) |
| `LIB_DIR` | `ROOT/lib` |
| `MAIN_SAGE` | `src/main.sage` |
| `BINARY_NAME` | `bonsai-harness` |
| `SAGE` | the `sage` binary found on `PATH` (else `/usr/local/bin/sage`) |

## Output helpers

The script prints a consistent, colorized report using helpers: `banner`,
`section`, `step`, `ok`, `fail`, `step_ok`, `step_fail`, `step_warn`. `run_cmd`
runs a subprocess with the current environment and fails loudly on error or a
missing executable.

## Dependency checks

`check_dependencies()` verifies that `sage` and `ollama` are on `PATH`, then runs
`ollama list` to confirm the daemon is reachable (warning, not fatal, if not).
`build`, `compile`, `run`, and `bench` all call it first.

## Command details

### `build`
Lints each `*.sage` file with `sage lint`. If any file's stderr contains "syntax
error" or "error", the file is reported failed; a non-zero count aborts the
build. On success: "all files pass syntax check".

### `compile`
Runs `sage --jit src/main.sage -o bonsai-harness`. If that produces the binary,
great. Otherwise it **falls back** to writing a small shell run-script named
`bonsai-harness` that invokes `sage --runtime jit` with the correct include paths
— so you always end up with an executable entry point.

### `run`
Launches `sage --runtime jit src/main.sage`, augmenting `SAGE_PATH` with `ROOT`
and `LIB_DIR` so imports resolve. Handles `Ctrl-C` gracefully.

### `test`
Runs each suite in `tests/` (`test_tools.sage`, `test_skills.sage`,
`test_benchmark.sage`) via `sage`, streaming their output. A non-zero exit from
any suite aborts with a failure count; otherwise prints "all test suites passed".
See [testing.md](testing.md).

### `bench`
The most involved command. For each category in `BENCH_CATEGORIES`
(`reasoning, knowledge, coding, tool_use, instruction`) — or the categories you
pass as args — it:

1. Spawns `sage bench/run_bench.sage` with `BENCH_CATEGORY=<cat>` in the
   environment (a **fresh process per category**, so memory is reclaimed between
   them — this is what prevents OOM on long runs).
2. Echoes the human-readable output, but intercepts the machine-readable
   `SCORE <cat> <correct> <total>` line to accumulate totals.
3. Handles timeouts (1800 s per category) and `Ctrl-C` gracefully.

After all categories it prints the aggregate:

```
OVERALL: <pct>% (<correct>/<total> tasks)
```

color-coded green/yellow/red at the 80%/50% thresholds.

### `install`
Copies `bonsai-harness` to `/usr/local/bin` and marks it executable. Fails with a
clear message if the binary is missing (run `compile` first) or if permissions
are denied (use `sudo`).

### `clean`
Removes build artifacts: the binary, `src/bonsai.c`, `src/bonsai.ll`, and a
`build/` directory if present.

### `all`
Convenience: `build` followed by `test`.

## Typical workflows

```bash
# First-time setup check
./sagemake build

# Iterate
./sagemake run

# Before committing
./sagemake all           # build + test
./sagemake bench         # measure model quality

# Ship a binary
./sagemake compile
sudo ./sagemake install
```

## Extending

- **Add a command:** write a `cmd_<name>(args)` function and register it in the
  `commands` dict inside `main()`.
- **Change benchmark categories:** edit `BENCH_CATEGORIES`.
- **Add lint rules or file filters:** adjust `cmd_build`'s `rglob`/error matching.

## Related

- [testing.md](testing.md) — what `test` runs.
- [benchmark.md](benchmark.md) — what `bench` runs and how isolation works.
- [main.md](main.md) — the program `run`/`compile` target.
