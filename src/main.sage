import lib.agent as agent
import lib.tools as tools
import lib.tui as tui
import lib.skills as skills
import lib.ollama as ollama
import lib.model_provider as provider
import lib.model_config as cfg
import thread
import sys

let skills_dir = "skills"
skills.load_skills(skills_dir)
var history = agent.init_history_with_skills(skills.get_skills_content())
var running = true

provider.use_primary()

proc process_input(line):
    let trimmed = strip(line)

    if trimmed == ":quit" or trimmed == ":exit":
        provider.unload_current()
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

    if trimmed == "":
        return true

    tui.print_user_msg(trimmed)
    tui.print_assistant_header()

    var event_queue = []
    var agent_done = false

    proc on_token_bg(tok):
        push(event_queue, {"type": "token", "val": tok})

    proc on_tool_call_bg(name, args):
        push(event_queue, {"type": "tool_call", "name": name, "args": args})

    proc on_final_bg(answer):
        push(event_queue, {"type": "final", "val": answer})

    proc bg_worker():
        agent.run_agent(trimmed, history, on_token_bg, on_tool_call_bg, on_final_bg)
        agent_done = true

    let bg_thread = thread.spawn(bg_worker)

    while not agent_done or len(event_queue) > 0:
        if len(event_queue) > 0:
            let evt = event_queue[0]
            let next_q = []
            for i in range(1, len(event_queue)):
                push(next_q, event_queue[i])
            event_queue = next_q

            let etype = evt["type"]
            if etype == "token":
                tui.print_token(evt["val"])
            elif etype == "tool_call":
                tui.print_assistant_footer()
                let tc_name = evt["name"]
                let tc_args = evt["args"]
                if tc_name == "result":
                    tui.print_tool_result(tc_args)
                elif tc_name == "error":
                    tui.print_tool_call("COMPILER ERROR", tc_args)
                else:
                    tui.print_tool_call(tc_name, tc_args)
            elif etype == "final":
                tui.print_assistant_footer()
                let ans = evt["val"]
                if ans != nil and strip(ans) != "":
                    print(ans)
        else:
            tui.tick_spinner()
            thread.sleep(0.04)

    thread.join(bg_thread)
    return true

tui.print_banner()

while running:
    let line = tui.get_input()
    running = process_input(line)

provider.unload_current()
print ""
print "Goodbye!"
