"""Abstract base class for secrets backends."""

from abc import ABC, abstractmethod


class BackendError(Exception):
    """Base exception for backend errors."""


class SecretNotFoundError(BackendError):
    """Raised when a secret is not found."""


class Backend(ABC):
    """Abstract base class for secrets storage backends."""

    name: str = "base"

    @abstractmethod
    def get(self, name: str) -> str | None:
        """Retrieve a secret by name. Returns None if not found."""

    @abstractmethod
    def store(self, name: str, value: str) -> None:
        """Store a secret. Overwrites if exists."""

    @abstractmethod
    def delete(self, name: str) -> bool:
        """Delete a secret. Returns True if deleted, False if not found."""

    @abstractmethod
    def list(self) -> list[str]:
        """List all secret names."""

    def exists(self, name: str) -> bool:
        """Check if a secret exists."""
        return self.get(name) is not None
