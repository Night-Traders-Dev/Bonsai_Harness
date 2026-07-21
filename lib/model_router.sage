import lib.model_config as cfg

let TASK_REASONING = "reasoning"
let TASK_PLANNING = "planning"
let TASK_CODING = "coding"
let TASK_ANALYSIS = "analysis"
let TASK_FINAL_RESPONSE = "final_response"
let TASK_TOOL_CALL = "tool_call"
let TASK_TOOL_COMPILE = "tool_compile"
let TASK_CLASSIFICATION = "classification"

proc route_task(task_type):
    if task_type == TASK_REASONING:
        return cfg.ROLE_PRIMARY
    if task_type == TASK_PLANNING:
        return cfg.ROLE_PRIMARY
    if task_type == TASK_CODING:
        return cfg.ROLE_PRIMARY
    if task_type == TASK_ANALYSIS:
        return cfg.ROLE_PRIMARY
    if task_type == TASK_FINAL_RESPONSE:
        return cfg.ROLE_PRIMARY
    if task_type == TASK_TOOL_CALL:
        return cfg.ROLE_TOOL_COMPILER
    if task_type == TASK_TOOL_COMPILE:
        return cfg.ROLE_TOOL_COMPILER
    if task_type == TASK_CLASSIFICATION:
        return cfg.ROLE_TOOL_COMPILER
    return cfg.ROLE_PRIMARY
