import sys
import io
import thread

# Strip ANSI escape sequences from untrusted text (tool results, model output)
# to prevent terminal injection attacks. Only the harness's own styling codes
# (which are applied outside this function) are safe.
proc strip_ansi(text):
    var out = ""
    var i = 0
    let n = len(text)
    while i < n:
        let c = slice(text, i, i + 1)
        if c == "\x1b":
            i = i + 1
            if i < n and slice(text, i, i + 1) == "[":
                i = i + 1
                while i < n:
                    let ec = ord(slice(text, i, i + 1))
                    i = i + 1
                    if ec >= 0x40 and ec <= 0x7e:
                        break
            else:
                while i < n:
                    let ec = ord(slice(text, i, i + 1))
                    i = i + 1
                    if ec >= 0x40 and ec <= 0x7e:
                        break
        else:
            out = out + c
            i = i + 1
    return out

let RESET = "\x1b[0m"
let BOLD = "\x1b[1m"
let DIM = "\x1b[2m"
let RED = "\x1b[31m"
let GREEN = "\x1b[32m"
let YELLOW = "\x1b[33m"
let BLUE = "\x1b[34m"
let MAGENTA = "\x1b[35m"
let CYAN = "\x1b[36m"
let GRAY = "\x1b[90m"
let BRIGHT_RED = "\x1b[91m"
let BRIGHT_GREEN = "\x1b[92m"
let BRIGHT_YELLOW = "\x1b[93m"
let BRIGHT_BLUE = "\x1b[94m"
let BRIGHT_MAGENTA = "\x1b[95m"
let BRIGHT_CYAN = "\x1b[96m"

var _thinking = false
var _spinner_idx = 0
var _in_think_block = false

proc tick_spinner():
    if _thinking:
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let f = frames[_spinner_idx % len(frames)]
        _spinner_idx = _spinner_idx + 1
        sys.stdout_write("\r\x1b[K  " + CYAN + f + RESET + DIM + " thinking..." + RESET)

proc stop_spinner():
    if _thinking:
        sys.stdout_write("\r\x1b[K")
        _thinking = false
        _spinner_idx = 0

proc print_raw(text):
    sys.stdout_write(text)

proc print_nl():
    sys.stdout_write("\n")

proc clear_screen():
    print_raw("\x1b[2J\x1b[H")

proc show_header():
    print_raw(CYAN + "╭──────────────────────────────────────────────╮\n" + RESET)
    print_raw(CYAN + "│ " + RESET + BOLD + "⚡ Bonsai Agent Harness" + RESET + "                      " + CYAN + "│\n" + RESET)
    print_raw(CYAN + "│ " + RESET + DIM + "SageLang + Ollama + Bonsai 4B + MiniCPM5" + RESET + "     " + CYAN + "│\n" + RESET)
    print_raw(CYAN + "╰──────────────────────────────────────────────╯\n" + RESET)

proc print_banner():
    clear_screen()
    show_header()
    print_raw(DIM + "type a message or :help for commands\n" + RESET)

proc print_user_msg(text):
    print_nl()
    print_raw(BLUE + "┃ " + RESET)
    print_raw(text)
    print_nl()
    print_nl()

proc print_assistant_header():
    stop_spinner()
    _thinking = true
    _spinner_idx = 0
    tick_spinner()

proc print_token(tok):
    stop_spinner()

    let clean_tok = strip_ansi(tok)

    if contains(clean_tok, "<think>"):
        if not _in_think_block:
            _in_think_block = true
            print_raw(DIM + GRAY + "💭 Reasoning:\n  " + RESET)
        let rest = replace(clean_tok, "<think>", "")
        if len(rest) > 0:
            print_raw(DIM + GRAY + rest + RESET)
        return

    if contains(clean_tok, "</think>"):
        let parts = split(clean_tok, "</think>")
        if len(parts) >= 1 and len(parts[0]) > 0:
            print_raw(DIM + GRAY + parts[0] + RESET)
        print_nl()
        _in_think_block = false
        if len(parts) >= 2 and len(parts[1]) > 0:
            print_raw(GREEN + parts[1] + RESET)
        return

    if _in_think_block:
        print_raw(DIM + GRAY + clean_tok + RESET)
    else:
        print_raw(GREEN + clean_tok + RESET)

proc print_assistant_footer():
    stop_spinner()
    _in_think_block = false
    print_nl()

proc print_tool_call(name, args_json):
    print_nl()
    let color = _tool_color(name)
    print_raw(color + BOLD + "⚡ " + name + RESET)
    if type(args_json) == "dict":
        let keys = dict_keys(args_json)
        for k in keys:
            let val_str = str(args_json[k])
            print_raw(DIM + " " + k + "=" + strip_ansi(val_str) + RESET)
    elif type(args_json) == "string":
        print_raw(" " + strip_ansi(args_json))
    print_nl()

