import json
import tcp
import strings
import sys
import lib.tui as tui

var current_model = "hf.co/prism-ml/Bonsai-4B-gguf:Q1_0"
var current_host = "localhost"
var current_port = 11434
var _timeout_ms = 60000
let CONNECTION_POOL = {}
let CONNECTION_EXPIRY = 60000
let last_activity = 0

proc set_model(name):
    current_model = name

proc get_model():
    return current_model

proc set_host(host):
    current_host = host

proc set_port(port):
    current_port = port

proc set_timeout(ms):
    _timeout_ms = ms

proc get_timeout():
    return _timeout_ms

proc get_timestamp():
    return sys.clock()

proc _check_timeout(start_ms, timeout_ms):
    if timeout_ms <= 0:
        return false
    let elapsed = (sys.clock() - start_ms) * 1000
    return elapsed >= timeout_ms

proc get_connection():
    let now = get_timestamp()
    let time_since_last = now - last_activity
    
    if time_since_last > CONNECTION_EXPIRY:
        let conn = CONNECTION_POOL[current_host]
        if conn != nil and conn != "":
            tcp.close(conn)
            CONNECTION_POOL[current_host] = ""
    
    if dict_has(CONNECTION_POOL, current_host):
        let conn = CONNECTION_POOL[current_host]
        if conn != nil and conn != "":
            last_activity = now
            return conn
    
    let conn = tcp.connect(current_host, current_port)
    CONNECTION_POOL[current_host] = conn
    last_activity = now
    return conn

proc release_connection(conn):
    let existing = CONNECTION_POOL[current_host]
    if existing != nil and existing != "":
        tcp.close(existing)
        CONNECTION_POOL[current_host] = ""
        last_activity = 0

# Generation options. Kept as one JSON fragment so both the streaming and
# non-streaming paths stay identical.
#  - num_ctx 8192: full context window
#  - temperature 0.1 + top_k/top_p/min_p: near-greedy but avoids degenerate
#    single-token loops that a 1-bit quant is prone to
#  - repeat_penalty 1.15: discourage repetition without distorting short answers
#  - num_predict 2048: enough room to finish reasoning AND emit the final answer
#    (too small a cap truncates mid-thinking and yields empty content)
let GEN_OPTIONS = "\"num_ctx\":8192,\"temperature\":0.1,\"top_k\":40,\"top_p\":0.9,\"min_p\":0.05,\"repeat_penalty\":1.15,\"num_predict\":2048"

# Keep the model resident in memory between requests to avoid reload latency.
let KEEP_ALIVE = "\"keep_alive\":\"10m\""

proc json_escape(s):
    let r = replace(s, "\\", "\\\\")
    r = replace(r, "\"", "\\\"")
    r = replace(r, "\n", "\\n")
    r = replace(r, "\r", "\\r")
    r = replace(r, "\t", "\\t")
    r = replace(r, "\b", "\\b")
    r = replace(r, "\f", "\\f")
    var i = 0
    let n = len(r)
    var out = ""
    while i < n:
        let c = slice(r, i, i + 1)
        let cv = ord(c)
        if cv >= 0 and cv < 32 and cv != 10 and cv != 13 and cv != 9 and cv != 8 and cv != 12:
            out = out + "\\u00"
            let hi = cv / 16
            let lo = cv % 16
            if hi < 10: out = out + chr(48 + hi)
            else: out = out + chr(87 + hi)
            if lo < 10: out = out + chr(48 + lo)
            else: out = out + chr(87 + lo)
        else:
            out = out + c
        i = i + 1
    return out

proc build_messages_json(messages):
    let parts = []
    for msg in messages:
        let role = msg["role"]
        let content = msg["content"]
        var extra = ""
        if dict_has(msg, "name"):
            extra = ",\"name\":\"" + json_escape(msg["name"]) + "\""
        let entry = "{\"role\":\"" + json_escape(role) + "\",\"content\":\"" + json_escape(content) + "\"" + extra + "}"
        push(parts, entry)
    return "[" + join(parts, ",") + "]"

