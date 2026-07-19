# Performance Audit & Tuning

This document describes the performance work done on the Bonsai Agent Harness,
the benchmark results, and the optimisations applied — all **without changing
the model**. Every improvement came from fixing the harness itself.

## Before and after

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| **Benchmark score** | 32% (8/25) | **96%** (24/25) | +64 pp |
| Reasoning | 40% | **100%** | +60 pp |
| Knowledge | 40% | **100%** | +60 pp |
| Coding | 20% | **100%** | +80 pp |
| Tool use | 20% | **100%** | +80 pp |
| Instruction | 40% | **80%** | +40 pp |
| Test suite | 55 pass | **57 pass** | +2 |
| OOM during bench | Yes (process OOM-killed) | **No** (process isolation) | ✅ |

## Root causes of the original 32% score

The low score was **not** the model's ability — it was the harness throwing away
correct answers:

1. **Truncated thinking → empty content.** `num_predict:512` cut generation off
   mid-reasoning. The model's `content` field (the real answer) never arrived,
   and the fallback scored the raw truncated `thinking` text instead.
2. **Choice scorer too strict.** The model often answered with the correct value
   (`Au` for gold) instead of the bare letter (`B`). The old scorer only
   accepted the letter.
3. **Memory accumulation across categories.** A long-running `sage` process
   accumulated native (cJSON) allocations that SageLang's GC did not reclaim,
   eventually getting OOM-killed mid-benchmark.

## Mitigations applied

### 1. Score the real answer, not truncated reasoning

**Files:** `lib/ollama.sage:85-91`, `:339-348`

`parse_response_body` now stores `content` and `thinking` as **separate**
fields. The new `answer_text()` helper prefers the (non-empty) `content` and
only falls back to `thinking` when `content` is genuinely absent.

```sage
proc answer_text(result):
    if dict_has(result, "content"):
        let c = result["content"]
        if c != nil and strip(c) != "":
            return c
    if dict_has(result, "thinking"):
        let t = result["thinking"]
        if t != nil:
            return t
    return ""
```

`lib/benchmark.sage` now calls `ollama.answer_text(result)` instead of reading
`result["content"]` directly, recovering every task where the model produced a
correct answer in the content field but it was being ignored.

### 2. Generation option tuning

**Files:** `lib/ollama.sage:9-20`

Options are now centralised in the `GEN_OPTIONS` constant so both the streaming
and non-streaming paths are always consistent.

| Option | Old value | New value | Why |
|--------|-----------|-----------|-----|
| `num_predict` | 512 | **2048** | Room to finish reasoning **and** emit the final answer. 512 truncated mid-thinking. |
| `repeat_penalty` | (none) | **1.15** | Discourages repetition loops without distorting short answers. A harsher 1.3 was found to hurt terse outputs. |
| `top_k` | (default) | **40** | Prevents degenerate single-token loops that 1-bit quants are prone to. |
| `top_p` | (default) | **0.9** | Nucleus sampling as an additional guard against degenerate output. |
| `min_p` | (default) | **0.05** | Eliminates very low-probability tokens from consideration. |
| `keep_alive` | (none) | **10m** | Keeps the model resident in VRAM between requests, avoiding reload latency. |

The `num_predict` change was the single most impactful fix. With 512 tokens,
the model would be cut off while still in its reasoning trace; the thinking
field (which the old parser fell back to) contained the first few hundred tokens
of a long reasoning chain but never the answer.

### 3. Non-streaming request path for benchmarks

**Files:** `lib/ollama.sage:309-348`, `lib/benchmark.sage:148-150`

The benchmark now uses `ollama.ask()` (the non-streaming `send_once` path)
instead of `ollama.chat_simple()` (streaming). The non-streaming path:

- Sends a single `stream:false` HTTP request
- Reads the response with a simpler, lower-allocation loop
- Avoids the incremental NDJSON parser that accumulates many small string
  allocations per call

This reduces per-request memory pressure significantly during batch evaluation.

### 4. `choice` scorer accepts value text

**Files:** `lib/benchmark.sage:127-129`

Knowledge tasks now carry an `"accept"` field with the correct option's value
text (e.g. `"au"` for the chemical symbol of gold). The `choice` scorer checks
this field in addition to the letter-based heuristics, so the model gets credit
whether it answers with the letter (`B`) or names the value (`Au`).

### 5. Per-category process isolation

**Files:** `sagemake:258-282`, `bench/run_bench.sage:55-57`

`sagemake bench` now spawns **one `sage` process per category** by setting the
`BENCH_CATEGORY` environment variable. The runner (`bench/run_bench.sage`)
reads this variable and runs only that category when set. This means:

- Memory allocated during one category's run (cJSON parse trees, string buffers,
  etc.) is fully reclaimed by the OS when the process exits.
- The next category starts with a clean heap.
- OOM kills are eliminated.

Without isolation, a single process running 25 sequential model calls would
accumulate native allocations that SageLang's GC (even under ARC/ORC) could not
fully reclaim, eventually causing the kernel OOM killer to terminate the
process.

## Results

### Benchmark breakdown

```
reasoning   100% (5/5)    gsm-1, gsm-2, gsm-3, gsm-4, logic-1 all pass
knowledge   100% (5/5)    mmlu-1 through mmlu-5 all pass
coding      100% (5/5)    code-1 through code-5 all pass
tool_use    100% (5/5)    tool-1 through tool-5 all pass
instruction  80% (4/5)    if-1, if-3, if-4, if-5 pass; if-2 (ultra-terse "z") fails
```

### The one remaining failure: `if-2` ("Answer with only the letter Z")

The model emits a reasoning trace like "Okay, the user wants me to answer with
only one letter... The letter Z..." but the `content` field is empty and the
`thinking` trace is too long / not a clean parseable answer. This is a genuine
limitation of the 1-bit Q1_0 quant — it struggles to suppress its reasoning
habit when the instruction is extremely terse.

Possible levers for the future:
- System-prompt nudge to shorten/omit reasoning for simple instructions.
- `/no_think` mode where the request disables the thinking field entirely.
- A different quant (Q4_K_M or higher) that follows terse instructions more
  reliably.

## Latency / throughput notes

- `keep_alive: 10m` ensures the model stays loaded between turns, making
  subsequent requests ~1–3 s faster (avoiding the ~5–10 s model-load time).
- Streaming tokens to the TUI adds negligible overhead because the incremental
  NDJSON parser processes each chunk in constant time per byte.
- The non-streaming benchmark path completes all 25 tasks in ~8–10 minutes
  (dominated by model inference, not harness overhead).

## Related

- [benchmark.md](benchmark.md) — the evaluation suite
- [ollama.md](ollama.md) — generation options and request paths
- [sagemake.md](sagemake.md) — per-category process isolation
- [README.md](../README.md) — benchmark results badge
