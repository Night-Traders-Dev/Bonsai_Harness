import lib.agent as agent
import lib.tools as tools
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

print ""
print "=== Bonsai Harness Agent Loop Tests ==="
print ""

print "--- init_history ---"

proc test_init_history_has_system():
    let h = agent.init_history()
    if len(h) != 1:
        print "    expected 1 entry, got " + str(len(h))
        return false
    return expect_eq(h[0]["role"], "system")

proc test_init_history_contains_tools():
    let h = agent.init_history()
    let content = h[0]["content"]
    return expect_contains(content, "Available tools")

run_test("init_history returns one system message", test_init_history_has_system)
run_test("init_history system message lists tools", test_init_history_contains_tools)

print "--- init_history_with_skills ---"

proc test_init_skills_nil():
    let h = agent.init_history_with_skills(nil)
    return expect_eq(len(h), 1)

proc test_init_skills_empty():
    let h = agent.init_history_with_skills("")
    return expect_eq(len(h), 1)

proc test_init_skills_content():
    let h = agent.init_history_with_skills("Custom skill content")
    let content = h[0]["content"]
    return expect_contains(content, "Custom skill content") and expect_contains(content, "Loaded Skills")

run_test("init_history_with_skills nil falls back", test_init_skills_nil)
run_test("init_history_with_skills empty falls back", test_init_skills_empty)
run_test("init_history_with_skills injects skills", test_init_skills_content)

print "--- parse_text_tool_call ---"

proc test_parse_function():
    let result = agent.parse_text_tool_call("FUNCTION: grep\nARGUMENTS: {\"pattern\":\"hello\"}")
    return result["has_tool_call"] and expect_eq(result["name"], "grep")

proc test_parse_final():
    let result = agent.parse_text_tool_call("FINAL: The answer is 42")
    return result["has_final"] and expect_eq(result["final_answer"], "The answer is 42")

proc test_parse_no_match():
    let result = agent.parse_text_tool_call("Just a normal response")
    return not result["has_tool_call"] and not result["has_final"]

proc test_parse_case_insensitive():
    let result = agent.parse_text_tool_call("function: bash\narguments: {\"command\":\"ls\"}")
    return result["has_tool_call"] and expect_eq(result["name"], "bash")

proc test_parse_empty():
    let result = agent.parse_text_tool_call("")
    return not result["has_tool_call"] and not result["has_final"]

proc test_parse_function_whitespace():
    let result = agent.parse_text_tool_call("  FUNCTION:   grep  ")
    return result["has_tool_call"] and expect_eq(result["name"], "grep")

run_test("parse FUNCTION: tool call", test_parse_function)
run_test("parse FINAL: answer", test_parse_final)
run_test("parse plain text returns no match", test_parse_no_match)
run_test("parse is case-insensitive", test_parse_case_insensitive)
run_test("parse empty string", test_parse_empty)
run_test("parse handles whitespace", test_parse_function_whitespace)

print "--- trim_history ---"

proc test_trim_keeps_system():
    let h = agent.init_history()
    push(h, {"role": "user", "content": "hello"})
    push(h, {"role": "assistant", "content": "world"})
    agent.trim_history(h)
    return expect_eq(h[0]["role"], "system") and len(h) >= 2

proc test_trim_keeps_last_message():
    let h = agent.init_history()
    push(h, {"role": "user", "content": "short"})
    push(h, {"role": "assistant", "content": "answer"})
    agent.trim_history(h)
    return expect_eq(h[0]["role"], "system") and h[len(h) - 1]["role"] == "assistant"

run_test("trim_history keeps system prompt", test_trim_keeps_system)
run_test("trim_history keeps last message", test_trim_keeps_last_message)

print "--- build_tool_result_entry ---"

proc test_build_entry_structure():
    let entry = agent.build_tool_result_entry("grep", "file.txt:1:match")
    return expect_eq(entry["role"], "tool") and expect_contains(entry["content"], "TOOL RESULT")

proc test_build_entry_name():
    let entry = agent.build_tool_result_entry("bash", "output")
    return expect_eq(entry["name"], "bash")

run_test("build_tool_result_entry has correct role", test_build_entry_structure)
run_test("build_tool_result_entry stores tool name", test_build_entry_name)

print "--- _cjson_get_str ---"

proc test_cjson_get_str_exists():
    let cj = json.cJSON_Parse("{\"path\":\"test.txt\"}")
    let val = agent._cjson_get_str(cj, "path")
    json.cJSON_Delete(cj)
    return expect_eq(val, "test.txt")

proc test_cjson_get_str_missing():
    let cj = json.cJSON_Parse("{\"name\":\"test\"}")
    let val = agent._cjson_get_str(cj, "nonexistent")
    json.cJSON_Delete(cj)
    return expect_eq(val, "")

run_test("_cjson_get_str extracts value", test_cjson_get_str_exists)
run_test("_cjson_get_str missing key returns empty", test_cjson_get_str_missing)

print "--- _cjson_into_dict ---"

proc test_cjson_into_dict():
    let cj = json.cJSON_Parse("{\"path\":\"test.txt\",\"command\":\"ls\",\"pattern\":\"hello\",\"url\":\"http://example.com\",\"content\":\"data\"}")
    var target = {}
    agent._cjson_into_dict(cj, target)
    json.cJSON_Delete(cj)
    return expect_eq(target["path"], "test.txt") and expect_eq(target["command"], "ls") and expect_eq(target["pattern"], "hello") and expect_eq(target["url"], "http://example.com") and expect_eq(target["content"], "data")

run_test("_cjson_into_dict copies all known keys", test_cjson_into_dict)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise "Some tests failed"