proc build_tools_json(tools):
    if tools == nil or len(tools) == 0:
        return ""
    let tool_parts = []
    for t in tools:
        let params_json = t["parameters"]
        let entry = "{\"type\":\"function\",\"function\":{\"name\":\"" + json_escape(t["name"]) + "\",\"description\":\"" + json_escape(t["description"]) + "\",\"parameters\":" + params_json + "}}"
        push(tool_parts, entry)
    return ",\"tools\":[" + join(tool_parts, ",") + "]"

proc build_request(messages, tools, stream):
    let body = "{\"model\":\"" + json_escape(current_model) + "\""
    body = body + ",\"messages\":" + build_messages_json(messages)
    body = body + build_tools_json(tools)
    body = body + ",\"stream\":" + str(stream)
    body = body + ",\"options\":{" + GEN_OPTIONS + "}"
    body = body + "," + KEEP_ALIVE
    body = body + "}"
    return body

proc parse_response_body(body_str):
    let result = {}
    result["content"] = ""
    result["tool_calls"] = []

    let obj = json.cJSON_Parse(body_str)
    if obj == nil:
        result["error"] = "JSON parse failed"
        return result

    let error_node = json.cJSON_GetObjectItem(obj, "error")
    if error_node != nil:
        let raw_err = json.cJSON_GetStringValue(error_node)
        if raw_err != nil:
            result["error"] = "" + raw_err
        json.cJSON_Delete(obj)
        return result

    let msg = json.cJSON_GetObjectItem(obj, "message")
    if msg == nil:
        result["error"] = "No message in response"
        json.cJSON_Delete(obj)
        return result

    result["thinking"] = ""

    let content_node = json.cJSON_GetObjectItem(msg, "content")
    if content_node != nil:
        let raw = json.cJSON_GetStringValue(content_node)
        if raw != nil:
            result["content"] = "" + raw

    let thinking_node = json.cJSON_GetObjectItem(msg, "thinking")
    if thinking_node != nil:
        let raw = json.cJSON_GetStringValue(thinking_node)
        if raw != nil:
            result["thinking"] = "" + raw

    let tc_node = json.cJSON_GetObjectItem(msg, "tool_calls")
    if tc_node != nil:
        var i = 0
        while true:
            let tc = json.cJSON_GetArrayItem(tc_node, i)
            if tc == nil:
                break
            let fn = json.cJSON_GetObjectItem(tc, "function")
            if fn != nil:
                let call = {}
                let fn_name = json.cJSON_GetObjectItem(fn, "name")
                if fn_name != nil:
                    let raw = json.cJSON_GetStringValue(fn_name)
                    if raw != nil:
                        call["name"] = "" + raw
                let fn_args = json.cJSON_GetObjectItem(fn, "arguments")
                if fn_args != nil:
                    call["arguments_str"] = "" + json.cJSON_Print(fn_args)
                push(result["tool_calls"], call)
            i = i + 1

    json.cJSON_Delete(obj)
    return result

