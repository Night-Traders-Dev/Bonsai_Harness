import lib.model_provider as provider
import lib.model_router as router
import lib.tool_compiler as compiler
import lib.tool_validator as validator
import lib.tools as tools
import lib.model_config as cfg
import io
import json

let MAX_ITERATIONS = 6
let MAX_HISTORY_CHARS = 8000
let MAX_TOOL_RETRIES = 1

let SYSTEM_PROMPT = "You are Bonsai, an AI assistant running in a Linux environment. You have access to tools you can use to help the user.\n\nAvailable tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch\n\nWhen you need information, call the appropriate tool. When you have enough information, provide a complete answer.\n\nRULES:\n- Use tools ONLY when the task actually requires filesystem or web access\n- For simple conversation, greetings, or chitchat, just reply naturally — do NOT call tools\n- Limit tool calls to 2-3 per task, then finalize\n- Use EXACT paths from tool results — never invent or guess file paths\n- Provide complete, helpful responses\n- ALWAYS explain your reasoning step by step before calling a tool. Show what you're thinking and why.\n- State your intent clearly before each tool use."

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
                    var args_dict = {}
                    _cjson_into_dict(parsed, args_dict)
                    result["arguments"] = args_dict
                    json.cJSON_Delete(parsed)
                else:
                    result["arguments"] = args_str
        elif startswith(upper_line, "FINAL:"):
            result["has_final"] = true
            result["final_answer"] = strip(slice(trimmed, 6, len(trimmed)))
    if not result["has_tool_call"]:
        let json_str = compiler.extract_json_from_text(content)
        if json_str != "":
            let parsed = json.cJSON_Parse(json_str)
            if parsed != nil:
                let name_node = json.cJSON_GetObjectItem(parsed, "name")
                let args_node = json.cJSON_GetObjectItem(parsed, "arguments")
                if name_node != nil and args_node != nil:
                    let raw_name = json.cJSON_GetStringValue(name_node)
                    if raw_name != nil:
                        result["has_tool_call"] = true
                        result["name"] = "" + raw_name
                        var args_dict = {}
                        _cjson_into_dict(args_node, args_dict)
                        result["arguments"] = args_dict
                json.cJSON_Delete(parsed)
    return result

proc _cjson_get_str(cj, key):
    let node = json.cJSON_GetObjectItem(cj, key)
    if node != nil:
        let raw = json.cJSON_GetStringValue(node)
        if raw != nil:
            return "" + raw
        return ""
    return ""

let CJSON_KEYS = ["path", "content", "pattern", "url", "command"]

proc _cjson_into_dict(cj, target):
    for key in CJSON_KEYS:
        let val = _cjson_get_str(cj, key)
        if val != nil and val != "":
            target[key] = val

proc build_tool_result_entry(name, result):
    let tool_msg = "TOOL RESULT (" + name + "):\n" + result
    let entry = {}
    entry["role"] = "tool"
    entry["content"] = tool_msg
    entry["name"] = name
    return entry

proc handle_tool_call(tc_name, tc_args_raw, history, on_tool_call):
    var tc_args = {}
    if type(tc_args_raw) == "dict":
        tc_args = tc_args_raw
    elif dict_has(tc_args_raw, "arguments_str"):
        let args_str = tc_args_raw["arguments_str"]
        let parsed = json.cJSON_Parse(args_str)
        if parsed != nil:
            _cjson_into_dict(parsed, tc_args)
            json.cJSON_Delete(parsed)

    if on_tool_call != nil:
        on_tool_call(tc_name, tc_args)

    if tc_name == "read_file" and dict_has(tc_args, "path"):
        let p = tc_args["path"]
        if p != nil and not io.exists(p):
            let result = "Error: File not found: " + p + ". Use list_dir to find valid paths."
            push(history, build_tool_result_entry(tc_name, result))
            if on_tool_call != nil:
                on_tool_call("result", "file not found")
            return history

    let result = tools.execute_tool(tc_name, tc_args)
    push(history, build_tool_result_entry(tc_name, result))

    if on_tool_call != nil:
        on_tool_call("result", tc_name + " (" + str(len(result)) + " chars)")

    return history

