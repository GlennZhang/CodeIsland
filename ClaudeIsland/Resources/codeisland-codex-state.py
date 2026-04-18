#!/usr/bin/env python3
"""
Vibe Island Codex CLI hook.

Normalizes official Codex hook events into the socket payload consumed by
HookSocketServer. PID is best-effort: only send it when a codex ancestor can be
found, otherwise let SessionStore reconcile by agent type and cwd.
"""

import json
import os
import shlex
import socket
import subprocess
import sys
from typing import Optional, Tuple

SOCKET_PATH = "/tmp/codeisland.sock"
AGENT_TYPE = "codex"
NON_BLOCKING_TIMEOUT_SECONDS = 5
BLOCKING_TIMEOUT_SECONDS = 30

# ---------------------------------------------------------------------------
# Codex PreToolUse Hook Protocol
# ---------------------------------------------------------------------------
# This hook implements the Codex CLI PreToolUse hook protocol:
#
# Allow response:  Exit code 0 with no stdout. Codex continues tool execution.
# Deny response:   Exit code 0 with JSON stdout:
#                   {"hookSpecificOutput": {
#                     "hookEventName": "PreToolUse",
#                     "permissionDecision": "deny",
#                     "permissionDecisionReason": "<reason>"
#                   }}
# Timeout/disconnect: Same as deny (fail-closed).
#
# Classification inputs (from Codex hook payload):
#   - permission_mode: "default" | "acceptEdits" | "plan" | "dontAsk" | "bypassPermissions"
#   - tool_name: currently "Bash" for PreToolUse
#   - tool_input.command: the shell command about to run
#
# Classification rules:
#   Non-blocking (report-only):
#     - permission_mode opts out of approval (`dontAsk`, `bypassPermissions`)
#     - permission_mode is non-executing/planning (`plan`)
#     - permission_mode delegates edits without extra prompts (`acceptEdits`)
#     - command falls into a known activity-only bucket (read-only queries, search, test/build)
#   Blocking (approval-needed):
#     - clear mutations, process control, remote/network side effects
#     - unknown commands in approval-capable modes
# ---------------------------------------------------------------------------

READ_ONLY_PREFIXES = [
    "git diff", "git status", "git log", "git show", "git branch",
    "git rev-parse", "git config", "git remote", "git tag",
    "ls", "cat", "head", "tail", "wc",
    "find", "grep", "rg", "ag", "fd", "lsof",
    "stat", "file", "readlink", "realpath", "basename", "dirname",
    "env", "printenv", "uname", "md5", "md5sum", "shasum", "cksum",
    "echo", "pwd", "which", "type", "whoami",
    "test", "[", "[[",
    "awk", "cut", "sort", "uniq",
]

ROUTINE_EXECUTION_PREFIXES = [
    "xcodebuild", "swift test", "swift build",
    "pytest", "python -m pytest", "python3 -m pytest", "uv run pytest",
    "npm test", "npm run test", "npm run build", "npm run lint", "npm run check",
    "npm run typecheck", "npm run preview",
    "pnpm test", "pnpm run test", "pnpm run build", "pnpm run lint",
    "pnpm run check", "pnpm run typecheck", "pnpm run preview",
    "yarn test", "yarn build", "yarn lint", "yarn check", "yarn typecheck",
    "cargo test", "cargo build", "go test", "go build",
    "make test", "make build",
    "tsc", "vue-tsc", "eslint", "vitest", "vite",
    "npx vitest", "npx tsc", "npx vue-tsc", "npx eslint", "npx vite",
]

MUTATING_PREFIXES = [
    "rm", "mv", "cp", "mkdir", "rmdir", "touch", "chmod", "chown",
    "sed -i", "perl -i",
    "kill", "pkill", "killall", "launchctl", "osascript",
    "git apply", "git am", "git cherry-pick", "git rebase", "git merge",
    "git commit", "git push", "git pull",
    "scp", "ssh",
    "npm publish", "pnpm publish", "yarn publish", "cargo publish",
]

