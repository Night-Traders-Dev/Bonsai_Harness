# PLAN.md

# Bonsai Dual-Model Agent Architecture

**Project:** Bonsai Harness
**Architecture:** Bonsai 4B 1-bit + MiniCPM5-1B F16
**Status:** Proposed
**Primary Goal:** Improve tool-use reliability and structured execution without sacrificing the reasoning and coding capabilities of Bonsai 4B.

---

## 1. Executive Summary

This plan introduces a dual-model architecture into Bonsai Harness.

The system will use:

* **Bonsai 4B 1-bit** as the primary reasoning, planning, coding, and synthesis model.
* **MiniCPM5-1B F16 Claude Opus Fable5 V2 Thinking** as a specialized tool-call and structured-output model.

The two models will **not be merged at the weight level**.

Instead, Bonsai Harness will act as an orchestration layer that routes different responsibilities to the model best suited for the task.

The core architecture is:

```text
                         User
                           │
                           ▼
                  ┌─────────────────┐
                  │   Bonsai 4B     │
                  │      1-bit      │
                  │                 │
                  │ Primary Agent   │
                  │ Reasoning       │
                  │ Planning        │
                  │ Coding          │
                  └────────┬────────┘
                           │
                           │ Tool required
                           ▼
                  ┌─────────────────┐
                  │   MiniCPM5      │
                  │      1B F16      │
                  │                 │
                  │ Tool Compiler   │
                  │ Tool Selection  │
                  │ Structured JSON │
                  │ XML Generation  │
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │   Tool Runtime  │
                  │                 │
                  │ bash            │
                  │ read_file       │
                  │ write_file      │
                  │ grep            │
                  │ glob            │
                  │ list_dir        │
                  │ web_fetch       │
                  └────────┬────────┘
                           │
                           │ Tool Result
                           ▼
                  ┌─────────────────┐
                  │   Bonsai 4B     │
                  │      1-bit      │
                  │                 │
                  │ Observe         │
                  │ Reason          │
                  │ Re-plan         │
                  │ Synthesize      │
                  └────────┬────────┘
                           │
                           ▼
                         User
```

The objective is to make the system behave like a single intelligent agent while internally separating:

1. **Reasoning**
2. **Tool-call compilation**
3. **Tool execution**
4. **Observation**
5. **Final synthesis**

---

# 2. Design Principles

The implementation must follow these principles.

## 2.1 No Weight Merging

Do not attempt to combine:

* Bonsai 4B weights
* MiniCPM5 weights

into a single neural network.

They are different architectures and training configurations.

The combination occurs at the **agent orchestration layer**, not the model-weight layer.

---

## 2.2 Bonsai Is the Primary Brain

Bonsai 4B 1-bit is responsible for:

* Understanding user intent
* Complex reasoning
* Planning
* Coding
* Architecture decisions
* Deciding when tools are required
* Interpreting tool results
* Re-planning after tool execution
* Producing final responses

Bonsai should remain the authoritative model for agent state.

---

## 2.3 MiniCPM5 Is a Specialized Tool Compiler

MiniCPM5-1B F16 is responsible for:

* Converting tool intent into structured tool calls
* Selecting tools when appropriate
* Generating valid tool arguments
* Producing strict XML/JSON tool-call structures
* Normalizing tool-call output
* Reducing malformed tool calls

MiniCPM should not own the primary conversation state.

It should receive a narrow task and return a structured result.

---

## 2.4 Deterministic Tool Execution

Models must never directly execute tools.

The architecture must remain:

```text
Model
  │
  ▼
Structured Tool Request
  │
  ▼
Validator
  │
  ▼
Tool Runtime
  │
  ▼
Tool Result
```

Never:

```text
Model
  │
  ▼
Direct Shell Execution
```

The existing Bonsai Harness security and validation layer remains authoritative.

---

# 3. Model Roles

## 3.1 Bonsai 4B 1-bit

### Primary responsibilities

```text
reasoning
planning
coding
analysis
architecture
context synthesis
agent state
final response
```

### Example

