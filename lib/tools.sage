import io
import sys
import json

var tool_registry = {}

proc register_tool(name, description, parameters, execute_fn):
    let tool = {}
    tool["name"] = name
    tool["description"] = description
    tool["parameters"] = parameters
    tool["execute"] = execute_fn
    tool_registry[name] = tool

proc get_tool_list():
    let result = []
    let keys = dict_keys(tool_registry)
    for k in keys:
        let t = tool_registry[k]
        let entry = {}
        entry["name"] = t["name"]
        entry["description"] = t["description"]
        entry["parameters"] = t["parameters"]
        push(result, entry)
    return result

proc execute_tool(name, args_json):
    if dict_has(tool_registry, name):
        let tool = tool_registry[name]
        return tool["execute"](args_json)
    else:
        return "Error: Unknown tool '" + name + "'"

proc bash_execute(args):
    if type(args) == "dict" and dict_has(args, "command"):
        let cmd = args["command"]
        let result = sys.shell_exec(cmd)
        if result == nil:
            return "Command returned no output"
        return result
    return "Error: 'command' argument required"

let bash_params = "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\",\"description\":\"The bash command to execute\"}},\"required\":[\"command\"]}"
register_tool("bash", "Execute a bash command on the system. Use for file operations, running scripts, and system tasks.", bash_params, bash_execute)

proc read_file_execute(args):
    if type(args) == "dict" and dict_has(args, "path"):
        let path = args["path"]
        if io.exists(path):
            return io.readfile(path)
        else:
            return "Error: File not found: " + path
    return "Error: 'path' argument required"

let read_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path to the file to read\"}},\"required\":[\"path\"]}"
register_tool("read_file", "Read the contents of a file from the filesystem.", read_params, read_file_execute)

proc write_file_execute(args):
    if type(args) == "dict" and dict_has(args, "path") and dict_has(args, "content"):
        let path = args["path"]
        let content = args["content"]
        io.writefile(path, content)
        return "File written: " + path
    return "Error: 'path' and 'content' arguments required"

let write_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path to write the file to\"},\"content\":{\"type\":\"string\",\"description\":\"Content to write to the file\"}},\"required\":[\"path\",\"content\"]}"
register_tool("write_file", "Write content to a file on the filesystem.", write_params, write_file_execute)

proc grep_execute(args):
    if type(args) == "dict" and dict_has(args, "pattern"):
        let pattern = args["pattern"]
        let search_path = "."
        if dict_has(args, "path"):
            search_path = args["path"]
        var results = []
        var collect_files = []
        proc walk(dir):
            let entries = io.listdir(dir)
            for e in entries:
                let full = dir + "/" + e
                if io.isdir(full):
                    if not startswith(e, "."):
                        walk(full)
                elif io.exists(full) and not io.isdir(full):
                    push(collect_files, full)
        if io.isdir(search_path):
            walk(search_path)
        elif io.exists(search_path) and not io.isdir(search_path):
            push(collect_files, search_path)
        for f in collect_files:
            let content = io.readfile(f)
            let lines = split(content, "\n")
            for li in range(len(lines)):
                let line = lines[li]
                let idx = indexof(line, pattern)
                if idx >= 0:
                    let entry = f + ":" + str(li + 1) + ":" + line
                    push(results, entry)
                    if len(results) >= 20:
                        break
            if len(results) >= 20:
                break
        if len(results) > 0:
            return join(results, "\n")
        return "No matches found"
    return "Error: 'pattern' argument required"

let grep_params = "{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\",\"description\":\"Search pattern (regex)\"},\"path\":{\"type\":\"string\",\"description\":\"Directory or file to search in (default: current directory)\"}},\"required\":[\"pattern\"]}"
register_tool("grep", "Search for text patterns in files using regex. Returns matching lines with line numbers.", grep_params, grep_execute)

proc glob_execute(args):
    if type(args) == "dict" and dict_has(args, "pattern"):
        let pattern = args["pattern"]
        var results = []

        proc match_glob(name, pat):
            let star = indexof(pat, "*")
            if star < 0:
                return name == pat
            if star == 0:
                let suffix = slice(pat, 1, len(pat))
                if suffix == "":
                    return true
                return endswith(name, suffix)
            let prefix = slice(pat, 0, star)
            return startswith(name, prefix)

        proc walk(dir, pat):
            let entries = io.listdir(dir)
            for e in entries:
                if startswith(e, "."):
                    continue
                let full = dir + "/" + e
                if match_glob(e, pat):
                    push(results, full)
                if io.isdir(full):
                    walk(full, pat)

        walk(".", pattern)
        if len(results) > 0:
            return join(results, "\n")
        return "No matches found"
    return "Error: 'pattern' argument required"

let glob_params = "{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\",\"description\":\"Glob pattern to match files (e.g., '*.sage')\"}},\"required\":[\"pattern\"]}"
register_tool("glob", "Find files matching a glob pattern.", glob_params, glob_execute)

proc list_dir_execute(args):
    let path = "."
    if type(args) == "dict" and dict_has(args, "path"):
        path = args["path"]
    if io.isdir(path):
        let files = io.listdir(path)
        return join(files, "\n")
    else:
        return "Error: Not a directory: " + path

let ls_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Directory path to list (default: current directory)\"}},\"required\":[]}"
register_tool("list_dir", "List files and directories in a given path.", ls_params, list_dir_execute)

proc web_fetch_execute(args):
    if type(args) == "dict" and dict_has(args, "url"):
        let url = args["url"]
        let host = url
        let path = "/"
        if startswith(url, "http://"):
            host = slice(url, 7, len(url))
        elif startswith(url, "https://"):
            host = slice(url, 8, len(url))
        let slash_idx = indexof(host, "/")
        if slash_idx >= 0:
            path = slice(host, slash_idx, len(host))
            host = slice(host, 0, slash_idx)
        let port_idx = indexof(host, ":")
        var port = 80
        if port_idx >= 0:
            port = tonumber(slice(host, port_idx + 1, len(host)))
            host = slice(host, 0, port_idx)
        let request = "GET " + path + " HTTP/1.0\r\nHost: " + host + "\r\nConnection: close\r\n\r\n"
        import tcp
        let conn = tcp.connect(host, port)
        tcp.send(conn, request)
        var resp = ""
        var buf = tcp.recv(conn, 4096)
        while len(buf) > 0:
            resp = resp + buf
            buf = tcp.recv(conn, 4096)
        tcp.close(conn)
        let idx = indexof(resp, "\r\n\r\n")
        if idx >= 0:
            let body = slice(resp, idx + 4, len(resp))
            return slice(body, 0, 4000)
        return slice(resp, 0, 4000)
    return "Error: 'url' argument required"

let web_params = "{\"type\":\"object\",\"properties\":{\"url\":{\"type\":\"string\",\"description\":\"URL to fetch\"}},\"required\":[\"url\"]}"
register_tool("web_fetch", "Fetch a URL and return the content. Supports HTTP only.", web_params, web_fetch_execute)
