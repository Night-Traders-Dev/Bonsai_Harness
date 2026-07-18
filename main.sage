import lib.agent as agent
import lib.tools as tools
import lib.tui as tui
import sys

var history = agent.init_history()
var running = true

proc on_token(tok):
    tui.print_token(tok)

proc on_tool_call(name, args):
    tui.print_assistant_footer()
    if name == "result":
        tui.print_tool_result(args)
    else:
        tui.print_tool_call(name, args)

proc on_final(answer):
    tui.print_assistant_footer()

proc process_input(line):
    let trimmed = strip(line)

    if trimmed == ":quit" or trimmed == ":exit":
        return false

    if trimmed == ":clear":
        tui.print_banner()
        return true

    if trimmed == ":help":
        tui.show_help()
        return true

    if trimmed == ":history":
        print "History entries: " + str(len(history))
        return true

    if trimmed == "":
        return true

    tui.print_user_msg(trimmed)
    tui.print_assistant_header()

    agent.run_agent(trimmed, history, on_token, on_tool_call, on_final)

    return true

tui.print_banner()

while running:
    let line = tui.get_input()
    running = process_input(line)

print ""
print "Goodbye!"
