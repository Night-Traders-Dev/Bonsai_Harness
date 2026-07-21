import lib.benchmark as bench
import lib.tool_compiler as compiler
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

print ""
print "=== Bonsai Harness Benchmark Tests ==="
print ""

print "--- structure ---"

proc test_eight_categories():
    return expect_eq(len(bench.get_categories()), 8)

proc test_categories_have_tasks():
    for c in bench.get_categories():
        let tasks = bench.get_tasks(c)
        if len(tasks) < 5:
            print "    category too small: " + c + " (" + str(len(tasks)) + " tasks)"
            return false
    return true

proc test_tasks_well_formed():
    for c in bench.get_categories():
        for t in bench.get_tasks(c):
            if not dict_has(t, "id"):
                return false
            if not dict_has(t, "kind"):
                return false
            if not dict_has(t, "prompt"):
                return false
            # tool_compilation tasks use "expected" and "input" instead of "answer"
            if c == "tool_compilation":
                if not dict_has(t, "input") or not dict_has(t, "expected") or not dict_has(t, "compiler_fn"):
                    return false
            else:
                if not dict_has(t, "answer"):
                    return false
    return true

proc test_unknown_category_empty():
    return expect_eq(len(bench.get_tasks("nonsense")), 0)

run_test("has exactly 8 categories", test_eight_categories)
run_test("every category has >= 5 tasks", test_categories_have_tasks)
run_test("every task has id/prompt/answer/kind", test_tasks_well_formed)
run_test("unknown category returns empty", test_unknown_category_empty)

print "--- number scoring ---"

proc test_num_exact():
    return expect_eq(bench.score({"kind": "number", "answer": "72"}, "72"), true)

proc test_num_in_sentence():
    return expect_eq(bench.score({"kind": "number", "answer": "72"}, "The total is 72."), true)

proc test_num_last_wins():
    return expect_eq(bench.score({"kind": "number", "answer": "5"}, "first 100 then finally 5"), true)

proc test_num_wrong():
    return expect_eq(bench.score({"kind": "number", "answer": "72"}, "73"), false)

run_test("number exact match", test_num_exact)
run_test("number embedded in sentence", test_num_in_sentence)
run_test("number takes last number", test_num_last_wins)
run_test("number wrong fails", test_num_wrong)

print "--- choice scoring ---"

proc test_choice_letter():
    return expect_eq(bench.score({"kind": "choice", "answer": "B"}, "B"), true)

proc test_choice_paren():
    return expect_eq(bench.score({"kind": "choice", "answer": "C"}, "the answer is (C)"), true)

proc test_choice_wrong():
    return expect_eq(bench.score({"kind": "choice", "answer": "B"}, "A"), false)

run_test("choice bare letter", test_choice_letter)
run_test("choice in parentheses", test_choice_paren)
run_test("choice wrong fails", test_choice_wrong)

print "--- contains scoring ---"

proc test_contains_ok():
    return expect_eq(bench.score({"kind": "contains", "answer": "read_file"}, "use read_file"), true)

proc test_contains_case_insensitive():
    return expect_eq(bench.score({"kind": "contains", "answer": "grep"}, "Use GREP now"), true)

proc test_contains_wrong():
    return expect_eq(bench.score({"kind": "contains", "answer": "grep"}, "use glob"), false)

run_test("contains substring", test_contains_ok)
run_test("contains is case-insensitive", test_contains_case_insensitive)
run_test("contains wrong fails", test_contains_wrong)

print "--- exact_word scoring ---"

proc test_exact_ok():
    return expect_eq(bench.score({"kind": "exact_word", "answer": "DONE"}, "DONE"), true)

proc test_exact_punct():
    return expect_eq(bench.score({"kind": "exact_word", "answer": "DONE"}, "done."), true)

proc test_exact_extra_words():
    return expect_eq(bench.score({"kind": "exact_word", "answer": "DONE"}, "all done here"), false)

run_test("exact_word match", test_exact_ok)
run_test("exact_word ignores punctuation/case", test_exact_punct)
run_test("exact_word rejects extra words", test_exact_extra_words)

print ""
print "--- tool_compilation ---"

proc test_tc_has_tasks():
    let tasks = bench.get_tasks("tool_compilation")
    let count = len(tasks)
    if count < 15:
        print "    expected >= 15 tasks, got " + str(count)
        return false
    return true

proc test_tc_tasks_well_formed():
    for t in bench.get_tasks("tool_compilation"):
        if not dict_has(t, "id"):
            return false
        if not dict_has(t, "compiler_fn"):
            return false
        if not dict_has(t, "input"):
            return false
        if not dict_has(t, "expected"):
            return false
    return true

proc test_tc_extract_json():
    let result = bench.score_compiler_task({"compiler_fn": "extract_json", "input": "Here: {\"name\":\"grep\",\"arguments\":{\"pattern\":\"test\"}}", "expected": "grep"})
    return expect_eq(result["correct"], true)

proc test_tc_extract_intent():
    let result = bench.score_compiler_task({"compiler_fn": "extract_intent", "input": "INTENT: find the error\nFUNCTION: grep", "expected": "find the error"})
    return expect_eq(result["correct"], true)

proc test_tc_validate_true():
    let result = bench.score_compiler_task({"compiler_fn": "validate", "input": "{\"name\":\"bash\",\"arguments_str\":\"{\\\"command\\\":\\\"ls\\\"}\"}", "expected": "true"})
    return expect_eq(result["correct"], true)

proc test_tc_validate_false():
    let result = bench.score_compiler_task({"compiler_fn": "validate", "input": "{\"name\":\"bash\",\"arguments_str\":\"{}\"}", "expected": "false"})
    return expect_eq(result["correct"], true)

proc test_tc_prompt_contains():
    let result = bench.score_compiler_task({"compiler_fn": "check_prompt_contains", "input": "search for error", "expected": "search for error"})
    return expect_eq(result["correct"], true)

proc test_tc_all_tasks_score():
    for t in bench.get_tasks("tool_compilation"):
        let result = bench.score_compiler_task(t)
        if not result["correct"]:
            print "    failed task: " + t["id"] + " output: " + slice(result["output"], 0, 100)
            return false
    return true

run_test("tool_compilation has tasks", test_tc_has_tasks)
run_test("tool_compilation tasks well-formed", test_tc_tasks_well_formed)
run_test("score_compiler_task extract_json", test_tc_extract_json)
run_test("score_compiler_task extract_intent", test_tc_extract_intent)
run_test("score_compiler_task validate true", test_tc_validate_true)
run_test("score_compiler_task validate false", test_tc_validate_false)
run_test("score_compiler_task prompt contains", test_tc_prompt_contains)
run_test("all tool_compilation tasks pass", test_tc_all_tasks_score)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise str(failed) + " test(s) failed"
