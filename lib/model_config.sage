let ROLE_PRIMARY = "primary"
let ROLE_TOOL_COMPILER = "tool_compiler"

let MODEL_BONSAI = "hf.co/prism-ml/Bonsai-4B-gguf:Q1_0"
let MODEL_MINICPM = "minicpm5-1b"

let DEFAULT_OLLAMA_HOST = "localhost"
let DEFAULT_OLLAMA_PORT = 11434

let MAX_TOOL_COMPILER_RETRIES = 2
let MAX_AGENT_ITERATIONS = 6

let model_roles = {}
model_roles[ROLE_PRIMARY] = MODEL_BONSAI
model_roles[ROLE_TOOL_COMPILER] = MODEL_MINICPM

proc get_model_for_role(role):
    if dict_has(model_roles, role):
        return model_roles[role]
    return MODEL_BONSAI

proc set_model_for_role(role, model_name):
    model_roles[role] = model_name

proc get_role_label(role):
    if role == ROLE_PRIMARY:
        return "Bonsai 4B (Primary)"
    if role == ROLE_TOOL_COMPILER:
        return "MiniCPM5 1B (Tool Compiler)"
    return role