proc compile_via_minicpm(intent, tool_defs, history, on_tool_call):
    let result = {}
    result["ok"] = false

    let compile_result = compiler.compile_tool_call(intent, tool_defs)
    if compile_result["success"]:
        let tc = compile_result["tool_call"]
        history = handle_tool_call(tc["name"], tc, history, on_tool_call)
        result["ok"] = true
    else:
        if on_tool_call != nil:
            on_tool_call("error", compile_result["error"])

    result["history"] = history
    return result

proc run_agent(user_input, history, on_token, on_tool_call, on_final):
    let user_msg = {}
    user_msg["role"] = "user"
    user_msg["content"] = user_input
    push(history, user_msg)

    let tool_defs = tools.get_tool_list()
    provider.use_primary()

    for iter in range(MAX_ITERATIONS):
        trim_history(history)

        if iter >= 4:
            let reminder = {}
            reminder["role"] = "user"
            reminder["content"] = "You have enough information now. Provide your FINAL answer — do not call more tools."
            push(history, reminder)

        var response = {}

        provider.use_primary()

        if on_token != nil:
            response = provider.chat(history, tool_defs, on_token, nil)
        else:
            response = provider.chat(history, tool_defs, nil, nil)

        if dict_has(response, "error"):
            let err = response["error"]
            push(history, {"role": "assistant", "content": "Error: " + err})
            if on_final != nil:
                on_final("Error: " + err)
            return

        let tool_calls = response["tool_calls"]
        let content = response["content"]

        if tool_calls != nil and len(tool_calls) > 0:
            let tc = tool_calls[0]
            let tc_name = tc["name"]
            push(history, {"role": "assistant", "content": content})

            let intent = "Use " + tc_name + " tool"
            if dict_has(tc, "arguments_str"):
                intent = intent + " with arguments: " + tc["arguments_str"]

            var compiled = false
            for retry in range(MAX_TOOL_RETRIES + 1):
                let cr = compile_via_minicpm(intent, tool_defs, history, on_tool_call)
                history = cr["history"]
                if cr["ok"]:
                    compiled = true
                    break
                if retry < MAX_TOOL_RETRIES:
                    intent = "Retry: " + intent

            if not compiled:
                history = handle_tool_call(tc_name, tc, history, on_tool_call)

        elif content != nil and len(content) > 0:
            let parse_result = parse_text_tool_call(content)
            if parse_result["has_tool_call"]:
                let tc_name = parse_result["name"]
                let tc_args = parse_result["arguments"]
                push(history, {"role": "assistant", "content": content})

                let intent = "Use " + tc_name + " tool"
                if type(tc_args) == "dict":
                    var args_parts = []
                    for key in dict_keys(tc_args):
                        let v = tc_args[key]
                        if v != nil and v != "":
                            push(args_parts, key + "=" + v)
                    if len(args_parts) > 0:
                        intent = intent + " with " + join(args_parts, ", ")

                var compiled = false
                for retry in range(MAX_TOOL_RETRIES + 1):
                    let cr = compile_via_minicpm(intent, tool_defs, history, on_tool_call)
                    history = cr["history"]
                    if cr["ok"]:
                        compiled = true
                        break
                    if retry < MAX_TOOL_RETRIES:
                        intent = "Retry: " + intent

                if not compiled:
                    history = handle_tool_call(tc_name, tc_args, history, on_tool_call)

            elif parse_result["has_final"]:
                let final = parse_result["final_answer"]
                push(history, {"role": "assistant", "content": final})
                if on_final != nil:
                    on_final(final)
                return
            else:
                push(history, {"role": "assistant", "content": content})
                if on_final != nil:
                    on_final(content)
                return
        else:
            if on_final != nil:
                on_final("")
            return

    let msg = "Maximum iterations reached. Please refine your question."
    push(history, {"role": "assistant", "content": msg})
    if on_final != nil:
        on_final(msg)