proc _flush_parse(buf, on_token, state):
    let lines = split(buf, "\n")
    var remaining = ""
    let n = len(lines)
    for li in range(n):
        let line = strip(lines[li])
        if line == "":
            continue
        if li == n - 1 and not endswith(buf, "\n"):
            remaining = line
            continue
        let cj = json.cJSON_Parse(line)
        if cj == nil:
            continue
        let cmsg = json.cJSON_GetObjectItem(cj, "message")
        if cmsg != nil:
            let cnode = json.cJSON_GetObjectItem(cmsg, "content")
            if cnode != nil:
                let raw_tok = json.cJSON_GetStringValue(cnode)
                if raw_tok != nil:
                    let tok = "" + raw_tok
                    if len(tok) > 0:
                        state["full_content"] = state["full_content"] + tok
                        if on_token != nil:
                            on_token(tok)
            let tnode = json.cJSON_GetObjectItem(cmsg, "thinking")
            if tnode != nil:
                let raw_ttok = json.cJSON_GetStringValue(tnode)
                if raw_ttok != nil:
                    let ttok = "" + raw_ttok
                    if len(ttok) > 0:
                        state["full_content"] = state["full_content"] + ttok
                        if on_token != nil:
                            on_token(ttok)
            let tc_node = json.cJSON_GetObjectItem(cmsg, "tool_calls")
            if tc_node != nil:
                var ti = 0
                while true:
                    let tc = json.cJSON_GetArrayItem(tc_node, ti)
                    if tc == nil:
                        break
                    let fn = json.cJSON_GetObjectItem(tc, "function")
                    if fn != nil:
                        let call = {}
                        let fn_name = json.cJSON_GetObjectItem(fn, "name")
                        if fn_name != nil:
                            let raw_name = json.cJSON_GetStringValue(fn_name)
                            if raw_name != nil:
                                call["name"] = "" + raw_name
                        let fn_args = json.cJSON_GetObjectItem(fn, "arguments")
                        if fn_args != nil:
                            call["arguments_str"] = "" + json.cJSON_Print(fn_args)
                        push(state["final_tool_calls"], call)
                    ti = ti + 1
        let ttc_node = json.cJSON_GetObjectItem(cj, "tool_calls")
        if ttc_node != nil:
            var ti2 = 0
            while true:
                let tc = json.cJSON_GetArrayItem(ttc_node, ti2)
                if tc == nil:
                    break
                let fn = json.cJSON_GetObjectItem(tc, "function")
                if fn != nil:
                    let call = {}
                    let fn_name = json.cJSON_GetObjectItem(fn, "name")
                    if fn_name != nil:
                        let raw_name = json.cJSON_GetStringValue(fn_name)
                        if raw_name != nil:
                            call["name"] = "" + raw_name
                    let fn_args = json.cJSON_GetObjectItem(fn, "arguments")
                    if fn_args != nil:
                        call["arguments_str"] = "" + json.cJSON_Print(fn_args)
                    push(state["final_tool_calls"], call)
                ti2 = ti2 + 1
        json.cJSON_Delete(cj)
    return remaining

