import lib.ollama as ollama

# Benchmark suite for the Bonsai harness model.
#
# Categories mirror the styles of widely used LLM evaluations:
#   coding       -> HumanEval / MBPP style (produce correct code / answer)
#   reasoning    -> GSM8K style (multi-step math word problems, exact answer)
#   knowledge    -> MMLU style (multiple-choice factual questions)
#   tool_use     -> function-calling (choose the right tool for a request)
#   instruction  -> IFEval style (follow precise output constraints)
#
# Each task has automated, deterministic scoring so the whole suite can
# run without a human grader.

proc _tasks_reasoning():
    return [
        {"id": "gsm-1", "prompt": "Answer with only the final number. Natalia sold clips to 48 friends in April, and then she sold half as many clips in May. How many clips did she sell altogether in April and May?", "answer": "72", "kind": "number"},
        {"id": "gsm-2", "prompt": "Answer with only the final number. A robe takes 2 bolts of blue fiber and half that much white fiber. How many bolts in total does it take?", "answer": "3", "kind": "number"},
        {"id": "gsm-3", "prompt": "Answer with only the final number. Weng earns $12 an hour for babysitting. Yesterday she babysat for 50 minutes. How many dollars did she earn?", "answer": "10", "kind": "number"},
        {"id": "gsm-4", "prompt": "Answer with only the final number. There are 15 trees in the grove. Workers plant trees so that afterward there are 21 trees. How many trees did they plant?", "answer": "6", "kind": "number"},
        {"id": "logic-1", "prompt": "Answer with only the final number. If it takes 5 machines 5 minutes to make 5 widgets, how many minutes does it take 100 machines to make 100 widgets?", "answer": "5", "kind": "number"}
    ]

proc _tasks_knowledge():
    return [
        {"id": "mmlu-1", "prompt": "Answer with only the letter. What is the chemical symbol for gold?\nA) Gd\nB) Au\nC) Ag\nD) Go", "answer": "B", "accept": "au", "kind": "choice"},
        {"id": "mmlu-2", "prompt": "Answer with only the letter. Which planet is closest to the Sun?\nA) Venus\nB) Earth\nC) Mercury\nD) Mars", "answer": "C", "accept": "mercury", "kind": "choice"},
        {"id": "mmlu-3", "prompt": "Answer with only the letter. In what year did World War II end?\nA) 1918\nB) 1939\nC) 1945\nD) 1950", "answer": "C", "accept": "1945", "kind": "choice"},
        {"id": "mmlu-4", "prompt": "Answer with only the letter. What data structure uses LIFO ordering?\nA) Queue\nB) Stack\nC) Heap\nD) Tree", "answer": "B", "accept": "stack", "kind": "choice"},
        {"id": "mmlu-5", "prompt": "Answer with only the letter. What is the time complexity of binary search on a sorted array?\nA) O(n)\nB) O(n log n)\nC) O(log n)\nD) O(1)", "answer": "C", "accept": "o(log n)", "kind": "choice"}
    ]

proc _tasks_coding():
    return [
        {"id": "code-1", "prompt": "Answer with only the final number. What does this Python code print?\n\nx = [1, 2, 3, 4]\nprint(sum(x[1:3]))", "answer": "5", "kind": "number"},
        {"id": "code-2", "prompt": "Answer with only the final number. What is the output?\n\ndef f(n):\n    if n <= 1:\n        return n\n    return f(n-1) + f(n-2)\nprint(f(7))", "answer": "13", "kind": "number"},
        {"id": "code-3", "prompt": "Answer with only the final number. What does this print?\n\ntotal = 0\nfor i in range(1, 6):\n    total += i\nprint(total)", "answer": "15", "kind": "number"},
        {"id": "code-4", "prompt": "Answer with only the word (true or false). Does this Python expression evaluate to True? len('hello') == 5", "answer": "true", "kind": "contains"},
        {"id": "code-5", "prompt": "Answer with only the final number. What is the output?\n\nd = {'a': 1, 'b': 2}\nd['c'] = 3\nprint(len(d))", "answer": "3", "kind": "number"}
    ]

