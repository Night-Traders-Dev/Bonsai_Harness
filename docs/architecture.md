# Architecture

This document describes how the Bonsai Agent Harness is put together: the
overall design, the ReAct control loop, the flow of data between modules,
concurrency, and the key design decisions.

## 1. Goals

The harness exists to turn a small, locally-served language model
(**Bonsai-27B**, a 1-bit `Q1_0` quant) into a useful, tool-using assistant with:

- a **ReAct loop** so the model can plan, call tools, observe results, and
  iterate toward an answer;
- **streaming output** so the user sees tokens as they are generated;
- a **skills system** so domain know-how can be injected without retraining;
- a **benchmark suite** so quality can be measured deterministically;
- a **build system** (`sagemake`) that wraps the whole workflow.

Everything (except the `sagemake` build driver, which is Python) is written in
**SageLang**.

## 2. Module map

| Module | File | Responsibility |
|--------|------|----------------|
| Entry point | `src/main.sage` | REPL, command dispatch, callback wiring |
| Agent | `lib/agent.sage` | ReAct loop, history, system prompt, tool-call parsing |
| Ollama client | `lib/ollama.sage` | HTTP chat (streaming + one-shot), request/response codec |
| Tools | `lib/tools.sage` | Tool registry + 7 built-in tools |
| TUI | `lib/tui.sage` | ANSI rendering, threaded spinner, streaming display |
| Skills | `lib/skills.sage` | Load and parse `SKILL.md` files into the system prompt |
| Benchmark | `lib/benchmark.sage` | Tasks + deterministic scorers + model query helper |
| Bench runner | `bench/run_bench.sage` | Runs benchmark categories, prints scores |
| HTTP client | `lib/http_client.sage` | Generic HTTP POST helper |
| Rich (vendored) | `lib/rich/__init__.sage` | Optional TUI helper library (colors/panels/tables) |

## 3. Data flow

A single user turn flows through the system like this:

```
1. main.sage: read a line of input via tui.get_input()
2. main.sage: if it starts with ':' → handle as a command and loop
3. main.sage: else → tui.print_user_msg(), tui.print_assistant_header()
               (the header starts the "thinking" spinner)
4. main.sage: call agent.run_agent(input, history, on_token, on_tool_call, on_final)
5. agent.sage: append the user message to history, fetch tool defs
6. agent.sage: LOOP (up to MAX_ITERATIONS):
      a. trim_history() to fit the context budget
      b. ollama.chat(history, tools, on_token, nil)
            → ollama.sage streams NDJSON from Ollama, calling on_token(tok)
              for every content/thinking token (tui prints them live)
            → returns a parsed {content, thinking, tool_calls} result
      c. if the response has a tool call:
            - on_tool_call(name, args)          (tui prints the call)
            - tools.execute_tool(name, args)     (runs the tool)
            - append "TOOL RESULT (...)" to history
            - on_tool_call("result", summary)    (tui prints result preview)
            - continue the loop
         else (final answer):
            - on_final(answer)                    (tui prints the footer)
            - return
7. main.sage: loop back for the next line
```

## 4. The ReAct loop

The agent implements **Re**asoning + **Act**ing. On each iteration the model
receives the full conversation (system prompt + skills + history) plus the tool
schemas, and produces one of:

- a **tool call** (native Ollama `tool_calls`, or a text fallback of the form
  `FUNCTION: <name>` / `ARGUMENTS: <json>`), or
- a **final answer** (plain text, optionally prefixed `FINAL:`).

Tool results are appended to the conversation as `role: "tool"` messages so the
model can observe them on the next turn. The loop runs at most
`MAX_ITERATIONS` (default **6**) to guarantee termination; if that limit is
reached the agent returns a "please refine your question" message.

See [agent.md](agent.md) for the full detail of each branch.

## 5. Two request paths

`lib/ollama.sage` deliberately provides **two** ways to talk to Ollama:

1. **Streaming** (`send_and_stream` / `chat`) — used by the interactive agent so
   tokens appear live in the TUI. It parses NDJSON chunks off a chunked HTTP
   transfer and calls `on_token` for each piece.
2. **One-shot** (`send_once` / `ask`) — used by the benchmark. It sends
   `stream:false` and reads the whole response at once. This is lighter on
   allocations, which matters when running many queries back-to-back.

Both paths build identical request bodies (same model, same options) via
`build_request`, so behavior is consistent. See [ollama.md](ollama.md).

## 6. Concurrency

The only concurrency in the harness is the **thinking spinner**. When the agent
is waiting for the first token, `lib/tui.sage` spawns a background thread
(`thread.spawn`) that animates a Braille spinner. A mutex-guarded boolean
(`_spinner_running`) tells the thread when to stop, and `thread.join` waits for
it to finish before the first real token is printed. This keeps the UI
responsive without blocking the main request thread. See [tui.md](tui.md).

## 7. Context management

Conversations can grow beyond the model's context window. `agent.trim_history`
keeps the system prompt (index 0) plus as many of the **most recent** messages
as fit within `MAX_HISTORY_CHARS` (default **8000** characters), dropping older
middle messages. The system prompt — which carries the injected skills — is
never dropped.

## 8. Skills injection

On startup `main.sage` calls `skills.load_skills("skills")`, which reads every
`SKILL.md`, strips its YAML frontmatter, and concatenates the bodies. The result
is appended to the system prompt between `=== Loaded Skills ===` markers by
`agent.init_history_with_skills`. The `:ingest-skills` command re-runs this at
runtime without restarting. See [skills.md](skills.md).

## 9. Generation tuning

Because Bonsai-27B is a 1-bit quant, it is prone to repetition loops and to
emitting long "thinking" traces. `lib/ollama.sage` centralizes generation
options in `GEN_OPTIONS`:

- `num_ctx: 8192` — full context window.
- `temperature: 0.1` with `top_k`/`top_p`/`min_p` — near-greedy but avoids
  degenerate single-token loops.
- `repeat_penalty: 1.15` — discourages repetition without distorting short
  answers.
- `num_predict: 2048` — enough room to finish reasoning **and** emit the final
  answer (too small a cap truncates mid-thinking and yields empty content).
- `keep_alive: 10m` — keeps the model resident between requests to avoid reload
  latency.

The model returns reasoning in a separate `thinking` field and the final answer
in `content`. `answer_text()` prefers `content` and only falls back to
`thinking` when `content` is genuinely empty — this is what lets the benchmark
score the real answer rather than truncated reasoning.

## 10. Design decisions & trade-offs

- **Text-based tool-call fallback.** Small models don't always emit valid native
  `tool_calls`, so the agent also parses a plain-text protocol
  (`FUNCTION:`/`ARGUMENTS:`/`FINAL:`). This makes the harness robust to weaker
  models at the cost of a little parsing code.
- **Character-budget history trimming.** A simple, dependency-free heuristic
  (character count) is used instead of a real tokenizer. It is approximate but
  predictable and fast.
- **Two request paths.** Streaming is best for UX; one-shot is best for batch
  evaluation. Keeping both avoids compromising either.
- **Per-category benchmark isolation.** The benchmark runner spawns one `sage`
  process per category so native allocations are reclaimed by the OS between
  categories, preventing memory growth during long runs. See [benchmark.md](benchmark.md).
