import sys
import io

let RESET = "\033[0m"
let BOLD = "\033[1m"
let DIM = "\033[2m"
let BLUE = "\033[34m"
let CYAN = "\033[36m"
let GRAY = "\033[90m"

proc print_raw(text):
    let escaped = replace(text, "'", "'\\''")
    sys.exec("echo -n '" + escaped + "'")

proc print_nl():
    sys.exec("echo ''")

proc print_lines(lines_arr):
    let n = len(lines_arr)
    for i in range(n):
        if i > 0:
            print_nl()
        print_raw(lines_arr[i])

proc clear_screen():
    print_raw("\033[2J\033[H")

proc show_header():
    print_raw(BOLD + CYAN + "╭─ Bonsai Agent Harness ────────╮" + RESET)
    print_nl()
    print_raw(BOLD + CYAN + "╰─ SageLang + Ollama + Bonsai-8B ╯" + RESET)
    print_nl()
    print_nl()

proc print_banner():
    clear_screen()
    show_header()
    print_raw(DIM + "type a message or :help for commands" + RESET)
    print_nl()

proc print_user_msg(text):
    print_nl()
    print_raw(BLUE + "> " + RESET)
    print_raw(text)
    print_nl()
    print_nl()

proc print_assistant_header():
    print_raw("  ")

proc print_token(tok):
    print_raw(tok)

proc print_assistant_footer():
    print_nl()

proc print_tool_call(name, args_json):
    print_nl()
    print_raw(DIM + "  [" + name + "]" + RESET)
    if type(args_json) == "dict":
        let keys = dict_keys(args_json)
        for k in keys:
            print_raw(" " + k + "=" + str(args_json[k]))
    elif type(args_json) == "string":
        print_raw(" " + args_json)
    print_nl()

proc print_tool_result(result):
    let lines = split(result, "\n")
    let n = len(lines)
    if n > 12:
        for i in range(6):
            print_raw(GRAY + "  | " + RESET)
            print_raw(lines[i])
            print_nl()
        print_raw(GRAY + "  | ... (" + str(n) + " lines total)" + RESET)
        print_nl()
        for i in range(n - 6, n):
            print_raw(GRAY + "  | " + RESET)
            print_raw(lines[i])
            print_nl()
    else:
        for i in range(n):
            print_raw(GRAY + "  | " + RESET)
            print_raw(lines[i])
            print_nl()

proc show_help():
    print_nl()
    print_raw(BOLD + "Commands:" + RESET)
    print_nl()
    print_raw("  :quit, :exit     Exit the harness")
    print_nl()
    print_raw("  :clear           Clear screen")
    print_nl()
    print_raw("  :help            Show this help")
    print_nl()
    print_raw("  :history         Show conversation history count")
    print_nl()
    print_raw("  :ingest-skills   Reload skill files from skills/ directory")
    print_nl()
    print_nl()

proc get_input():
    print_raw(BOLD + "> " + RESET)
    let line = input()
    return line
