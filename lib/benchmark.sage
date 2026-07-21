import lib.ollama as ollama
import lib.tool_compiler as compiler
import lib.tool_validator as validator
import lib.tools as tools
import json

# Benchmark suite for the Bonsai harness model.
#
# Categories mirror the styles of widely used LLM evaluations used by
# frontier models (GPT-4, Claude, Gemini, Llama, DeepSeek, etc.):
#   reasoning           -> GSM8K / MATH / BBH (math word problems, logic)
#   knowledge           -> MMLU / MMLU-Pro (multiple-choice across STEM+humanities)
#   coding              -> HumanEval / MBPP (code output prediction)
#   tool_use            -> function-calling / BFCL (choose the right tool)
#   instruction         -> IFEval / follow instructions precisely
#   reading_comprehension -> DROP / SQuAD (short-passage Q&A, answer in text)
#   commonsense_reasoning  -> HellaSwag / WinoGrande / TruthfulQA
#
# Each task has automated, deterministic scoring so the whole suite can
# run without a human grader.  Models tested include Bonsai-27B (1-bit quant)
# and any model served through Ollama.

# ──────────────────────────────────────────────
# reasoning — GSM8K / BBH / MATH style
#   Multi-step math word problems and logic
# ──────────────────────────────────────────────
proc _tasks_reasoning():
    return [
        {"id": "gsm-1", "prompt": "Answer with only the final number. Natalia sold clips to 48 friends in April, and then she sold half as many clips in May. How many clips did she sell altogether in April and May?", "answer": "72", "kind": "number"},
        {"id": "gsm-2", "prompt": "Answer with only the final number. A robe takes 2 bolts of blue fiber and half that much white fiber. How many bolts in total does it take?", "answer": "3", "kind": "number"},
        {"id": "gsm-3", "prompt": "Answer with only the final number. Weng earns $12 an hour for babysitting. Yesterday she babysat for 50 minutes. How many dollars did she earn?", "answer": "10", "kind": "number"},
        {"id": "gsm-4", "prompt": "Answer with only the final number. There are 15 trees in the grove. Workers plant trees so that afterward there are 21 trees. How many trees did they plant?", "answer": "6", "kind": "number"},
        {"id": "logic-1", "prompt": "Answer with only the final number. If it takes 5 machines 5 minutes to make 5 widgets, how many minutes does it take 100 machines to make 100 widgets?", "answer": "5", "kind": "number"},
        {"id": "gsm-5", "prompt": "Answer with only the final number. Tom has 12 apples. He gives a third of them to his friend and then eats 2. How many apples does Tom have left?", "answer": "6", "kind": "number"},
        {"id": "gsm-6", "prompt": "Answer with only the final number. A bakery sells bread for $3 per loaf and cookies for $2 per pack. If a customer buys 2 loaves and 3 packs of cookies, how much do they pay total?", "answer": "12", "kind": "number"},
        {"id": "gsm-7", "prompt": "Answer with only the final number. John is twice as old as Mary. Mary is 12. How old will John be in 5 years?", "answer": "29", "kind": "number"},
        {"id": "gsm-8", "prompt": "Answer with only the final number. A train travels at 60 miles per hour. How many miles does it travel in 15 minutes?", "answer": "15", "kind": "number"},
        {"id": "gsm-9", "prompt": "Answer with only the final number. A recipe calls for 2 cups of flour for every 3 cups of sugar. If you use 9 cups of sugar, how many cups of flour do you need?", "answer": "6", "kind": "number"},
        {"id": "bbh-1", "prompt": "Answer with only the letter. A boolean expression: (True and False) or (True and True). Does it evaluate to:\nA) True\nB) False", "answer": "A", "accept": "true", "kind": "choice"},
        {"id": "bbh-2", "prompt": "Answer with only the letter. If all A are B, and all B are C, then:\nA) All A are C\nB) All C are A\nC) No A is C\nD) Some C are not A", "answer": "A", "accept": "all a are c", "kind": "choice"},
        {"id": "bbh-3", "prompt": "Answer with only the final number. A rectangle has length 8 and width 5. What is its perimeter?", "answer": "26", "kind": "number"},
        {"id": "bbh-4", "prompt": "Answer with only the final number. Yesterday was Tuesday. What day of the week is it 10 days from today?", "answer": "5", "kind": "number"},
        {"id": "bbh-5", "prompt": "Answer with only the letter. A coin is flipped 3 times. What is the probability of getting exactly 2 heads?\nA) 1/8\nB) 3/8\nC) 1/2\nD) 1/4", "answer": "B", "accept": "3/8", "kind": "choice"}
    ]

