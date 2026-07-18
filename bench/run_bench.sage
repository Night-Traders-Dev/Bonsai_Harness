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

print ""
print CYAN + "╭──────────────────────────────────────────────╮" + RESET
print CYAN + "│ " + RESET + BOLD + "Bonsai Harness Benchmark Suite" + RESET + "                 " + CYAN + "│" + RESET
print CYAN + "│ " + RESET + DIM + "coding · reasoning · knowledge · tools · IF" + RESET + "    " + CYAN + "│" + RESET
print CYAN + "╰──────────────────────────────────────────────╯" + RESET
print ""

let categories = bench.get_categories()
var grand_total = 0
var grand_correct = 0

for cat in categories:
    let tasks = bench.get_tasks(cat)
    var correct = 0
    let total = len(tasks)
    print BOLD + cat + RESET + DIM + " (" + str(total) + " tasks)" + RESET
    for task in tasks:
        sys.stdout_write("  " + DIM + task["id"] + RESET + " ... ")
        let response = bench.query_model(task["prompt"])
        let ok = bench.score(task, response)
        if ok:
            print GREEN + "✓ pass" + RESET
            correct = correct + 1
        else:
            let preview = strip(response)
            if len(preview) > 40:
                preview = slice(preview, 0, 40) + "..."
            print RED + "✗ fail" + RESET + DIM + " (got: " + preview + ")" + RESET
    let pct = correct * 100 / total
    var color = RED
    if pct >= 80:
        color = GREEN
    elif pct >= 50:
        color = YELLOW
    print "  " + color + bar(pct) + RESET + " " + color + str(pct) + "%" + RESET + DIM + " (" + str(correct) + "/" + str(total) + ")" + RESET
    print ""
    grand_total = grand_total + total
    grand_correct = grand_correct + correct

let overall = grand_correct * 100 / grand_total
print CYAN + "══════════════════════════════════════════════════" + RESET
var oc = RED
if overall >= 80:
    oc = GREEN
elif overall >= 50:
    oc = YELLOW
print BOLD + "OVERALL: " + RESET + oc + str(overall) + "%" + RESET + DIM + " (" + str(grand_correct) + "/" + str(grand_total) + " tasks)" + RESET
print CYAN + "══════════════════════════════════════════════════" + RESET
print ""
