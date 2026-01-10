"""Cryptographic operations for secrets encryption/decryption."""

import base64
import os
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

DEFAULT_ALGO = "aes-256-cbc"
DEFAULT_ROUNDS = 100000
DEFAULT_KEY_ALGO = "pbkdf2"


class CryptoError(Exception):
    """Base exception for cryptographic errors."""


def generate_salt() -> str:
    """Generate a 16-byte random salt as hex string."""
    return os.urandom(16).hex()


def _derive_key(passphrase: str, salt: bytes, rounds: int = DEFAULT_ROUNDS) -> bytes:
    """Derive a 32-byte key from passphrase using PBKDF2."""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=rounds,
    )
    return kdf.derive(passphrase.encode())


def _pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    """Apply PKCS7 padding."""
    padding_len = block_size - (len(data) % block_size)
    return data + bytes([padding_len] * padding_len)


def _pkcs7_unpad(data: bytes) -> bytes:
    """Remove PKCS7 padding."""
    if not data:
        raise CryptoError("Empty data")
    padding_len = data[-1]
    if padding_len > len(data) or padding_len == 0:
        raise CryptoError("Invalid padding")
    if data[-padding_len:] != bytes([padding_len] * padding_len):
        raise CryptoError("Invalid padding")
    return data[:-padding_len]


def encrypt(
    value: str,
    passphrase: str,
    salt: str | None = None,
    rounds: int = DEFAULT_ROUNDS,
) -> tuple[str, str]:
    """
    Encrypt a value with AES-256-CBC.

    Returns:
        Tuple of (encrypted_base64, salt_hex)
    """
    if salt is None:
        salt = generate_salt()

    salt_bytes = bytes.fromhex(salt)
    key = _derive_key(passphrase, salt_bytes, rounds)

    iv = os.urandom(16)
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()

    padded = _pkcs7_pad(value.encode())
    ciphertext = encryptor.update(padded) + encryptor.finalize()

    encrypted = base64.b64encode(iv + ciphertext).decode()
    return encrypted, salt


def decrypt(
    encrypted: str,
    passphrase: str,
    salt: str,
    rounds: int = DEFAULT_ROUNDS,
) -> str:
    """
    Decrypt a value encrypted with AES-256-CBC.

    Raises:
        CryptoError: If decryption fails (wrong passphrase or corrupted data)
    """
    try:
        data = base64.b64decode(encrypted)
        if len(data) < 32:
            raise CryptoError("Data too short")

        iv = data[:16]
        ciphertext = data[16:]

        salt_bytes = bytes.fromhex(salt)
        key = _derive_key(passphrase, salt_bytes, rounds)

        cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
        decryptor = cipher.decryptor()

        padded = decryptor.update(ciphertext) + decryptor.finalize()
        return _pkcs7_unpad(padded).decode()
    except CryptoError:
        raise
    except Exception as e:
        raise CryptoError(str(e)) from e


class MasterKey:
    """Manages the master key for encrypting delete backups."""

    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.key_file = data_dir / "master-key"

    def ensure_exists(self) -> None:
        """Ensure the master key file exists, creating if necessary."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        if not self.key_file.exists():
            key = base64.b64encode(os.urandom(32)).decode()
            self.key_file.write_text(key)
            self.key_file.chmod(0o600)

    def get(self) -> str:
        """Get the master key."""
        self.ensure_exists()
        return self.key_file.read_text().strip()

    def encrypt(self, value: str) -> str:
        """Encrypt a value with the master key (for backup storage)."""
        key = self.get()
        salt = generate_salt()
        encrypted, _ = encrypt(value, key, salt)
        return f"{salt}:{encrypted}"

    def decrypt(self, encrypted: str) -> str:
        """Decrypt a value encrypted with the master key."""
        key = self.get()
        if ":" in encrypted:
            salt, data = encrypted.split(":", 1)
            return decrypt(data, key, salt)
        else:
            raise CryptoError("Invalid encrypted backup format")
