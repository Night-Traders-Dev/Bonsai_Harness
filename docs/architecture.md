# Architecture

This document describes how the Bonsai Agent Harness is put together: the
overall design, the dual-model ReAct control loop, the flow of data between
modules, concurrency, and the key design decisions.

## 1. Goals

The harness exists to turn two small, locally-served language models into a
single, coherent tool-using assistant:

- **Bonsai 4B (1-bit Q1_0)** — primary reasoning, planning, coding, synthesis
- **MiniCPM5 1B (F16)** — specialized tool-call compiler and structured output

By splitting responsibilities, the system achieves higher tool-call reliability
without sacrificing the reasoning quality of the larger Bonsai model.

## 2. Core principles

1. **No weight merging.** The two models remain separate neural networks of
   different architectures. Combination happens at the orchestration layer.
2. **Bonsai is the primary brain.** It owns the conversation state, plans,
   and decides when tools are needed.
3. **MiniCPM is a specialized compiler.** It receives a narrow task (the tool
   intent) and returns a structured tool call. It never owns conversation state.
4. **Deterministic tool execution.** Models never execute tools directly. Every
   tool call passes through a validation pipeline before reaching the runtime.

## 3. Module map

| Module | File | Responsibility |
|--------|------|----------------|
| Entry point | `src/main.sage` | REPL, command dispatch, callback wiring |
| Agent | `lib/agent.sage` | Dual-model ReAct loop, history, tool compilation pipeline |
| Model provider | `lib/model_provider.sage` | Abstracted model access (switch between Bonsai and MiniCPM) |
| Model config | `lib/model_config.sage` | Model names, roles, constants |
| Model router | `lib/model_router.sage` | Task-type to model-role mapping |
| Tool compiler | `lib/tool_compiler.sage` | Bonsai intent → MiniCPM → structured tool call |
| Tool validator | `lib/tool_validator.sage` | Security and schema validation for tool calls |
| Ollama client | `lib/ollama.sage` | HTTP chat (streaming + one-shot), request/response codec, configurable model |
| Tools | `lib/tools.sage` | Tool registry + 7 built-in tools |
| TUI | `lib/tui.sage` | ANSI rendering, threaded spinner, streaming display |
| Skills | `lib/skills.sage` | Load and parse `SKILL.md` files into the system prompt |
| Benchmark | `lib/benchmark.sage` | Tasks + deterministic scorers + model query helper |
| Bench runner | `bench/run_bench.sage` | Runs benchmark categories, prints scores |
| HTTP client | `lib/http_client.sage` | Generic HTTP POST helper |
| Model config files | `models/bonsai.sage`, `models/minicpm.sage` | Per-model configuration |

## 4. Dual-model data flow

A single user turn flows through the system like this:

```
User Input
    │
    ▼
┌─────────────────────┐
│    Bonsai 4B 1-bit  │
│                     │
│ • Reasoning         │
│ • Planning          │
│ • Tool Intent       │
└──────────┬──────────┘
           │
      Tool Intent
           │
           ▼
┌─────────────────────┐
│  MiniCPM5 1B F16    │
│                     │
│ • Tool Compiler     │
│ • Structured JSON   │
└──────────┬──────────┘
           │
     Tool Call JSON
           │
           ▼
┌─────────────────────┐
│   Tool Validator    │
│                     │
│ • Schema check      │
│ • Security check    │
└──────────┬──────────┘
           │
      If valid
           │
           ▼
┌─────────────────────┐
│   Tool Runtime      │
│                     │
│ • execute_tool()    │
└──────────┬──────────┘
           │
     Tool Result
           │
           ▼
┌─────────────────────┐
│    Bonsai 4B 1-bit  │
│                     │
│ • Observe           │
│ • Reason            │
│ • Re-plan           │
└──────────┬──────────┘
           │
           ▼
      Final Answer
```

### The agent loop in detail

In `lib/agent.sage`, the `run_agent` procedure implements this as a ReAct loop
with model routing:

1. User message is appended to conversation history.
2. **Bonsai** (primary model) is called with full context + tool definitions.
3. Bonsai generates a response — either a tool call (native or text) or a final
   answer.
4. If a tool call is detected:
   - An **intent** is extracted from Bonsai's output.
   - The intent is passed to **MiniCPM** via the tool compiler.
   - MiniCPM generates a structured tool call (`{name, arguments}`).
   - The **tool validator** checks the call for correctness and security.
   - If valid: the tool is executed, the result is appended to history, and
     control returns to Bonsai.
   - If compilation fails (max retries exceeded): the agent falls back to
     Bonsai's original tool call directly.
5. If a final answer: it is displayed to the user and the loop ends.
6. If `MAX_ITERATIONS` (default 6) is reached: a timeout message is returned.

## 5. Model routing

The `lib/model_router.sage` module maps task types to model roles:

