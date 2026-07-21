# `lib/ollama.sage` — Ollama HTTP Client

This module is the harness's connection to the model. It builds Ollama
`/api/chat` requests, sends them over a raw TCP socket, parses the responses,
and exposes both a **streaming** and a **one-shot** chat interface. It supports
**dynamic model switching** for the dual-model architecture.

## Configuration

| Variable | Default | Purpose | Set via |
|----------|---------|---------|---------|
| `current_model` | `hf.co/prism-ml/Bonsai-4B-gguf:Q1_0` | The model tag sent to Ollama. | `set_model(name)` |
| `current_host` | `localhost` | Ollama daemon host. | `set_host(host)` |
| `current_port` | `11434` | Ollama daemon port. | `set_port(port)` |
| `GEN_OPTIONS` | JSON fragment | Generation options (see below). | edit source |
| `KEEP_ALIVE` | `"keep_alive":"10m"` | Keeps the model resident between requests. | edit source |

### Model switching

Unlike the original single-model version, the harness now supports dynamically
switching between models mid-session:

```sage
ollama.set_model("hf.co/prism-ml/Bonsai-4B-gguf:Q1_0")  # Bonsai
ollama.set_model("hf.co/GnLOLot/MiniCPM5-1B-Claude-Opus-Fable5-V2-Thinking-GGUF:Q8_0")  # MiniCPM
```

This is used by `lib/model_provider.sage` to switch between the primary
reasoning model (Bonsai 4B) and the tool compiler model (MiniCPM5 1B).

### `GEN_OPTIONS`

```text
"num_ctx":8192,"temperature":0.1,"top_k":40,"top_p":0.9,"min_p":0.05,"repeat_penalty":1.15,"num_predict":2048
```

| Option | Value | Why |
|--------|-------|-----|
| `num_ctx` | 8192 | Use the full context window. |
| `temperature` | 0.1 | Near-greedy, deterministic answers. |
| `top_k` / `top_p` / `min_p` | 40 / 0.9 / 0.05 | Nucleus/top-k sampling to avoid degenerate single-token loops. |
| `repeat_penalty` | 1.15 | Discourage repetition without distorting short answers. |
| `num_predict` | 2048 | Enough room to finish reasoning **and** emit the final answer. |

## Request building

### `json_escape(s) -> string`
Escapes special characters for safe embedding in JSON string literals.

### `build_messages_json(messages) -> string`
Serializes the history list into a JSON array of `{role, content}` objects,
adding `"name"` when a message has one.

### `build_tools_json(tools) -> string`
Serializes tool definitions into the Ollama `tools` array.

### `build_request(messages, tools, stream) -> string`
Assembles the full request body using `current_model`, messages, tools,
`stream` flag, `options`, and `keep_alive`.

## Response parsing

### `parse_response_body(body_str) -> dict`
Parses a complete JSON response into:

```text
{
  "content":    <string>,     # the final answer
  "thinking":   <string>,     # the reasoning trace (may be empty)
  "tool_calls": [ {name, arguments}, ... ],
  "error":      <string>      # only present on failure
}
```

### `answer_text(result) -> string`
Returns the model's actual answer: prefers a non-empty `content`, falls back
to `thinking` when content is empty.

## Streaming path

### `send_and_stream(messages, tools, on_token, on_done) -> string`
The interactive path. Sends a `stream:true` request, reads NDJSON chunks in
real time, calls `on_token()` for each content/thinking token, and
reassembles the final response.

### `chat(messages, tools, on_token, on_done) -> dict`
Convenience wrapper: `send_and_stream` then `parse_response_body`. Called by
`agent.run_agent` for interactive turns.

### `chat_simple(messages, tools) -> dict`
Like `chat` but with an internal token collector.

## One-shot path

### `send_once(messages, tools) -> string`
Sends a `stream:false` request and reads the entire response body at once.

### `ask(messages, tools) -> dict`
Convenience wrapper: `send_once` then `parse_response_body`. Used by the
tool compiler and benchmark for efficient single-response queries.

## Which path should I use?

| Use case | Function | Why |
|----------|----------|-----|
| Interactive agent turn | `chat` | Streams tokens to the TUI. |
| Streamed text, no custom callback | `chat_simple` | Collects `full_content` for you. |
| Batch evaluation / tool compiler | `ask` | One request, minimal allocation, returns clean `content`. |

## Extending

- **Swap models:** call `set_model(name)` — works with any Ollama-served model.
- **Point at a remote Ollama:** change `set_host` / `set_port`.
- **Retune generation:** edit `GEN_OPTIONS`.
- **Add TLS:** the sockets are plain TCP; HTTPS would require a TLS layer.

## Related

- [architecture.md](architecture.md) §9 — model switching.
- [agent.md](agent.md) — the caller of `chat`.
- [benchmark.md](benchmark.md) — the caller of `ask`.
- [http_client.md](http_client.md) — a separate, generic HTTP helper.
