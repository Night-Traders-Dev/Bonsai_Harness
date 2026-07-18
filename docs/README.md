# Bonsai Agent Harness — Documentation

This directory contains detailed, per-component documentation for the Bonsai
Agent Harness — a [SageLang](https://github.com/Night-Traders-Dev/SageLang)
program that turns the **Bonsai-8B** model (served locally by **Ollama**) into
a tool-using [ReAct](https://arxiv.org/abs/2210.03629) agent with a streaming
terminal UI, a skills system, and a self-contained benchmark suite.

Every source file in the project has a corresponding document here. Each
document explains **what the component does**, **how it works internally**,
**every public procedure**, the **data shapes** it produces or consumes, and
**how to extend it**.

## Index

| Document | Component | Summary |
|----------|-----------|---------|
| [architecture.md](architecture.md) | Whole system | High-level design, the ReAct loop, data flow, threading, and how the pieces fit together. |
| [main.md](main.md) | `src/main.sage` | The entry point: REPL loop, slash-command dispatch, callback wiring. |
| [agent.md](agent.md) | `lib/agent.sage` | The ReAct agent loop, history management, tool-call parsing, system prompt. |
| [ollama.md](ollama.md) | `lib/ollama.sage` | Ollama HTTP client: request building, streaming + non-streaming chat, response parsing, generation options. |
| [tools.md](tools.md) | `lib/tools.sage` | The tool registry and the seven built-in tools. |
| [tui.md](tui.md) | `lib/tui.sage` | Terminal UI: ANSI styling, the threaded spinner, streaming token rendering. |
| [skills.md](skills.md) | `lib/skills.sage` + `skills/` | The skills system, `SKILL.md` format, frontmatter parser, authoring guide. |
| [benchmark.md](benchmark.md) | `lib/benchmark.sage` + `bench/run_bench.sage` | The evaluation suite: task categories, scorers, the runner, process isolation. |
| [http_client.md](http_client.md) | `lib/http_client.sage` | A general-purpose HTTP POST client (chunked-transfer aware). |
| [sagemake.md](sagemake.md) | `sagemake` | The Python build system: build, compile, run, test, bench, install, clean. |
| [testing.md](testing.md) | `tests/` | The three self-test suites and how to add tests. |

## Quick orientation

```
User input
   │
   ▼
src/main.sage ──────────────► lib/tui.sage        (render banner, spinner, tokens)
   │
   ▼
lib/agent.sage  (ReAct loop)
   │        │
   │        ├──► lib/ollama.sage ──► Ollama HTTP API ──► Bonsai-8B
   │        │
   │        └──► lib/tools.sage ──► bash / files / grep / glob / web
   │
   ▼
lib/skills.sage (injects SKILL.md guidance into the system prompt)
```

For build and run instructions see the top-level [README](../README.md) or
[sagemake.md](sagemake.md).
