import lib.rich as rich
import sys
import io

let RESET = "\033[0m"
let BOLD = "\033[1m"
let DIM = "\033[2m"
let RED = "\033[31m"
let GREEN = "\033[32m"
let YELLOW = "\033[33m"
let BLUE = "\033[34m"
let MAGENTA = "\033[35m"
let CYAN = "\033[36m"
let GRAY = "\033[90m"
let BRIGHT_RED = "\033[91m"
let BRIGHT_GREEN = "\033[92m"
let BRIGHT_YELLOW = "\033[93m"
let BRIGHT_BLUE = "\033[94m"
let BRIGHT_MAGENTA = "\033[95m"
let BRIGHT_CYAN = "\033[96m"

var _thinking = false
var _spinner_thread = nil
var _spinner_running = false

proc print_raw(text):
    sys.stdout_write(text)

proc print_nl():
    sys.stdout_write("\n")

proc clear_screen():
    print_raw("\033[2J\033[H")

proc show_header():
    let box = rich.panel(
        rich.style("Bonsai Agent Harness", BOLD) + "\n" +
        rich.style("SageLang + Ollama + Bonsai-8B", DIM),
        "rounded", CYAN(), "⚡ Bonsai", "left", 1
    )
    print_raw(box + "\n\n")

proc print_banner():
    clear_screen()
    show_header()
    print_raw(rich.style("type a message or :help for commands", DIM) + "\n")

proc print_user_msg(text):
    print_nl()
    print_raw(rich.style("┃ ", BLUE))
    print_raw(text)
    print_nl()
    print_nl()

proc print_assistant_header():
    print_raw(DIM + "  ⠋" + RESET)
    _thinking = true

proc print_token(tok):
    if _thinking:
        print_raw("\r\033[K" + GREEN + "  " + RESET)
        _thinking = false
    print_raw(GREEN + tok + RESET)

proc print_assistant_footer():
    print_nl()

proc print_tool_call(name, args_json):
    print_nl()
    let color = _tool_color(name)
    print_raw(rich.style("⚡ " + name, color + BOLD))
    if type(args_json) == "dict":
        let keys = dict_keys(args_json)
        for k in keys:
            print_raw(DIM + " " + k + "=" + str(args_json[k]) + RESET)
    elif type(args_json) == "string":
        print_raw(" " + args_json)
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
    let lines = split(result, "\n")
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
    print_raw(rich.style("Commands:", BOLD))
    print_nl()
    print_raw("  " + rich.style(":quit", CYAN) + ", " + rich.style(":exit", CYAN) + "     Exit the harness")
    print_nl()
    print_raw("  " + rich.style(":clear", CYAN) + "           Clear screen")
    print_nl()
    print_raw("  " + rich.style(":help", CYAN) + "            Show this help")
    print_nl()
    print_raw("  " + rich.style(":history", CYAN) + "         Show conversation history count")
    print_nl()
    print_raw("  " + rich.style(":ingest-skills", CYAN) + "   Reload skill files from skills/ directory")
    print_nl()
    print_nl()

proc get_input():
    print_raw(BOLD + "> " + RESET)
    let line = input()
    return line