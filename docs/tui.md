# `lib/tui.sage` — Terminal UI

This module renders everything the user sees: the banner, the input prompt, the
user/assistant message blocks, streamed tokens, tool calls and their results,
and a non-blocking animated "thinking" spinner. It uses raw ANSI escape codes —
no external TUI dependency.

## ANSI palette

The module defines named color/style constants using **hex** escape codes
(`\x1b[...m`), e.g.:

```sage
let RESET = "\x1b[0m"
let BOLD  = "\x1b[1m"
let GREEN = "\x1b[32m"
let CYAN  = "\x1b[36m"
```

> **SageLang note:** string literals do **not** support the `\033` octal escape;
> the ANSI introducer must be written as the hex escape `\x1b`.

Available: `RESET`, `BOLD`, `DIM`, the eight standard foreground colors, and the
eight bright variants (`BRIGHT_RED` … `BRIGHT_CYAN`), plus `GRAY`.

## The threaded spinner

While the agent waits for the model's first token, a background thread animates a
Braille spinner so the UI doesn't look frozen.

### State
```sage
var _thinking = false           # is the assistant "thinking" right now?
var _spinner_thread = nil       # handle to the spawned thread
var _spinner_running = false    # shared stop-flag (guarded by the mutex)
let _spinner_lock = thread.mutex()
```

### `_spinner_loop()`
The thread body. It cycles through ten Braille frames, writing
`\r  <frame> thinking...` to stdout every **0.08 s** (`thread.sleep` takes
**seconds**). Each iteration it reads `_spinner_running` under the mutex; when
that becomes false it clears the line (`\r\x1b[K`) and exits.

### `start_spinner()`
Sets `_spinner_running = true` (under the lock) and spawns `_spinner_loop` with
`thread.spawn`.

### `stop_spinner()`
Sets `_spinner_running = false` (under the lock) and, if the thread was running,
`thread.join`s it so the animation is fully cleaned up before anything else is
printed. This prevents the spinner from racing with real output.

## Output primitives

| Proc | Effect |
|------|--------|
| `print_raw(text)` | Write text to stdout with no newline (`sys.stdout_write`). |
| `print_nl()` | Write a newline. |
| `clear_screen()` | Clear the screen and home the cursor (`\x1b[2J\x1b[H`). |

## Screen sections

### `show_header()` / `print_banner()`
`show_header` draws the cyan boxed title ("⚡ Bonsai Agent Harness" + subtitle).
`print_banner` clears the screen, draws the header, and prints the "type a
message or :help" hint. `:clear` in the REPL calls `print_banner`.

### `print_user_msg(text)`
Renders the user's message with a blue `┃` gutter and blank lines around it.

### `print_assistant_header()`
Marks the start of an assistant turn: sets `_thinking = true` and starts the
spinner. Called by `main.sage` just before `agent.run_agent`.

### `print_token(tok)`
Renders one streamed token. On the **first** token it stops the spinner, clears
the spinner line, and switches to green output; subsequent tokens are just
printed green. This is the `on_token` callback's target.

### `print_assistant_footer()`
Ends the assistant turn: stops the spinner if still running and prints a newline.
Called before tool output and at the final answer.

## Tool rendering

### `print_tool_call(name, args_json)`
Prints a bold, color-coded `⚡ <name>` line followed by the arguments. If
`args_json` is a dict it prints each `key=value` dimmed; if a string it prints it
inline. The color comes from `_tool_color`.

### `_tool_color(name) -> ansi`
Maps each tool to a distinct color (bash→yellow, read_file→blue,
write_file→magenta, grep→cyan, glob→red, list_dir→green, web_fetch→magenta;
default yellow) so tool activity is visually scannable.

### `print_tool_result(result)`
Prints the tool's output in a gray `│`-gutter block. For outputs longer than
**12** lines it shows the first 6 lines, a `... (N lines)` marker, and the last 6
lines — keeping long results readable without flooding the screen.

## Help & input

### `show_help()`
Prints the list of slash-commands (`:quit`/`:exit`, `:clear`, `:help`,
`:history`, `:ingest-skills`) with cyan highlighting.

### `get_input() -> string`
Prints the bold `> ` prompt and returns a line read with `input()`.

## Interaction sequence

```
print_assistant_header()   → spinner starts
   ... (waiting) ...
print_token("The")         → spinner stops, "The" prints green
print_token(" answer")     → " answer" prints green
   ... more tokens ...
print_assistant_footer()   → newline, turn ends
```

For a tool call the sequence interleaves `print_assistant_footer()`,
`print_tool_call(...)`, then `print_tool_result(...)` before the next model turn.

## Extending

- **Recolor:** edit the palette constants or `_tool_color`.
- **Change the spinner:** edit the `frames` list or the sleep interval in
  `_spinner_loop`.
- **Adjust result truncation:** change the `12` / `6` thresholds in
  `print_tool_result`.

## Related

- [main.md](main.md) — the callbacks that drive these functions.
- [architecture.md](architecture.md) §6 — the concurrency model.
