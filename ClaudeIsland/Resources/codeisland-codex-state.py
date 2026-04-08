#!/usr/bin/env python3
"""
Vibe Island Codex CLI hook.

Normalizes official Codex hook events into the socket payload consumed by
HookSocketServer. PID is best-effort: only send it when a codex ancestor can be
found, otherwise let SessionStore reconcile by agent type and cwd.
"""

import json
import os
import socket
import subprocess
import sys

SOCKET_PATH = "/tmp/codeisland.sock"
AGENT_TYPE = "codex"
TIMEOUT_SECONDS = 300


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    state = {
        "session_id": data.get("session_id", data.get("id", "unknown")),
        "cwd": data.get("cwd", ""),
        "event": event,
        "status": normalize_status(event),
        "tty": get_tty(),
        "agent_type": AGENT_TYPE,
    }

    tool_name = data.get("tool_name")
    tool_input = data.get("tool_input", {})
    if tool_name:
        state["tool"] = tool_name
    if tool_input:
        state["tool_input"] = tool_input
    if data.get("tool_use_id"):
        state["tool_use_id"] = data.get("tool_use_id")

    agent_pid = find_agent_pid("codex")
    if agent_pid is not None:
        state["pid"] = agent_pid

    if event == "PreToolUse":
        # Codex currently supports Bash interception. Approve by exiting with
        # no output; deny by returning the documented blocking JSON shape.
        response = send_event(state, wait_for_response=True)
        if response and response.get("decision") == "deny":
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": response.get("reason") or "Denied by user via Vibe Island",
                }
            }
            print(json.dumps(output))
        sys.exit(0)

    send_event(state)


def normalize_status(event):
    mapping = {
        "UserPromptSubmit": "processing",
        "PreToolUse": "waiting_for_approval",
        "PostToolUse": "processing",
        "SessionStart": "waiting_for_input",
        "Stop": "waiting_for_input",
    }
    return mapping.get(event, "idle")


def send_event(state, wait_for_response=False):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        if wait_for_response:
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        sock.close()
    except (ConnectionRefusedError, FileNotFoundError, OSError, json.JSONDecodeError):
        return None
    return None


def get_tty():
    try:
        return os.ttyname(sys.stdin.fileno())
    except OSError:
        return None


def find_agent_pid(process_name):
    pid = os.getppid()
    for _ in range(20):
        try:
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "ppid=,command="],
                capture_output=True,
                text=True,
                timeout=1,
            )
            if result.returncode != 0:
                return None
            parts = result.stdout.strip().split(None, 1)
            if len(parts) != 2:
                return None
            ppid, command = int(parts[0]), parts[1]
            tokens = command.split()
            if any(os.path.basename(token) == process_name for token in tokens) and "app-server" not in tokens:
                return pid
            if ppid <= 1 or ppid == pid:
                return None
            pid = ppid
        except Exception:
            return None
    return None


if __name__ == "__main__":
    main()
