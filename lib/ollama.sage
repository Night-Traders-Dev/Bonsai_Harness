import json
import tcp
import strings

let DEFAULT_MODEL = "hf.co/prism-ml/Bonsai-8B-gguf:Q1_0"
let OLLAMA_HOST = "localhost"
let OLLAMA_PORT = 11434

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
    r = replace(r, "\t", "\\t")
    return r

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
    let body = "{\"model\":\"" + json_escape(DEFAULT_MODEL) + "\""
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
        result["error"] = json.cJSON_GetStringValue(error_node)
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
        result["content"] = json.cJSON_GetStringValue(content_node)

    let thinking_node = json.cJSON_GetObjectItem(msg, "thinking")
    if thinking_node != nil:
        result["thinking"] = json.cJSON_GetStringValue(thinking_node)

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
                    call["name"] = json.cJSON_GetStringValue(fn_name)
                let fn_args = json.cJSON_GetObjectItem(fn, "arguments")
                if fn_args != nil:
                    let args_str = json.cJSON_Print(fn_args)
                    let parsed = json.cJSON_Parse(args_str)
                    if parsed != nil:
                        call["arguments"] = parsed
                        json.cJSON_Delete(parsed)
                push(result["tool_calls"], call)
            i = i + 1

    json.cJSON_Delete(obj)
    return result

proc send_and_stream(messages, tools, on_token, on_done):
    let body_str = build_request(messages, tools, true)

    let req = "POST /api/chat HTTP/1.1\r\n"
    req = req + "Host: " + OLLAMA_HOST + ":" + str(OLLAMA_PORT) + "\r\n"
    req = req + "Content-Type: application/json\r\n"
    req = req + "Content-Length: " + str(len(body_str)) + "\r\n"
    req = req + "Accept: application/x-ndjson\r\n"
    req = req + "Connection: close\r\n\r\n"
    req = req + body_str

    let conn = tcp.connect(OLLAMA_HOST, OLLAMA_PORT)
    tcp.send(conn, req)

    var status_line = ""
    var ch = tcp.recv(conn, 1)
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

    var full_content = ""
    var final_tool_calls = []
    var parse_buf = ""

    proc flush_parse_buf(buf):
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
                    let tok = json.cJSON_GetStringValue(cnode)
                    if tok != nil and len(tok) > 0:
                        full_content = full_content + tok
                        if on_token != nil:
                            on_token(tok)
                let tnode = json.cJSON_GetObjectItem(cmsg, "thinking")
                if tnode != nil:
                    let ttok = json.cJSON_GetStringValue(tnode)
                    if ttok != nil and len(ttok) > 0:
                        full_content = full_content + ttok
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
                                call["name"] = json.cJSON_GetStringValue(fn_name)
                            let fn_args = json.cJSON_GetObjectItem(fn, "arguments")
                            if fn_args != nil:
                                let args_str = json.cJSON_Print(fn_args)
                                let parsed = json.cJSON_Parse(args_str)
                                if parsed != nil:
                                    call["arguments"] = parsed
                                    json.cJSON_Delete(parsed)
                            push(final_tool_calls, call)
                        ti = ti + 1
            json.cJSON_Delete(cj)
        return remaining

    if chunked:
        while true:
            var sl = ""
            ch = tcp.recv(conn, 1)
            while ch != "\n":
                sl = sl + ch
                ch = tcp.recv(conn, 1)
            let hex_str = strip(sl)
            if hex_str == "":
                break
            let chunk_size = tonumber("0x" + hex_str)
            if chunk_size == 0:
                break
            let chunk_data = tcp.recv(conn, chunk_size)
            tcp.recv(conn, 2)
            parse_buf = flush_parse_buf(parse_buf + chunk_data)
    else:
        if content_length > 0:
            let data = tcp.recv(conn, content_length)
            parse_buf = flush_parse_buf(parse_buf + data)
        else:
            var buf = tcp.recv(conn, 4096)
            while len(buf) > 0:
                parse_buf = flush_parse_buf(parse_buf + buf)
                buf = tcp.recv(conn, 4096)

    tcp.close(conn)

    let final_body = "{\"message\":{\"role\":\"assistant\",\"content\":\"" + json_escape(full_content) + "\""
    if len(final_tool_calls) > 0:
        let tc_parts = []
        for tc in final_tool_calls:
            let args_str = "{}"
            if dict_has(tc, "arguments"):
                args_str = json.cJSON_Print(tc["arguments"])
            let entry = "{\"function\":{\"name\":\"" + json_escape(tc["name"]) + "\",\"arguments\":" + args_str + "}}"
            push(tc_parts, entry)
        final_body = final_body + ",\"tool_calls\":[" + join(tc_parts, ",") + "]"
    final_body = final_body + "}}"

    if on_done != nil:
        on_done(final_body)

    return final_body

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
    let body_str = build_request(messages, tools, false)

    var req = "POST /api/chat HTTP/1.1\r\n"
    req = req + "Host: " + OLLAMA_HOST + ":" + str(OLLAMA_PORT) + "\r\n"
    req = req + "Content-Type: application/json\r\n"
    req = req + "Content-Length: " + str(len(body_str)) + "\r\n"
    req = req + "Connection: close\r\n\r\n"
    req = req + body_str

    let conn = tcp.connect(OLLAMA_HOST, OLLAMA_PORT)
    tcp.send(conn, req)

    var status_line = ""
    var ch = tcp.recv(conn, 1)
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
            if contains(low, "chunked"):
                chunked = true

    var body = ""
    if chunked:
        while true:
            var sl = ""
            ch = tcp.recv(conn, 1)
            while ch != "\n":
                sl = sl + ch
                ch = tcp.recv(conn, 1)
            let hex_str = strip(sl)
            if hex_str == "":
                break
            let chunk_size = tonumber("0x" + hex_str)
            if chunk_size == 0:
                break
            body = body + tcp.recv(conn, chunk_size)
            tcp.recv(conn, 2)
    elif content_length > 0:
        body = tcp.recv(conn, content_length)
    else:
        var buf = tcp.recv(conn, 4096)
        while len(buf) > 0:
            body = body + buf
            buf = tcp.recv(conn, 4096)

    tcp.close(conn)
    return body

proc ask(messages, tools):
    let body = send_once(messages, tools)
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
