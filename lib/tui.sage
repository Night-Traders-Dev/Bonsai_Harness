let RESET = "\033[0m"
let BOLD = "\033[1m"
let BLUE = "\033[34m"
let GREEN = "\033[32m"
let YELLOW = "\033[33m"
let CYAN = "\033[36m"
let GRAY = "\033[90m"

proc clear_screen():
    print "\033[2J\033[H"

proc show_header():
    print BOLD + CYAN + "╔══════════════════════════════════════════╗" + RESET
    print BOLD + CYAN + "║     Bonsai Agent Harness v1.0           ║" + RESET
    print BOLD + CYAN + "║     SageLang + Ollama + Bonsai-8B       ║" + RESET
    print BOLD + CYAN + "╚══════════════════════════════════════════╝" + RESET
    print ""

proc print_banner():
    clear_screen()
    show_header()
    print GRAY + "Type your message or :help for commands" + RESET
    print GRAY + "Commands: :quit, :clear, :help, :history" + RESET
    print ""

proc print_user_msg(text):
    print ""
    print BLUE + "┌─ You" + RESET
    for line in split(text, "\n"):
        print BLUE + "│ " + line + RESET
    print BLUE + "└─" + RESET

proc print_assistant_header():
    print ""
    print GREEN + "┌─ Bonsai" + RESET

proc print_token(tok):
    print GREEN + "│ " + tok + RESET

proc print_assistant_footer():
    print GREEN + "└─" + RESET

proc print_tool_call(name, args):
    print ""
    print YELLOW + "┌─ Tool: " + name + RESET
    if type(args) == "dict" or type(args) == "instance":
        let keys = dict_keys(args)
        for k in keys:
            print YELLOW + "│ " + k + " = " + str(args[k]) + RESET
    else:
        print YELLOW + "│ " + str(args) + RESET
    print YELLOW + "└─" + RESET

proc print_tool_result(result):
    print YELLOW + "┌─ Result" + RESET
    let lines = split(result, "\n")
    if len(lines) > 8:
        for i in range(4):
            print YELLOW + "│ " + lines[i] + RESET
        print YELLOW + "│ ... (" + str(len(lines)) + " lines total)" + RESET
        for i in range(len(lines) - 4, len(lines)):
            print YELLOW + "│ " + lines[i] + RESET
    else:
        for line in lines:
            print YELLOW + "│ " + line + RESET
    print YELLOW + "└─" + RESET

proc show_help():
    print ""
    print BOLD + "Commands:" + RESET
    print "  :quit, :exit  - Exit the harness"
    print "  :clear        - Clear screen"
    print "  :help         - Show this help"
    print "  :history      - Show conversation history count"
    print ""

proc get_input():
    print ""
    print BOLD + "> " + RESET
    let line = input()
    return line
