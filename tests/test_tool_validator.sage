import lib.tool_validator as validator
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

proc expect_valid(result):
    if not result["valid"]:
        print "    expected valid, got error: " + result["error"]
        return false
    return true

proc expect_invalid(result, expected_error):
    if result["valid"]:
        print "    expected invalid, but was valid"
        return false
    return expect_contains(result["error"], expected_error)

print ""
print "=== Bonsai Harness Tool Validator Tests ==="
print ""

print "--- argument extraction ---"

proc test_get_arguments_dict():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments"] = {"command": "echo hello"}
    let args = validator.get_arguments(tc)
    return expect_eq(args["command"], "echo hello")

proc test_get_arguments_str():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments_str"] = "{\"command\":\"echo hello\"}"
    let args = validator.get_arguments(tc)
    return expect_eq(args["command"], "echo hello")

proc test_get_arguments_empty():
    let tc = {}
    tc["name"] = "bash"
    let args = validator.get_arguments(tc)
    return expect_eq(len(dict_keys(args)), 0)

run_test("get_arguments from dict", test_get_arguments_dict)
run_test("get_arguments from arguments_str", test_get_arguments_str)
run_test("get_arguments returns empty dict when absent", test_get_arguments_empty)

print "--- structural validation ---"

proc test_valid_tool_call():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments"] = {"command": "echo hello"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

proc test_missing_name():
    let tc = {}
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "name")

proc test_missing_arguments():
    let tc = {}
    tc["name"] = "noargs_tool"
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "Unknown")

proc test_empty_name():
    let tc = {}
    tc["name"] = ""
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "empty")

proc test_non_string_name():
    let tc = {}
    tc["name"] = 123
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "string")

run_test("valid tool call passes", test_valid_tool_call)
run_test("missing name fails", test_missing_name)
run_test("unknown tool rejected on bad name", test_missing_arguments)
run_test("empty name fails", test_empty_name)
run_test("non-string name fails", test_non_string_name)

print "--- unknown tool ---"

proc test_unknown_tool():
    let tc = {}
    tc["name"] = "nonexistent_tool"
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "Unknown")

run_test("unknown tool rejected", test_unknown_tool)

print "--- bash validation ---"

proc test_bash_missing_command():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "command")

proc test_bash_empty_command():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments"] = {"command": ""}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "command")

proc test_bash_valid():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments"] = {"command": "ls -la"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

proc test_bash_destructive_rejected():
    let tc = {}
    tc["name"] = "bash"
    tc["arguments"] = {"command": "rm -rf /"}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "security")

run_test("bash missing command rejected", test_bash_missing_command)
run_test("bash empty command rejected", test_bash_empty_command)
run_test("bash valid command passes", test_bash_valid)
run_test("bash destructive command rejected", test_bash_destructive_rejected)

print "--- grep validation ---"

proc test_grep_missing_pattern():
    let tc = {}
    tc["name"] = "grep"
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "pattern")

proc test_grep_valid():
    let tc = {}
    tc["name"] = "grep"
    tc["arguments"] = {"pattern": "hello"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

run_test("grep missing pattern rejected", test_grep_missing_pattern)
run_test("grep valid pattern passes", test_grep_valid)

print "--- glob validation ---"

proc test_glob_missing_pattern():
    let tc = {}
    tc["name"] = "glob"
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "pattern")

proc test_glob_valid():
    let tc = {}
    tc["name"] = "glob"
    tc["arguments"] = {"pattern": "*.sage"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

run_test("glob missing pattern rejected", test_glob_missing_pattern)
run_test("glob valid pattern passes", test_glob_valid)

print "--- read_file validation ---"

proc test_read_file_missing_path():
    let tc = {}
    tc["name"] = "read_file"
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "path")

proc test_read_file_path_traversal():
    let tc = {}
    tc["name"] = "read_file"
    tc["arguments"] = {"path": "../../etc/passwd"}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "traversal")

proc test_read_file_valid():
    let tc = {}
    tc["name"] = "read_file"
    tc["arguments"] = {"path": "test.txt"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

run_test("read_file missing path rejected", test_read_file_missing_path)
run_test("read_file path traversal rejected", test_read_file_path_traversal)
run_test("read_file valid path passes", test_read_file_valid)

print "--- web_fetch validation ---"

proc test_web_fetch_missing_url():
    let tc = {}
    tc["name"] = "web_fetch"
    tc["arguments"] = {}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "url")

proc test_web_fetch_unsupported_scheme_rejected():
    let tc = {}
    tc["name"] = "web_fetch"
    tc["arguments"] = {"url": "ftp://example.com"}
    let r = validator.validate_tool_call(tc)
    return expect_invalid(r, "URLs are supported")

proc test_web_fetch_valid_http():
    let tc = {}
    tc["name"] = "web_fetch"
    tc["arguments"] = {"url": "http://example.com"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

proc test_web_fetch_valid_https():
    let tc = {}
    tc["name"] = "web_fetch"
    tc["arguments"] = {"url": "https://example.com"}
    let r = validator.validate_tool_call(tc)
    return expect_valid(r)

run_test("web_fetch missing url rejected", test_web_fetch_missing_url)
run_test("web_fetch unsupported scheme rejected", test_web_fetch_unsupported_scheme_rejected)
run_test("web_fetch valid http passes", test_web_fetch_valid_http)
run_test("web_fetch valid https passes", test_web_fetch_valid_https)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise "Some tests failed"
