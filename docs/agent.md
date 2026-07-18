# `lib/agent.sage` — The ReAct Agent Loop

This module is the brain of the harness. It owns the conversation history, the
system prompt, the tool-call parsing, and the iterative ReAct loop that drives
the model to call tools and eventually produce an answer.

## Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `MAX_ITERATIONS` | `6` | Maximum number of model turns per user query. Guarantees the loop terminates. |
| `MAX_HISTORY_CHARS` | `8000` | Character budget for trimming old messages (excludes the always-kept system prompt). |
| `SYSTEM_PROMPT` | (string) | The base instructions given to the model on every request. |

### `SYSTEM_PROMPT`

Tells the model it is "Bonsai", lists the available tools, and lays out rules:
use tools when information is needed, be thorough, give complete answers, and
**explain reasoning step by step before calling a tool**. The last rule
encourages the visible "thinking" that the TUI streams.

## Message shape

History is a list of dicts. Every message has at least:

```
{ "role": "system" | "user" | "assistant" | "tool", "content": <string> }
```

Tool-result messages additionally carry `"name": <tool_name>`.

## Procedures

### `init_history() -> list`
Builds a fresh history containing only the base system prompt. Used when no
skills are supplied.

### `init_history_with_skills(skills_content) -> list`
Builds a history whose system message is the base prompt **plus** an injected
skills block:

```
<SYSTEM_PROMPT>

=== Loaded Skills ===
<skills_content>
=== End Skills ===
```

If `skills_content` is `nil` or empty, the block is omitted and the result is
identical to `init_history()`. This is the function `main.sage` uses at startup
and on `:ingest-skills`.

### `trim_history(history)`
Keeps the conversation within `MAX_HISTORY_CHARS`. It **always keeps index 0**
(the system prompt) and then walks the history **from newest to oldest**, keeping
each message whose content fits the remaining budget. Older messages that don't
fit are dropped. If nothing else fits, it forcibly keeps the most recent message
so the model still sees the latest turn. The history list is mutated in place.

This is an approximate, tokenizer-free heuristic — it counts characters, not
tokens — chosen for speed and zero dependencies.

### `parse_text_tool_call(content) -> dict`
A fallback parser for models that emit tool calls as **plain text** instead of
native `tool_calls`. It scans each line for three prefixes (case-insensitive):

| Prefix | Sets | Meaning |
|--------|------|---------|
| `FUNCTION:` | `has_tool_call = true`, `name` | The tool to call. |
| `ARGUMENTS:` | `arguments` | JSON args (parsed with `cJSON_Parse`; falls back to the raw string if parsing fails). |
| `FINAL:` | `has_final = true`, `final_answer` | The model's final answer. |

Returns a dict with `has_tool_call`, `has_final`, and (when present) `name`,
`arguments`, `final_answer`.

### `run_agent(user_input, history, on_token, on_tool_call, on_final)`
The main loop. Steps:

1. Append the user message to `history`.
2. Fetch tool schemas via `tools.get_tool_list()`.
3. Loop up to `MAX_ITERATIONS` times:
   1. `trim_history(history)`.
   2. Call `ollama.chat(history, tool_defs, on_token, nil)` (streaming if
      `on_token` is provided, else non-streaming).
   3. **Error?** Append an error assistant message, call `on_final` with the
      error, and return.
   4. **Native tool call?** (`response["tool_calls"]` non-empty)
      - Append the assistant message.
      - `on_tool_call(name, args)`.
      - `tools.execute_tool(name, args)`.
      - Append a `role: "tool"` message: `TOOL RESULT (<name>):\n<result>`.
      - `on_tool_call("result", "<name> (<n> chars)")`.
      - Continue the loop.
   5. **Text-based tool call?** (parsed from content) — same handling as above,
      but the tool call came from `parse_text_tool_call`.
   6. **Final answer via `FINAL:`** — append it, call `on_final`, return.
   7. **Plain content, no tool call** — treat it as the final answer, call
      `on_final`, return.
   8. **Empty content** — treat as final (empty), call `on_final`, return.
4. If the loop exhausts `MAX_ITERATIONS`, append and return a "Maximum
   iterations reached. Please refine your question." message.

#### Callback contract

`run_agent` never prints anything itself — all output goes through the three
callbacks, which the caller (`main.sage`) maps to the TUI. This keeps the agent
UI-agnostic and testable.

| Callback | When | Argument |
|----------|------|----------|
| `on_token(tok)` | per streamed token | the token string |
| `on_tool_call(name, args)` | tool requested, and again after it runs (`name == "result"`) | name + args, or `"result"` + summary |
| `on_final(answer)` | once, at the end | the final answer string |

Any callback may be `nil`; the agent guards each call.

## Example: a two-step turn

```
user: "How many .sage files are in lib?"

iter 0: model → tool_call glob {"pattern": "lib/*.sage"}
        → execute_tool → "lib/agent.sage\nlib/ollama.sage\n..."
        → history gains a tool result
iter 1: model → "There are 7 .sage files in lib." (final)
        → on_final("There are 7 .sage files in lib.")
```

## Extending

- **Change the persona / rules:** edit `SYSTEM_PROMPT`.
- **Allow more tool round-trips:** raise `MAX_ITERATIONS`.
- **Use a real token budget:** replace the character counting in
  `trim_history` with a tokenizer-based measure.
- **Support multiple tool calls per turn:** the loop currently handles
  `tool_calls[0]`; extend it to iterate over all returned calls.

## Related

- [ollama.md](ollama.md) — `chat`, response shape.
- [tools.md](tools.md) — `get_tool_list`, `execute_tool`.
- [main.md](main.md) — how the callbacks are wired.
