"""Linux pass (password-store) backend for secrets storage."""

import subprocess

from .base import Backend, BackendError

PREFIX = "secrets"


class PassBackend(Backend):
    """Linux pass-based secrets storage backend."""

    name = "pass"

    def __init__(self, prefix: str = PREFIX):
        self.prefix = prefix

    def _pass_path(self, name: str) -> str:
        return f"{self.prefix}/{name}"

    def _run_pass(
        self, *args: str, input_data: str | None = None
    ) -> tuple[int, str, str]:
        """Run the pass command and return (returncode, stdout, stderr)."""
        result = subprocess.run(
            ["pass", *args],
            input=input_data,
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr

    def get(self, name: str) -> str | None:
        path = self._pass_path(name)

        code, stdout, _ = self._run_pass("show", path)
        if code == 0:
            return stdout.rstrip("\n")

        code, stdout, _ = self._run_pass("show", name)
        if code == 0:
            return stdout.rstrip("\n")

        return None

    def store(self, name: str, value: str) -> None:
        path = self._pass_path(name)

        code, _, stderr = self._run_pass("insert", "-e", path, input_data=value)
        if code != 0:
            raise BackendError(f"Failed to store secret in pass: {stderr}")

    def delete(self, name: str) -> bool:
        path = self._pass_path(name)

        code, _, _ = self._run_pass("rm", "-f", path)
        if code == 0:
            return True

        code, _, _ = self._run_pass("rm", "-f", name)
        return code == 0

    def list(self) -> list[str]:
        code, stdout, _ = self._run_pass("ls", self.prefix)
        if code != 0:
            return []

        secrets = []
        for line in stdout.splitlines()[1:]:
            name = line.lstrip("├└─│ ").strip()
            if name:
                secrets.append(name)
        return sorted(secrets)
