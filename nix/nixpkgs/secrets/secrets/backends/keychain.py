"""macOS Keychain backend for secrets storage."""

import os
import subprocess

from .base import Backend, BackendError

PREFIX = "secrets"


class KeychainBackend(Backend):
    """macOS Keychain-based secrets storage backend."""

    name = "keychain"

    def __init__(
        self,
        service_prefix: str = PREFIX,
        account: str | None = None,
    ):
        self.service_prefix = service_prefix
        self.account = account or os.environ.get("USER", "")

    def _service_name(self, name: str) -> str:
        return f"{self.service_prefix}/{name}"

    def _run_security(self, *args: str) -> tuple[int, str, str]:
        """Run the security command and return (returncode, stdout, stderr)."""
        result = subprocess.run(
            ["security", *args],
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr

    def get(self, name: str) -> str | None:
        service = self._service_name(name)

        code, stdout, _ = self._run_security(
            "find-generic-password",
            "-w",
            "-s",
            service,
            "-a",
            self.account,
        )
        if code == 0:
            return stdout.rstrip("\n")

        code, stdout, _ = self._run_security(
            "find-generic-password",
            "-w",
            "-s",
            name,
            "-a",
            self.account,
        )
        if code == 0:
            return stdout.rstrip("\n")

        return None

    def store(self, name: str, value: str) -> None:
        service = self._service_name(name)

        self._run_security(
            "delete-generic-password",
            "-s",
            service,
            "-a",
            self.account,
        )

        code, _, stderr = self._run_security(
            "add-generic-password",
            "-s",
            service,
            "-a",
            self.account,
            "-w",
            value,
        )
        if code != 0:
            raise BackendError(f"Failed to store secret in Keychain: {stderr}")

    def delete(self, name: str) -> bool:
        service = self._service_name(name)

        code, _, _ = self._run_security(
            "delete-generic-password",
            "-s",
            service,
            "-a",
            self.account,
        )
        if code == 0:
            return True

        code, _, _ = self._run_security(
            "delete-generic-password",
            "-s",
            name,
            "-a",
            self.account,
        )
        return code == 0

    def list(self) -> list[str]:
        code, stdout, _ = self._run_security("dump-keychain")
        if code != 0:
            return []

        secrets = []
        prefix = f'"svce"<blob>="{self.service_prefix}/'
        for line in stdout.splitlines():
            if prefix in line:
                start = line.find(prefix) + len(prefix)
                end = line.find('"', start)
                if end > start:
                    secrets.append(line[start:end])
        return sorted(secrets)