User:

```text
Fix the compiler error caused by s_strip.
```

Bonsai determines:

```text
1. Inspect source tree.
2. Search for s_strip.
3. Inspect relevant source files.
4. Determine whether the function exists.
5. Fix implementation or declaration.
6. Rebuild.
7. Analyze build output.
8. Report result.
```

Bonsai produces the intent.

---

## 3.2 MiniCPM5-1B F16

### Primary responsibilities

```text
tool selection
tool-call compilation
structured output
argument generation
format normalization
```

Given:

```text
Intent:
Search the repository for all references to s_strip.
```

MiniCPM should produce:

```xml
<tool_call>
{
  "name": "grep",
  "arguments": {
    "pattern": "s_strip",
    "path": "."
  }
}
</tool_call>
```

The exact format should match the existing Bonsai Harness tool protocol.

MiniCPM must not be required to reason about the entire task.

Its job is:

```text
Intent → Valid Tool Call
```

---

# 4. Proposed Agent Loop

The current ReAct loop should be extended to support model routing.

## Phase 1 — User Input

```text
User Input
    │
    ▼
Bonsai 4B
```

Bonsai analyzes the request.

---

## Phase 2 — Planning

Bonsai determines whether the request requires:

* Direct response
* Tool execution
* Multi-step tool execution
* Code generation
* Repository modification

If no tool is required:

```text
Bonsai
  │
  ▼
Final Response
```

If a tool is required:

```text
Bonsai
  │
  ▼
Tool Intent
```

---

## Phase 3 — Tool Compilation

The tool intent is passed to MiniCPM5.

Input:

```text
Task:
Find all references to s_strip.

Available tools:
- grep
- glob
- read_file
- list_dir
- bash

Constraints:
- Do not execute arbitrary shell commands.
- Return exactly one tool call.
```

MiniCPM5 generates:

```json
{
  "name": "grep",
  "arguments": {
    "pattern": "s_strip",
    "path": "."
  }
}
```

---

## Phase 4 — Validation

The generated tool call must pass through a validator.

Validation requirements:

* Tool exists
* Arguments are valid
* Required arguments exist
* Argument types are correct
* Paths are allowed
* Command execution policy is satisfied
* No unexpected fields are present

Invalid calls must never reach execution.

---

## Phase 5 — Tool Execution

The validated call is executed by the existing tool layer.

Example:

```text
MiniCPM
    │
    ▼
Tool Validator
    │
    ▼
grep()
    │
    ▼
Tool Result
```

---

## Phase 6 — Observation

The tool result is returned to Bonsai.

Example:

```text
Tool:
grep

Result:
src/main.sage:97
lib/string.sage:42
```

Bonsai evaluates the result.

---

## Phase 7 — ReAct Iteration

Bonsai decides:

```text
Continue
```

or:

```text
Finish
```

or:

```text
Call another tool
```

The cycle repeats:

```text
Bonsai
   ↓
MiniCPM
   ↓
Validator
   ↓
Tool
   ↓
Result
   ↓
Bonsai
```

Maximum iterations should remain configurable.

Recommended initial default:

```text
MAX_ITERATIONS = 6
```

---

# 5. Architecture Changes

The existing Bonsai Harness should be extended with a model-routing layer.

Proposed structure:

```text
Bonsai_Harness/
│
├── PLAN.md
├── ARCHITECTURE.md
├── sagemake
│
├── lib/
│   ├── agent.sage
│   ├── ollama.sage
│   ├── tools.sage
│   ├── tui.sage
│   ├── http_client.sage
│   ├── skills.sage
│   │
│   ├── model_router.sage
│   ├── tool_compiler.sage
│   ├── tool_validator.sage
│   └── model_config.sage
│
├── models/
│   ├── bonsai.sage
│   └── minicpm.sage
│
├── src/
│   ├── main.sage
│   └── bonsai.c
│
└── tests/
    ├── test_model_router.sage
    ├── test_tool_compiler.sage
    ├── test_tool_validator.sage
    └── test_agent_loop.sage
```

