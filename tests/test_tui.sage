import lib.tui as tui

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
print "=== Bonsai Harness TUI Tests ==="
print ""

proc test_strip_ansi():
    let input_str = "\x1b[31mRed Text\x1b[0m"
    let clean = tui.strip_ansi(input_str)
    return expect_eq(clean, "Red Text")

proc test_strip_ansi_plain():
    let input_str = "Plain Text"
    let clean = tui.strip_ansi(input_str)
    return expect_eq(clean, "Plain Text")

run_test("strip_ansi removes escape codes", test_strip_ansi)
run_test("strip_ansi leaves plain text unchanged", test_strip_ansi_plain)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise "TUI tests failed"