proc send_and_stream(messages, tools, on_token, on_done):
    import thread

    let body_str = build_request(messages, tools, true)

    let conn = tcp.connect(current_host, current_port)
    let req = "POST /api/chat HTTP/1.1\r\n"
    req = req + "Host: " + current_host + ":" + str(current_port) + "\r\n"
    req = req + "Content-Type: application/json\r\n"
    req = req + "Content-Length: " + str(len(body_str)) + "\r\n"
    req = req + "Accept: application/x-ndjson\r\n"
    req = req + "Connection: close\r\n\r\n"
    req = req + body_str

    tcp.sendall(conn, req)

    # (spinner was already stopped when first token was received)

    var status_line = ""
    var ch = tcp.recv(conn, 1)
    var tries = 0
    while ch == "" and tries < 10:
        tries = tries + 1
        thread.sleep(0.1 * tries)
        ch = tcp.recv(conn, 1)
    while ch != "\n":
        status_line = status_line + ch
        ch = tcp.recv(conn, 1)

    var content_length = 0
    var chunked = false

    while true:
        var hdr = ""
        ch = tcp.recv(conn, 1)
        while ch != "\n":
            hdr = hdr + ch
            ch = tcp.recv(conn, 1)
        hdr = strip(hdr)
        if hdr == "":
            break
        let low = lower(hdr)
        if startswith(low, "content-length:"):
            let parts = split(hdr, ":")
            if len(parts) >= 2:
                content_length = tonumber(strip(parts[1]))
        if startswith(low, "transfer-encoding:"):
            let parts = split(hdr, ":")
            if len(parts) >= 2:
                if contains(strip(parts[1]), "chunked"):
                    chunked = true

    var state = {}
    state["full_content"] = ""
    state["final_tool_calls"] = []
    var parse_buf = ""

    if chunked:
        while true:
            var sl = ""
            ch = tcp.recv(conn, 1)
            if ch == "":
                thread.sleep(0.01)
                ch = tcp.recv(conn, 1)
                if ch == "":
                    break
            while ch != "\n":
                sl = sl + ch
                ch = tcp.recv(conn, 1)
            let hex_str = strip(sl)
            if hex_str == "":
                break
            let chunk_size = tonumber("0x" + hex_str)
            if chunk_size == 0:
                break
            var chunk_data = ""
            var got = 0
            while got < chunk_size:
                let more = tcp.recv(conn, chunk_size - got)
                var retries = 5
                while len(more) == 0 and retries > 0:
                    thread.sleep(0.02)
                    more = tcp.recv(conn, chunk_size - got)
                    retries = retries - 1
                if len(more) == 0:
                    break
                chunk_data = chunk_data + more
                got = got + len(more)
            tcp.recv(conn, 2)
            parse_buf = _flush_parse(parse_buf + chunk_data, on_token, state)
    elif content_length > 0:
        var data = ""
        var got = 0
        while got < content_length:
            let more = tcp.recv(conn, content_length - got)
            var retries = 5
            while len(more) == 0 and retries > 0:
                thread.sleep(0.02)
                more = tcp.recv(conn, content_length - got)
                retries = retries - 1
            if len(more) == 0:
                break
            data = data + more
            got = got + len(more)
        parse_buf = _flush_parse(parse_buf + data, on_token, state)
    else:
        var buf = tcp.recv(conn, 4096)
        var retries = 5
        while len(buf) > 0:
            parse_buf = _flush_parse(parse_buf + buf, on_token, state)
            buf = tcp.recv(conn, 4096)
            retries = 5
            while len(buf) == 0 and retries > 0:
                thread.sleep(0.02)
                buf = tcp.recv(conn, 4096)
                retries = retries - 1

    tcp.close(conn)

    let final_body = "{\"message\":{\"role\":\"assistant\",\"content\":\"" + json_escape(state["full_content"]) + "\""
    if len(state["final_tool_calls"]) > 0:
        let tc_parts = []
        for tc in state["final_tool_calls"]:
            let args_str = "{}"
            if dict_has(tc, "arguments_str"):
                args_str = tc["arguments_str"]
            let entry = "{\"function\":{\"name\":\"" + json_escape(tc["name"]) + "\",\"arguments\":" + args_str + "}}"
            push(tc_parts, entry)
        final_body = final_body + ",\"tool_calls\":[" + join(tc_parts, ",") + "]"
    final_body = final_body + "}}"

    if on_done != nil:
        on_done(final_body)

    return final_body

proc unload_model():
    let conn = tcp.connect(current_host, current_port)
    let body = "{\"model\":\"" + json_escape(current_model) + "\",\"keep_alive\":0}"
    let req = "POST /api/generate HTTP/1.1\r\n"
    req = req + "Host: " + current_host + ":" + str(current_port) + "\r\n"
    req = req + "Content-Type: application/json\r\n"
    req = req + "Content-Length: " + str(len(body)) + "\r\n"
    req = req + "Connection: close\r\n\r\n"
    req = req + body
    tcp.send(conn, req)
    tcp.close(conn)

proc chat(messages, tools, on_token, on_done):
    let body = send_and_stream(messages, tools, on_token, on_done)
    return parse_response_body(body)

var _chat_simple_content = ""

proc _chat_simple_token_collector(tok):
    _chat_simple_content = _chat_simple_content + tok

proc chat_simple(messages, tools):
    _chat_simple_content = ""
    let result = chat(messages, tools, _chat_simple_token_collector, nil)
    result["full_content"] = _chat_simple_content
    return result

