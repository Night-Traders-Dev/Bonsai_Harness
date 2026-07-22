import lib.ollama as ollama
import lib.model_config as cfg

var loaded_role = ""

proc use_role(role):
    let model_name = cfg.get_model_for_role(role)
    ollama.set_model(model_name)
    loaded_role = role

proc use_primary():
    use_role(cfg.ROLE_PRIMARY)

proc use_tool_compiler():
    use_role(cfg.ROLE_TOOL_COMPILER)

proc get_current_role():
    return loaded_role

proc get_current_model():
    return ollama.get_model()

proc chat(messages, tools, on_token, on_done):
    return ollama.ollama_chat(messages, tools, on_token, on_done)

proc ask(messages, tools):
    return ollama.ollama_ask(messages, tools)

proc unload_current():
    ollama.unload_model()
    loaded_role = ""

proc unload_all():
    unload_current()
