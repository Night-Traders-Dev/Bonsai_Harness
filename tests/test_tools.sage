import lib.tools as tools
import io
import sys
import json

var passed = 0
var failed = 0

proc run_test(name, fn):
    print "  " + name + " ... "
    let ok = fn()
    if ok:
        print "    PASS"
        passed = passed + 1
    else:
        print "    FAIL"
        failed = failed + 1

proc expect_eq(actual, expected):
    if actual != expected:
        print "    expected: " + str(expected)
        print "    actual:   " + str(actual)
        return false
    return true

proc expect_contains(actual, substr):
    let idx = indexof(actual, substr)
    if idx < 0:
        print "    expected to contain: " + substr
        print "    actual:             " + str(actual)
        return false
    return true

proc expect_startswith(actual, prefix):
    if not startswith(actual, prefix):
        print "    expected to start with: " + prefix
        print "    actual:                " + str(actual)
        return false
    return true

proc expect_nil(val):
    if val != nil:
        print "    expected nil, got: " + str(val)
        return false
    return true

let TEST_FILE = "test_bonsai_write_temp.txt"
let TEST_CONTENT = "Hello from Bonsai test suite!"

print ""
print "=== Bonsai Harness Tool Tests ==="
print ""

print "--- register_tool / get_tool_list ---"

proc test_list_count():
    let list = tools.get_tool_list()
    return expect_eq(len(list), 7)

proc test_list_props():
    let list = tools.get_tool_list()
    for t in list:
        if not dict_has(t, "name") or not dict_has(t, "description") or not dict_has(t, "parameters"):
            return false
    return true

proc test_list_names():
    let names = ["bash", "read_file", "write_file", "grep", "glob", "list_dir", "web_fetch"]
    let list = tools.get_tool_list()
    for n in names:
        var found = false
        for t in list:
            if t["name"] == n:
                found = true
                break
        if not found:
            print "    missing tool: " + n
            return false
    return true

run_test("get_tool_list returns 7 tools", test_list_count)
run_test("entries have name, description, parameters", test_list_props)
run_test("all 7 tool names are correct", test_list_names)

print "--- bash ---"

proc test_bash_echo():
    let result = tools.execute_tool("bash", {"command": "echo hello_bonsai"})
    return expect_contains(result, "hello_bonsai")

proc test_bash_pwd():
    let result = tools.execute_tool("bash", {"command": "pwd"})
    return expect_contains(result, "Bonsai_Harness")

proc test_bash_no_command():
    let result = tools.execute_tool("bash", {})
    return expect_eq(result, "Error: 'command' argument required")

run_test("echo command", test_bash_echo)
run_test("pwd returns working directory", test_bash_pwd)
run_test("missing command returns error", test_bash_no_command)

print "--- write_file ---"

proc test_write_creates_file():
    let r = tools.execute_tool("write_file", {"path": TEST_FILE, "content": TEST_CONTENT})
    if not expect_eq(r, "File written: " + TEST_FILE):
        return false
    if not io.exists(TEST_FILE):
        print "    file was not created"
        return false
    return true

proc test_write_missing_path():
    let r = tools.execute_tool("write_file", {"content": "x"})
    return expect_eq(r, "Error: 'path' and 'content' arguments required")

proc test_write_missing_content():
    let r = tools.execute_tool("write_file", {"path": "/tmp/x"})
    return expect_eq(r, "Error: 'path' and 'content' arguments required")

run_test("creates file with content", test_write_creates_file)
run_test("missing path returns error", test_write_missing_path)
run_test("missing content returns error", test_write_missing_content)

print "--- read_file ---"

proc test_read_written():
    let r = tools.execute_tool("read_file", {"path": TEST_FILE})
    return expect_eq(r, TEST_CONTENT)

proc test_read_missing():
    let r = tools.execute_tool("read_file", {"path": "nonexistent_bonsai_test_file"})
    return expect_startswith(r, "Error: File not found:")

proc test_read_no_path():
    let r = tools.execute_tool("read_file", {})
    return expect_eq(r, "Error: 'path' argument required")

run_test("reads written content", test_read_written)
run_test("missing file returns error", test_read_missing)
run_test("missing path argument returns error", test_read_no_path)

print "--- grep ---"

proc test_grep_find():
    let r = tools.execute_tool("grep", {"pattern": "Bonsai", "path": TEST_FILE})
    return expect_contains(r, "Bonsai")

proc test_grep_no_match():
    let r = tools.execute_tool("grep", {"pattern": "XYZZYX_NOMATCH_12345", "path": TEST_FILE})
    return expect_contains(r, "No matches")

proc test_grep_no_pattern():
    let r = tools.execute_tool("grep", {})
    return expect_eq(r, "Error: 'pattern' argument required")

run_test("find pattern in file", test_grep_find)
run_test("no match returns message", test_grep_no_match)
run_test("missing pattern returns error", test_grep_no_pattern)

print "--- glob ---"

proc test_glob_sage():
    let r = tools.execute_tool("glob", {"pattern": "*.sage"})
    return expect_contains(r, ".sage")

proc test_glob_no_match():
    let r = tools.execute_tool("glob", {"pattern": "XYZZYX_NOMATCH_12345"})
    return expect_contains(r, "No matches")

proc test_glob_no_pattern():
    let r = tools.execute_tool("glob", {})
    return expect_eq(r, "Error: 'pattern' argument required")

run_test("find .sage files", test_glob_sage)
run_test("no match returns message", test_glob_no_match)
run_test("missing pattern returns error", test_glob_no_pattern)

print "--- list_dir ---"

proc test_list_cwd():
    let r = tools.execute_tool("list_dir", {})
    return expect_contains(r, "lib")

proc test_list_lib():
    let r = tools.execute_tool("list_dir", {"path": "lib"})
    return expect_contains(r, "agent.sage")

proc test_list_invalid():
    let r = tools.execute_tool("list_dir", {"path": "nonexistent_bonsai_dir_xyz"})
    return expect_startswith(r, "Error: Not a directory:")

run_test("current directory", test_list_cwd)
run_test("lib directory lists agent.sage", test_list_lib)
run_test("invalid path returns error", test_list_invalid)

print "--- web_fetch ---"

proc test_web_fetch_ssrf_blocked():
    let r = tools.execute_tool("web_fetch", {"url": "http://localhost:11434"})
    return expect_contains(r, "cannot fetch from private or loopback")

proc test_web_fetch_https_ssrf_blocked():
    let r = tools.execute_tool("web_fetch", {"url": "https://localhost:11434"})
    return expect_contains(r, "cannot fetch from private or loopback")

proc test_web_fetch_no_url():
    let r = tools.execute_tool("web_fetch", {})
    return expect_eq(r, "Error: 'url' argument required")

run_test("SSRF blocks localhost", test_web_fetch_ssrf_blocked)
run_test("HTTPS SSRF blocks localhost", test_web_fetch_https_ssrf_blocked)
run_test("missing url returns error", test_web_fetch_no_url)

print "--- unknown tool ---"

proc test_unknown_tool():
    let r = tools.execute_tool("nonexistent_tool_xyz", {})
    return expect_startswith(r, "Error: Unknown tool")

run_test("unknown tool returns error", test_unknown_tool)

print "--- cleanup ---"

io.remove(TEST_FILE)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise str(failed) + " test(s) failed"
