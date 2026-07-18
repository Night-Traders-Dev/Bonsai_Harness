# `lib/tools.sage` — Tool System

This module implements a small tool registry and the seven built-in tools the
agent can call. Every tool is a `(name, description, parameters, execute_fn)`
tuple; the agent discovers them via `get_tool_list()` and invokes them via
`execute_tool(name, args)`.

## The registry

```sage
var tool_registry = {}
```

A dict keyed by tool name. Each entry stores `name`, `description`,
`parameters` (a JSON Schema **string**), and `execute` (the function to run).

### `register_tool(name, description, parameters, execute_fn)`
Adds a tool to the registry. Called once per tool at module load time.

### `get_tool_list() -> list`
Returns a list of `{name, description, parameters}` dicts (without the executable
function) — the shape `lib/ollama.sage` needs to build the request's `tools`
array.

### `execute_tool(name, args_json) -> string`
Looks up `name` and calls its `execute` function with `args_json`. Returns
`"Error: Unknown tool '<name>'"` if the tool isn't registered. Tool functions
always return a **string** (results or an error message), which the agent appends
to history as a `TOOL RESULT`.

## Argument convention

Every `execute` function receives the arguments as a dict and validates them
defensively:

```sage
if type(args) == "dict" and dict_has(args, "command"):
    ...
return "Error: 'command' argument required"
```

Missing/invalid arguments produce a descriptive `Error: ...` string rather than
crashing — the model sees the error and can correct itself.

## The seven built-in tools

### `bash`
Runs a shell command via `sys.shell_exec` and returns its output. Returns
`"Command returned no output"` when the command produces nothing.

- **Args:** `command` (string, required)
- **Use for:** file operations, running scripts, arbitrary system tasks.

### `read_file`
Reads a file with `io.readfile` after checking `io.exists`.

- **Args:** `path` (string, required)
- **Errors:** `"Error: File not found: <path>"`

### `write_file`
Writes `content` to `path` with `io.writefile`.

- **Args:** `path`, `content` (both required)
- **Returns:** `"File written: <path>"`

### `grep`
Searches for a substring pattern across files. If `path` is a directory it walks
it recursively (skipping dot-directories); if it's a file it searches just that
file. Returns up to **20** matches, each formatted `path:lineno:line`.

- **Args:** `pattern` (required), `path` (optional, default `.`)
- **Returns:** matching lines, or `"No matches found"`
- **Note:** matching is substring-based (`indexof`), not full regex, despite the
  "regex" wording in the schema description.

### `glob`
Finds files matching a simple glob. Supports a single `*`:
- `*suffix` → `endswith`
- `prefix*` → `startswith`
- no `*` → exact match

Walks from the current directory recursively (skipping dot-entries).

- **Args:** `pattern` (required)
- **Returns:** matching paths, or `"No matches found"`

### `list_dir`
Lists the entries of a directory with `io.listdir`.

- **Args:** `path` (optional, default `.`)
- **Errors:** `"Error: Not a directory: <path>"`

### `web_fetch`
Fetches an `http://` (or `https://`-prefixed, treated as host) URL over a raw TCP
socket, strips the HTTP headers, and returns the first **4000** characters of the
body. Parses host, optional `:port`, and path from the URL.

- **Args:** `url` (required)
- **Note:** HTTP only — there is no TLS, so `https://` URLs connect on the parsed
  host/port without encryption. For real HTTPS you'd need a TLS layer.

## Registration table

| Tool | Required args | Optional args | Returns |
|------|---------------|---------------|---------|
| `bash` | `command` | — | command output |
| `read_file` | `path` | — | file contents |
| `write_file` | `path`, `content` | — | confirmation |
| `grep` | `pattern` | `path` | up to 20 `path:line:text` matches |
| `glob` | `pattern` | — | matching paths |
| `list_dir` | — | `path` | directory entries |
| `web_fetch` | `url` | — | first 4000 chars of body |

## Adding a new tool

1. Write an `execute` function that takes an args dict and returns a string:

   ```sage
   proc word_count_execute(args):
       if type(args) == "dict" and dict_has(args, "path"):
           let text = io.readfile(args["path"])
           return str(len(split(text, " ")))
       return "Error: 'path' argument required"
   ```

2. Define its JSON Schema as a string and register it:

   ```sage
   let wc_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}"
   register_tool("word_count", "Count words in a file.", wc_params, word_count_execute)
   ```

3. It is now automatically included in `get_tool_list()` and callable by the
   model. Update the system prompt tool list in `lib/agent.sage` and add a test
   in `tests/test_tools.sage`.

## Testing

`tests/test_tools.sage` covers registration, all seven tools (happy path +
missing-argument errors), and the unknown-tool case (23 tests). See
[testing.md](testing.md).

## Related

- [agent.md](agent.md) — how tools are surfaced and executed in the loop.
- [ollama.md](ollama.md) — how `parameters` schemas reach the model.
