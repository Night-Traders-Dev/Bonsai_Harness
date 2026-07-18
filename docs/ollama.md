# `lib/ollama.sage` — Ollama HTTP Client

This module is the harness's connection to the model. It builds Ollama
`/api/chat` requests, sends them over a raw TCP socket, parses the responses,
and exposes both a **streaming** and a **one-shot** chat interface. It also owns
the generation options that tune Bonsai-8B's behavior.

## Configuration

| Constant | Value | Purpose |
|----------|-------|---------|
| `DEFAULT_MODEL` | `hf.co/prism-ml/Bonsai-8B-gguf:Q1_0` | The model tag sent to Ollama. |
| `OLLAMA_HOST` | `localhost` | Ollama daemon host. |
| `OLLAMA_PORT` | `11434` | Ollama daemon port. |
| `GEN_OPTIONS` | JSON fragment | Generation options (see below). |
| `KEEP_ALIVE` | `"keep_alive":"10m"` | Keeps the model resident between requests. |

### `GEN_OPTIONS`

```
"num_ctx":8192,"temperature":0.1,"top_k":40,"top_p":0.9,"min_p":0.05,"repeat_penalty":1.15,"num_predict":2048
```

| Option | Value | Why |
|--------|-------|-----|
| `num_ctx` | 8192 | Use the full context window. |
| `temperature` | 0.1 | Near-greedy, deterministic answers. |
| `top_k` / `top_p` / `min_p` | 40 / 0.9 / 0.05 | Nucleus/top-k sampling to avoid the degenerate single-token loops a 1-bit quant is prone to. |
| `repeat_penalty` | 1.15 | Discourage repetition without distorting short answers (a harsher 1.3 was found to hurt terse outputs). |
| `num_predict` | 2048 | Enough room to finish reasoning **and** emit the final answer. A small cap truncates mid-thinking and yields empty content. |

The options are kept as a single string fragment so the streaming and
non-streaming paths produce byte-identical requests.

## Request building

### `json_escape(s) -> string`
Escapes `\`, `"`, newline, and tab for safe embedding in JSON string literals.

### `build_messages_json(messages) -> string`
Serializes the history list into a JSON array of `{role, content}` objects,
adding `"name"` when a message has one (used for tool-result messages).

### `build_tools_json(tools) -> string`
Serializes tool definitions into the Ollama `tools` array
(`{"type":"function","function":{name, description, parameters}}`). Returns an
empty string when there are no tools. Each tool's `parameters` is already a JSON
string (the JSON Schema) and is inlined verbatim.

### `build_request(messages, tools, stream) -> string`
Assembles the full request body: model, messages, tools, `stream` flag,
`options` (from `GEN_OPTIONS`), and `keep_alive`. Used by both request paths.

## Response parsing

### `parse_response_body(body_str) -> dict`
Parses a **complete** (non-streaming or reassembled) JSON response into:

```
{
  "content":    <string>,     # the final answer
  "thinking":   <string>,     # the reasoning trace (may be empty)
  "tool_calls": [ {name, arguments}, ... ],
  "error":      <string>      # only present on failure
}
```

It reads the `message` object, pulls `content` and `thinking` separately (they
are kept distinct — this is important, see `answer_text`), and walks
`tool_calls`, extracting each function's `name` and JSON-parsed `arguments`. All
cJSON handles are freed with `cJSON_Delete`.

Error cases set `result["error"]`: JSON parse failure, an `error` field in the
response, or a missing `message`.

### `answer_text(result) -> string`
Returns the model's **actual answer**: prefers a non-empty `content`, and only
falls back to `thinking` when `content` is genuinely empty. This is what lets
callers (notably the benchmark) score the real answer instead of a truncated
reasoning trace. Separating `content` from `thinking` in `parse_response_body`
and preferring `content` here was the single biggest correctness fix in the
project.

## Streaming path

### `send_and_stream(messages, tools, on_token, on_done) -> string`
The interactive path. It:

1. Builds a `stream:true` request and sends it over a TCP socket with a manual
   HTTP request line + headers.
2. Reads the status line and headers, detecting `Content-Length` vs
   `Transfer-Encoding: chunked`.
3. Reads the body. For chunked transfers it decodes each hex chunk size, reads
   that many bytes, and feeds them to the incremental parser.
4. **`flush_parse_buf(buf)`** (a nested proc) splits the buffer on newlines,
   parses each complete NDJSON line, and for each line:
   - emits any `content` token via `on_token` (accumulating into `full_content`),
   - emits any `thinking` token via `on_token` (also accumulated), so reasoning
     streams to the UI too,
   - collects any `tool_calls`.
   It returns the trailing partial line to be prepended to the next buffer.
5. After the stream ends, it reassembles a single `{message:{...}}` JSON string
   (content + any tool calls) and, if provided, calls `on_done(final_body)`.
6. Returns that reassembled body.

The reassembled body is deliberately in the same shape as a non-streaming
response, so it can be handed straight to `parse_response_body`.

### `chat(messages, tools, on_token, on_done) -> dict`
Convenience wrapper: `send_and_stream` then `parse_response_body`. This is what
`agent.run_agent` calls.

### `chat_simple(messages, tools) -> dict`
Like `chat` but with an internal token collector; the full streamed text is also
returned under `result["full_content"]`. Useful when you want the streamed text
without supplying your own `on_token`.

## One-shot path

### `send_once(messages, tools) -> string`
Sends a `stream:false` request and reads the entire response body (chunked or
`Content-Length`), returning the raw JSON string. Lighter on allocations than the
streaming path — preferred for batch work.

### `ask(messages, tools) -> dict`
Convenience wrapper: `send_once` then `parse_response_body`. This is what the
benchmark uses (`lib/benchmark.sage`).

## Which path should I use?

| Use case | Function | Why |
|----------|----------|-----|
| Interactive agent turn | `chat` | Streams tokens to the TUI. |
| Streamed text, no custom callback | `chat_simple` | Collects `full_content` for you. |
| Batch evaluation / scripting | `ask` | One request, minimal allocation, returns clean `content`. |

## Extending

- **Point at a remote Ollama:** change `OLLAMA_HOST` / `OLLAMA_PORT`.
- **Swap models:** change `DEFAULT_MODEL`.
- **Retune generation:** edit `GEN_OPTIONS` (both paths pick it up automatically).
- **Add TLS:** the sockets are plain TCP; HTTPS would require a TLS layer.

## Related

- [architecture.md](architecture.md) §5 — why there are two request paths.
- [agent.md](agent.md) — the caller of `chat`.
- [benchmark.md](benchmark.md) — the caller of `ask` / `answer_text`.
- [http_client.md](http_client.md) — a separate, generic HTTP helper.
