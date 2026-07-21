import lib.tui as tui
import lib.model_provider as provider

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

print ""
print "=== Bonsai Harness TUI & Interactive Tests ==="
print ""

proc test_strip_ansi():
    let input_str = "\x1b[31mRed Text\x1b[0m"
    let clean = tui.strip_ansi(input_str)
    return expect_eq(clean, "Red Text")

proc test_strip_ansi_plain():
    let input_str = "Plain Text"
    let clean = tui.strip_ansi(input_str)
    return expect_eq(clean, "Plain Text")

proc test_find_suggestion_builtin():
    let match_help = tui.find_suggestion(":h")
    let match_clear = tui.find_suggestion(":cl")
    let match_models = tui.find_suggestion(":m")
    let match_bench = tui.find_suggestion(":b")
    return expect_eq(match_help, ":help") and expect_eq(match_clear, ":clear") and expect_eq(match_models, ":models") and expect_eq(match_bench, ":bench")

proc test_find_suggestion_history():
    tui.add_to_input_history("what is the weather today")
    tui.add_to_input_history("how to calculate fibonacci")
    let match_what = tui.find_suggestion("what")
    let match_case = tui.find_suggestion("HOW TO")
    return expect_eq(match_what, "what is the weather today") and expect_eq(match_case, "how to calculate fibonacci")

proc test_find_suggestion_empty():
    let empty_match = tui.find_suggestion("")
    let nomatch = tui.find_suggestion(":nonexistent_cmd")
    return expect_eq(empty_match, "") and expect_eq(nomatch, "")

proc test_model_provider_unload_all():
    # Verify provider.unload_all is callable without throwing runtime exceptions
    provider.unload_all()
    return true

run_test("strip_ansi removes escape codes", test_strip_ansi)
run_test("strip_ansi leaves plain text unchanged", test_strip_ansi_plain)
run_test("find_suggestion matches builtin commands", test_find_suggestion_builtin)
run_test("find_suggestion matches past history entries", test_find_suggestion_history)
run_test("find_suggestion handles empty and non-matching inputs", test_find_suggestion_empty)
run_test("model_provider unload_all procedure execution", test_model_provider_unload_all)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise "TUI tests failed"