The exact structure may be adjusted to match the existing repository.

---

# 6. New Components

## 6.1 model_router.sage

Responsible for determining which model handles a task.

Conceptual API:

```text
model_route(task_type)
```

Possible routes:

```text
REASONING
    → Bonsai

CODING
    → Bonsai

PLANNING
    → Bonsai

FINAL_RESPONSE
    → Bonsai

TOOL_CALL
    → MiniCPM5

STRUCTURED_OUTPUT
    → MiniCPM5

CLASSIFICATION
    → MiniCPM5
```

The router should initially use explicit routing.

Do not introduce autonomous model selection until the baseline architecture is stable.

---

## 6.2 tool_compiler.sage

Responsible for:

```text
Bonsai Intent
    ↓
MiniCPM5 Prompt
    ↓
MiniCPM5 Output
    ↓
Parsed Tool Call
```

The compiler should:

1. Build the specialized prompt.
2. Include only relevant tool definitions.
3. Invoke MiniCPM5.
4. Extract the tool call.
5. Normalize the output.
6. Pass it to validation.

---

## 6.3 tool_validator.sage

Responsible for security and correctness.

Validation pipeline:

```text
Raw Model Output
       │
       ▼
Parser
       │
       ▼
Schema Validation
       │
       ▼
Tool Validation
       │
       ▼
Argument Validation
       │
       ▼
Security Validation
       │
       ▼
Execution
```

Rejected calls should return a structured error.

Example:

```json
{
  "error": "invalid_tool_call",
  "reason": "Unknown tool: execute_command"
}
```

The error can be returned to Bonsai for recovery.

---

# 7. Model Configuration

The system should support environment-based configuration.

Example:

```text
Bonsai:
  MODEL=bonsai-4b
  QUANT=Q1_0
  ROLE=primary

MiniCPM:
  MODEL=minicpm5-1b
  QUANT=F16
  ROLE=tool_compiler
```

The model backend should remain abstract.

Possible backends:

```text
Ollama
llama.cpp
OpenAI-compatible HTTP server
Custom local inference server
```

The routing layer should not depend directly on one inference backend.

---

# 8. Prompt Architecture

## 8.1 Bonsai System Prompt

Bonsai should receive the complete agent context.

It should know:

* User request
* Current task
* Previous reasoning state
* Tool results
* Available tools
* Current iteration
* Project context
* Skills

Bonsai should output an internal action request.

Example:

```text
ACTION: TOOL
TOOL: grep
INTENT:
Search for all references to s_strip in the repository.
```

The actual format should be finalized during implementation.

---

## 8.2 MiniCPM System Prompt

MiniCPM should receive a much smaller context.

Example:

```text
You are the Bonsai Tool Compiler.

Your only task is to convert the supplied tool intent
into exactly one valid tool call.

Do not explain your reasoning.

Do not answer the user.

Do not invent tools.

Return only the required structured tool call.
```

Then provide:

```text
Available Tool:
grep

Schema:
{
  "pattern": string,
  "path": string
}

Intent:
Search for all references to s_strip in the repository.
```

This constrained prompt is critical.

The MiniCPM model should not be burdened with the entire agent conversation.

---

# 9. F16 vs Q8_0 Testing

The initial implementation should use:

```text
MiniCPM5-1B F16
```

because the objective is to establish the highest-quality baseline.

After functionality is verified, benchmark:

```text
MiniCPM5 F16
vs
MiniCPM5 Q8_0
```

Measure:

* Tool-call accuracy
* JSON validity
* XML validity
* Argument accuracy
* Tool selection
* Latency
* Tokens/sec
* VRAM
* RAM
* Context usage
* Failure rate

The F16 model should only remain the default if it demonstrates measurable improvements.

Otherwise use Q8_0.

---

# 10. Benchmark Suite

Create a dedicated dual-model benchmark.

## Test Categories

### A. Simple Tool Selection

```text
Read file X.
```

Expected:

```text
read_file
```

---

### B. Search

```text
Find all references to function X.
```

Expected:

```text
grep
```

