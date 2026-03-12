"""JSON-RPC proxy for nvim-mcp with dynamic Neovim socket discovery.

Intercepts connect/connect_tcp tool calls where target is empty or "auto",
resolves the Neovim socket via tmux-nvim-select, and substitutes it.
All other messages are forwarded unmodified.
"""

import json
import os
import subprocess
import sys
import threading


def build_component():
    window = os.environ.get("TARGET_WINDOW", "")
    if window:
        return f"nvim-mcp(@{window})"
    return "nvim-mcp"


COMPONENT = build_component()


def clog(logger_proc, level, msg):
    if not logger_proc:
        return
    try:
        logger_proc.stdin.write(f"[devlogs] {level.upper()} {COMPONENT}: {msg}\n")
        logger_proc.stdin.flush()
    except (BrokenPipeError, OSError):
        pass


def discover_socket():
    """Run tmux-nvim-select and return the NVIM_SOCKET path, or None."""
    try:
        result = subprocess.run(
            ["tmux-nvim-select"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.splitlines():
            if line.startswith("NVIM_SOCKET="):
                return line.split("=", 1)[1]
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return None


def error_response(req_id, code, message):
    return json.dumps(
        {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}
    )


def relay_stderr(src, logger_proc):
    """Relay child stderr lines through structured logging."""
    try:
        for line in src:
            line = line.rstrip("\n")
            if logger_proc:
                try:
                    logger_proc.stdin.write(f"[devlogs] DEBUG {COMPONENT}: {line}\n")
                    logger_proc.stdin.flush()
                except (BrokenPipeError, OSError):
                    pass
    except (BrokenPipeError, OSError):
        pass


def relay(src, dst):
    """Copy lines from src to dst until EOF."""
    try:
        for line in src:
            dst.write(line)
            dst.flush()
    except (BrokenPipeError, OSError):
        pass


def main():
    socket = discover_socket()
    cmd = ["nvim-mcp"] + sys.argv[1:]
    if socket:
        cmd = ["nvim-mcp", "--connect", socket] + sys.argv[1:]

    try:
        logger_proc = subprocess.Popen(
            ["logger", "-t", "devlogs"],
            stdin=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        logger_proc = None

    if socket:
        clog(logger_proc, "info", f"socket discovered socket={socket}")
    else:
        clog(logger_proc, "info", "no socket discovered")

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    threading.Thread(target=relay, args=(proc.stdout, sys.stdout), daemon=True).start()
    threading.Thread(
        target=relay_stderr, args=(proc.stderr, logger_proc), daemon=True
    ).start()

    try:
        for line in sys.stdin:
            if not line.strip():
                continue

            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                proc.stdin.write(line)
                proc.stdin.flush()
                continue

            if msg.get("method") == "tools/call" and msg.get("params", {}).get(
                "name"
            ) in ("connect", "connect_tcp"):
                target = msg.get("params", {}).get("arguments", {}).get("target", "")
                if not target or target == "auto":
                    resolved = discover_socket()
                    if resolved:
                        clog(
                            logger_proc,
                            "info",
                            f"auto-connect resolved socket={resolved}",
                        )
                        msg["params"]["arguments"]["target"] = resolved
                        proc.stdin.write(json.dumps(msg) + "\n")
                        proc.stdin.flush()
                    else:
                        clog(logger_proc, "error", "auto-connect failed, no nvim")
                        sys.stdout.write(
                            error_response(
                                msg.get("id"),
                                -32000,
                                "No Neovim instance found. Start Neovim in a tmux pane and try again.",
                            )
                            + "\n"
                        )
                        sys.stdout.flush()
                    continue

            proc.stdin.write(line)
            proc.stdin.flush()
    except (BrokenPipeError, OSError, KeyboardInterrupt):
        pass
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        if logger_proc:
            logger_proc.terminate()
        sys.exit(proc.returncode or 0)


if __name__ == "__main__":
    main()