# ──────────────────────────────────────────────
# knowledge — MMLU / MMLU-Pro style
#   Multiple-choice factual questions across
#   biology, physics, history, geography, CS,
#   law, economics, psychology, and more
# ──────────────────────────────────────────────
proc _tasks_knowledge():
    return [
        {"id": "mmlu-1", "prompt": "Answer with only the letter. What is the chemical symbol for gold?\nA) Gd\nB) Au\nC) Ag\nD) Go", "answer": "B", "accept": "au", "kind": "choice"},
        {"id": "mmlu-2", "prompt": "Answer with only the letter. Which planet is closest to the Sun?\nA) Venus\nB) Earth\nC) Mercury\nD) Mars", "answer": "C", "accept": "mercury", "kind": "choice"},
        {"id": "mmlu-3", "prompt": "Answer with only the letter. In what year did World War II end?\nA) 1918\nB) 1939\nC) 1945\nD) 1950", "answer": "C", "accept": "1945", "kind": "choice"},
        {"id": "mmlu-4", "prompt": "Answer with only the letter. What data structure uses LIFO ordering?\nA) Queue\nB) Stack\nC) Heap\nD) Tree", "answer": "B", "accept": "stack", "kind": "choice"},
        {"id": "mmlu-5", "prompt": "Answer with only the letter. What is the time complexity of binary search on a sorted array?\nA) O(n)\nB) O(n log n)\nC) O(log n)\nD) O(1)", "answer": "C", "accept": "o(log n)", "kind": "choice"},
        {"id": "mmlu-6", "prompt": "Answer with only the letter. What is the powerhouse of the cell?\nA) Nucleus\nB) Ribosome\nC) Mitochondrion\nD) Golgi body", "answer": "C", "accept": "mitochondrion", "kind": "choice"},
        {"id": "mmlu-7", "prompt": "Answer with only the letter. What force keeps planets in orbit around the Sun?\nA) Electromagnetic force\nB) Gravity\nC) Strong nuclear force\nD) Centrifugal force", "answer": "B", "accept": "gravity", "kind": "choice"},
        {"id": "mmlu-8", "prompt": "Answer with only the letter. What is the longest river in the world?\nA) Amazon\nB) Mississippi\nC) Nile\nD) Yangtze", "answer": "C", "accept": "nile", "kind": "choice"},
        {"id": "mmlu-9", "prompt": "Answer with only the letter. Which of these is a prime number?\nA) 15\nB) 21\nC) 23\nD) 27", "answer": "C", "accept": "23", "kind": "choice"},
        {"id": "mmlu-10", "prompt": "Answer with only the letter. Who wrote the play Romeo and Juliet?\nA) Charles Dickens\nB) William Shakespeare\nC) Jane Austen\nD) Mark Twain", "answer": "B", "accept": "william shakespeare", "kind": "choice"},
        {"id": "mmlu-11", "prompt": "Answer with only the letter. In economics, what does GDP stand for?\nA) Gross Domestic Product\nB) General Demand Price\nC) Gross Development Plan\nD) Government Debt Percentage", "answer": "A", "accept": "gross domestic product", "kind": "choice"},
        {"id": "mmlu-12", "prompt": "Answer with only the letter. Which layer of the Earth is the hottest?\nA) Crust\nB) Mantle\nC) Outer core\nD) Inner core", "answer": "D", "accept": "inner core", "kind": "choice"},
        {"id": "mmlu-13", "prompt": "Answer with only the letter. What is the value of pi rounded to two decimal places?\nA) 3.14\nB) 3.16\nC) 3.12\nD) 3.18", "answer": "A", "accept": "3.14", "kind": "choice"},
        {"id": "mmlu-14", "prompt": "Answer with only the letter. The cerebellum is part of which body system?\nA) Circulatory\nB) Nervous\nC) Skeletal\nD) Respiratory", "answer": "B", "accept": "nervous", "kind": "choice"},
        {"id": "mmlu-15", "prompt": "Answer with only the letter. Which of these is NOT an operating system?\nA) Linux\nB) Windows\nC) Apache\nD) macOS", "answer": "C", "accept": "apache", "kind": "choice"},
        {"id": "mmlu-16", "prompt": "Answer with only the letter. What is the SI unit of electric current?\nA) Volt\nB) Watt\nC) Ampere\nD) Ohm", "answer": "C", "accept": "ampere", "kind": "choice"}
    ]

