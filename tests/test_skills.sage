import lib.skills as skills
import lib.agent as agent
import io
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

let TEST_DIR = "/tmp/bonsai_skills_test"
let SKILL1_PATH = TEST_DIR + "/test_skill_a.md"
let SKILL2_PATH = TEST_DIR + "/test_skill_b.md"
let SKILL1_NAME = "test_skill_a"
let SKILL2_NAME = "test_skill_b"

proc setup():
    if not io.exists(TEST_DIR):
        io.mkdir(TEST_DIR)
    io.writefile(SKILL1_PATH, "This is skill A.\nIt has multiple lines.\n")
    io.writefile(SKILL2_PATH, "This is skill B.\n")

proc teardown():
    io.remove(SKILL1_PATH)
    io.remove(SKILL2_PATH)
    io.remove(TEST_DIR)

print ""
print "=== Bonsai Harness Skills Tests ==="
print ""

setup()

print "--- load_skills ---"

proc test_load_md():
    let result = skills.load_skills(TEST_DIR)
    if not expect_contains(result, "Skill: " + SKILL1_NAME):
        return false
    if not expect_contains(result, "This is skill A."):
        return false
    if not expect_contains(result, "Skill: " + SKILL2_NAME):
        return false
    if not expect_contains(result, "This is skill B."):
        return false
    return true

proc test_count_two():
    return expect_eq(skills.get_skills_count(), 2)

proc test_content_nonempty():
    let c = skills.get_skills_content()
    return expect_eq(len(c) > 0, true)

proc test_empty_dir():
    let empty_dir = TEST_DIR + "/empty"
    if not io.exists(empty_dir):
        io.mkdir(empty_dir)
    let result = skills.load_skills(empty_dir)
    let ok = expect_eq(result, "")
    io.remove(empty_dir)
    return ok

proc test_nonexistent_dir():
    let result = skills.load_skills("/tmp/bonsai_nonexistent_xyz_skills")
    return expect_eq(result, "")

run_test("loads .md files from directory", test_load_md)
run_test("get_skills_count returns 2", test_count_two)
run_test("get_skills_content returns non-empty", test_content_nonempty)
run_test("load empty directory returns empty", test_empty_dir)
run_test("load non-existent directory returns empty", test_nonexistent_dir)

print "--- init_history_with_skills ---"

proc test_hist_includes_skills():
    skills.load_skills(TEST_DIR)
    let hist = agent.init_history_with_skills(skills.get_skills_content())
    if not expect_eq(len(hist), 1):
        return false
    if not expect_eq(hist[0]["role"], "system"):
        return false
    if not expect_contains(hist[0]["content"], "Loaded Skills"):
        return false
    if not expect_contains(hist[0]["content"], "Skill: " + SKILL1_NAME):
        return false
    if not expect_contains(hist[0]["content"], "This is skill A."):
        return false
    return true

proc test_hist_empty_skills():
    let hist_default = agent.init_history()
    let hist_empty = agent.init_history_with_skills("")
    if not expect_eq(len(hist_empty), 1):
        return false
    if not expect_eq(hist_empty[0]["role"], "system"):
        return false
    if not expect_contains(hist_empty[0]["content"], "Available tools"):
        return false
    if indexof(hist_empty[0]["content"], "Loaded Skills") >= 0:
        print "    should NOT contain skills header when no skills"
        return false
    return true

proc test_hist_nil_skills():
    let hist = agent.init_history_with_skills(nil)
    let content = hist[0]["content"]
    if indexof(content, "Loaded Skills") >= 0:
        print "    should NOT contain skills header when nil"
        return false
    return true

run_test("history with skills includes skills in system prompt", test_hist_includes_skills)
run_test("history with empty skills is same as default", test_hist_empty_skills)
run_test("history with nil skills is same as default", test_hist_nil_skills)

print "--- frontmatter parsing ---"

