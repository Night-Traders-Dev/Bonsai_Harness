import tcp
import json

var http_debug = false

proc http_set_debug(on):
    http_debug = on

proc read_line(conn):
    var buf = ""
    while true:
        let c = tcp.recv(conn, 1)
        if c == "\n":
            return strip(buf)
        if c == "\r":
        else:
            buf = buf + c
    return buf

proc http_post(host, port, path, body, on_chunk):
    let req = "POST " + path + " HTTP/1.1\r\n"
    req = req + "Host: " + host + ":" + str(port) + "\r\n"
    req = req + "Content-Type: application/json\r\n"
    req = req + "Content-Length: " + str(len(body)) + "\r\n"
    req = req + "Accept: application/json\r\n"
    req = req + "Connection: close\r\n\r\n"
    req = req + body

    if http_debug:
        print "[http] POST " + path

    let conn = tcp.connect(host, port)
    tcp.send(conn, req)

    var status_line = read_line(conn)
    if http_debug:
        print "[http] " + status_line

    var content_length = 0
    var chunked = false
    var transfer_encoding = ""

    while true:
        let line = read_line(conn)
        if line == "":
            break
        let lower_line = lower(line)
        if startswith(lower_line, "content-length:"):
            let parts = split(line, ":")
            if len(parts) >= 2:
                content_length = tonumber(strip(parts[1]))
        if startswith(lower_line, "transfer-encoding:"):
            let parts = split(line, ":")
            if len(parts) >= 2:
                transfer_encoding = strip(parts[1])
                if contains(transfer_encoding, "chunked"):
                    chunked = true

    var full_body = ""

    if chunked:
        while true:
            let size_line = read_line(conn)
            if len(size_line) == 0:
                let size_line = read_line(conn)
            let hex_str = strip(size_line)
            if hex_str == "":
                break
            let chunk_size = tonumber("0x" + hex_str)
            if chunk_size == 0:
                break
            let chunk = tcp.recv(conn, chunk_size)
            tcp.recv(conn, 2)
            full_body = full_body + chunk
            if on_chunk != nil:
                on_chunk(chunk)
    else:
        if content_length > 0:
            full_body = tcp.recv(conn, content_length)
        else:
            var chunk = tcp.recv(conn, 4096)
            while len(chunk) > 0:
                full_body = full_body + chunk
                if on_chunk != nil:
                    on_chunk(chunk)
                chunk = tcp.recv(conn, 4096)

    tcp.close(conn)
    return full_body

proc http_post_raw(host, port, path, body):
    return http_post(host, port, path, body, nil)