# ──────────────────────────────────────────────
# coding — HumanEval / MBPP style
#   Predict Python code output, trace execution
# ──────────────────────────────────────────────
proc _tasks_coding():
    return [
        {"id": "code-1", "prompt": "Answer with only the final number. What does this Python code print?\n\nx = [1, 2, 3, 4]\nprint(sum(x[1:3]))", "answer": "5", "kind": "number"},
        {"id": "code-2", "prompt": "Answer with only the final number. What is the output?\n\ndef f(n):\n    if n <= 1:\n        return n\n    return f(n-1) + f(n-2)\nprint(f(7))", "answer": "13", "kind": "number"},
        {"id": "code-3", "prompt": "Answer with only the final number. What does this print?\n\ntotal = 0\nfor i in range(1, 6):\n    total += i\nprint(total)", "answer": "15", "kind": "number"},
        {"id": "code-4", "prompt": "Answer with only the word (true or false). Does this Python expression evaluate to True? len('hello') == 5", "answer": "true", "kind": "contains"},
        {"id": "code-5", "prompt": "Answer with only the final number. What is the output?\n\nd = {'a': 1, 'b': 2}\nd['c'] = 3\nprint(len(d))", "answer": "3", "kind": "number"},
        {"id": "code-6", "prompt": "Answer with only the final number. What does this print?\n\ns = 'hello'\nprint(s[1:4])", "answer": "4", "kind": "number"},
        {"id": "code-7", "prompt": "Answer with only the word true or false. Does this expression evaluate to True? not(False) and True", "answer": "true", "kind": "contains"},
        {"id": "code-8", "prompt": "Answer with only the final number. What does this print?\n\nresult = [x*2 for x in range(4)]\nprint(len(result))", "answer": "4", "kind": "number"},
        {"id": "code-9", "prompt": "Answer with only the final number. What does this print?\n\nx = [3, 1, 4, 1, 5]\nprint(x.count(1))", "answer": "2", "kind": "number"},
        {"id": "code-10", "prompt": "Answer with only the final number. What is the output?\n\ndef add(a, b):\n    return a + b\nprint(add(3, add(4, 5)))", "answer": "12", "kind": "number"},
        {"id": "code-11", "prompt": "Answer with only the word true or false. Is 'python'.isalpha() True?", "answer": "true", "kind": "contains"},
        {"id": "code-12", "prompt": "Answer with only the final number. What does this print?\n\nprint(len(set([1, 2, 2, 3, 3, 3])))", "answer": "3", "kind": "number"},
        {"id": "code-13", "prompt": "Answer with only the final number. Trace this:\n\nx = 10\ny = 3\nprint(x // y)", "answer": "3", "kind": "number"},
        {"id": "code-14", "prompt": "Answer with only the final number. What does this print?\n\nmatrix = [[1,2],[3,4]]\nprint(matrix[1][0])", "answer": "3", "kind": "number"},
        {"id": "code-15", "prompt": "Answer with only the final number. What does this print?\n\nprint(2**10)", "answer": "1024", "kind": "number"}
    ]

