<div align="center">

# 🤖 Bonsai Agent Harness

**Bonsai-8B + Ollama + SageLang — A ReAct agent with tools, streaming, and TUI**

[![SageLang](https://img.shields.io/badge/SageLang-4.0.9-7C3AED?style=flat-square&logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBvbHlsaW5lIHBvaW50cz0iMTYgMTggMjIgMTIgMTYgNiIvPjxwb2x5bGluZSBwb2ludHM9IjggNiAyIDEyIDggMTgiLz48L3N2Zz4=)](https://github.com/Night-Traders-Dev/SageLang)
[![Ollama](https://img.shields.io/badge/Ollama-0.32.1-EE4C2C?style=flat-square&logo=ollama)](https://ollama.ai)
[![Bonsai-8B](https://img.shields.io/badge/Bonsai--8B-Q1_0-22C55E?style=flat-square)](https://huggingface.co/prism-ml/Bonsai-8B-gguf)
[![License](https://img.shields.io/badge/license-MIT-F59E0B?style=flat-square)](LICENSE)
[![Python](https://img.shields.io/badge/build-sagemake-3B82F6?style=flat-square)](#-quick-start)
[![GitHub](https://img.shields.io/github/stars/Night-Traders-Dev/Bonsai_Harness?style=flat-square&logo=github)](https://github.com/Night-Traders-Dev/Bonsai_Harness)

<pre style="background:#1a1b26;color:#a9b1d6;padding:16px;border-radius:12px;font-family:'JetBrains Mono',monospace;line-height:1.5">
┌─ You
│ What files are in the current directory?
└─

┌─ Bonsai
│ I'll check the filesystem to find out.

┌─ Tool: bash
│ command = ls -la
└─

┌─ Result
│ total 48
│ drwxr-xr-x  5 user user  160 ...
│ -rw-r--r--  1 user user 2112 main.sage
│ drwxr-xr-x  2 user user  160 lib/
└─

┌─ Bonsai
│ Here are the files in the current directory...
└─
</pre>

</div>

---

## ✨ Features

- **🤖 ReAct Agent Loop** — Plan, act, observe, reason. Up to 6 iterations per query.
- **🛠️ 7 Built-in Tools** — `bash`, `read_file`, `write_file`, `grep`, `glob`, `list_dir`, `web_fetch`
- **🎨 Streaming TUI** — Colored box-drawing terminal UI with ANSI formatting
- **⚡ JIT Compilation** — Profile-guided native code via SageLang's JIT runtime
- **🔌 Ollama Integration** — HTTP streaming JSON API with chunked transfer support
- **🧠 Bonsai-8B** — Lightweight 8B-parameter Q1_0 quantized model

---

## 📋 Prerequisites

| Dependency | Version | Install |
|-----------|---------|---------|
| SageLang | ≥ 4.0.9 | `curl -sSf https://raw.githubusercontent.com/Night-Traders-Dev/SageLang/main/install.sh \| sh` |
| Ollama | ≥ 0.32.1 | `curl -fsSL https://ollama.com/install.sh \| sh` |
| Bonsai-8B | Q1_0 | `ollama pull hf.co/prism-ml/Bonsai-8B-gguf:Q1_0` |

---

## 🚀 Quick Start

```bash
# 1. Clone and enter
git clone https://github.com/Night-Traders-Dev/Bonsai_Harness.git
cd Bonsai_Harness

# 2. Start Ollama (if not already running)
ollama serve

# 3. Pull the model
ollama pull hf.co/prism-ml/Bonsai-8B-gguf:Q1_0

# 4. Launch the harness
./sagemake run
# or directly:
sage --runtime jit main.sage
```

---

## 🎮 Commands

| Command | Action |
|---------|--------|
| `:quit` / `:exit` | Exit the harness |
| `:clear` | Clear screen |
| `:help` | Show command help |
| `:history` | Show conversation history count |

---

## 🏗️ Project Structure

```
Bonsai_Harness/
├── main.sage              # Entry point — event loop and callbacks
├── sagemake               # Python build/run CLI
├── lib/
│   ├── agent.sage         # ReAct loop, prompt, tool-call parsing
│   ├── ollama.sage        # Ollama HTTP client (chat, stream, JSON)
│   ├── tools.sage         # Tool registry and implementations
│   ├── tui.sage           # ANSI terminal UI components
│   └── http_client.sage   # Low-level TCP HTTP client
└── src/                   # (reserved for future native extensions)
```

### 📦 Module Map

| Module | Role | Key Procs |
|--------|------|-----------|
| `lib.agent` | Agent loop | `run_agent`, `init_history`, `parse_text_tool_call` |
| `lib.ollama` | Ollama API | `chat`, `chat_simple`, `send_and_stream`, `build_request` |
| `lib.tools` | Tool system | `register_tool`, `execute_tool`, `get_tool_list` |
| `lib.tui` | Terminal UI | `print_banner`, `print_user_msg`, `print_token`, `print_tool_call` |
| `lib.http_client` | HTTP | `http_post`, `http_post_raw`, `read_line` |

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
| `web_fetch` | Fetch URL (HTTP) | `url` (string) |

---

## 🔧 Build System

The `sagemake` script provides a complete build/run workflow:

```bash
./sagemake build      # Syntax check + lint
./sagemake compile    # AOT+JIT native binary (falls back to run script)
./sagemake run        # Launch with JIT profiling
./sagemake test       # Run self-tests
./sagemake install    # Copy to /usr/local/bin
./sagemake clean      # Remove artifacts
```

---

## 🧠 Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    User      │────▶│   TUI        │────▶│   Agent      │
│  (stdin)     │     │  (lib.tui)   │     │  (lib.agent) │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                 │
                    ┌────────────────────────────┼────────────┐
                    │                            │            │
                    ▼                            ▼            ▼
            ┌──────────────┐            ┌──────────────┐
            │   Ollama     │            │   Tools      │
            │ (lib.ollama) │            │ (lib.tools)  │
            └──────┬───────┘            └──────┬───────┘
                   │                          │
                   ▼                          ▼
           ┌──────────────┐           ┌──────────────┐
           │  Bonsai-8B   │           │  Linux OS    │
           │  (Ollama)    │           │  (bash, fs)  │
           └──────────────┘           └──────────────┘
```

The agent follows a **ReAct** (Reasoning + Acting) loop:

1. Send conversation history + tool definitions to Ollama
2. Parse response for tool calls or final answer
3. If tool call → execute tool → append result to history → repeat
4. If final answer → display to user → end

---

## 📜 License

MIT — see [LICENSE](LICENSE).

---

<div align="center">
<sub>Built with ❤️ using <a href="https://github.com/Night-Traders-Dev/SageLang">SageLang</a> and <a href="https://ollama.ai">Ollama</a></sub>
</div>
