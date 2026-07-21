import lib.model_router as router
import lib.model_config as cfg

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
print "=== Bonsai Harness Model Router Tests ==="
print ""

print "--- route_task ---"

proc test_route_reasoning():
    let role = router.route_task(router.TASK_REASONING)
    return expect_eq(role, cfg.ROLE_PRIMARY)

proc test_route_planning():
    let role = router.route_task(router.TASK_PLANNING)
    return expect_eq(role, cfg.ROLE_PRIMARY)

proc test_route_coding():
    let role = router.route_task(router.TASK_CODING)
    return expect_eq(role, cfg.ROLE_PRIMARY)

proc test_route_analysis():
    let role = router.route_task(router.TASK_ANALYSIS)
    return expect_eq(role, cfg.ROLE_PRIMARY)

proc test_route_final_response():
    let role = router.route_task(router.TASK_FINAL_RESPONSE)
    return expect_eq(role, cfg.ROLE_PRIMARY)

proc test_route_tool_call():
    let role = router.route_task(router.TASK_TOOL_CALL)
    return expect_eq(role, cfg.ROLE_TOOL_COMPILER)

proc test_route_tool_compile():
    let role = router.route_task(router.TASK_TOOL_COMPILE)
    return expect_eq(role, cfg.ROLE_TOOL_COMPILER)

proc test_route_classification():
    let role = router.route_task(router.TASK_CLASSIFICATION)
    return expect_eq(role, cfg.ROLE_TOOL_COMPILER)

proc test_route_unknown():
    let role = router.route_task("unknown_task_type")
    return expect_eq(role, cfg.ROLE_PRIMARY)

proc test_route_empty():
    let role = router.route_task("")
    return expect_eq(role, cfg.ROLE_PRIMARY)

run_test("reasoning routes to primary", test_route_reasoning)
run_test("planning routes to primary", test_route_planning)
run_test("coding routes to primary", test_route_coding)
run_test("analysis routes to primary", test_route_analysis)
run_test("final_response routes to primary", test_route_final_response)
run_test("tool_call routes to tool compiler", test_route_tool_call)
run_test("tool_compile routes to tool compiler", test_route_tool_compile)
run_test("classification routes to tool compiler", test_route_classification)
run_test("unknown task routes to primary (fallback)", test_route_unknown)
run_test("empty task routes to primary (fallback)", test_route_empty)

print "--- model_config ---"

proc test_get_model_for_role_primary():
    let model = cfg.get_model_for_role(cfg.ROLE_PRIMARY)
    return expect_eq(model, cfg.MODEL_BONSAI)

proc test_get_model_for_role_tool():
    let model = cfg.get_model_for_role(cfg.ROLE_TOOL_COMPILER)
    return expect_eq(model, cfg.MODEL_MINICPM)

proc test_set_model_for_role():
    cfg.set_model_for_role(cfg.ROLE_PRIMARY, "test-model")
    let model = cfg.get_model_for_role(cfg.ROLE_PRIMARY)
    cfg.set_model_for_role(cfg.ROLE_PRIMARY, cfg.MODEL_BONSAI)
    return expect_eq(model, "test-model")

proc test_get_role_label_primary():
    let label = cfg.get_role_label(cfg.ROLE_PRIMARY)
    return expect_contains(label, "Bonsai")

proc test_get_role_label_tool():
    let label = cfg.get_role_label(cfg.ROLE_TOOL_COMPILER)
    return expect_contains(label, "MiniCPM")

run_test("get_model_for_role returns Bonsai for primary", test_get_model_for_role_primary)
run_test("get_model_for_role returns MiniCPM for tool", test_get_model_for_role_tool)
run_test("set_model_for_role updates model", test_set_model_for_role)
run_test("get_role_label for primary contains Bonsai", test_get_role_label_primary)
run_test("get_role_label for tool contains MiniCPM", test_get_role_label_tool)

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise "Some tests failed"
