"""Google Cloud Secret Manager backend for secrets storage."""

from __future__ import annotations

import os
import warnings
from typing import TYPE_CHECKING

from .base import Backend, BackendError

warnings.filterwarnings(
    "ignore", message="Your application has authenticated using end user credentials"
)

if TYPE_CHECKING:
    from google.cloud import secretmanager

DEFAULT_PROJECT = "modiase-infra"


class GCPBackend(Backend):
    """Google Cloud Secret Manager backend."""

    name = "gcp"

    def __init__(self, project: str | None = None):
        self.project = project or os.environ.get(
            "GOOGLE_CLOUD_PROJECT", DEFAULT_PROJECT
        )
        self._client: secretmanager.SecretManagerServiceClient | None = None

    @property
    def client(self) -> "secretmanager.SecretManagerServiceClient":
        if self._client is None:
            try:
                from google.cloud import secretmanager

                self._client = secretmanager.SecretManagerServiceClient()
            except ImportError as e:
                raise BackendError(
                    "google-cloud-secret-manager not installed. "
                    "Install with: pip install google-cloud-secret-manager"
                ) from e
        return self._client

    def _parent(self) -> str:
        return f"projects/{self.project}"

    def _secret_path(self, name: str) -> str:
        return f"projects/{self.project}/secrets/{name}"

    def _version_path(self, name: str, version: str = "latest") -> str:
        return f"projects/{self.project}/secrets/{name}/versions/{version}"

    def get(self, name: str) -> str | None:
        try:
            response = self.client.access_secret_version(name=self._version_path(name))
            return response.payload.data.decode("utf-8")
        except Exception:
            return None

    def store(self, name: str, value: str) -> None:
        try:
            self.client.get_secret(name=self._secret_path(name))
            self.client.add_secret_version(
                parent=self._secret_path(name),
                payload={"data": value.encode("utf-8")},
            )
        except Exception:
            try:
                self.client.create_secret(
                    parent=self._parent(),
                    secret_id=name,
                    secret={"replication": {"automatic": {}}},
                )
                self.client.add_secret_version(
                    parent=self._secret_path(name),
                    payload={"data": value.encode("utf-8")},
                )
            except Exception as e:
                raise BackendError(f"Failed to store secret in GCP: {e}") from e

    def delete(self, name: str) -> bool:
        try:
            self.client.delete_secret(name=self._secret_path(name))
            return True
        except Exception:
            return False

    def list(self) -> list[str]:
        try:
            secrets = []
            for secret in self.client.list_secrets(parent=self._parent()):
                name = secret.name.split("/")[-1]
                secrets.append(name)
            return sorted(secrets)
        except Exception:
            return []
