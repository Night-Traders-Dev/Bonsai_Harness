# Security Audit & Mitigations

This document describes the security posture of the Bonsai Agent Harness, the
results of a systematic audit, and the mitigations that have been applied.

## Threat model

The harness is an **LLM agent that executes tools on the host**. The model's
output is **untrusted** — it can be steered by prompt injection from files the
agent reads, web pages it fetches, or tool results it observes — yet it drives
the `bash`, `write_file`, and `web_fetch` tools with full OS access.

| Who | Can send | To | Risk |
|-----|----------|----|------|
| User (interactive) | text prompts | harness | low — user owns the machine |
| Model output | tool calls | bash, files, network | **high** — indirect prompt injection |
| Tool results (file, web) | next model input | model → tool calls | **critical** — data-injection vector |
| An attacker on the LAN | HTTP requests to Ollama | model | medium — no auth (localhost assumption) |

## Audit summary

| ID | Severity | Component | Issue | Mitigated |
|----|----------|-----------|-------|-----------|
| C1 | **Critical** | tools/agent | Unconfined auto-executed `bash` (no sandbox, no confirmation) | Partial (file confinement) |
| C2 | **Critical** | agent | Indirect prompt injection flows straight to tool execution | See C1 + M2 |
| H1 | **High** | tools | Path traversal / unrestricted filesystem access | ✅ |
| H2 | **High** | tools | SSRF — model can hit cloud metadata / internal services | ✅ |
| M1 | **Medium** | ollama | Incomplete JSON control-char escaping → injection / corrupt JSON | ✅ |
| M2 | **Medium** | tui | ANSI / terminal escape injection → UI spoofing | ✅ |
| M3 | **Medium** | ollama/http | Plaintext HTTP, no auth (localhost-only) | Documented |
| M4 | **Medium** | tools | `https://` silently downgraded to cleartext TCP | ✅ |
| L1 | Low | tools | `web_fetch` URL parser is fragile (no @, fragments, IPv6) | Noted |
| L2 | Low | tools | Unbounded directory walks in grep/glob → CPU/IO DoS | Noted |
| L3 | Low | tools | No size limit on `write_file` → disk fill | Noted |
| L4 | Info | sagemake | Full env forwarded to child processes | Acceptable |
| L5 | Info | — | No secret handling issues | ✓ |

---

## Mitigations applied

### V1 — Tool validation layer

**Files:** `lib/tool_validator.sage`

The dual-model architecture adds a dedicated validation layer that intercepts
every tool call before execution. `tool_validator.validate_tool_call()` enforces:

- **Tool existence** — rejects calls to unknown or unregistered tools.
- **Required arguments** — verifies every required argument is present and is
  a string.
- **Security policies:**
  - `bash`: blocks destructive commands (`rm -rf /`, `mkfs`, `dd if=`)
  - `read_file`/`write_file`: requires `path`, blocks `..` traversal
  - `web_fetch`: only `http://` URLs, no `https://`

Calls that fail validation return a structured error which is surfaced in the
TUI and the agent can recover from it. This adds a defense-in-depth layer
independent of the tool runtime's existing path/SSRF checks.

### H1 — Workspace confinement for file tools

**Files:** `lib/tools.sage:15-35`

All file-access tools (`read_file`, `write_file`, `list_dir`, `grep`, and
`glob`) now validate that the requested path is **relative** to the workspace
and contains **no directory traversal** (`..`). The `_validate_path` helper
checks every path argument and returns a descriptive error message when:

- The path is absolute (starts with `/`)
- The path contains `..`
- The path is empty

This prevents the model from reading/writing outside the harness working
directory, blocking attacks against `/etc/passwd`, `~/.ssh/`, cloud credential
files, and other sensitive locations.

```sage
proc _validate_path(path):
    if path == nil or strip(path) == "":
        return "Error: path is empty"
    if startswith(path, "/"):
        return "Error: path must be relative to the workspace (got absolute path)"
    if contains(path, ".."):
        return "Error: path traversal not allowed ('..' in path)"
    return path
```

> **Limitation:** SageLang has no `realpath` function, so symlink-based escapes
> are not detected. This is a known gap; full resolution would need a C FFI
> call to `realpath(3)`.

### H2 — SSRF protection in `web_fetch`

