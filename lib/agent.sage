import lib.ollama as ollama
import lib.tools as tools
import json

let MAX_ITERATIONS = 6
let MAX_HISTORY_CHARS = 8000

let SYSTEM_PROMPT = "You are Bonsai, an AI assistant running in a Linux environment. You have access to tools you can use to help the user.\n\nAvailable tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch\n\nWhen you need information, call the appropriate tool. When you have enough information, provide a complete answer.\n\nRULES:\n- Use tools when you need information\n- Be thorough - check files, run commands, verify facts\n- Provide complete, helpful responses\n- ALWAYS explain your reasoning step by step before calling a tool. Show what you're thinking and why."

proc trim_history(history):
    if len(history) <= 2:
        return
    var used = len(history[0]["content"])
    let keep = [0]
    for i in range(len(history) - 1, 1, -1):
        let cost = len(history[i]["content"])
        if used + cost <= MAX_HISTORY_CHARS:
            push(keep, i)
            used = used + cost
    if len(keep) <= 1:
        push(keep, len(history) - 1)
    let result = [history[0]]
    for i in range(1, len(history)):
        var found = false
        for j in keep:
            if j == i:
                found = true
                break
        if found:
            push(result, history[i])
    for i in range(len(result)):
        history[i] = result[i]
    let diff = len(history) - len(result)
    for i in range(diff):
        pop(history)

proc init_history():
    let history = []
    let sys_msg = {}
    sys_msg["role"] = "system"
    sys_msg["content"] = SYSTEM_PROMPT
    push(history, sys_msg)
    return history

proc init_history_with_skills(skills_content):
    let history = []
    let sys_msg = {}
    var prompt = SYSTEM_PROMPT
    if skills_content != nil and len(skills_content) > 0:
        prompt = prompt + "\n\n=== Loaded Skills ===\n" + skills_content + "\n=== End Skills ==="
    sys_msg["role"] = "system"
    sys_msg["content"] = prompt
    push(history, sys_msg)
    return history

proc parse_text_tool_call(content):
    let result = {}
    result["has_tool_call"] = false
    result["has_final"] = false

    let lines = split(content, "\n")
    for line in lines:
        let trimmed = strip(line)
        let upper_line = upper(trimmed)
        if startswith(upper_line, "FUNCTION:"):
            result["has_tool_call"] = true
            result["name"] = strip(slice(trimmed, 9, len(trimmed)))
        elif startswith(upper_line, "ARGUMENTS:"):
            let args_str = strip(slice(trimmed, 10, len(trimmed)))
            if len(args_str) > 0:
                let parsed = json.cJSON_Parse(args_str)
                if parsed != nil:
                    result["arguments"] = parsed
                else:
                    result["arguments"] = args_str
        elif startswith(upper_line, "FINAL:"):
            result["has_final"] = true
            result["final_answer"] = strip(slice(trimmed, 6, len(trimmed)))
    return result

let MAX_CONCURRENT_TOOLS = 4
let EXECUTION_SEMAPHORE = MAX_CONCURRENT_TOOLS
import sys

proc get_timestamp():
    return sys.clock()

proc execute_concurrent_tools(tool_calls, history, on_tool_call):
    var tool_results = []
    let executed_count = 0
    var available_slots = EXECUTION_SEMAPHORE
    
    for tool_call in tool_calls:
        if available_slots <= 0:
            break
        
        let tc_name = tool_call["name"]
        let tc_args = tool_call["arguments"]
        available_slots = available_slots - 1
        
        let tool_result = tools.execute_tool(tc_name, tc_args)
        executed_count = executed_count + 1
        
        let tool_msg = "TOOL RESULT (" + tc_name + "):\n" + tool_result
        let tool_entry = {}
        tool_entry["role"] = "tool"
        tool_entry["content"] = tool_msg
        tool_entry["name"] = tc_name
        
        push(history, tool_entry)
        
        if on_tool_call != nil:
            on_tool_call("result", tc_name + " (" + str(len(tool_result)) + " chars)")
        
        push(tool_results, {"name": tc_name, "result": tool_result})
        
        available_slots = available_slots + 1
    
    return history

proc _cjson_into_dict(cj, target):
    target["path"] = _cjson_get_str(cj, "path")
    target["content"] = _cjson_get_str(cj, "content")
    target["pattern"] = _cjson_get_str(cj, "pattern")
    target["url"] = _cjson_get_str(cj, "url")
    target["command"] = _cjson_get_str(cj, "command")

proc _cjson_get_str(cj, key):
    let node = json.cJSON_GetObjectItem(cj, key)
    if node != nil:
        let raw = json.cJSON_GetStringValue(node)
        if raw != nil:
            return "" + raw
        return ""
    return ""

proc run_agent(user_input, history, on_token, on_tool_call, on_final):
    let user_msg = {}
    user_msg["role"] = "user"
    user_msg["content"] = user_input
    push(history, user_msg)

    let tool_defs = tools.get_tool_list()

    for iter in range(MAX_ITERATIONS):
        trim_history(history)
        var response = {}

        if on_token != nil:
            response = ollama.chat(history, tool_defs, on_token, nil)
        else:
            response = ollama.chat(history, tool_defs, nil, nil)

        if dict_has(response, "error"):
            let err = response["error"]
            push(history, {"role": "assistant", "content": "Error: " + err})
            on_final("Error: " + err)
            return

        let tool_calls = response["tool_calls"]
        let content = response["content"]

        if tool_calls != nil and len(tool_calls) > 0:
            let tc = tool_calls[0]
            let tc_name = tc["name"]
            var tc_args = {}
            if dict_has(tc, "arguments_str"):
                let parsed = json.cJSON_Parse(tc["arguments_str"])
                if parsed != nil:
                    _cjson_into_dict(parsed, tc_args)
                    json.cJSON_Delete(parsed)
            elif dict_has(tc, "arguments"):
                tc_args = tc["arguments"]

            push(history, {"role": "assistant", "content": content})

            if on_tool_call != nil:
                on_tool_call(tc_name, tc_args)

            let result = tools.execute_tool(tc_name, tc_args)
            let tool_msg = "TOOL RESULT (" + tc_name + "):\n" + result
            let tool_entry = {}
            tool_entry["role"] = "tool"
            tool_entry["content"] = tool_msg
            tool_entry["name"] = tc_name
            push(history, tool_entry)

            if on_tool_call != nil:
                on_tool_call("result", tc_name + " (" + str(len(result)) + " chars)")

        elif len(content) > 0:
            let parse_result = parse_text_tool_call(content)
            if parse_result["has_tool_call"]:
                let tc_name = parse_result["name"]
                let tc_args = parse_result["arguments"]

                push(history, {"role": "assistant", "content": content})

                if on_tool_call != nil:
                    on_tool_call(tc_name, tc_args)

                let result = tools.execute_tool(tc_name, tc_args)
                let tool_msg = "TOOL RESULT (" + tc_name + "):\n" + result
                push(history, {"role": "tool", "content": tool_msg, "name": tc_name})

                if on_tool_call != nil:
                    on_tool_call("result", tc_name + " (" + str(len(result)) + " chars)")

            elif parse_result["has_final"]:
                let final = parse_result["final_answer"]
                push(history, {"role": "assistant", "content": final})
                on_final(final)
                return
            else:
                push(history, {"role": "assistant", "content": content})
                on_final(content)
                return
        else:
            push(history, {"role": "assistant", "content": content})
            on_final(content)
            return

    let msg = "Maximum iterations reached. Please refine your question."
    push(history, {"role": "assistant", "content": msg})
    on_final(msg)
