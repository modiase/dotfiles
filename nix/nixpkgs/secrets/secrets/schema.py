"""Schema handling for secrets JSON wrapping."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from .crypto import (
    DEFAULT_ALGO,
    DEFAULT_KEY_ALGO,
    DEFAULT_ROUNDS,
    CryptoError,
    decrypt,
    encrypt,
    generate_salt,
)

SCHEMA_PREFIX = "modiase-secrets/v"
SCHEMA_VERSION = 2
CURRENT_SCHEMA = f"{SCHEMA_PREFIX}{SCHEMA_VERSION}"


class SchemaError(Exception):
    """Raised when schema validation fails."""


@dataclass
class SecretWrapper:
    """Wrapper for a stored secret with optional encryption metadata."""

    value: str
    schema: str = CURRENT_SCHEMA
    algo: str | None = None
    rounds: int | None = None
    key_algo: str | None = None
    salt: str | None = None

    @property
    def is_encrypted(self) -> bool:
        return self.algo is not None

    def to_json(self) -> str:
        """Serialize to JSON string."""
        return json.dumps(
            {
                "schema": self.schema,
                "value": self.value,
                "algo": self.algo,
                "rounds": self.rounds,
                "keyAlgo": self.key_algo,
                "salt": self.salt,
            }
        )

    @classmethod
    def from_json(cls, data: str) -> SecretWrapper:
        """Deserialize from JSON string."""
        try:
            obj = json.loads(data)
        except json.JSONDecodeError:
            return cls(value=data)

        if not isinstance(obj, dict):
            return cls(value=data)

        schema = obj.get("schema", "")
        if not schema.startswith(SCHEMA_PREFIX):
            return cls(value=data)

        return cls(
            value=obj.get("value", ""),
            schema=schema,
            algo=obj.get("algo"),
            rounds=obj.get("rounds"),
            key_algo=obj.get("keyAlgo"),
            salt=obj.get("salt"),
        )


def wrap_secret(value: str, encrypted: bool = False, **crypto_params: Any) -> str:
    """
    Wrap a secret value in the schema JSON format.

    Args:
        value: The secret value (plaintext or encrypted)
        encrypted: Whether the value is encrypted
        crypto_params: Encryption parameters (algo, rounds, salt, key_algo)
    """
    if encrypted:
        wrapper = SecretWrapper(
            value=value,
            algo=crypto_params.get("algo", DEFAULT_ALGO),
            rounds=crypto_params.get("rounds", DEFAULT_ROUNDS),
            key_algo=crypto_params.get("key_algo", DEFAULT_KEY_ALGO),
            salt=crypto_params.get("salt"),
        )
    else:
        wrapper = SecretWrapper(value=value)
    return wrapper.to_json()


def unwrap_secret(
    raw: str,
    passphrase: str | None = None,
    prompt_passphrase: Any | None = None,
) -> str:
    """
    Unwrap a secret from its schema JSON format.

    Args:
        raw: The raw stored value (may be JSON-wrapped or plain)
        passphrase: Passphrase for decryption (if encrypted)
        prompt_passphrase: Callable to prompt for passphrase if not provided

    Returns:
        The unwrapped (and possibly decrypted) secret value
    """
    wrapper = SecretWrapper.from_json(raw)

    if not wrapper.is_encrypted:
        return wrapper.value

    if passphrase is None and prompt_passphrase is not None:
        passphrase = prompt_passphrase()

    if passphrase is None:
        raise SchemaError("Passphrase required for encrypted secret")

    if wrapper.salt is None:
        raise SchemaError("Missing salt for encrypted secret")

    try:
        return decrypt(
            wrapper.value,
            passphrase,
            wrapper.salt,
            wrapper.rounds or DEFAULT_ROUNDS,
        )
    except CryptoError as e:
        raise SchemaError(str(e)) from e


def encrypt_and_wrap(
    value: str,
    passphrase: str,
    rounds: int = DEFAULT_ROUNDS,
) -> str:
    """Encrypt a value and wrap it in the schema JSON format."""
    salt = generate_salt()
    encrypted, _ = encrypt(value, passphrase, salt, rounds)
    return wrap_secret(
        encrypted,
        encrypted=True,
        algo=DEFAULT_ALGO,
        rounds=rounds,
        key_algo=DEFAULT_KEY_ALGO,
        salt=salt,
    )
