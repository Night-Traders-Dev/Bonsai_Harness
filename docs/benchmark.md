# `lib/benchmark.sage` + `bench/run_bench.sage` — Benchmark Suite

A self-contained evaluation harness that measures the model across five
categories using **automated, deterministic scoring** — no human grader and no
network dependency beyond the local Ollama daemon.

## Categories

Each category mirrors the style of a widely used LLM benchmark:

| Category | Style | Measures | # tasks |
|----------|-------|----------|---------|
| `reasoning` | GSM8K | multi-step math word problems (exact numeric answer) | 5 |
| `knowledge` | MMLU | multiple-choice factual questions | 5 |
| `coding` | HumanEval / MBPP | predicting program output & code behavior | 5 |
| `tool_use` | function-calling | choosing the correct tool for a request | 5 |
| `instruction` | IFEval | following precise output constraints | 5 |

Total: **25 tasks**.

## Task shape

Each task is a dict:

```sage
{ "id": "gsm-1",
  "prompt": "Answer with only the final number. ...",
  "answer": "72",
  "kind": "number" }        # scorer to use
```

`choice` tasks additionally carry an `"accept"` field with the answer's **value
text** (e.g. `"au"` for "gold"), so the model gets credit whether it emits the
letter (`B`) or names the value (`Au`).

## Task providers

`_tasks_reasoning`, `_tasks_knowledge`, `_tasks_coding`, `_tasks_tool_use`, and
`_tasks_instruction` each return their list of tasks. Two dispatchers expose them:

- `get_categories() -> ["reasoning", "knowledge", "coding", "tool_use", "instruction"]`
- `get_tasks(category) -> list` (returns `[]` for an unknown category)

## Scoring

### `score(task, response) -> bool`
Normalizes the response (`lower(strip(response))`) and applies the matcher named
by `task["kind"]`:

| `kind` | Passes when… |
|--------|--------------|
| `number` | the **last** number in the response equals the expected digits. |
| `choice` | the response starts with the letter, or contains `answer is <letter>`, `(<letter>)`, `<letter>)`, **or** contains the `accept` value text. |
| `contains` | the response contains the expected string. |
| `exact_word` | the response, stripped of `.!,` whitespace and newlines, exactly equals the expected word. |

### Helpers
- `_only_digits(s)` — keeps just the digit characters of `s`.
- `_last_number(s)` — returns the last contiguous run of digits in `s` (robust to
  reasoning that mentions several numbers before the final answer).

## Querying the model

### `query_model(prompt) -> string`
Sends the prompt as a single user message via `ollama.ask` (the **non-streaming**
path — lighter for batch runs) and returns `ollama.answer_text(result)`, which
prefers the model's `content` (final answer) over its `thinking` trace. Returns
`""` on error.

> This helper is the reason the benchmark measures the real answer rather than a
> truncated reasoning dump — see [ollama.md](ollama.md) `answer_text`.

## The runner — `bench/run_bench.sage`

A colored CLI that runs tasks and prints results.

### `bar(pct) -> string`
Renders a 20-cell `█`/`░` progress bar for a percentage.

### `run_category(cat)`
Prints a header, iterates the category's tasks, and for each: shows the id, calls
`query_model`, scores with `score`, and prints `pass` (green) or `fail` (red,
with a 40-char preview of what the model actually said). At the end it prints a
color-coded bar + pass rate, then a machine-readable line:

```
SCORE <category> <correct> <total>
```

### Process-isolation mode
The script reads the `BENCH_CATEGORY` environment variable:

- **set** → run only that one category (used by `sagemake bench`).
- **unset** → run the whole suite in one process.

Per-category isolation exists because a long-running `sage` process accumulates
native (cJSON) allocations across many model calls; running each category in its
own process lets the OS reclaim that memory between categories and avoids OOM on
long runs. See [architecture.md](architecture.md) §10.

## Running

```bash
./sagemake bench          # per-category process isolation (recommended)
sage bench/run_bench.sage # whole suite in one process
```

`./sagemake bench` spawns one `sage` process per category, echoes the
human-readable output, parses each `SCORE` line, and prints an aggregate:

```
══════════════════════════════════════════════════
OVERALL: 96% (24/25 tasks)
══════════════════════════════════════════════════
```

You can also limit categories: `./sagemake bench reasoning coding`.

## Interpreting results

- The **preview** on a failure shows exactly what the model produced — invaluable
  for telling a genuine wrong answer from a formatting/parsing miss.
- Because scoring is deterministic and `temperature` is low, runs are largely
  reproducible.
- A low score is often a *harness* problem (truncation, scorer too strict), not a
  model problem — the project's jump from 32%→96% came entirely from scoring the
  right field and tuning generation options, with **no model change**.

## Adding or editing tasks

1. Add a dict to the relevant `_tasks_*` proc with `id`, `prompt`, `answer`, and
   `kind` (plus `accept` for `choice`).
2. Choose the `kind` whose matcher fits the expected answer.
3. Run `./sagemake test` — `tests/test_benchmark.sage` validates structure and
   every scorer.
4. Run `./sagemake bench` to see the model's score.

## Related

- [ollama.md](ollama.md) — `ask` / `answer_text`.
- [sagemake.md](sagemake.md) — `cmd_bench` and aggregation.
- [testing.md](testing.md) — `tests/test_benchmark.sage`.