SCRIPT_EVAL_PREFIXES = {
    "python -c", "python3 -c", "node -e", "ruby -e", "perl -e",
    "perl -ne", "perl -pe",
}

APPROVAL_BYPASS_MODES = {"dontAsk", "bypassPermissions"}
NON_BLOCKING_PERMISSION_MODES = {"acceptEdits", "plan"}
SHELL_WRAPPERS = {"bash", "sh", "zsh"}

READ_ONLY_SCRIPT_MARKERS = [
    "read_text", "read_bytes", "json.load", "json.loads", "Path(",
    "open(", "print(", "pprint(", "sys.stdout", "stdout.write",
]

WRITE_SCRIPT_MARKERS = [
    ".write(", "write_text", "write_bytes", "truncate(", "unlink(",
    "remove(", "rename(", "replace(", "mkdir(", "rmdir(", "chmod(",
    "chown(", "symlink(", "link(", "touch(", "subprocess.", "os.system(",
    "Popen(", "run(", "exec(", "spawn(", "requests.post", "requests.put",
    "requests.patch", "requests.delete", "curl ", "tee(",
]


def debug_log(event: str, **fields) -> None:
    """Emit opt-in structured hook traces to stderr for local debugging."""
    if os.environ.get("CODEISLAND_DEBUG_HOOKS") != "1":
        return
    payload = {"agent": AGENT_TYPE, "event": event}
    payload.update(fields)
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)


def strip_leading_assignments(command: str) -> str:
    cmd = command.strip()
    parts = cmd.split()
    while parts and "=" in parts[0] and not parts[0].startswith((">", "<")):
        parts = parts[1:]
    return " ".join(parts)


def command_matches_prefix(command: str, prefix: str) -> bool:
    return command == prefix or command.startswith(prefix + " ")


