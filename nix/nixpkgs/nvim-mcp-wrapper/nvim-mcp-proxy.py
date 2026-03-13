"""JSON-RPC proxy for nvim-mcp with automatic Neovim socket discovery.

Intercepts connect/connect_tcp tool calls where target is empty or "auto",
resolves the Neovim socket via tmux-nvim-select, and substitutes it.
Runs a background auto-detect loop that discovers new Neovim instances
and reconnects when sockets disappear. Substitutes connection_id="auto"
with the real cached connection_id on all tool calls.

Uses asyncio for concurrency — no threads, no locks.
"""

import asyncio
import contextlib
import json
import os
import sys

from devlogs import setup_logging

log = setup_logging("nvim-mcp")


def _error_response(req_id: object, code: int, message: str) -> str:
    return json.dumps(
        {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}
    )


def _success_response(req_id: object, text: str) -> str:
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"content": [{"type": "text", "text": text}]},
        }
    )


def _extract_connection_id(result: dict) -> str | None:
    for item in result.get("content", ()):
        if item.get("type") != "text":
            continue
        with contextlib.suppress(json.JSONDecodeError, TypeError):
            data = json.loads(item["text"])
            cid = data.get("connection_id")
            if cid:
                return cid
    return None


class McpProxy:
    """Sits between mcp-clients and nvim-mcp, making Neovim connections invisible.

    AI agents shouldn't need to know which tmux pane has Neovim or what its
    socket path is. This proxy resolves that automatically so tools like
    connect(target="auto") and connection_id="auto" just work.
    """

    def __init__(self) -> None:
        self.socket: str | None = None
        self.connection_id: str | None = None
        self._auto_counter: int = 0
        self._pending_connects: dict[str, asyncio.Future[str | None]] = {}
        self._auto_ids: set[str] = set()
        self._child: asyncio.subprocess.Process | None = None

    def _next_auto_id(self) -> str:
        self._auto_counter += 1
        return f"_auto_{self._auto_counter}"

    async def _write_child(self, msg: str) -> None:
        assert self._child and self._child.stdin
        self._child.stdin.write((msg + "\n").encode())
        await self._child.stdin.drain()

    async def _write_stdout(self, msg: str) -> None:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self._write_stdout_sync, msg + "\n")

    @staticmethod
    def _write_stdout_sync(data: str) -> None:
        sys.stdout.write(data)
        sys.stdout.flush()

    async def discover_socket(self) -> str | None:
        """Find Neovim in the caller's tmux window via tmux-nvim-select."""
        with contextlib.suppress(asyncio.TimeoutError, FileNotFoundError, OSError):
            proc = await asyncio.create_subprocess_exec(
                "tmux-nvim-select",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
            if proc.returncode != 0:
                return None
            for line in stdout.decode().splitlines():
                if line.startswith("NVIM_SOCKET="):
                    return line.split("=", 1)[1]
        return None

    async def send_connect(self, socket_path: str) -> str | None:
        """Inject a connect call into nvim-mcp on behalf of the agent."""
        req_id = self._next_auto_id()
        self._auto_ids.add(req_id)
        fut: asyncio.Future[str | None] = asyncio.get_running_loop().create_future()
        self._pending_connects[req_id] = fut

        connect_msg = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "method": "tools/call",
                "params": {"name": "connect", "arguments": {"target": socket_path}},
            }
        )
        log.info("auto-connect sending id=%s socket=%s", req_id, socket_path)
        await self._write_child(connect_msg)
        self.socket = socket_path

        try:
            return await asyncio.wait_for(fut, timeout=5.0)
        except asyncio.TimeoutError:
            log.warning("auto-connect timed out id=%s", req_id)
            self._pending_connects.pop(req_id, None)
            return None

    def _resolve_pending_connect(self, msg_id: str, msg: dict) -> None:
        fut = self._pending_connects.pop(msg_id)
        error = msg.get("error")

        if error:
            log.warning("connect error id=%s: %s", msg_id, error.get("message", ""))
            if not fut.done():
                fut.set_result(None)
            return

        cid = _extract_connection_id(msg.get("result", {}))
        if cid:
            self.connection_id = cid
            log.info("connect response id=%s connection_id=%s", msg_id, cid)
        if not fut.done():
            fut.set_result(cid)

    def _is_filtered(self, msg_id: object) -> bool:
        if msg_id is None or msg_id not in self._auto_ids:
            return False
        self._auto_ids.discard(msg_id)
        return True

    async def relay_stdout(self) -> None:
        """Forward nvim-mcp responses, filtering out proxy-initiated ones."""
        assert self._child and self._child.stdout
        with contextlib.suppress(asyncio.CancelledError, OSError):
            async for raw in self._child.stdout:
                line = raw.decode().rstrip("\n")
                if not line:
                    continue

                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    await self._write_stdout(line)
                    continue

                msg_id = msg.get("id")

                if msg_id is not None and msg_id in self._pending_connects:
                    self._resolve_pending_connect(msg_id, msg)
                    if self._is_filtered(msg_id):
                        continue

                if self._is_filtered(msg_id):
                    continue

                await self._write_stdout(line)

    async def relay_stderr(self) -> None:
        assert self._child and self._child.stderr
        with contextlib.suppress(asyncio.CancelledError, OSError):
            async for raw in self._child.stderr:
                log.debug(raw.decode().rstrip("\n"))

    async def auto_detect_loop(self) -> None:
        """Periodically check socket health and reconnect if Neovim restarts."""
        try:
            while True:
                await asyncio.sleep(3)
                await self._health_check_and_reconnect()
        except asyncio.CancelledError:
            pass
        except Exception:
            log.exception("auto-detect loop crashed")

    async def _health_check_and_reconnect(self) -> None:
        if self.socket and os.path.exists(self.socket):
            log.debug("socket healthy socket=%s", self.socket)
            return

        if self.socket:
            log.info("socket gone socket=%s", self.socket)
            self.socket = None
            self.connection_id = None

        discovered = await self.discover_socket()
        if not discovered:
            log.debug("no socket found")
            return

        log.info("discovered socket=%s", discovered)
        await self.send_connect(discovered)

    def _register_pending(self, req_id: object) -> None:
        fut: asyncio.Future[str | None] = asyncio.get_running_loop().create_future()
        self._pending_connects[str(req_id)] = fut

    async def _handle_auto_connect(self, msg: dict, req_id: object) -> None:
        if self.socket and os.path.exists(self.socket) and self.connection_id:
            log.info("connect no-op, already connected socket=%s", self.socket)
            await self._write_stdout(
                _success_response(
                    req_id,
                    json.dumps(
                        {
                            "connection_id": self.connection_id,
                            "message": f"Already connected to {self.socket}",
                        }
                    ),
                )
            )
            return

        resolved = await self.discover_socket()
        if not resolved:
            log.error("connect failed, no nvim")
            await self._write_stdout(
                _error_response(
                    req_id,
                    -32000,
                    "No Neovim instance found. Start Neovim in a tmux pane and try again.",
                )
            )
            return

        log.info("connect resolved socket=%s", resolved)
        msg["params"]["arguments"]["target"] = resolved
        self._register_pending(req_id)
        self.socket = resolved
        await self._write_child(json.dumps(msg))

    async def _ensure_connected(self) -> None:
        if self.connection_id:
            return
        resolved = await self.discover_socket()
        if not resolved:
            return
        log.info("pre-call auto-connect socket=%s", resolved)
        await self.send_connect(resolved)

    async def handle_message(self, msg: dict) -> None:
        """Route an incoming JSON-RPC message, rewriting auto-connect targets."""
        params = msg.get("params", {})
        req_id = msg.get("id")

        if msg.get("method") != "tools/call":
            await self._write_child(json.dumps(msg))
            return

        tool_name = params.get("name", "")

        if tool_name in ("connect", "connect_tcp"):
            target = params.get("arguments", {}).get("target", "")
            if not target or target == "auto":
                await self._handle_auto_connect(msg, req_id)
                return
            self._register_pending(req_id)
            await self._write_child(json.dumps(msg))
            return

        await self._ensure_connected()

        args = params.get("arguments", {})
        if "connection_id" in args and self.connection_id:
            args["connection_id"] = self.connection_id

        await self._write_child(json.dumps(msg))

    async def relay_stdin(self) -> None:
        """Read JSON-RPC from the agent (stdin) and dispatch via handle_message."""
        loop = asyncio.get_running_loop()
        while True:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                break
            line = line.strip()
            if not line:
                continue

            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                await self._write_child(line)
                continue

            await self.handle_message(msg)

    async def run(self) -> None:
        """Launch nvim-mcp and bridge stdin/stdout until the agent disconnects."""
        socket_path = await self.discover_socket()
        cmd = ["nvim-mcp"] + sys.argv[1:]
        if socket_path:
            cmd = ["nvim-mcp", "--connect", socket_path] + sys.argv[1:]
            self.socket = socket_path
            log.info("socket discovered socket=%s", socket_path)
        else:
            log.info("no socket discovered")

        self._child = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        tasks = [
            asyncio.create_task(self.relay_stdout()),
            asyncio.create_task(self.relay_stderr()),
            asyncio.create_task(self.auto_detect_loop()),
        ]

        with contextlib.suppress(KeyboardInterrupt, EOFError):
            await self.relay_stdin()

        for t in tasks:
            t.cancel()
        self._child.terminate()
        try:
            await asyncio.wait_for(self._child.wait(), timeout=5)
        except asyncio.TimeoutError:
            self._child.kill()
            await self._child.wait()
        await asyncio.gather(*tasks, return_exceptions=True)
        sys.exit(self._child.returncode or 0)


if __name__ == "__main__":
    asyncio.run(McpProxy().run())