proc send_once(messages, tools):
    import thread
    let body_str = build_request(messages, tools, false)
    let _start = sys.clock()

    var req = "POST /api/chat HTTP/1.1\r\n"
    req = req + "Host: " + current_host + ":" + str(current_port) + "\r\n"
    req = req + "Content-Type: application/json\r\n"
    req = req + "Content-Length: " + str(len(body_str)) + "\r\n"
    req = req + "Connection: close\r\n\r\n"
    req = req + body_str

    let conn = tcp.connect(current_host, current_port)
    tcp.send(conn, req)

    var status_line = ""
    var ch = tcp.recv(conn, 1)
    while ch != "\n":
        if _check_timeout(_start, _timeout_ms):
            tcp.close(conn)
            return ""
        status_line = status_line + ch
        ch = tcp.recv(conn, 1)

    var content_length = 0
    var chunked = false
    while true:
        if _check_timeout(_start, _timeout_ms):
            tcp.close(conn)
            return ""
        var hdr = ""
        ch = tcp.recv(conn, 1)
        while ch != "\n":
            if _check_timeout(_start, _timeout_ms):
                tcp.close(conn)
                return ""
            hdr = hdr + ch
            ch = tcp.recv(conn, 1)
        hdr = strip(hdr)
        if hdr == "":
            break
        let low = lower(hdr)
        if startswith(low, "content-length:"):
            let parts = split(hdr, ":")
            if len(parts) >= 2:
                content_length = tonumber(strip(parts[1]))
        if startswith(low, "transfer-encoding:"):
            if contains(low, "chunked"):
                chunked = true

    var body = ""
    if chunked:
        while true:
            if _check_timeout(_start, _timeout_ms):
                break
            var sl = ""
            ch = tcp.recv(conn, 1)
            while ch != "\n":
                if _check_timeout(_start, _timeout_ms):
                    break
                sl = sl + ch
                ch = tcp.recv(conn, 1)
            if _check_timeout(_start, _timeout_ms):
                break
            let hex_str = strip(sl)
            if hex_str == "":
                break
            let chunk_size = tonumber("0x" + hex_str)
            if chunk_size == 0:
                break
            var got = 0
            while got < chunk_size:
                if _check_timeout(_start, _timeout_ms):
                    break
                let more = tcp.recv(conn, chunk_size - got)
                var retries = 5
                while len(more) == 0 and retries > 0 and not _check_timeout(_start, _timeout_ms):
                    thread.sleep(0.02)
                    more = tcp.recv(conn, chunk_size - got)
                    retries = retries - 1
                if len(more) == 0:
                    break
                body = body + more
                got = got + len(more)
            if _check_timeout(_start, _timeout_ms):
                break
            tcp.recv(conn, 2)
    elif content_length > 0:
        var got = 0
        while got < content_length:
            if _check_timeout(_start, _timeout_ms):
                break
            let more = tcp.recv(conn, content_length - got)
            var retries = 5
            while len(more) == 0 and retries > 0 and not _check_timeout(_start, _timeout_ms):
                thread.sleep(0.02)
                more = tcp.recv(conn, content_length - got)
                retries = retries - 1
            if len(more) == 0:
                break
            body = body + more
            got = got + len(more)
    else:
        var buf = tcp.recv(conn, 4096)
        var retries = 5
        while len(buf) > 0:
            if _check_timeout(_start, _timeout_ms):
                break
            body = body + buf
            buf = tcp.recv(conn, 4096)
            retries = 5
            while len(buf) == 0 and retries > 0 and not _check_timeout(_start, _timeout_ms):
                thread.sleep(0.02)
                buf = tcp.recv(conn, 4096)
                retries = retries - 1

    tcp.close(conn)
    return body

proc ask(messages, tools):
    let body = send_once(messages, tools)
    if body == "":
        let err = {}
        err["error"] = "Request timed out after " + str(_timeout_ms) + "ms"
        err["content"] = ""
        err["tool_calls"] = []
        return err
    return parse_response_body(body)

# Return the model's actual answer text: prefer the post-reasoning content
# field, falling back to thinking only when content is genuinely empty.
proc answer_text(result):
    if dict_has(result, "content"):
        let c = result["content"]
        if c != nil and strip(c) != "":
            return c
    if dict_has(result, "thinking"):
        let t = result["thinking"]
        if t != nil:
            return t
    return ""
