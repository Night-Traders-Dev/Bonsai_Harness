import lib.tools as tools
import json

proc get_arguments(tool_call):
    if dict_has(tool_call, "arguments"):
        let args = tool_call["arguments"]
        if type(args) == "dict":
            return args
    if dict_has(tool_call, "arguments_str"):
        let args_str = tool_call["arguments_str"]
        let parsed = json.cJSON_Parse(args_str)
        if parsed != nil:
            var args = {}
            args["path"] = _cjson_str(parsed, "path")
            args["content"] = _cjson_str(parsed, "content")
            args["pattern"] = _cjson_str(parsed, "pattern")
            args["url"] = _cjson_str(parsed, "url")
            args["command"] = _cjson_str(parsed, "command")
            json.cJSON_Delete(parsed)
            var clean = {}
            for key in dict_keys(args):
                let val = args[key]
                if val != nil and val != "":
                    clean[key] = val
            return clean
    return {}

proc _cjson_str(cj, key):
    let node = json.cJSON_GetObjectItem(cj, key)
    if node != nil:
        let raw = json.cJSON_GetStringValue(node)
        if raw != nil:
            return "" + raw
    return ""

proc validate_tool_call(tool_call):
    let result = {}
    result["valid"] = false
    result["error"] = ""
    result["tool_call"] = tool_call

    if type(tool_call) != "dict":
        result["error"] = "Tool call must be a dict"
        return result

    if not dict_has(tool_call, "name"):
        result["error"] = "Missing 'name' field"
        return result

    let name = tool_call["name"]

    if type(name) != "string" or strip(name) == "":
        result["error"] = "Tool name must be a non-empty string"
        return result

    let registry = tools.get_tool_list()
    var tool_found = false
    for t in registry:
        if t["name"] == name:
            tool_found = true
            break

    if not tool_found:
        result["error"] = "Unknown tool: " + name
        return result

    let args = get_arguments(tool_call)

    if name == "bash":
        if not dict_has(args, "command") or args["command"] == "":
            result["error"] = "bash tool requires 'command' argument"
            return result
        let cmd = args["command"]
        if contains(cmd, "rm -rf /") or contains(cmd, "mkfs") or contains(cmd, "dd if="):
            result["error"] = "Command rejected by security policy"
            return result

    if name == "read_file" or name == "write_file":
        if not dict_has(args, "path") or args["path"] == "":
            result["error"] = name + " tool requires 'path' argument"
            return result
        if contains(args["path"], ".."):
            result["error"] = "Path traversal not allowed"
            return result

    if name == "grep":
        if not dict_has(args, "pattern") or args["pattern"] == "":
            result["error"] = "grep tool requires 'pattern' argument"
            return result

    if name == "glob":
        if not dict_has(args, "pattern") or args["pattern"] == "":
            result["error"] = "glob tool requires 'pattern' argument"
            return result

    if name == "web_fetch":
        if not dict_has(args, "url") or args["url"] == "":
            result["error"] = "web_fetch tool requires 'url' argument"
            return result
        let url = args["url"]
        if not startswith(url, "http://"):
            result["error"] = "Only http:// URLs are supported"
            return result

    result["valid"] = true
    return result