---

### C. File Discovery

```text
Find all Sage source files.
```

Expected:

```text
glob
```

---

### D. Multi-Step Task

```text
Find the implementation of s_strip,
inspect it,
and determine why compilation fails.
```

Expected:

```text
Bonsai
  ↓
grep
  ↓
Bonsai
  ↓
read_file
  ↓
Bonsai
```

---

### E. Tool Failure Recovery

Test:

```text
Invalid path
Missing file
Malformed tool result
Command failure
```

The agent must recover.

---

### F. Malformed Output

Intentionally induce:

```text
Invalid JSON
Unknown tool
Missing argument
Extra argument
Invalid path
```

The validator must reject these safely.

---

# 11. Performance Targets

Initial targets:

| Metric                      |     Target |
| --------------------------- | ---------: |
| Tool-call validity          |       >95% |
| Correct tool selection      |       >90% |
| Valid argument generation   |       >90% |
| Unauthorized tool execution |         0% |
| Tool compiler timeout       | <5 seconds |
| Agent iteration limit       |          6 |
| Model routing overhead      |    Minimal |

These are engineering targets, not guaranteed model benchmarks.

---

# 12. Memory Strategy

The system should support two operating modes.

## Mode A — Dual Resident

Both models remain loaded.

```text
Bonsai 4B
+
MiniCPM5 1B
```

Advantages:

* Lowest switching latency
* Best interactive performance

Disadvantages:

* Higher memory use

Recommended for:

```text
RTX 5060 8 GB
Desktop GPU
High-memory systems
```

---

## Mode B — Dynamic Loading

Only one model is loaded at a time.

```text
Bonsai
  ↓
Unload
  ↓
MiniCPM
  ↓
Unload
  ↓
Bonsai
```

Advantages:

* Lower memory requirements

Disadvantages:

* Model loading latency

Recommended for:

```text
Mobile
Low-RAM systems
Embedded devices
```

The architecture must support both.

---

# 13. Galaxy S26 Strategy

For mobile deployment, initially test:

```text
Bonsai 4B 1-bit
+
MiniCPM5 1B Q8_0
```

Do not assume F16 is optimal on mobile.

Benchmark:

```text
F16
Q8_0
```

against:

* CPU inference
* GPU inference
* Vulkan
* Snapdragon acceleration
* NPU-capable backend, if supported

The NPU should only be considered a viable target if the inference backend can actually execute the model architecture and quantization format on the NPU.

Do not assume that a GGUF model automatically runs on the NPU.

---

# 14. Failure Handling

If MiniCPM5 fails to produce a valid tool call:

```text
MiniCPM5
   ↓
Invalid Output
   ↓
Validator
   ↓
Retry
```

Recommended retry count:

```text
MAX_TOOL_COMPILER_RETRIES = 2
```

If retries fail:

```text
MiniCPM5
   ↓
Failure
   ↓
Bonsai
```

Bonsai should then be allowed to:

1. Retry with a simplified tool intent.
2. Directly generate a tool call.
3. Ask the user for clarification.
4. Abort safely.

The primary model must always have a fallback path.

---

# 15. Security Model

The addition of a second model must not weaken the existing security architecture.

MiniCPM5 must never have direct access to:

* Shell execution
* Filesystem APIs
* Network APIs
* Process creation

It only generates structured requests.

The tool runtime remains responsible for:

* Permissions
* Sandboxing
* Path validation
* Command restrictions
* Network restrictions
* Output limits

---

# 16. Implementation Phases

## Phase 1 — Baseline

Implement:

```text
Bonsai 4B
    ↓
Existing Tools
```

Record baseline metrics.

---

## Phase 2 — Model Abstraction

Create:

```text
ModelProvider
ModelRouter
```

Make the agent independent of the specific inference backend.

---

## Phase 3 — MiniCPM Integration

Add:

```text
MiniCPM5 F16
```

as a second model provider.

Verify standalone inference.

---

## Phase 4 — Tool Compiler

Implement:

```text
Bonsai Intent
    ↓
MiniCPM5
    ↓
Structured Tool Call
```