proc _tool_color(name):
    if name == "bash": return YELLOW
    if name == "read_file": return BLUE
    if name == "write_file": return MAGENTA
    if name == "grep": return CYAN
    if name == "glob": return RED
    if name == "list_dir": return GREEN
    if name == "web_fetch": return MAGENTA
    return YELLOW

proc print_tool_result(result):
    let clean = strip_ansi(result)
    let lines = split(clean, "\n")
    let n = len(lines)
    if n > 12:
        for i in range(6):
            print_raw(GRAY + "  │ " + RESET)
            var ltext = lines[i]
            if len(ltext) > 74:
                ltext = slice(ltext, 0, 71) + "..."
            print_raw(ltext)
            print_nl()
        print_raw(GRAY + "  │ ... (" + str(n) + " lines)" + RESET)
        print_nl()
        for i in range(n - 6, n):
            print_raw(GRAY + "  │ " + RESET)
            var ltext = lines[i]
            if len(ltext) > 74:
                ltext = slice(ltext, 0, 71) + "..."
            print_raw(ltext)
            print_nl()
    else:
        for i in range(n):
            print_raw(GRAY + "  │ " + RESET)
            var ltext = lines[i]
            if len(ltext) > 74:
                ltext = slice(ltext, 0, 71) + "..."
            print_raw(ltext)
            print_nl()

var input_history = []
var eof_count = 0

let BUILTIN_COMMANDS = [":help", ":clear", ":history", ":models", ":ingest-skills", ":bench", ":quit", ":exit"]

proc add_to_input_history(line):
    let trimmed = strip(line)
    if trimmed != "" and not startswith(trimmed, ":"):
        var exists = false
        for item in input_history:
            if item == trimmed:
                exists = true
        if not exists:
            push(input_history, trimmed)

proc find_suggestion(prefix):
    let p = strip(prefix)
    if p == "":
        return ""

    if startswith(p, ":"):
        for cmd in BUILTIN_COMMANDS:
            if startswith(cmd, p) and cmd != p:
                return cmd
    else:
        for item in input_history:
            if startswith(lower(item), lower(p)) and item != p:
                return item
    return ""

proc show_help():
    print_nl()
    print_raw(BOLD + "Commands & Shortcuts:" + RESET)
    print_nl()
    print_raw("  " + CYAN + ":clear" + RESET + " (or " + BOLD + "Ctrl+L" + RESET + ")     Clear screen")
    print_nl()
    print_raw("  " + CYAN + ":help" + RESET + "                 Show this help menu")
    print_nl()
    print_raw("  " + CYAN + ":history" + RESET + "              Show conversation history count")
    print_nl()
    print_raw("  " + CYAN + ":models" + RESET + "               Show active model configuration")
    print_nl()
    print_raw("  " + CYAN + ":ingest-skills" + RESET + "        Reload skill files from skills/ directory")
    print_nl()
    print_raw("  " + CYAN + ":quit" + RESET + " / " + CYAN + ":exit" + RESET + "         Exit the harness")
    print_nl()
    print_raw("  " + BOLD + "Tab" + RESET + "                   Autocomplete command or history suggestion")
    print_nl()
    print_raw("  " + BOLD + "Esc" + RESET + " / " + BOLD + "Ctrl+C" + RESET + "            Interrupt active query without exiting")
    print_nl()
    print_raw("  " + BOLD + "Ctrl+D" + RESET + " (twice)        Exit harness and unload models to free RAM")
    print_nl()
    print_nl()

proc get_input():
    print_raw(BOLD + "> " + RESET)
    let line = input()

    if line == nil:
        eof_count = eof_count + 1
        if eof_count == 1:
            print_raw(DIM + " (Press Ctrl+D again to exit & unload RAM)\n" + RESET)
            return ""
        eof_count = 0
        return ":quit-unload"

    eof_count = 0

    if contains(line, "\x03") or contains(line, "\x1b"):
        print_raw(YELLOW + "^C\n" + RESET)
        return ""

    if contains(line, "\x0c") or strip(line) == ":clear" or strip(line) == ":c" or strip(line) == ":cl":
        clear_screen()
        show_header()
        return ""

    if contains(line, "\t"):
        let parts = split(line, "\t")
        let prefix = parts[0]
        let match = find_suggestion(prefix)
        if match != "":
            print_raw(GRAY + " → " + match + RESET + "\n")
            add_to_input_history(match)
            return match
        return prefix

    let trimmed = strip(line)

    if startswith(trimmed, ":clear"):
        clear_screen()
        show_header()
        return ""

    add_to_input_history(trimmed)
    return line
