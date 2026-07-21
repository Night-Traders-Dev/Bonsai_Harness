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
            # consume escape sequence: ESC [ params... final
            # final byte is in range 0x40-0x7e (ASCII letter)
            # parameter / intermediate bytes 0x20-0x3f
            i = i + 1
            while i < n:
                let ec = ord(slice(text, i, i + 1))
                i = i + 1
                if ec >= 0x40 and ec <= 0x7e:
                    break  # final byte — escape sequence ends
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

proc print_raw(text):
    sys.stdout_write(text)

proc print_nl():
    sys.stdout_write("\n")

proc clear_screen():
    print_raw("\x1b[2J\x1b[H")

proc show_header():
    print_raw(CYAN + "╭──────────────────────────────────────────╮\n" + RESET)
    print_raw(CYAN + "│ " + RESET + BOLD + "⚡ Bonsai Agent Harness" + RESET + "                  " + CYAN + "│\n" + RESET)
    print_raw(CYAN + "│ " + RESET + DIM + "SageLang + Ollama + Bonsai 4B + MiniCPM5" + RESET + "    " + CYAN + "│\n" + RESET)
    print_raw(CYAN + "╰──────────────────────────────────────────╯\n" + RESET)

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
    _thinking = true
    print_raw(DIM + "  thinking..." + RESET)

proc print_token(tok):
    if _thinking:
        print_raw("\r\x1b[K" + GREEN + "  " + RESET)
        _thinking = false
    print_raw(GREEN + strip_ansi(tok) + RESET)

proc print_assistant_footer():
    if _thinking:
        print_raw("\r\x1b[K")
        _thinking = false
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
            print_raw(lines[i])
            print_nl()
        print_raw(GRAY + "  │ ... (" + str(n) + " lines)" + RESET)
        print_nl()
        for i in range(n - 6, n):
            print_raw(GRAY + "  │ " + RESET)
            print_raw(lines[i])
            print_nl()
    else:
        for i in range(n):
            print_raw(GRAY + "  │ " + RESET)
            print_raw(lines[i])
            print_nl()

proc show_help():
    print_nl()
    print_raw(BOLD + "Commands:" + RESET)
    print_nl()
    print_raw("  " + CYAN + ":quit" + RESET + ", " + CYAN + ":exit" + RESET + "     Exit the harness")
    print_nl()
    print_raw("  " + CYAN + ":clear" + RESET + "           Clear screen")
    print_nl()
    print_raw("  " + CYAN + ":help" + RESET + "            Show this help")
    print_nl()
    print_raw("  " + CYAN + ":history" + RESET + "         Show conversation history count")
    print_nl()
    print_raw("  " + CYAN + ":ingest-skills" + RESET + "   Reload skill files from skills/ directory")
    print_nl()
    print_nl()

proc get_input():
    print_raw(BOLD + "> " + RESET)
    let line = input()
    if line == nil:
        return ":quit"
    return line