| Task type | Model role |
|-----------|-----------|
| `reasoning`, `planning`, `coding`, `analysis` | Bonsai 4B (primary) |
| `tool_call`, `tool_compile`, `classification` | MiniCPM5 1B (tool compiler) |
| `final_response` | Bonsai 4B (primary) |

The `lib/model_provider.sage` module provides `use_primary()` and
`use_tool_compiler()` to switch the active model in `lib/ollama.sage`.

## 6. Tool compilation pipeline

When Bonsai decides a tool is needed, the following pipeline runs:

1. **Intent extraction.** Bonsai's output (tool name + arguments or natural
   language) is captured as an intent string.
2. **Compiler prompt.** A minimal prompt is built containing:
   - System instructions for the tool compiler
   - Available tool schemas (name, description, parameters)
   - The tool intent
3. **MiniCPM invocation.** The prompt is sent to MiniCPM via `ollama.ask()`
   (non-streaming, one-shot).
4. **JSON extraction.** The raw response is scanned for a balanced JSON object.
5. **Parsing.** The JSON is parsed with cJSON — `name` and `arguments` are
   extracted.
6. **Validation.** The parsed tool call is checked by `tool_validator`.
7. **Execution.** If valid, the tool runs. If invalid, the compiler retries
   (up to `MAX_TOOL_COMPILER_RETRIES = 2`).

## 7. Tool validation

The `lib/tool_validator.sage` module enforces:

- Tool exists in registry
- Required arguments are present and are strings
- Security policies:
  - `bash`: blocks destructive commands (`rm -rf /`, `rm -rf ~`, `mkfs`, `dd if=`, `:(){ :|:& };:`, `chmod -R 777 /`)
  - `read_file`/`write_file`: requires `path`, blocks `..` traversal and symlink resolution outside workspace root
  - `web_fetch`: supports `http://` and `https://` URLs with SSRF host validation against private/loopback subnets
- Rejected calls return a structured error shown in the TUI

## 8. Two request paths

`lib/ollama.sage` provides **two** ways to talk to Ollama:

1. **Streaming** (`send_and_stream` / `chat`) — used by the interactive agent
   for live token display.
2. **One-shot** (`send_once` / `ask`) — used by the tool compiler and
   benchmark for efficient single-response queries.

Both paths use `build_request` with the currently configured model
(`ollama.set_model()`).

## 9. Configurable model

Previously hardcoded to a single model, `lib/ollama.sage` now supports dynamic
model switching via:

- `ollama.set_model(name)` — sets the model tag for subsequent requests
- `ollama.get_model()` — returns the current model tag
- `ollama.set_host(host)` / `ollama.set_port(port)` — configurable endpoint

This is used by `lib/model_provider.sage` to switch between Bonsai and MiniCPM
within the same agent session.

## 10. Memory strategy

Two operating modes are supported:

- **Dual resident** (desktop): both models loaded simultaneously in Ollama.
  Requires RTX 5060 8GB or similar.
- **Dynamic loading** (mobile/low-RAM): only one model loaded at a time;
  Ollama swaps them on demand.

The current implementation uses dynamic loading — `ollama.set_model()` triggers
Ollama to load/unload models as needed.

## 11. Terminal UI & State Management

Terminal rendering in `lib/tui.sage` uses clean single-threaded state tracking. While waiting for Ollama tokens, `  thinking...` is displayed. As tokens stream in, `print_token` detects `<think>` and `</think>` tags, formatting reasoning blocks in dimmed gray under a `💭 Reasoning:` header.

## 12. Context management

Conversations can grow beyond the model's context window. `agent.trim_history`
keeps the system prompt (index 0) plus as many of the **most recent** messages
as fit within `MAX_HISTORY_CHARS` (default **8000** characters), dropping older
middle messages.

## 13. Generation tuning

`lib/ollama.sage` centralizes generation options in `GEN_OPTIONS`:

- `num_ctx: 2048` — optimized context window for fast local CPU inference.
- `temperature: 0.1` with `top_k`/`top_p`/`min_p` — near-greedy but avoids
  degenerate single-token loops common in 1-bit quants.
- `repeat_penalty: 1.15` — discourages repetition.
- `num_predict: 2048` — enough for reasoning + answer.
- `keep_alive: 10m` — keeps model resident.

## 14. Design decisions & trade-offs

- **Dual-model over single.** Separating reasoning from structured output
   improves tool-call validity without burdening the primary model with
   precise JSON generation.
- **No weight merging.** The two models have different architectures; fusing
   them would be impractical. The combination is at the orchestration layer.
- **Fallback path.** If MiniCPM fails to produce a valid call, Bonsai's
   original tool call is used directly. This ensures the system degrades
   gracefully.
- **Character-budget history trimming.** A simple, dependency-free heuristic
   instead of a real tokenizer. Approximate but fast.
- **Two request paths.** Streaming for UX, one-shot for batch work.
- **Dynamic model switching.** The harness calls `ollama.set_model()` before
   each request, allowing Ollama's built-in model loading to manage memory.