---

## Phase 5 — Validator

Implement strict validation.

No tool call should execute without passing validation.

---

## Phase 6 — Dual-Model ReAct Loop

Implement:

```text
Bonsai
  ↓
MiniCPM
  ↓
Validator
  ↓
Tool
  ↓
Bonsai
```

---

## Phase 7 — Benchmarking

Run the complete benchmark suite.

Compare:

```text
Bonsai-only
Bonsai + MiniCPM F16
Bonsai + MiniCPM Q8_0
```

---

## Phase 8 — Optimization

Optimize:

* Prompt length
* Tool schemas
* Model loading
* Context reuse
* KV cache
* Streaming
* Routing latency

---

## Phase 9 — Mobile Profile

Create:

```text
Desktop Profile
Mobile Profile
Embedded Profile
```

Desktop:

```text
Bonsai Q1_0
+
MiniCPM F16
```

Mobile:

```text
Bonsai Q1_0
+
MiniCPM Q8_0
```

Embedded:

```text
Bonsai Q1_0
```

with optional dynamic MiniCPM loading.

---

# 17. Success Criteria

The architecture is successful if it demonstrates:

1. Higher tool-call reliability than Bonsai alone.
2. No measurable degradation in reasoning quality.
3. Lower malformed tool-call frequency.
4. Reliable structured output.
5. Safe tool execution.
6. Acceptable latency.
7. Efficient memory usage.
8. Clean model abstraction.
9. Backend independence.
10. Successful operation on desktop and mobile profiles.

---

# 18. Final Recommended Architecture

The production target should be:

```text
                    ┌─────────────────────┐
                    │        User         │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │    Bonsai 4B 1-bit  │
                    │                     │
                    │ Primary Intelligence│
                    │                     │
                    │ • Reasoning         │
                    │ • Coding            │
                    │ • Planning          │
                    │ • Agent State       │
                    │ • Synthesis         │
                    └──────────┬──────────┘
                               │
                         Tool Intent
                               │
                               ▼
                    ┌─────────────────────┐
                    │ MiniCPM5 1B F16     │
                    │                     │
                    │ Tool Compiler       │
                    │                     │
                    │ • Tool Selection    │
                    │ • JSON/XML          │
                    │ • Arguments         │
                    │ • Structured Output │
                    └──────────┬──────────┘
                               │
                         Tool Request
                               │
                               ▼
                    ┌─────────────────────┐
                    │    Tool Validator   │
                    └──────────┬──────────┘
                               │
                         Valid Request
                               │
                               ▼
                    ┌─────────────────────┐
                    │     Tool Runtime    │
                    │                     │
                    │ bash                │
                    │ read_file           │
                    │ write_file          │
                    │ grep                │
                    │ glob                │
                    │ list_dir            │
                    │ web_fetch           │
                    └──────────┬──────────┘
                               │
                           Tool Result
                               │
                               ▼
                    ┌─────────────────────┐
                    │    Bonsai 4B 1-bit  │
                    │                     │
                    │ Observe             │
                    │ Reason              │
                    │ Re-plan             │
                    │ Synthesize          │
                    └──────────┬──────────┘
                               │
                               ▼
                            User
```

## Final Recommendation

**Implement Bonsai 4B 1-bit + MiniCPM5-1B F16 as a dual-model system first.**

Do not merge the models.

Use:

```text
Bonsai 4B 1-bit
    =
Primary intelligence
```

and:

```text
MiniCPM5-1B F16
    =
Specialized tool-call compiler
```

Then benchmark F16 against Q8_0. If F16 provides negligible improvement in tool-call reliability, switch the production configuration to Q8_0 to reduce memory usage.

The long-term architecture should make the model roles configurable so the system can eventually support:

```text
Primary Model
Tool Model
Fast Model
Coding Model
Vision Model
Embedding Model
```

This turns Bonsai Harness from a single-model ReAct wrapper into a **modular multi-model agent runtime**, while keeping Bonsai 4B as the central intelligence layer.
