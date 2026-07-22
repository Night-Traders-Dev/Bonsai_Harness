import lib.tools as tools
import json



proc _cjson_str(cj, key):
    let node = json.cJSON_GetObjectItem(cj, key)
    if node != nil:
        let raw = json.cJSON_GetStringValue(node)
        if raw != nil:
            return "" + raw
    return ""

proc get_arguments(tool_call):
    if dict_has(tool_call, "arguments"):
        let tool_args = tool_call["arguments"]
        if type(tool_args) == "dict":
            return tool_args
        
    if dict_has(tool_call, "arguments_str"):
        let args_str = tool_call["arguments_str"]
        let parsed = json.cJSON_Parse(args_str)
        if parsed != nil:
            var tool_args_dict = {}
            tool_args_dict["path"] = _cjson_str(parsed, "path")
            tool_args_dict["content"] = _cjson_str(parsed, "content")
            tool_args_dict["pattern"] = _cjson_str(parsed, "pattern")
            tool_args_dict["url"] = _cjson_str(parsed, "url")
            tool_args_dict["command"] = _cjson_str(parsed, "command")
            json.cJSON_Delete(parsed)
            
            for key in dict_keys(tool_args_dict):
                let val = tool_args_dict[key]
                if val == "":
                    dict_delete(tool_args_dict, key)
            
            return tool_args_dict
        
    return {}

proc validate_tool_call(tool_call):
    var result = {"valid": true, "error": ""}

    if type(tool_call) != "dict" or not dict_has(tool_call, "name"):
        result["valid"] = false
        result["error"] = "Invalid tool call format"
        return result

    let name = tool_call["name"]
    let tool_args = get_arguments(tool_call)

    let registry = tools.get_tool_list()
    var tool_found = false
    for t in registry:
        if t["name"] == name:
            tool_found = true
            break

    if not tool_found:
        result["valid"] = false
        result["error"] = "Unknown tool: " + name
        return result

    if name == "bash":
        if not dict_has(tool_args, "command") or tool_args["command"] == "":
            result["error"] = "bash tool requires 'command' argument"
            result["valid"] = false
        else:
            let cmd = tool_args["command"]
            if startswith(cmd, "rm -rf /") or startswith(cmd, "sudo "):
                result["error"] = "Unsafe bash command detected"
                result["valid"] = false
            
    elif name == "read_file" or name == "write_file":
        if not dict_has(tool_args, "path") or tool_args["path"] == "":
            result["error"] = name + " tool requires 'path' argument"
            result["valid"] = false
        elif contains(tool_args["path"], ".."):
            result["error"] = "Path traversal is not allowed"
            result["valid"] = false
            
    elif name == "grep":
        if not dict_has(tool_args, "pattern") or tool_args["pattern"] == "":
            result["error"] = "grep tool requires 'pattern' argument"
            result["valid"] = false
            
    elif name == "glob":
        if not dict_has(tool_args, "pattern") or tool_args["pattern"] == "":
            result["error"] = "glob tool requires 'pattern' argument"
            result["valid"] = false
            
    elif name == "web_fetch":
        if not dict_has(tool_args, "url") or tool_args["url"] == "":
            result["error"] = "web_fetch tool requires 'url' argument"
            result["valid"] = false
        else:
            let url = tool_args["url"]
            if not startswith(url, "http://") and not startswith(url, "https://"):
                result["error"] = "URL must start with http:// or https://"
                result["valid"] = false
            
    return result
