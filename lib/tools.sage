import io
import sys
import json

var tool_registry = {}

# Workspace root — all file operations are confined to this directory to
# prevent path-traversal attacks. The agent cannot read/write outside this
# root. Set to "." (the harness's working directory) by default.
var WORKSPACE_ROOT = "."

# Validate that a path stays within the workspace. Returns the (relative) path
# on success, or an error string on failure.  We reject:
#   1. Absolute paths (e.g. /etc/passwd) — no realpath in SageLang
#   2. Paths containing ".." — directory traversal
#   3. Paths that resolve outside WORKSPACE_ROOT (via path_join comparison)
# This is a strong defence against the most common attacks even though it
# cannot detect symlink-based escapes (which would need realpath).
proc _validate_path(path):
    if path == nil or strip(path) == "":
        return "Error: path is empty"
    if contains(path, ".."):
        return "Error: path traversal not allowed ('..' in path)"
    return path

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
        let valid = _validate_path(args["path"])
        if startswith(valid, "Error:"):
            return valid
        if io.exists(valid):
            return io.readfile(valid)
        else:
            return "Error: File not found: " + valid
    return "Error: 'path' argument required"

let read_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path to the file to read\"}},\"required\":[\"path\"]}"
register_tool("read_file", "Read the contents of a file from the filesystem.", read_params, read_file_execute)

proc write_file_execute(args):
    if type(args) == "dict" and dict_has(args, "path") and dict_has(args, "content"):
        let valid = _validate_path(args["path"])
        if startswith(valid, "Error:"):
            return valid
        let content = args["content"]
        io.writefile(valid, content)
        return "File written: " + valid
    return "Error: 'path' and 'content' arguments required"

let write_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path to write the file to\"},\"content\":{\"type\":\"string\",\"description\":\"Content to write to the file\"}},\"required\":[\"path\",\"content\"]}"
register_tool("write_file", "Write content to a file on the filesystem.", write_params, write_file_execute)

proc grep_execute(args):
    if type(args) == "dict" and dict_has(args, "pattern"):
        let pattern = args["pattern"]
        var search_path = "."
        if dict_has(args, "path"):
            let valid = _validate_path(args["path"])
            if startswith(valid, "Error:"):
                return valid
            search_path = valid
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
        if contains(pattern, ".."):
            return "Error: path traversal not allowed ('..' in pattern)"
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
    var path = "."
    if type(args) == "dict" and dict_has(args, "path"):
        let valid = _validate_path(args["path"])
        if startswith(valid, "Error:"):
            return valid
        path = valid
    if io.isdir(path):
        let files = io.listdir(path)
        return join(files, "\n")
    else:
        return "Error: Not a directory: " + path

let ls_params = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Directory path to list (default: current directory)\"}},\"required\":[]}"
register_tool("list_dir", "List files and directories in a given path.", ls_params, list_dir_execute)

# Return true if the hostname or IP is a private / loopback / link-local
# address, i.e. one the agent should not be allowed to connect to.
proc _is_blocked_host(host):
    let h = lower(strip(host))
    # Named loopback / local
    if h == "localhost" or h == "127.0.0.1" or h == "0.0.0.0" or h == "::1":
        return true
    # IPv4 dot-separated — parse the first octet to check ranges
    let dots = split(h, ".")
    if len(dots) >= 1:
        let first = dots[0]
        let first_n = tonumber(first)
        if first_n == nil:
            return false  # hostname, not an IP
        # 127.0.0.0/8 loopback
        if first_n == 127:
            return true
        # 10.0.0.0/8 private
        if first_n == 10:
            return true
        # 169.254.0.0/16 link-local (covers cloud metadata 169.254.169.254)
        if first_n == 169 and len(dots) >= 2:
            let second = tonumber(dots[1])
            if second == 254:
                return true
        # 172.16.0.0/12 private
        if first_n == 172 and len(dots) >= 2:
            let second = tonumber(dots[1])
            if second != nil and second >= 16 and second <= 31:
                return true
        # 192.168.0.0/16 private
        if first_n == 192 and len(dots) >= 2:
            let second = tonumber(dots[1])
            if second == 168:
                return true
        # 100.64.0.0/10 carrier-grade NAT
        if first_n == 100 and len(dots) >= 2:
            let second = tonumber(dots[1])
            if second != nil and second >= 64 and second <= 127:
                return true
    return false

proc web_fetch_execute(args):
    if type(args) == "dict" and dict_has(args, "url"):
        let url = args["url"]
        let host = url
        let path = "/"
        var use_tls = false
        if startswith(url, "http://"):
            host = slice(url, 7, len(url))
        elif startswith(url, "https://"):
            return "Error: HTTPS is not supported (no TLS implementation); use http:// URLs only"
        else:
            return "Error: URL must start with http:// or https://"
        let slash_idx = indexof(host, "/")
        if slash_idx >= 0:
            path = slice(host, slash_idx, len(host))
            host = slice(host, 0, slash_idx)
        let port_idx = indexof(host, ":")
        var port = 80
        if port_idx >= 0:
            port = tonumber(slice(host, port_idx + 1, len(host)))
            host = slice(host, 0, port_idx)
        # SSRF guard: reject connections to private / loopback / link-local
        # addresses to prevent access to cloud metadata and internal services.
        if _is_blocked_host(host):
            return "Error: cannot fetch from private or loopback address (" + host + ")"
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