def shell_split(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def has_write_redirection(command: str) -> bool:
    tokens = command.split()
    for token in tokens:
        if token in {">", ">>", "1>", "1>>", "2>", "2>>"}:
            return True
        if token.startswith((">", ">>", "1>", "1>>", "2>", "2>>")):
            return True
    return False


def unwrap_shell_wrapper(command: str) -> Optional[str]:
    tokens = shell_split(command)
    if len(tokens) >= 3 and tokens[0] in SHELL_WRAPPERS and tokens[1] in {"-c", "-lc"}:
        return tokens[2]
    return None


def is_mutating_sed(tokens: list[str]) -> bool:
    return any(token == "-i" or token.startswith("-i") for token in tokens[1:])


def is_read_only_sed(tokens: list[str]) -> bool:
    if not tokens or tokens[0] != "sed":
        return False
    return not is_mutating_sed(tokens)


def is_mutating_perl(tokens: list[str]) -> bool:
    return any(token == "-i" or token.startswith("-i") for token in tokens[1:])


def is_read_only_perl(tokens: list[str]) -> bool:
    if not tokens or tokens[0] != "perl":
        return False
    return not is_mutating_perl(tokens)


def is_read_only_script_eval(tokens: list[str], command: str) -> bool:
    if len(tokens) < 3:
        return False

    prefix = f"{tokens[0]} {tokens[1]}"
    if prefix not in SCRIPT_EVAL_PREFIXES:
        return False

    snippet = command.split(tokens[1], 1)[1].strip()
    if not snippet:
        return False

    lowered = snippet.lower()
    if any(marker.lower() in lowered for marker in WRITE_SCRIPT_MARKERS):
        return False

    return any(marker.lower() in lowered for marker in READ_ONLY_SCRIPT_MARKERS)


def classify_command(command: str) -> Tuple[str, str]:
    cmd = strip_leading_assignments(command)
    if not cmd:
        return ("approvalRequired", "empty_or_unparsed_command")

    wrapped = unwrap_shell_wrapper(cmd)
    if wrapped:
        policy, reason = classify_command(wrapped)
        return (policy, f"wrapped:{reason}")

    if has_write_redirection(cmd):
        return ("approvalRequired", "write_redirection")

    tokens = shell_split(cmd)
    if tokens:
        if is_read_only_sed(tokens):
            return ("activityOnly", "read_only:sed")
        if is_read_only_perl(tokens):
            return ("activityOnly", "read_only:perl")
        if is_read_only_script_eval(tokens, cmd):
            return ("activityOnly", f"read_only_script:{tokens[0]}")

    for prefix in READ_ONLY_PREFIXES:
        if command_matches_prefix(cmd, prefix):
            return ("activityOnly", f"read_only:{prefix}")

    for prefix in ROUTINE_EXECUTION_PREFIXES:
        if command_matches_prefix(cmd, prefix):
            return ("activityOnly", f"routine_execution:{prefix}")

    for prefix in MUTATING_PREFIXES:
        if command_matches_prefix(cmd, prefix):
            return ("approvalRequired", f"mutation:{prefix}")

    if " | tee " in f" {cmd} " or cmd.startswith("tee ") or " tee " in f" {cmd} ":
        return ("approvalRequired", "tee_write_like")

    if "curl " in f" {cmd} " or cmd.startswith("curl "):
        if any(flag in cmd for flag in [" -X POST", " -X PUT", " -X PATCH", " -X DELETE", " --request "]):
            return ("approvalRequired", "network_mutation")

    return ("approvalRequired", "unknown_command")


def classify_pre_tool_use(permission_mode: str, tool_name: Optional[str], command: str) -> Tuple[str, str]:
    """Return (policy, reason) for Codex PreToolUse.

    Policies:
      - activityOnly
      - approvalRequired
    """
    if permission_mode in APPROVAL_BYPASS_MODES:
        return ("activityOnly", f"permission_mode:{permission_mode}")

    if permission_mode in NON_BLOCKING_PERMISSION_MODES:
        return ("activityOnly", f"permission_mode:{permission_mode}")

    if permission_mode != "default":
        return ("approvalRequired", f"unknown_permission_mode:{permission_mode}")

    if tool_name and tool_name != "Bash":
        return ("activityOnly", f"non_bash_tool:{tool_name}")

    return classify_command(command)


def requires_approval(permission_mode: str, tool_name: Optional[str], command: str) -> bool:
    policy, _ = classify_pre_tool_use(permission_mode, tool_name, command)
    return policy == "approvalRequired"


def emit_denial(reason: str) -> None:
    """Output Codex-documented denial payload to stdout."""
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(output))


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
    permission_mode = data.get("permission_mode", "default")
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
        command = (tool_input or {}).get("command", "")
        policy, reason = classify_pre_tool_use(permission_mode, tool_name, command)
        debug_log(
            "pre_tool_use_policy",
            session_id=state["session_id"],
            permission_mode=permission_mode,
            tool_name=tool_name,
            command=command,
            policy=policy,
            reason=reason,
        )

        if policy != "approvalRequired":
            # Ordinary tool activity: report it, but do not gate execution.
            state["status"] = "processing"
            send_event(state)
            sys.exit(0)

        # Approval-required command: keep the hook open until the app resolves it.
        state["status"] = "waiting_for_approval"
        response = send_event(
            state,
            wait_for_response=True,
            timeout_seconds=BLOCKING_TIMEOUT_SECONDS,
        )
        if response and response.get("decision") == "deny":
            emit_denial(response.get("reason") or "Denied by user via CodeIsland")
        elif response is None:
            # Approval-required requests fail closed when the listener disappears.
            emit_denial("CodeIsland approval service unavailable")
        sys.exit(0)

    send_event(state)


def normalize_status(event):
    mapping = {
        "UserPromptSubmit": "processing",
        "PreToolUse": "processing",
        "PostToolUse": "processing",
        "SessionStart": "waiting_for_input",
        "Stop": "waiting_for_input",
    }
    return mapping.get(event, "idle")


def send_event(state, wait_for_response=False, timeout_seconds=NON_BLOCKING_TIMEOUT_SECONDS):
    # Quick check: if the socket file doesn't exist, the app isn't running.
    # Exit immediately to avoid blocking Codex on a 5s connect timeout.
    if not os.path.exists(SOCKET_PATH):
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout_seconds)
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
