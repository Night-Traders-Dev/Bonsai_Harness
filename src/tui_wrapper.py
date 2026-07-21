#!/usr/bin/env python3
import sys
import os
import tty
import termios
import subprocess
import threading
import select

HISTORY_FILE = os.path.expanduser("~/.bonsai_history")
BUILTIN_COMMANDS = [":help", ":clear", ":history", ":models", ":ingest-skills", ":bench", ":quit", ":exit"]

def load_history():
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r") as f:
                return [line.strip() for line in f.readlines() if line.strip()]
        except:
            pass
    return []

def save_history(history):
    try:
        with open(HISTORY_FILE, "w") as f:
            for item in history:
                f.write(item + "\n")
    except:
        pass

def find_suggestion(prefix, history):
    if not prefix: return ""
    if prefix.startswith(":"):
        for cmd in BUILTIN_COMMANDS:
            if cmd.startswith(prefix) and cmd != prefix:
                return cmd
    else:
        for item in reversed(history):
            if item.lower().startswith(prefix.lower()) and item != prefix:
                return item
    return ""

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--no-wrapper":
        os.execv(sys.argv[2], sys.argv[2:])

    # Find the binary or fallback to sagemake run
    binary_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bonsai-harness.jit")
    
    if os.path.exists(binary_path):
        cmd = [binary_path] + sys.argv[1:]
    else:
        root = os.path.dirname(os.path.abspath(__file__))
        lib_dir = os.path.join(root, "lib")
        sage_path = os.environ.get("SAGE_PATH", "")
        os.environ["SAGE_PATH"] = f"{root}:{lib_dir}:{sage_path}"
        cmd = ["sage", "--runtime", "jit", os.path.join(root, "src", "main.sage")] + sys.argv[1:]

    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=None, stderr=None)
    
    history = load_history()
    
    old_settings = termios.tcgetattr(sys.stdin)
    try:
        tty.setcbreak(sys.stdin.fileno())
        
        line = ""
        history_idx = len(history)
        
        while p.poll() is None:
            char = sys.stdin.read(1)
            if not char:
                break
                
            if char == '\x04': # Ctrl+D
                if not line:
                    p.stdin.write(b"\x04\n")
                    p.stdin.flush()
                continue
                
            if char == '\x0c': # Ctrl+L
                p.stdin.write(b"\x0c\n")
                p.stdin.flush()
                line = ""
                history_idx = len(history)
                continue
                
            if char == '\r' or char == '\n':
                # Clear ghost text before newline
                sys.stdout.write(" " * 20 + f"\x1b[20D")
                sys.stdout.write("\r\n")
                sys.stdout.flush()
                trimmed = line.strip()
                if trimmed and not trimmed.startswith(":clear") and trimmed not in history:
                    history.append(trimmed)
                    save_history(history)
                
                p.stdin.write(line.encode('utf-8') + b"\n")
                p.stdin.flush()
                line = ""
                history_idx = len(history)
                continue
                
            if char == '\x7f' or char == '\b': # Backspace
                if len(line) > 0:
                    line = line[:-1]
                    sys.stdout.write("\b \b")
                    
                    # Redraw ghost text if needed
                    sug = find_suggestion(line, history)
                    if sug:
                        rem = sug[len(line):]
                        sys.stdout.write(f"\x1b[90m{rem}\x1b[0m")
                        sys.stdout.write(f"\x1b[{len(rem)}D")
                    else:
                        # Clear old ghost text by overwriting with spaces and returning
                        sys.stdout.write(" " * 20 + f"\x1b[20D")
                        
                    sys.stdout.flush()
                continue
                
            if char == '\t': # Tab autocomplete
                sug = find_suggestion(line, history)
                if sug:
                    rem = sug[len(line):]
                    line = sug
                    sys.stdout.write(rem)
                    sys.stdout.flush()
                continue
                
            if char == '\x1b': # Escape sequence
                r, _, _ = select.select([sys.stdin], [], [], 0.05)
                if r:
                    char2 = sys.stdin.read(1)
                    if char2 == '[':
                        char3 = sys.stdin.read(1)
                        if char3 == 'A': # Up
                            if history_idx > 0:
                                history_idx -= 1
                                sys.stdout.write(f"\r\x1b[K\x1b[1m> \x1b[0m{history[history_idx]}")
                                sys.stdout.flush()
                                line = history[history_idx]
                        elif char3 == 'B': # Down
                            if history_idx < len(history) - 1:
                                history_idx += 1
                                sys.stdout.write(f"\r\x1b[K\x1b[1m> \x1b[0m{history[history_idx]}")
                                sys.stdout.flush()
                                line = history[history_idx]
                            else:
                                history_idx = len(history)
                                sys.stdout.write(f"\r\x1b[K\x1b[1m> \x1b[0m")
                                sys.stdout.flush()
                                line = ""
                        continue
                else:
                    # Bare Esc -> treat like Ctrl+C
                    char = '\x03'
            
            if char == '\x03': # Ctrl+C or Esc
                p.stdin.write(b"\x03\n")
                p.stdin.flush()
                line = ""
                history_idx = len(history)
                continue

            # Normal char
            line += char
            sys.stdout.write(char)
            sys.stdout.flush()
            
            # Suggestion ghost text
            sug = find_suggestion(line, history)
            if sug:
                rem = sug[len(line):]
                sys.stdout.write(f"\x1b[90m{rem}\x1b[0m")
                sys.stdout.write(f"\x1b[{len(rem)}D")
            else:
                # Clear old ghost text
                sys.stdout.write(" " * 20 + f"\x1b[20D")
            sys.stdout.flush()
                
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        try:
            p.terminate()
        except:
            pass

if __name__ == "__main__":
    main()
