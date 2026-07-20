# `src/main.sage` — Entry Point

The main program. It wires the modules together, renders the banner, runs the
read-eval-print loop (REPL), dispatches slash-commands, and connects the agent's
callbacks to the TUI.

## Responsibilities

1. Load skills and build the initial conversation history.
2. Print the banner.
3. Loop: read a line, process it, repeat until the user quits.
4. Translate agent events (tokens, tool calls, final answer) into TUI output.

## Startup

```sage
let skills_dir = "skills"
var history = agent.init_history_with_skills(skills.load_skills(skills_dir))
var running = true
```

- `skills.load_skills("skills")` reads every `SKILL.md` under `skills/` and
  returns their concatenated bodies (frontmatter stripped).
- `agent.init_history_with_skills(...)` builds a one-element history whose only
  entry is the system message (base prompt + the injected skills block).
- `history` is a mutable list of message dicts that persists across turns.

## Callbacks

`main.sage` defines three callbacks and passes them into `agent.run_agent`. The
agent invokes them as events occur.

### `on_token(tok)`
Called for every streamed token (content or thinking). Delegates to
`tui.print_token`, which stops the spinner on the first token and then prints
the token in green.

### `on_tool_call(name, args)`
Called twice per tool use:
- once with the **tool name and arguments** when the model requests a tool, and
- once with `name == "result"` and a short summary after the tool runs.

It first calls `tui.print_assistant_footer()` to close the streaming block, then
either `tui.print_tool_result(args)` (for the `"result"` event) or
`tui.print_tool_call(name, args)` (for the request event).

### `on_final(answer)`
Called once when the agent produces its final answer. It calls
`tui.print_assistant_footer()` to terminate the assistant's output block and
then prints the answer text directly via `print`. (The answer text may also
have been streamed via `on_token`; this ensures it is visible even when the
model only emits tool calls and no content tokens.)

## `process_input(line) -> bool`

Handles one line of user input. Returns `true` to keep looping, `false` to quit.

| Input | Behavior |
|-------|----------|
| `:quit` / `:exit` | Returns `false` → the REPL ends. |
| `:clear` | Re-prints the banner (clears the screen). |
| `:help` | Prints the command help via `tui.show_help()`. |
| `:history` | Prints the number of entries in `history`. |
| `:ingest-skills` | Re-loads skills, rebuilds `history`, and reports how many skill files were ingested. |
| `""` (empty) | Ignored; loop continues. |
| anything else | Treated as a prompt: render it, start the assistant block, and call `agent.run_agent`. |

The `:ingest-skills` branch is the runtime hot-reload path:

```sage
if trimmed == ":ingest-skills":
    let count = skills.load_skills(skills_dir)
    history = agent.init_history_with_skills(skills.get_skills_content())
    ...
```

Note that rebuilding `history` from scratch resets the conversation to just the
(updated) system prompt — this is intentional, so newly-edited skills take full
effect.

## The REPL

```sage
tui.print_banner()

while running:
    let line = tui.get_input()
    running = process_input(line)

print ""
print "Goodbye!"
```

`tui.get_input()` prints the `>` prompt and reads a line. Each iteration calls
`process_input`; when it returns `false`, the loop exits and a goodbye message
is printed.

## Extending

- **Add a command:** add another `if trimmed == ":yourcmd":` branch in
  `process_input`, and document it in `tui.show_help()`.
- **Change what streams to the screen:** modify the callbacks. For example, to
  suppress thinking tokens you would filter inside `on_token` (though the current
  design shows them to give the user insight into the model's reasoning).
- **Persist conversations:** serialize `history` to disk in `process_input`
  before/after each turn.

## Related

- [agent.md](agent.md) — what `run_agent` does with the callbacks.
- [tui.md](tui.md) — the rendering functions used here.
- [skills.md](skills.md) — `load_skills` / `get_skills_content`.