**Files:** `lib/tools.sage:196-244`

The `web_fetch` tool now refuses to connect to private, loopback, link-local,
or carrier-grade NAT addresses. The `_is_blocked_host` helper checks:

- Named hosts: `localhost`, `127.0.0.1`, `0.0.0.0`, `::1`
- Loopback: `127.0.0.0/8`
- Private: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- Link-local: `169.254.0.0/16` (covers cloud metadata `169.254.169.254`)
- Carrier-grade NAT: `100.64.0.0/10`

This prevents the model from being steered to exfiltrate cloud metadata
(AWS/GCP/Azure instance credentials), attack internal services, or
reflect/scrape LAN resources.

### M4 — HTTPS rejection

**Files:** `lib/tools.sage:250-251`

The `web_fetch` tool now returns a clear error for `https://` URLs instead of
silently downgrading them to unencrypted TCP. Real TLS support would require
a TLS library binding, which is not currently available in SageLang's stdlib.

### M1 — JSON control-char escaping

**Files:** `lib/ollama.sage:22-52`

The `json_escape` proc previously escaped only `\`, `"`, `\n`, and `\t`.
It now also escapes:

| Character | Escape |
|-----------|--------|
| CR (`\r`) | `\r` |
| Backspace (`\b`) | `\b` |
| Form feed (`\f`) | `\f` |
| All other 0x00–0x1f | `\u00XX` (hex) |

Content from tool results and web pages flows through `build_messages_json` into
the Ollama request body. Unescaped control characters produce invalid JSON,
causing request failures or, depending on the parser, potential injection past
the content boundary.

### M2 — ANSI escape stripping in TUI

**Files:** `lib/tui.sage:10-28`, `:115`, `:138`, `:166`

Tool results, model tokens, and tool-call argument values are now sanitized
through `strip_ansi` before being printed. This removes all ANSI escape
sequences (`\x1b[...`) from untrusted text, preventing terminal injection
attacks that could:

- Spoof or hide output with cursor-movement codes
- Rewrite terminal history / scrollback
- Exploit terminal emulator vulnerabilities (e.g. clipboard access, title
  changes)

The harness's own styling codes are applied outside `strip_ansi` in the
calling code, so the UI remains colored even while untrusted text is sanitized.

---

## Remaining risks (not mitigated)

### C1 + C2 — Unconfirmed, unsandboxed tool execution

The agent still auto-executes every tool call the model emits with **no
confirmation prompt** and **no sandbox** (no container, no seccomp, no cgroup).
A successful prompt injection in any file or web page the agent reads can make
it run arbitrary `bash` commands or write arbitrary files. Mitigating this
requires one of:

- **Interactive confirmation** — prompt the user before running `bash`,
  `write_file`, or any tool with side effects.
- **Allowlist / denylist** — restrict `bash` to a safe set of commands.
- **Container sandbox** — run the agent inside a Docker container or a
  minimal chroot.
- **Read-only workspace** — mount the workspace as read-only and use a
  separate write directory.
- **Tool-output sanitisation** — wrap tool output in clearly-delimited
  "data-only" framing so the model learns to treat tool results as facts,
  not instructions.

These are product-design decisions that depend on your deployment context
(interactive desktop vs. headless automation) and acceptable risk level.

---

## Audit methodology

1. Read every source file in the project.
2. Identified every path where untrusted data (model output, file contents,
   web responses) crosses a trust boundary into a system call or display.
3. Classified each finding by severity:
   - **Critical** — direct, unconfined OS execution from untrusted input.
   - **High** — access to sensitive resources without authorisation.
   - **Medium** — injection that requires specific conditions to exploit.
   - **Low** — DoS, resource exhaustion, or borderline scenarios.

## Running the test suite

The existing test suite was updated to reflect the new security boundaries:

```bash
./sagemake test
```

Tests that previously used absolute paths (`/tmp/...`) or localhost URLs now
test the security error messages instead, confirming that the mitigations are
active.

## Related

- [tools.md](tools.md) — the file tools and web_fetch implementation
- [tui.md](tui.md) — ANSI sanitization in the terminal UI
- [ollama.md](ollama.md) — JSON escaping in request building
- [architecture.md](architecture.md) — data flow showing where untrusted data enters the system
