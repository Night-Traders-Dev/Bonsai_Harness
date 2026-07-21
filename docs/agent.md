# `lib/agent.sage` — The Dual-Model ReAct Agent Loop

This module is the brain of the harness. It owns the conversation history, the
system prompt, the tool-call parsing, and the iterative ReAct loop that drives
the dual-model architecture — **Bonsai 4B** for reasoning and **MiniCPM5 1B**
for tool compilation.

## Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `MAX_ITERATIONS` | `6` | Maximum number of model turns per user query. |
| `MAX_HISTORY_CHARS` | `8000` | Character budget for trimming old messages. |
| `MAX_TOOL_RETRIES` | `2` | Retry attempts when MiniCPM tool compilation fails. |
| `SYSTEM_PROMPT` | (string) | Base instructions given to the model. |

### `SYSTEM_PROMPT`

Tells Bonsai it is "Bonsai", lists the available tools, and lays out rules:
use tools when information is needed, be thorough, give complete answers, and
**explain reasoning step by step before calling a tool**.

## Message shape

History is a list of dicts. Every message has at least:

```text
{ "role": "system" | "user" | "assistant" | "tool", "content": <string> }
```

Tool-result messages additionally carry `"name": <tool_name>`.

## Procedures

### `init_history() -> list`
Builds a fresh history containing only the base system prompt.

### `init_history_with_skills(skills_content) -> list`
Builds a history whose system message is the base prompt **plus** an injected
skills block:

```text
<SYSTEM_PROMPT>

=== Loaded Skills ===
<skills_content>
=== End Skills ===
```

### `trim_history(history)`
Keeps the conversation within `MAX_HISTORY_CHARS`. Always keeps index 0
(system prompt) and the most recent messages that fit the budget.

### `parse_text_tool_call(content) -> dict`
A fallback parser for models that emit tool calls as **plain text**. Scans
each line for three prefixes (case-insensitive):

| Prefix | Sets | Meaning |
|--------|------|---------|
| `FUNCTION:` | `has_tool_call = true`, `name` | The tool to call. |
| `ARGUMENTS:` | `arguments` | JSON args (parsed with `cJSON_Parse`). |
| `FINAL:` | `has_final = true`, `final_answer` | The model's final answer. |

### `_cjson_get_str(cj, key) -> string`
Extracts a string value from a cJSON object by key.

### `_cjson_into_dict(cj, target)`
Copies known argument keys (`path`, `content`, `pattern`, `url`, `command`)
from a cJSON object into a SageLang dict.

### `build_tool_result_entry(name, result) -> dict`
Creates a `role: "tool"` history entry with the tool name and result.

### `handle_tool_call(tc_name, tc_args_raw, history, on_tool_call) -> list`
Executes a tool call directly (fallback path). Handles both `dict` and
`arguments_str` argument formats. Calls `on_tool_call` before and after
execution.

### `compile_via_minicpm(intent, tool_defs, history, on_tool_call) -> dict`
The core dual-model pipeline. Steps:
1. Passes the intent + tool definitions to `tool_compiler.compile_tool_call()`
2. MiniCPM generates a structured `{name, arguments}` tool call
3. If successful: executes the tool via `handle_tool_call`
4. If failed: calls `on_tool_call("error", ...)` with the error message
Returns `{"ok": true/false, "history": <updated history>}`.

### `run_agent(user_input, history, on_token, on_tool_call, on_final)`
The main loop. Steps:

1. Append user message to history, switch to **Bonsai** as active model.
2. Fetch tool schemas via `tools.get_tool_list()`.
3. Loop up to `MAX_ITERATIONS`:
   1. `trim_history(history)`.
   2. Call `provider.chat(history, tool_defs, on_token, nil)` — Bonsai
      generates a response with access to tool definitions.
   3. **Error?** Append error, call `on_final`, return.
   4. **Native tool call?** (`response["tool_calls"]` non-empty)
      - Append assistant message.
      - Build intent string from the tool name and arguments.
      - **Route through MiniCPM** via `compile_via_minicpm` with up to
        `MAX_TOOL_RETRIES` retries.
      - If MiniCPM fails: fall back to direct execution via
        `handle_tool_call`.
      - Continue the loop.
   5. **Text-based tool call?** (parsed from content)
      - Same dual-model pipeline as native tool calls.
   6. **Final answer via `FINAL:`** — append, call `on_final`, return.
   7. **Plain content** — treat as final answer, call `on_final`, return.
   8. **Empty content** — call `on_final("")`, return.
4. If loop exhausts `MAX_ITERATIONS`: return timeout message.

#### Callback contract

| Callback | When | Argument |
|----------|------|----------|
| `on_token(tok)` | per streamed token | the token string |
| `on_tool_call(name, args)` | tool requested, or `"result"` after execution, or `"error"` on compilation failure | varies |
| `on_final(answer)` | once, at the end | the final answer string |

Any callback may be `nil`; the agent guards each call.

## Dual-model flow

```
Bonsai produces tool call (native or text)
    │
    ▼
Extract intent (tool name + arguments)
    │
    ▼
MiniCPM compiles intent → structured {name, arguments} JSON
    │
    ▼
Tool validator checks schema + security
    │
    ▼
If valid → execute tool → result → back to Bonsai
If invalid → retry (up to 2) → fallback to Bonsai's original call
```

## Related

- [architecture.md](architecture.md) — system design, data flow.
- [ollama.md](ollama.md) — model configuration, streaming.
- [tools.md](tools.md) — tool registry.
- [main.md](main.md) — callback wiring.