# ──────────────────────────────────────────────
# tool_use — function-calling / BFCL style
#   Choose the right tool for a given request
# ──────────────────────────────────────────────
proc _tasks_tool_use():
    return [
        {"id": "tool-1", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to see the contents of config.json.", "answer": "read_file", "kind": "contains"},
        {"id": "tool-2", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to find every file that contains the word TODO.", "answer": "grep", "kind": "contains"},
        {"id": "tool-3", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to list all files in the src directory.", "answer": "list_dir", "kind": "contains"},
        {"id": "tool-4", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to download and read a documentation page from a URL.", "answer": "web_fetch", "kind": "contains"},
        {"id": "tool-5", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to find all files matching the pattern *.sage.", "answer": "glob", "kind": "contains"},
        {"id": "tool-6", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to remove a file called old.log.", "answer": "bash", "kind": "contains"},
        {"id": "tool-7", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to create a new file called notes.txt with some content.", "answer": "write_file", "kind": "contains"},
        {"id": "tool-8", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to check the current disk usage.", "answer": "bash", "kind": "contains"},
        {"id": "tool-9", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to search for the word 'error' in the file server.log.", "answer": "grep", "kind": "contains"},
        {"id": "tool-10", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to look up the weather forecast for tomorrow.", "answer": "web_fetch", "kind": "contains"},
        {"id": "tool-11", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to edit a configuration file.", "answer": "read_file", "kind": "contains"},
        {"id": "tool-12", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to see what files are in the project.", "answer": "list_dir", "kind": "contains"},
        {"id": "tool-13", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to save a JSON response to a file.", "answer": "write_file", "kind": "contains"},
        {"id": "tool-14", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to find all Python files in the project.", "answer": "glob", "kind": "contains"},
        {"id": "tool-15", "prompt": "You have these tools: bash, read_file, write_file, grep, glob, list_dir, web_fetch. Answer with ONLY the single tool name that best fits: The user asks to download a CSV file from an API.", "answer": "web_fetch", "kind": "contains"}
    ]

# ──────────────────────────────────────────────
# instruction — IFEval style
#   Follow precise output constraints
# ──────────────────────────────────────────────
proc _tasks_instruction():
    return [
        {"id": "if-1", "prompt": "Respond with exactly the single word: ACKNOWLEDGED", "answer": "acknowledged", "kind": "exact_word"},
        {"id": "if-2", "prompt": "Answer with only the letter Z and nothing else.", "answer": "z", "kind": "exact_word"},
        {"id": "if-3", "prompt": "Reply with only the number 42.", "answer": "42", "kind": "number"},
        {"id": "if-4", "prompt": "Answer with only the word yes or no: Is the sky blue on a clear day?", "answer": "yes", "kind": "contains"},
        {"id": "if-5", "prompt": "Respond with exactly this word in uppercase: DONE", "answer": "done", "kind": "exact_word"},
        {"id": "if-6", "prompt": "Respond with exactly the single word: HELLO", "answer": "hello", "kind": "exact_word"},
        {"id": "if-7", "prompt": "Answer with only the word apple or orange: Which fruit grows on trees?", "answer": "apple", "kind": "contains"},
        {"id": "if-8", "prompt": "Reply with only the number 100.", "answer": "100", "kind": "number"},
        {"id": "if-9", "prompt": "Respond with exactly the single word: GRANTED", "answer": "granted", "kind": "exact_word"},
        {"id": "if-10", "prompt": "Answer with only the single letter X.", "answer": "x", "kind": "exact_word"},
        {"id": "if-11", "prompt": "Answer with only the word red or blue: What color is the sky on a clear day?", "answer": "blue", "kind": "contains"},
        {"id": "if-12", "prompt": "Reply with exactly the number 7.", "answer": "7", "kind": "number"},
        {"id": "if-13", "prompt": "Respond with exactly the word: COMPLETE", "answer": "complete", "kind": "exact_word"},
        {"id": "if-14", "prompt": "Answer with only the word yes or no: Is 2 + 2 equal to 5?", "answer": "no", "kind": "contains"},
        {"id": "if-15", "prompt": "Reply with exactly the number 0.", "answer": "0", "kind": "number"}
    ]

# ──────────────────────────────────────────────
# reading_comprehension — DROP / SQuAD style
#   Short passage, factual question, answer
#   extracted directly from the text
# ──────────────────────────────────────────────
proc _tasks_reading():
    return [
        {"id": "read-1", "prompt": "Read this and answer with only the final number. Passage: 'The Amazon river flows through Brazil, Peru, Colombia, and several other countries. It is approximately 6400 kilometers long and has over 1000 tributaries.' Question: How many kilometers long is the Amazon river?", "answer": "6400", "kind": "number"},
        {"id": "read-2", "prompt": "Read this and answer with only the word. Passage: 'Photosynthesis is the process by which green plants convert sunlight into energy. The main pigment involved is chlorophyll, which gives plants their green color.' Question: What is the main pigment involved in photosynthesis?", "answer": "chlorophyll", "kind": "contains"},
        {"id": "read-3", "prompt": "Read this and answer with only the final number. Passage: 'A standard chessboard has 8 rows and 8 columns, making 64 squares total. Each player starts with 16 pieces: 8 pawns, 2 rooks, 2 knights, 2 bishops, 1 queen, and 1 king.' Question: How many total squares are on a standard chessboard?", "answer": "64", "kind": "number"},
        {"id": "read-4", "prompt": "Read this and answer with only the word. Passage: 'Mars is the fourth planet from the Sun and the second smallest planet in the Solar System. It has two moons named Phobos and Deimos.' Question: What are the two moons of Mars called?", "answer": "phobos", "kind": "contains"},
        {"id": "read-5", "prompt": "Read this and answer with only the final number. Passage: 'The human body has 206 bones. The smallest bone is the stapes in the ear, which is approximately 0.3 centimeters long.' Question: How many bones does the human body have?", "answer": "206", "kind": "number"},
        {"id": "read-6", "prompt": "Read this and answer with only the word. Passage: 'The Great Wall of China was built over many centuries, starting in the 7th century BC. It stretches approximately 21196 kilometers and was designated a UNESCO World Heritage site in 1987.' Question: In which year was the Great Wall designated a UNESCO World Heritage site?", "answer": "1987", "kind": "contains"},
        {"id": "read-7", "prompt": "Read this and answer with only the final number. Passage: 'Water freezes at 0 degrees Celsius and boils at 100 degrees Celsius at standard atmospheric pressure. It reaches its maximum density at 4 degrees Celsius.' Question: At what temperature does water freeze?", "answer": "0", "kind": "number"},
        {"id": "read-8", "prompt": "Read this and answer with only the word. Passage: 'Elephants are the largest land animals. African elephants can weigh up to 6000 kilograms, while Asian elephants are slightly smaller at up to 4000 kilograms.' Question: Which type of elephant is larger?", "answer": "african", "kind": "contains"},
        {"id": "read-9", "prompt": "Read this and answer with only the final number. Passage: 'A year on Mercury lasts about 88 Earth days. A year on Venus lasts about 225 Earth days. A year on Mars lasts about 687 Earth days.' Question: How many Earth days is a year on Mars?", "answer": "687", "kind": "number"},
        {"id": "read-10", "prompt": "Read this and answer with only the word. Passage: 'The three states of matter are solid, liquid, and gas. When a solid turns directly into a gas without becoming liquid first, this is called sublimation. Dry ice is a common example of sublimation.' Question: What is it called when a solid turns directly into a gas?", "answer": "sublimation", "kind": "contains"},
        {"id": "read-11", "prompt": "Read this and answer with only the final number. Passage: 'Mount Everest is the highest mountain on Earth at 8848 meters above sea level. Mauna Kea is taller when measured from its base on the ocean floor at 10210 meters, but only 4205 meters above sea level.' Question: How tall is Mount Everest in meters?", "answer": "8848", "kind": "number"},
        {"id": "read-12", "prompt": "Read this and answer with only the word. Passage: 'DNA, or deoxyribonucleic acid, carries the genetic instructions used in the growth, development, functioning, and reproduction of all known living organisms. It consists of two strands that form a double helix structure.' Question: What shape does DNA form?", "answer": "double helix", "kind": "contains"}
    ]

# ──────────────────────────────────────────────
# commonsense_reasoning — HellaSwag / WinoGrande /
#   TruthfulQA style.  Everyday physics, social
#   knowledge, truthfulness about common claims
# ──────────────────────────────────────────────
proc _tasks_commonsense():
    return [
        {"id": "cs-1", "prompt": "Answer with only the letter. If you drop a feather and a bowling ball from the same height in a vacuum, which hits the ground first?\nA) The feather\nB) The bowling ball\nC) Both at the same time\nD) Neither", "answer": "C", "accept": "both at the same time", "kind": "choice"},
        {"id": "cs-2", "prompt": "Answer with only the letter. If a glass of water is left in a freezer for several hours, what will happen to the water?\nA) It will evaporate\nB) It will freeze into ice\nC) It will boil\nD) Nothing", "answer": "B", "accept": "freeze into ice", "kind": "choice"},
        {"id": "cs-3", "prompt": "Answer with only the letter. The doctor handed the nurse the stethoscope. Then _____ checked the patient's heartbeat. Who checked the heartbeat?\nA) The doctor\nB) The nurse\nC) The patient\nD) Cannot determine", "answer": "A", "accept": "the doctor", "kind": "choice"},
        {"id": "cs-4", "prompt": "Answer with only the letter. Which of the following is the best way to measure the length of a room?\nA) A thermometer\nB) A measuring tape\nC) A stopwatch\nD) A scale", "answer": "B", "accept": "measuring tape", "kind": "choice"},
        {"id": "cs-5", "prompt": "Answer with only the letter. Why does an ice cube float in water?\nA) Ice is heavier than water\nB) Ice is less dense than water\nC) Water pushes it down\nD) Ice dissolves in water", "answer": "B", "accept": "less dense", "kind": "choice"},
        {"id": "cs-6", "prompt": "Answer with only the letter. The trophy would not fit in the suitcase because it was too small. What was too small?\nA) The trophy\nB) The suitcase\nC) Neither\nD) Both", "answer": "B", "accept": "the suitcase", "kind": "choice"},
        {"id": "cs-7", "prompt": "Answer with only the word true or false: Bats are birds.", "answer": "false", "kind": "contains"},
        {"id": "cs-8", "prompt": "Answer with only the word true or false: Humans use only 10 percent of their brain.", "answer": "false", "kind": "contains"},
        {"id": "cs-9", "prompt": "Answer with only the letter. Which of these objects is MOST likely to conduct electricity?\nA) A rubber eraser\nB) A copper wire\nC) A wooden pencil\nD) A glass bottle", "answer": "B", "accept": "copper wire", "kind": "choice"},
        {"id": "cs-10", "prompt": "Answer with only the letter. The cat chased the mouse until it hid under the couch. Who hid under the couch?\nA) The cat\nB) The mouse\nC) Cannot determine\nD) Both", "answer": "B", "accept": "the mouse", "kind": "choice"},
        {"id": "cs-11", "prompt": "Answer with only the letter. Why do we see lightning before we hear thunder during a storm?\nA) Light is faster than sound\nB) Sound is faster than light\nC) Thunder is quieter\nD) Lightning is closer", "answer": "A", "accept": "light is faster than sound", "kind": "choice"},
        {"id": "cs-12", "prompt": "Answer with only the word true or false: Fortune cookies were invented in China.", "answer": "false", "kind": "contains"},
        {"id": "cs-13", "prompt": "Answer with only the letter. If someone says 'I could care less', what do they typically mean?\nA) They care very much\nB) They care very little\nC) They could care more\nD) They are indifferent", "answer": "B", "accept": "they care very little", "kind": "choice"},
        {"id": "cs-14", "prompt": "Answer with only the letter. Which of these would cause a plant to grow best?\nA) Darkness and dry soil\nB) Sunlight and water\nC) Cold temperature and sand\nD) No soil", "answer": "B", "accept": "sunlight and water", "kind": "choice"},
        {"id": "cs-15", "prompt": "Answer with only the word true or false: The Earth is flat.", "answer": "false", "kind": "contains"}
    ]

# ──────────────────────────────────────────────
# tool_compilation — Dual-model tool-compiler pipeline
#   Tests the deterministic parts of the intent→tool-call pipeline:
#     A) JSON extraction from MiniCPM output
#     B) Intent extraction from Bonsai output
#     C) Prompt building (verifies structure)
#     D) Validation logic on synthetic tool calls
#   These are deterministic (no model call) so they run fast and
#   measure the compiler's correctness rather than model accuracy.
# ──────────────────────────────────────────────
proc _tasks_tool_compilation():
    return [
        # ── A: JSON extraction (extract_json_from_text) ──
        {"id": "comp-extract-1", "prompt": "simple extraction", "input": "Here is the result: {\"name\":\"grep\",\"arguments\":{\"pattern\":\"TODO\"}}", "expected": "grep", "compiler_fn": "extract_json", "kind": "comp_extract"},
        {"id": "comp-extract-2", "prompt": "nested json", "input": "{\"name\":\"bash\",\"arguments\":{\"command\":\"ls -la\"}}", "expected": "bash", "compiler_fn": "extract_json", "kind": "comp_extract"},
        {"id": "comp-extract-3", "prompt": "extract from surrounding text", "input": "I think we should use the grep tool: {\"name\":\"grep\",\"arguments\":{\"pattern\":\"error\"}}. That will find matches.", "expected": "grep", "compiler_fn": "extract_json", "kind": "comp_extract"},
        {"id": "comp-extract-4", "prompt": "no json returns empty", "input": "This is plain text with no JSON object", "expected": "", "compiler_fn": "extract_json", "kind": "comp_extract"},
        {"id": "comp-extract-5", "prompt": "extract with braces in string", "input": "{\"name\":\"bash\",\"arguments\":{\"command\":\"echo {hello}\"}}", "expected": "bash", "compiler_fn": "extract_json", "kind": "comp_extract"},
        {"id": "comp-extract-6", "prompt": "first of multiple json objects", "input": "First {\"name\":\"grep\"} then {\"name\":\"bash\"}", "expected": "grep", "compiler_fn": "extract_json", "kind": "comp_extract"},

        # ── B: Intent extraction (extract_intent_from_bonsai) ──
        {"id": "comp-intent-1", "prompt": "intent with marker", "input": "I'll search the codebase.\nINTENT: Find all references to function parse_config\nACTION: TOOL_CALL(...)", "expected": "Find all references to function parse_config", "compiler_fn": "extract_intent", "kind": "comp_intent"},
        {"id": "comp-intent-2", "prompt": "multi-line intent", "input": "INTENT: Search for the string 'timeout'\nin the src directory\nFUNCTION: grep", "expected": "Search for the string 'timeout'\nin the src directory", "compiler_fn": "extract_intent", "kind": "comp_intent"},
        {"id": "comp-intent-3", "prompt": "no marker returns full text", "input": "I need to find where timeout is defined in the codebase.", "expected": "I need to find where timeout is defined in the codebase.", "compiler_fn": "extract_intent", "kind": "comp_intent"},
        {"id": "comp-intent-4", "prompt": "empty input", "input": "", "expected": "", "compiler_fn": "extract_intent", "kind": "comp_intent"},

        # ── C: Prompt building (build_compiler_prompt) ──
        {"id": "comp-prompt-1", "prompt": "prompt contains intent", "input": "search for error", "expected": "search for error", "compiler_fn": "check_prompt_contains", "kind": "comp_prompt"},
        {"id": "comp-prompt-2", "prompt": "prompt has JSON format", "input": "find file", "expected": "arguments", "compiler_fn": "check_prompt_contains", "kind": "comp_prompt"},

        # ── D: Validation (validate_tool_call) ──
        {"id": "comp-val-1", "prompt": "valid bash call", "input": "{\"name\":\"bash\",\"arguments_str\":\"{\\\"command\\\":\\\"ls\\\"}\"}", "expected": "true", "compiler_fn": "validate", "kind": "comp_validate"},
        {"id": "comp-val-2", "prompt": "missing required arg", "input": "{\"name\":\"bash\",\"arguments_str\":\"{}\"}", "expected": "false", "compiler_fn": "validate", "kind": "comp_validate"},
        {"id": "comp-val-3", "prompt": "unknown tool", "input": "{\"name\":\"nonexistent_tool\",\"arguments_str\":\"{}\"}", "expected": "false", "compiler_fn": "validate", "kind": "comp_validate"},
        {"id": "comp-val-4", "prompt": "destructive bash (rm -rf /)", "input": "{\"name\":\"bash\",\"arguments_str\":\"{\\\"command\\\":\\\"rm -rf /\\\"}\"}", "expected": "false", "compiler_fn": "validate", "kind": "comp_validate"},
        {"id": "comp-val-5", "prompt": "valid grep call", "input": "{\"name\":\"grep\",\"arguments_str\":\"{\\\"pattern\\\":\\\"hello\\\"}\"}", "expected": "true", "compiler_fn": "validate", "kind": "comp_validate"},
    ]

# ──────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────
proc get_categories():
    return ["reasoning", "knowledge", "coding", "tool_use", "instruction", "reading_comprehension", "commonsense_reasoning", "tool_compilation"]

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
    if category == "reading_comprehension":
        return _tasks_reading()
    if category == "commonsense_reasoning":
        return _tasks_commonsense()
    if category == "tool_compilation":
        return _tasks_tool_compilation()
    return []

# ──────────────────────────────────────────────
# Internal scoring helpers
# ──────────────────────────────────────────────
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

# Score a tool_compilation benchmark task deterministically (no model call).
# Returns {"correct": bool, "output": string}.
proc score_compiler_task(task):
    let fn = task["compiler_fn"]
    let input = task["input"]
    let expected = task["expected"]

    if fn == "extract_json":
        let result = compiler.extract_json_from_text(input)
        if result == "":
            let ok = expected == ""
            return {"correct": ok, "output": result}
        let parsed = json.cJSON_Parse(result)
        if parsed == nil:
            let ok = expected == ""
            return {"correct": ok, "output": result}
        let name_node = json.cJSON_GetObjectItem(parsed, "name")
        var name = ""
        if name_node != nil:
            name = json.cJSON_GetStringValue(name_node)
        json.cJSON_Delete(parsed)
        let ok = name == expected
        return {"correct": ok, "output": name}

    if fn == "extract_intent":
        let result = compiler.extract_intent_from_bonsai(input)
        let ok = strip(result) == strip(expected)
        return {"correct": ok, "output": slice(result, 0, 200)}

    if fn == "check_prompt_contains":
        let tools_list = tools.get_tool_list()
        let prompt = compiler.build_compiler_prompt(input, tools_list)
        let ok = contains(prompt, expected)
        return {"correct": ok, "output": slice(prompt, 0, 200)}

    if fn == "validate":
        let ref = tools.get_tool_list()
        if len(ref) == 0:
            {}
        let call = {}
        call["name"] = ""
        call["arguments_str"] = "{}"
        let parsed_call = json.cJSON_Parse(input)
        if parsed_call != nil:
            let name_n = json.cJSON_GetObjectItem(parsed_call, "name")
            if name_n != nil:
                let raw = json.cJSON_GetStringValue(name_n)
                if raw != nil:
                    call["name"] = "" + raw
            let args_n = json.cJSON_GetObjectItem(parsed_call, "arguments_str")
            if args_n != nil:
                let raw_a = json.cJSON_GetStringValue(args_n)
                if raw_a != nil:
                    call["arguments_str"] = "" + raw_a
            json.cJSON_Delete(parsed_call)
        let v = validator.validate_tool_call(call)
        let ok = (expected == "true" and v["valid"]) or (expected == "false" and not v["valid"])
        return {"correct": ok, "output": str(v["valid"])}

    return {"correct": false, "output": "unknown compiler_fn: " + fn}
