import lib.ollama as ollama
import lib.tools as tools
import lib.model_config as cfg
import lib.tool_validator as validator
import json

let TOOL_COMPILER_PROMPT = "You are the Bonsai Tool Compiler.\n\nYour only task is to convert the supplied tool intent into exactly one valid tool call.\n\nDo not explain your reasoning. Do not answer the user. Do not invent tools. Do not add any text before or after the JSON output.\n\nOutput exactly:\n{\"name\":\"tool_name\",\"arguments\":{\"arg1\":\"value1\"}}\n\nReplace tool_name and arg1/value1 with actual values from the Available Tools list. Keep the exact same JSON structure."

proc build_compiler_prompt(intent, tool_defs):
    var prompt = TOOL_COMPILER_PROMPT + "\n\nAvailable Tools:\n"
    for t in tool_defs:
        prompt = prompt + "\n- " + t["name"] + ": " + t["description"]
        prompt = prompt + "\n  Schema: " + t["parameters"]
    prompt = prompt + "\n\nTool Intent:\n" + intent
    return prompt

proc extract_json_from_text(text):
    let start = indexof(text, "{")
    if start < 0:
        return ""
    var depth = 0
    var end_pos = -1
    var in_string = false
    var escaped = false
    for i in range(start, len(text)):
        let ch = slice(text, i, i + 1)
        if in_string:
            if escaped:
                escaped = false
            elif ch == "\\":
                escaped = true
            elif ch == "\"":
                in_string = false
        else:
            if ch == "\"":
                in_string = true
            elif ch == "{":
                depth = depth + 1
            elif ch == "}":
                depth = depth - 1
                if depth == 0:
                    end_pos = i + 1
                    break
    if end_pos > start:
        return slice(text, start, end_pos)
    return ""

proc compile_tool_call(intent, tool_defs, timeout_ms=30000):
    let result = {}
    result["success"] = false
    result["tool_call"] = {}
    result["error"] = ""

    ollama.set_model(cfg.MODEL_MINICPM)
    ollama.set_timeout(timeout_ms)

    let messages = []
    let sys_msg = {}
    sys_msg["role"] = "system"
    sys_msg["content"] = build_compiler_prompt(intent, tool_defs)
    push(messages, sys_msg)

    let user_msg = {}
    user_msg["role"] = "user"
    user_msg["content"] = "Convert this intent into a tool call: " + intent
    push(messages, user_msg)

    let response = ollama.ask(messages, nil)

    if dict_has(response, "error"):
        result["error"] = "Model error: " + response["error"]
        return result

    let content = response["content"]
    if content == nil or strip(content) == "":
        let thinking = response["thinking"]
        if thinking != nil and strip(thinking) != "":
            content = thinking
        else:
            result["error"] = "Empty response from tool compiler"
            return result

    let json_str = extract_json_from_text(content)
    if json_str == "":
        result["error"] = "No JSON found in response"
        return result

    let parsed = json.cJSON_Parse(json_str)
    if parsed == nil:
        result["error"] = "Failed to parse JSON"
        return result

    let name_node = json.cJSON_GetObjectItem(parsed, "name")
    let args_node = json.cJSON_GetObjectItem(parsed, "arguments")

    if name_node == nil or args_node == nil:
        result["error"] = "Missing 'name' or 'arguments' in JSON"
        json.cJSON_Delete(parsed)
        return result

    let name_str = json.cJSON_GetStringValue(name_node)
    if name_str == nil:
        result["error"] = "'name' must be a string"
        json.cJSON_Delete(parsed)
        return result

    let args_json_str = json.cJSON_Print(args_node)
    json.cJSON_Delete(parsed)

    let tool_call = {}
    tool_call["name"] = "" + name_str
    tool_call["arguments_str"] = args_json_str

    let validation = validator.validate_tool_call(tool_call)
    if validation["valid"]:
        result["success"] = true
        result["tool_call"] = tool_call
    else:
        result["error"] = "Validation failed: " + validation["error"]

    return result

proc extract_intent_from_bonsai(content):
    let lines = split(content, "\n")
    var in_intent = false
    var intent_lines = []
    for line in lines:
        let trimmed = strip(line)
        if startswith(upper(trimmed), "INTENT:"):
            let rest = strip(slice(trimmed, 7, len(trimmed)))
            if rest != "":
                push(intent_lines, rest)
            in_intent = true
        elif in_intent:
            if startswith(trimmed, "ACTION:") or startswith(trimmed, "TOOL:") or startswith(trimmed, "FUNCTION:"):
                break
            push(intent_lines, trimmed)
    if len(intent_lines) > 0:
        return join(intent_lines, "\n")
    return content
