import lib.benchmark as bench
import sys

let RESET = "\x1b[0m"
let BOLD = "\x1b[1m"
let DIM = "\x1b[2m"
let GREEN = "\x1b[32m"
let RED = "\x1b[31m"
let YELLOW = "\x1b[33m"
let CYAN = "\x1b[36m"

proc bar(pct):
    let width = 20
    let filled = pct * width / 100
    var s = ""
    var i = 0
    while i < width:
        if i < filled:
            s = s + "█"
        else:
            s = s + "░"
        i = i + 1
    return s

proc run_category(cat):
    let tasks = bench.get_tasks(cat)
    var correct = 0
    let total = len(tasks)
    print BOLD + cat + RESET + DIM + " (" + str(total) + " tasks)" + RESET
    for task in tasks:
        sys.stdout_write("  " + DIM + task["id"] + RESET + " ... ")
        let response = bench.query_model(task["prompt"])
        let ok = bench.score(task, response)
        if ok:
            print GREEN + "pass" + RESET
            correct = correct + 1
        else:
            var preview = strip(response)
            if len(preview) > 40:
                preview = slice(preview, 0, 40) + "..."
            print RED + "fail" + RESET + DIM + " (got: " + preview + ")" + RESET
    let pct = correct * 100 / total
    var color = RED
    if pct >= 80:
        color = GREEN
    elif pct >= 50:
        color = YELLOW
    print "  " + color + bar(pct) + RESET + " " + color + str(pct) + "%" + RESET + DIM + " (" + str(correct) + "/" + str(total) + ")" + RESET
    # machine-readable line for the aggregator
    print "SCORE " + cat + " " + str(correct) + " " + str(total)

# If BENCH_CATEGORY is set, run only that category (used by `sagemake bench`
# to isolate each category in its own process so memory is freed between them).
# Otherwise run the whole suite in one process.
let only = sys.getenv("BENCH_CATEGORY")
if only != nil and only != "":
    run_category(only)
else:
    print ""
    print CYAN + "Bonsai Harness Benchmark Suite" + RESET
    print ""
    for cat in bench.get_categories():
        run_category(cat)
        print ""
