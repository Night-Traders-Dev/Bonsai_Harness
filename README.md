<div align="center">

# 🤖 Bonsai Agent Harness

**Dual-Model Agent Architecture — Bonsai 4B + MiniCPM5 1B + Ollama + SageLang**

<!-- PROJECT VERSION BADGES -->
[![SageLang](https://img.shields.io/badge/SageLang-4.1.0-7C3AED?style=flat-square&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBvbHlsaW5lIHBvaW50cz0iMTYgMTggMjIgMTIgMTYgNiIvPjxwb2x5bGluZSBwb2ludHM9IjggNiAyIDEyIDggMTgiLz48L3N2Zz4=)](https://github.com/Night-Traders-Dev/SageLang)
[![Ollama](https://img.shields.io/badge/Ollama-0.32.1-EE4C2C?style=flat-square&logo=ollama)](https://ollama.ai)
[![Bonsai-4B](https://img.shields.io/badge/Bonsai--4B-Q1_0-22C55E?style=flat-square)](https://huggingface.co/prism-ml/Bonsai-4B-gguf)
[![License](https://img.shields.io/badge/license-MIT-F59E0B?style=flat-square)](LICENSE)
[![Python](https://img.shields.io/badge/build-sagemake-3B82F6?style=flat-square)](#-quick-start)
[![GitHub](https://img.shields.io/github/stars/Night-Traders-Dev/Bonsai_Harness?style=flat-square&logo=github)](https://github.com/Night-Traders-Dev/Bonsai_Harness)

![Conversation Demo](assets/conversation.png)

</div>

---

## ✨ Features

- **Dual-model architecture** — Bonsai 4B handles reasoning/planning/coding; MiniCPM5 1B handles tool-call compilation
- **ReAct agent loop** — plan, call tools, observe results, iterate
- **Streaming TUI** — live token display with threaded spinner
- **7 built-in tools** — bash, read/write file, grep, glob, list_dir, web_fetch
- **Tool validation pipeline** — every tool call is validated before execution
- **Skills system** — inject domain knowledge via Markdown files
- **Benchmark suite** — deterministic evaluation across 7 categories

![Features](assets/features.png)

---

## 📋 Prerequisites

| Dependency | Version | Install |
|-----------|---------|---------|
| SageLang | ≥ 4.1.0 | `git clone https://github.com/Night-Traders-Dev/SageLang && cd SageLang && sudo ./sagemake --install --skip-tests` |
| Ollama | ≥ 0.32.1 | `curl -fsSL https://ollama.com/install.sh \| sh` |
| Bonsai-4B | Q1_0 | `ollama pull hf.co/prism-ml/Bonsai-4B-gguf:Q1_0` |
| MiniCPM5-1B | Q8_0 | `ollama pull hf.co/GnLOLot/MiniCPM5-1B-Claude-Opus-Fable5-V2-Thinking-GGUF:Q8_0` |

---

## 🚀 Quick Start

```bash
# 1. Clone and enter
git clone https://github.com/Night-Traders-Dev/Bonsai_Harness.git
cd Bonsai_Harness

# 2. Start Ollama (if not already running)
ollama serve

# 3. Pull the models
ollama pull hf.co/prism-ml/Bonsai-4B-gguf:Q1_0
ollama pull hf.co/GnLOLot/MiniCPM5-1B-Claude-Opus-Fable5-V2-Thinking-GGUF:Q8_0

# 4. Launch the harness
./sagemake run
# or directly:
sage --runtime jit src/main.sage
```

---

## 🎮 Commands

| Command | Action |
|---------|--------|
| `:quit` / `:exit` | Exit the harness |
| `:clear` | Clear screen |
| `:help` | Show command help |
| `:history` | Show conversation history count |
| `:models` | Show active model configuration |
| `:ingest-skills` | Reload skill files from `skills/` directory |

---

## 🏗️ Project Structure

![Project Structure](assets/directory.png)

### 📦 Module Map

| Module | Role | Key Procs |
|--------|------|-----------|
| `src/main` | Entry point / REPL | `process_input`, `on_token`, `on_tool_call`, `on_final` |
| `lib.agent` | Dual-model ReAct loop | `run_agent`, `compile_via_minicpm`, `handle_tool_call` |
| `lib.model_provider` | Model abstraction | `use_primary`, `use_tool_compiler`, `chat`, `ask` |
| `lib.model_config` | Model definitions | `get_model_for_role`, `set_model_for_role` |
| `lib.model_router` | Task routing | `route_task` — maps task types to model roles |
| `lib.tool_compiler` | MiniCPM tool compilation | `compile_tool_call`, `extract_intent_from_bonsai` |
| `lib.tool_validator` | Tool call validation | `validate_tool_call` — security + schema checks |
| `lib.ollama` | Ollama API client | `chat`, `ask`, `set_model`, `build_request` |
| `lib.tools` | Tool registry | `register_tool`, `execute_tool`, `get_tool_list` |
| `lib.tui` | Terminal UI | `print_banner`, `print_user_msg`, `print_token`, `print_tool_call` |
| `lib.skills` | Skills system | `load_skills`, `parse_frontmatter`, `get_skills_meta`, `get_skills_content` |
| `lib.benchmark` | Eval suite | `get_categories`, `get_tasks`, `score`, `query_model` |
| `lib.http_client` | HTTP | `http_post`, `http_post_raw`, `read_line` |
| `models/` | Model configs | `bonsai.sage`, `minicpm.sage` |

---

## 🧠 Dual-Model Architecture

```
                    User
                      │
                      ▼
             ┌─────────────────┐
             │   Bonsai 4B     │
             │    1-bit        │
             │                 │
             │ Primary Agent   │
             │ Reasoning       │
             │ Planning        │
             │ Coding          │
             └────────┬────────┘
                      │
                 Tool Intent
                      │
                      ▼
             ┌─────────────────┐
             │   MiniCPM5      │
             │    1B F16       │
             │                 │
             │ Tool Compiler   │
             │ Tool Selection  │
             │ Structured JSON │
             └────────┬────────┘
                      │
                      ▼
             ┌─────────────────┐
             │ Tool Validator  │
             └────────┬────────┘
                      │
                      ▼
             ┌─────────────────┐
             │   Tool Runtime  │
             └────────┬────────┘
                      │
                 Tool Result
                      │
                      ▼
             ┌─────────────────┐
             │   Bonsai 4B     │
             │                 │
             │ Observe         │
             │ Reason          │
             │ Re-plan         │
             └────────┬────────┘
                      │
                      ▼
                    User
```

**Bonsai 4B (1-bit)** handles reasoning, planning, coding, analysis, and final synthesis. **MiniCPM5 1B (F16)** specializes in converting natural-language intents into precise structured tool calls. A validation layer ensures every tool call is safe before execution.

---

## 📚 Documentation

Detailed, per-component documentation lives in [`docs/`](docs/). Start with the
[documentation index](docs/README.md) or jump straight to a topic:

| Document | Covers |
|----------|--------|
| [architecture.md](docs/architecture.md) | Dual-model system design, data flow, model routing |
| [agent.md](docs/agent.md) | `lib/agent.sage` — dual-model ReAct loop, tool compilation pipeline |
| [ollama.md](docs/ollama.md) | `lib/ollama.sage` — configurable model, streaming + one-shot |
| [tools.md](docs/tools.md) | `lib/tools.sage` — registry + the 7 built-in tools |
| [tui.md](docs/tui.md) | `lib/tui.sage` — ANSI rendering, threaded spinner |
| [skills.md](docs/skills.md) | `lib/skills.sage` + `skills/` — skills system & authoring |
| [benchmark.md](docs/benchmark.md) | `lib/benchmark.sage` + runner — eval suite & scorers |
| [http_client.md](docs/http_client.md) | `lib/http_client.sage` — generic HTTP POST client |
| [sagemake.md](docs/sagemake.md) | `sagemake` — build/run/test/bench/install |
| [testing.md](docs/testing.md) | `tests/` — the three self-test suites |

---

## 🛠️ Tools Available

| Tool | Description | Arguments |
|------|-------------|-----------|
| `bash` | Execute shell commands | `command` (string) |
| `read_file` | Read file contents | `path` (string) |
| `write_file` | Write content to file | `path`, `content` |
| `grep` | Regex search in files | `pattern`, `path` (optional) |
| `glob` | Find files by glob pattern | `pattern` (string) |
| `list_dir` | List directory contents | `path` (optional, default: `.`) |
| `web_fetch` | Fetch URL (HTTP only) | `url` (string) |

---

## 🧪 Tests

```bash
./sagemake test
```

Three self-test suites run without touching the network:

| Suite | Coverage |
|-------|----------|
| `tests/test_tools.sage` | tool registration, dispatch, argument handling (23 tests) |
| `tests/test_skills.sage` | skill loading, frontmatter parsing, subdir `SKILL.md`, shipped-skill validation (15 tests) |
| `tests/test_benchmark.sage` | benchmark structure and every scoring matcher (17 tests) |

---

## 📊 Benchmark Suite

```bash
./sagemake bench
```

A built-in evaluation harness measures the model across five categories with
automated, deterministic scoring.

---

## 🔧 Build System

```bash
./sagemake build      # Syntax check + lint
./sagemake compile    # JIT-packaged binary
./sagemake run        # Launch with JIT profiling
./sagemake test       # Run self-tests
./sagemake bench      # Run benchmark suite
./sagemake install    # Copy binary to /usr/local/bin
./sagemake clean      # Remove artifacts
```

---

## 📜 License

MIT — see [LICENSE](LICENSE).

---

<div align="center">
<sub>Built with ❤️ using <a href="https://github.com/Night-Traders-Dev/SageLang">SageLang</a> and <a href="https://ollama.ai">Ollama</a></sub>
</div>
