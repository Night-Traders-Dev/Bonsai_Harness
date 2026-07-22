import lib.agent as agent
import lib.tools as tools
import lib.tui as tui
import lib.skills as skills
import lib.ollama as ollama
import lib.model_provider as provider
import lib.model_config as cfg
import bench.run_bench as bench_runner
import thread
import sys

let skills_dir = "skills"
skills.load_skills(skills_dir)
var history = agent.init_history_with_skills(skills.get_skills_content())
var running = true

provider.use_primary()

proc on_token_sync(tok):
    tui.print_token(tok)

proc on_tool_call_sync(name, tool_args):
    tui.print_assistant_footer()
    if name == "result":
        tui.print_tool_result(tool_args)
    elif name == "error":
        tui.print_tool_call("COMPILER ERROR", tool_args)
    else:
        tui.print_tool_call(name, tool_args)
    tui.print_assistant_header()

proc on_final_sync(answer):
    tui.print_assistant_footer()
    if answer != nil and strip(answer) != "":
        print(answer)

proc process_input(line):
    let trimmed = strip(line)

    if trimmed == ":quit" or trimmed == ":exit":
        provider.unload_current()
        return false

    if trimmed == ":quit-unload":
        print "\x1b[33mUnloading models and freeing RAM...\x1b[0m"
        provider.unload_all()
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

    if trimmed == ":ingest-skills":
        let count = skills.load_skills(skills_dir)
        history = agent.init_history_with_skills(skills.get_skills_content())
        tui.print_assistant_header()
        tui.print_token("Skills re-loaded: " + str(skills.get_skills_count()) + " skill files ingested")
        tui.print_assistant_footer()
        return true

    if trimmed == ":models":
        print "Primary: " + cfg.MODEL_BONSAI
        print "Tool Compiler: " + cfg.MODEL_MINICPM
        print "Current: " + provider.get_current_model()
        return true

    if trimmed == ":bench":
        bench_runner.main()
        return true

    if trimmed == "":
        return true

    tui.print_user_msg(trimmed)
    tui.print_assistant_header()

    agent.run_agent(trimmed, history, on_token_sync, on_tool_call_sync, on_final_sync)
    return true

tui.print_banner()

while running:
    let line = tui.get_input()
    running = process_input(line)

provider.unload_current()
print ""
print "Goodbye!"