proc _tasks_tool_use():
    return [
        {"id": "tool-1", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to see the contents of config.json.", "answer": "read_file", "kind": "contains"},
        {"id": "tool-2", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to find every file that contains the word TODO.", "answer": "grep", "kind": "contains"},
        {"id": "tool-3", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to list all files in the src directory.", "answer": "list_dir", "kind": "contains"},
        {"id": "tool-4", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to download and read a documentation page from a URL.", "answer": "web_fetch", "kind": "contains"},
        {"id": "tool-5", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to find all files matching the pattern *.sage.", "answer": "glob", "kind": "contains"}
    ]

proc _tasks_instruction():
    return [
        {"id": "if-1", "prompt": "Respond with exactly the single word: ACKNOWLEDGED", "answer": "acknowledged", "kind": "exact_word"},
        {"id": "if-2", "prompt": "Answer with only the letter Z and nothing else.", "answer": "z", "kind": "exact_word"},
        {"id": "if-3", "prompt": "Reply with only the number 42.", "answer": "42", "kind": "number"},
        {"id": "if-4", "prompt": "Answer with only the word yes or no: Is the sky blue on a clear day?", "answer": "yes", "kind": "contains"},
        {"id": "if-5", "prompt": "Respond with exactly this word in uppercase: DONE", "answer": "done", "kind": "exact_word"}
    ]

proc get_categories():
    return ["reasoning", "knowledge", "coding", "tool_use", "instruction"]

proc get_tasks(category):
    if category == "reasoning":
        return _tasks_reasoning()
    if category == "knowledge":
        return _tasks_knowledge()
    if category == "coding":
        return _tasks_coding()
    if category == "tool_use":
        return _tasks_tool_use()
    if category == "instruction":
        return _tasks_instruction()
    return []

proc _only_digits(s):
    var out = ""
    var i = 0
    let n = len(s)
    while i < n:
        let c = slice(s, i, i + 1)
        if c == "0" or c == "1" or c == "2" or c == "3" or c == "4" or c == "5" or c == "6" or c == "7" or c == "8" or c == "9":
            out = out + c
        i = i + 1
    return out

proc _last_number(s):
    var current = ""
    var last = ""
    var i = 0
    let n = len(s)
    while i < n:
        let c = slice(s, i, i + 1)
        let is_digit = c == "0" or c == "1" or c == "2" or c == "3" or c == "4" or c == "5" or c == "6" or c == "7" or c == "8" or c == "9"
        if is_digit:
            current = current + c
        else:
            if current != "":
                last = current
                current = ""
        i = i + 1
    if current != "":
        last = current
    return last

# Score a single response against a task. Returns true if correct.
proc score(task, response):
    let kind = task["kind"]
    let expected = task["answer"]
    let resp = lower(strip(response))

    if kind == "number":
        return _last_number(resp) == _only_digits(expected)

    if kind == "choice":
        # accept the letter as a standalone answer near the start
        let letter = lower(expected)
        let first = slice(resp, 0, 1)
        if first == letter:
            return true
        if indexof(resp, "answer is " + letter) >= 0:
            return true
        if indexof(resp, "(" + letter + ")") >= 0:
            return true
        if indexof(resp, letter + ")") >= 0:
            return true
        # also accept the correct option's value text (model often names the
        # answer instead of emitting the bare letter)
        if dict_has(task, "accept"):
            if indexof(resp, lower(task["accept"])) >= 0:
                return true
        return false

    if kind == "contains":
        return indexof(resp, lower(expected)) >= 0

    if kind == "exact_word":
        var cleaned = ""
        var i = 0
        let n = len(resp)
        while i < n:
            let c = slice(resp, i, i + 1)
            if c != "." and c != "!" and c != "," and c != "\n" and c != " ":
                cleaned = cleaned + c
            i = i + 1
        return cleaned == lower(expected)

    return false

# Query the model for a single prompt, return its text response.
proc query_model(prompt):
    let messages = [{"role": "user", "content": prompt}]
    let result = ollama.ask(messages, [])
    if dict_has(result, "error"):
        return ""
    return ollama.answer_text(result)
