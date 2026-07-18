# `lib/http_client.sage` — Generic HTTP POST Client

A small, general-purpose HTTP POST helper built on raw TCP sockets. It supports
both `Content-Length` and chunked `Transfer-Encoding` responses and can stream
response chunks to a callback. It is a standalone utility — the main Ollama path
in `lib/ollama.sage` implements its own inline socket handling — but this module
is a clean, reusable HTTP building block.

## State

```sage
var http_debug = false
```

A module-level debug flag. When on, request/response status lines are printed.

### `http_set_debug(on)`
Toggles `http_debug`.

## Procedures

### `read_line(conn) -> string`
Reads one line from a socket, byte by byte, up to `\n`. Carriage returns (`\r`)
are dropped, and the returned line is `strip`ped. Used to read the HTTP status
line and each header.

### `http_post(host, port, path, body, on_chunk) -> string`
Performs a full HTTP/1.1 `POST`:

1. Builds the request (request line + `Host`, `Content-Type: application/json`,
   `Content-Length`, `Accept: application/json`, `Connection: close`) and appends
   `body`.
2. Optionally logs `[http] POST <path>` when `http_debug` is on.
3. Connects, sends the request, and reads the status line.
4. Reads headers until the blank line, detecting `Content-Length` and
   `Transfer-Encoding: chunked`.
5. Reads the body:
   - **chunked** — decodes each hex chunk size, reads that many bytes plus the
     trailing `\r\n`, appends to `full_body`, and (if provided) calls
     `on_chunk(chunk)` per chunk. A zero-size chunk ends the body.
   - **`Content-Length`** — reads exactly that many bytes.
   - **neither** — reads 4 KB at a time until the socket closes, calling
     `on_chunk` for each read.
6. Closes the socket and returns the full body string.

**Parameters**

| Param | Meaning |
|-------|---------|
| `host` | server hostname |
| `port` | server port |
| `path` | request path (e.g. `/api/chat`) |
| `body` | request body (JSON string) |
| `on_chunk` | optional callback called with each body chunk; pass `nil` to buffer only |

**Returns:** the complete response body as a string (headers stripped).

### `http_post_raw(host, port, path, body) -> string`
Convenience wrapper: `http_post` with `on_chunk = nil` (buffer the whole
response, no streaming callback).

## Usage example

```sage
import lib.http_client as http

let body = "{\"key\":\"value\"}"
let resp = http.http_post_raw("localhost", 8080, "/api", body)
print resp
```

Streaming variant:

```sage
proc on_chunk(c):
    print "got chunk of " + str(len(c)) + " bytes"

http.http_post("localhost", 8080, "/api", body, on_chunk)
```

## Relationship to `lib/ollama.sage`

`lib/ollama.sage` does **not** use this module — it inlines its own socket read
loops in `send_and_stream` and `send_once` because it needs fine-grained,
incremental NDJSON parsing during streaming. `http_client.sage` is the
general-purpose alternative for simpler request/response needs and is a good
starting point if you add new HTTP integrations.

## Limitations

- **HTTP only** — plain TCP, no TLS.
- **POST only** — no GET/PUT/DELETE helpers (add them following the same pattern).
- Assumes the server honors `Connection: close`.

## Related

- [ollama.md](ollama.md) — the specialized, streaming Ollama client.
- [tools.md](tools.md) — `web_fetch` uses a similar raw-socket approach for GET.