proc test_fm_basic():
    let content = "---\nname: my-skill\ndescription: Does a thing.\n---\n\n# Body\nHello.\n"
    let p = skills.parse_frontmatter(content)
    if not expect_eq(p["has_frontmatter"], true):
        return false
    if not expect_eq(p["name"], "my-skill"):
        return false
    if not expect_eq(p["description"], "Does a thing."):
        return false
    if not expect_contains(p["body"], "# Body"):
        return false
    if indexof(p["body"], "name: my-skill") >= 0:
        print "    body should not contain frontmatter"
        return false
    return true

proc test_fm_none():
    let content = "# Just a heading\nNo frontmatter here.\n"
    let p = skills.parse_frontmatter(content)
    if not expect_eq(p["has_frontmatter"], false):
        return false
    if not expect_eq(p["name"], ""):
        return false
    if not expect_eq(p["body"], content):
        return false
    return true

proc test_fm_body_stripped_in_prompt():
    let dir = TEST_DIR + "/fm"
    if not io.exists(dir):
        io.mkdir(dir)
    let p = dir + "/skilled.md"
    io.writefile(p, "---\nname: skilled\ndescription: A described skill.\n---\n\nUseful body text.\n")
    let result = skills.load_skills(dir)
    let ok1 = expect_contains(result, "Skill: skilled")
    let ok2 = expect_contains(result, "A described skill.")
    let ok3 = expect_contains(result, "Useful body text.")
    var ok4 = true
    if indexof(result, "name: skilled") >= 0:
        print "    raw frontmatter leaked into prompt"
        ok4 = false
    io.remove(p)
    io.remove(dir)
    return ok1 and ok2 and ok3 and ok4

run_test("parse_frontmatter extracts name/description/body", test_fm_basic)
run_test("parse_frontmatter handles no frontmatter", test_fm_none)
run_test("loaded skill strips raw frontmatter from prompt", test_fm_body_stripped_in_prompt)

print "--- SKILL.md in subdirectories ---"

proc test_subdir_skill():
    let base = TEST_DIR + "/subdirtest"
    let sub = base + "/mytool"
    if not io.exists(base):
        io.mkdir(base)
    if not io.exists(sub):
        io.mkdir(sub)
    io.writefile(sub + "/SKILL.md", "---\nname: mytool\ndescription: A subdir skill.\n---\n\nSubdir body.\n")
    let result = skills.load_skills(base)
    let ok1 = expect_contains(result, "Skill: mytool")
    let ok2 = expect_contains(result, "Subdir body.")
    io.remove(sub + "/SKILL.md")
    io.remove(sub)
    io.remove(base)
    return ok1 and ok2

run_test("loads SKILL.md from subdirectories", test_subdir_skill)

print "--- shipped skills validation ---"

let SHIPPED = ["code-review", "debugging", "git-commit", "test-writing", "refactoring", "shell-safety", "web-research", "documentation"]

proc test_shipped_skills_load():
    if not io.exists("skills") or not io.isdir("skills"):
        print "    skills/ directory missing"
        return false
    skills.load_skills("skills")
    let meta = skills.get_skills_meta()
    var names = []
    for m in meta:
        push(names, m["name"])
    for expected in SHIPPED:
        var found = false
        for n in names:
            if n == expected:
                found = true
        if not found:
            print "    missing shipped skill: " + expected
            return false
    return true

proc test_shipped_skills_have_descriptions():
    skills.load_skills("skills")
    let meta = skills.get_skills_meta()
    for m in meta:
        if m["description"] == "":
            print "    skill missing description: " + m["name"]
            return false
        if indexof(lower(m["description"]), "use when") < 0:
            print "    description lacks trigger guidance: " + m["name"]
            return false
    return true

proc test_shipped_skills_count():
    skills.load_skills("skills")
    return expect_eq(skills.get_skills_count() >= 8, true)

run_test("all shipped skills load by name", test_shipped_skills_load)
run_test("shipped skills have trigger descriptions", test_shipped_skills_have_descriptions)
run_test("at least 8 shipped skills present", test_shipped_skills_count)

print "--- cleanup ---"

teardown()

print ""
print "=== Results ==="
print "  Passed: " + str(passed)
print "  Failed: " + str(failed)
print ""

if failed > 0:
    raise str(failed) + " test(s) failed"
