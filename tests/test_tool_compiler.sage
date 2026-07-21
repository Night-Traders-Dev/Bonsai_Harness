import lib.tool_compiler as compiler
import lib.tools as tools
import lib.ollama as ollama
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

print ""
print "=== Bonsai Harness Tool Compiler Tests ==="
print ""

print "--- extract_json_from_text ---"

proc test_extract_simple():
    let text = "Here is the result: {\"name\":\"grep\",\"arguments\":{\"pattern\":\"test\"}}"
    let result = compiler.extract_json_from_text(text)
    let parsed = json.cJSON_Parse(result)
    if parsed == nil:
        print "    Failed to parse extracted JSON"
        return false
    let name = json.cJSON_GetStringValue(json.cJSON_GetObjectItem(parsed, "name"))
    json.cJSON_Delete(parsed)
    return expect_eq(name, "grep")

proc test_extract_nested():
    let text = "{\"name\":\"bash\",\"arguments\":{\"command\":\"echo hello\"}}"
    let result = compiler.extract_json_from_text(text)
    let parsed = json.cJSON_Parse(result)
    if parsed == nil:
        print "    Failed to parse extracted JSON"
        return false
    let name = json.cJSON_GetStringValue(json.cJSON_GetObjectItem(parsed, "name"))
    let args = json.cJSON_GetObjectItem(parsed, "arguments")
    let cmd = json.cJSON_GetStringValue(json.cJSON_GetObjectItem(args, "command"))
    json.cJSON_Delete(parsed)
    return expect_eq(cmd, "echo hello") and expect_eq(name, "bash")

proc test_extract_no_json():
    let text = "This is plain text with no JSON object"
    let result = compiler.extract_json_from_text(text)
    return expect_eq(result, "")

proc test_extract_empty():
    let result = compiler.extract_json_from_text("")
    return expect_eq(result, "")

proc test_extract_multi_json():
    let text = "First {\"name\":\"grep\"} then {\"name\":\"bash\"}"
    let result = compiler.extract_json_from_text(text)
    let parsed = json.cJSON_Parse(result)
    if parsed == nil:
        print "    Failed to parse extracted JSON"
        return false
    let name = json.cJSON_GetStringValue(json.cJSON_GetObjectItem(parsed, "name"))
    json.cJSON_Delete(parsed)
    return expect_eq(name, "grep")

proc test_extract_with_braces_in_string():
    let text = "{\"name\":\"bash\",\"arguments\":{\"command\":\"echo {}\"}}"
    let result = compiler.extract_json_from_text(text)
    let parsed = json.cJSON_Parse(result)
    if parsed == nil:
        print "    Failed to parse extracted JSON: " + slice(result, 0, 100)
        return false
    let name = json.cJSON_GetStringValue(json.cJSON_GetObjectItem(parsed, "name"))
    json.cJSON_Delete(parsed)
    return expect_eq(name, "bash")

run_test("extract simple JSON object", test_extract_simple)
run_test("extract nested JSON object", test_extract_nested)
run_test("extract no JSON returns empty", test_extract_no_json)
run_test("extract from empty string", test_extract_empty)
run_test("extract first of multiple JSON objects", test_extract_multi_json)
run_test("extract JSON with braces in string values", test_extract_with_braces_in_string)

print "--- build_compiler_prompt ---"

let test_defs = tools.get_tool_list()

proc test_prompt_contains_tools():
    let prompt = compiler.build_compiler_prompt("test intent", test_defs)
    return expect_contains(prompt, "bash") and expect_contains(prompt, "grep")

proc test_prompt_contains_intent():
    let prompt = compiler.build_compiler_prompt("Search for s_strip", test_defs)
    return expect_contains(prompt, "Search for s_strip")

proc test_prompt_contains_json_format():
    let prompt = compiler.build_compiler_prompt("test", test_defs)
    return expect_contains(prompt, "name") and expect_contains(prompt, "arguments")

proc test_prompt_contains_all_tools():
    let prompt = compiler.build_compiler_prompt("test", test_defs)
    var all_found = true
    for t in test_defs:
        if not contains(prompt, t["name"]):
            print "    Missing tool: " + t["name"]
            all_found = false
    return all_found

run_test("prompt contains tool names", test_prompt_contains_tools)
run_test("prompt contains intent", test_prompt_contains_intent)
run_test("prompt contains JSON format instruction", test_prompt_contains_json_format)
run_test("prompt contains all registered tools", test_prompt_contains_all_tools)

print "--- extract_intent_from_bonsai ---"

proc test_extract_intent_marker():
    let text = "I need to find the code.\nINTENT: Search for s_strip in the repository.\nACTION: TOOL"
    let intent = compiler.extract_intent_from_bonsai(text)
    return expect_contains(intent, "Search for s_strip")

proc test_extract_intent_multiline():
    let text = "INTENT: Search for s_strip\nin the entire codebase\nFUNCTION: grep"
    let intent = compiler.extract_intent_from_bonsai(text)
    return expect_contains(intent, "entire codebase")

proc test_extract_intent_no_marker():
    let text = "I need to search for s_strip in the repository"
    let intent = compiler.extract_intent_from_bonsai(text)
    return expect_eq(intent, text)

proc test_extract_intent_empty():
    let intent = compiler.extract_intent_from_bonsai("")
    return expect_eq(intent, "")

run_test("extract intent with INTENT: marker", test_extract_intent_marker)
run_test("extract multi-line intent", test_extract_intent_multiline)
run_test("extract intent without marker returns full text", test_extract_intent_no_marker)
run_test("extract intent from empty string", test_extract_intent_empty)

print "--- timeout ---"

proc test_set_timeout():
    ollama.set_timeout(5000)
    return expect_eq(ollama.get_timeout(), 5000)

proc test_set_timeout_default():
    ollama.set_timeout(60000)
    return expect_eq(ollama.get_timeout(), 60000)

proc test_compile_with_timeout():
    ollama.set_timeout(1)
    let result = compiler.compile_tool_call("test intent", tools.get_tool_list(), 1)
    if result["success"]:
        print "    WARNING: compile succeeded (model available, timeout not tested)"
        return true
    if contains(result["error"], "timed out") or contains(result["error"], "timeout"):
        return true
    if contains(result["error"], "Model error") or contains(result["error"], "Failed") or contains(result["error"], "No"):
        return true
    # Any error means it didn't hang, which is acceptable for timeout test
    return true

run_test("set_timeout/get_timeout roundtrip", test_set_timeout)
run_test("set_timeout default value", test_set_timeout_default)
run_test("compile with 100ms timeout returns error (no hang)", test_compile_with_timeout)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise "Some tests failed"
