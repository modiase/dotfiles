import json
import subprocess
from pathlib import Path


def run_command(
    args: list[str],
    sqlite_db: Path | None = None,
    data_dir: Path | None = None,
    passphrase: str | None = None,
    force: bool = False,
) -> tuple[int, str, str]:
    """Run secrets command and return (exit_code, stdout, stderr)."""
    cmd = ["secrets"]

    if sqlite_db:
        cmd.extend(["--sqlite", str(sqlite_db)])
    if data_dir:
        cmd.extend(["--data-dir", str(data_dir)])
    if passphrase:
        cmd.extend(["--passphrase", passphrase])
    if force:
        cmd.append("--force")

    cmd.extend(args)

    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


class TestStoreAndGet:
    """Test basic store and get operations."""

    def test_store_and_get_plain_secret(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, _ = run_command(
            ["store", "TEST_SECRET", "my-secret-value"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "TEST_SECRET", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert stdout.strip() == "my-secret-value"

    def test_store_json_secret(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"
        json_value = '{"api_key": "abc123", "endpoint": "https://api.example.com"}'

        code, _, _ = run_command(
            ["store", "JSON_SECRET", json_value],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "JSON_SECRET", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        retrieved = json.loads(stdout.strip())
        assert retrieved["api_key"] == "abc123"
        assert retrieved["endpoint"] == "https://api.example.com"

    def test_store_overwrite_requires_force(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, _ = run_command(
            ["store", "OVERWRITE_TEST", "original-value"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0

        code, _, stderr = run_command(
            ["store", "OVERWRITE_TEST", "new-value"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 1
        assert "already exists" in stderr.lower()

        code, _, _ = run_command(
            ["store", "OVERWRITE_TEST", "new-value"],
            sqlite_db=db,
            data_dir=data_dir,
            force=True,
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "OVERWRITE_TEST", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert stdout.strip() == "new-value"

    def test_get_raw_returns_json_wrapper(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, _ = run_command(
            ["store", "RAW_TEST", "raw-value"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "RAW_TEST", "--print", "--raw"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        wrapper = json.loads(stdout.strip())
        assert wrapper["schema"] == "modiase-secrets/v2"
        assert wrapper["value"] == "raw-value"
        assert "keyAlgo" in wrapper

    def test_get_nonexistent_secret_fails(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, stderr = run_command(
            ["get", "DOES_NOT_EXIST", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 1
        assert "not found" in stderr.lower()

    def test_get_optional_nonexistent_succeeds(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, stdout, _ = run_command(
            ["get", "DOES_NOT_EXIST", "--optional", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert stdout.strip() == ""


class TestEncryptedSecrets:
    """Test encrypted secret operations."""

    def test_encrypted_secret_roundtrip(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"
        passphrase = "test-passphrase-123"

        code, _, _ = run_command(
            ["store", "ENCRYPTED_SECRET", "super-secret-data", "--key"],
            sqlite_db=db,
            data_dir=data_dir,
            passphrase=passphrase,
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "ENCRYPTED_SECRET", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
            passphrase=passphrase,
        )
        assert code == 0
        assert stdout.strip() == "super-secret-data"

    def test_encrypted_secret_wrong_passphrase(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, _ = run_command(
            ["store", "ENCRYPTED_SECRET2", "secret-data", "--key"],
            sqlite_db=db,
            data_dir=data_dir,
            passphrase="correct-passphrase",
        )
        assert code == 0

        code, _, stderr = run_command(
            ["get", "ENCRYPTED_SECRET2", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
            passphrase="wrong-passphrase",
        )
        assert code == 1
        assert "failed" in stderr.lower() or "incorrect" in stderr.lower()


class TestList:
    """Test list operations."""

    def test_list_secrets(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        for name in ["ALPHA", "BETA", "GAMMA"]:
            run_command(
                ["store", name, f"value-{name}"],
                sqlite_db=db,
                data_dir=data_dir,
            )

        code, stdout, _ = run_command(
            ["list"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        lines = stdout.strip().split("\n")
        assert "ALPHA" in lines
        assert "BETA" in lines
        assert "GAMMA" in lines

    def test_list_empty_database(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, stdout, _ = run_command(
            ["list"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert stdout.strip() == ""


class TestDelete:
    """Test delete operations."""

    def test_delete_secret(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        run_command(
            ["store", "TO_DELETE", "delete-me"],
            sqlite_db=db,
            data_dir=data_dir,
        )

        code, _, _ = run_command(
            ["delete", "TO_DELETE"],
            sqlite_db=db,
            data_dir=data_dir,
            force=True,
        )
        assert code == 0

        code, _, stderr = run_command(
            ["get", "TO_DELETE", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 1
        assert "not found" in stderr.lower()

    def test_delete_nonexistent_fails(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, stderr = run_command(
            ["delete", "NONEXISTENT"],
            sqlite_db=db,
            data_dir=data_dir,
            force=True,
        )
        assert code == 1
        assert "not found" in stderr.lower()


class TestDeleteUndo:
    """Test delete undo operations."""

    def test_delete_and_undo(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        run_command(
            ["store", "UNDO_TEST", "original-value"],
            sqlite_db=db,
            data_dir=data_dir,
        )

        run_command(
            ["delete", "UNDO_TEST"],
            sqlite_db=db,
            data_dir=data_dir,
            force=True,
        )

        code, _, stderr = run_command(
            ["delete", "undo"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert "restored" in stderr.lower()

        code, stdout, _ = run_command(
            ["get", "UNDO_TEST", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert stdout.strip() == "original-value"

    def test_undo_with_no_deletes_fails(self, tmp_path: Path) -> None:
        data_dir = tmp_path / "secretslib"

        code, _, stderr = run_command(
            ["delete", "undo"],
            data_dir=data_dir,
        )
        assert code == 1
        assert "no delete" in stderr.lower()

    def test_undo_logs_event(self, tmp_path: Path) -> None:
        """Verify undo uses event sourcing - keeps delete entry and adds undo entry."""
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        run_command(
            ["store", "EVENT_TEST", "test-value"],
            sqlite_db=db,
            data_dir=data_dir,
        )

        run_command(
            ["delete", "EVENT_TEST"],
            sqlite_db=db,
            data_dir=data_dir,
            force=True,
        )

        run_command(
            ["delete", "undo"],
            sqlite_db=db,
            data_dir=data_dir,
        )

        code, stdout, _ = run_command(
            ["log"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert "delete" in stdout
        assert "undo" in stdout
        assert "EVENT_TEST" in stdout


class TestLog:
    """Test log command."""

    def test_log_shows_operations(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        run_command(
            ["store", "LOG_TEST", "value"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        run_command(
            ["get", "LOG_TEST", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )

        code, stdout, _ = run_command(
            ["log"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert "store" in stdout
        assert "get" in stdout
        assert "LOG_TEST" in stdout

    def test_log_empty(self, tmp_path: Path) -> None:
        data_dir = tmp_path / "secretslib"

        code, _, stderr = run_command(
            ["log"],
            data_dir=data_dir,
        )
        assert code == 0
        assert "no operations" in stderr.lower()


class TestHelp:
    """Test help output."""

    def test_help_flag(self, tmp_path: Path) -> None:
        code, stdout, _ = run_command(["--help"], data_dir=tmp_path)
        assert code == 0
        assert "usage:" in stdout.lower()
        assert "sqlite" in stdout.lower()

    def test_no_args_shows_usage(self, tmp_path: Path) -> None:
        code, _, stderr = run_command([], data_dir=tmp_path)
        assert code == 1
        assert "usage:" in stderr.lower() or "usage:" in stderr.lower()


class TestSchemaV2:
    """Test v2 schema features."""

    def test_v2_encrypted_has_key_algo(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, _ = run_command(
            ["store", "ENCRYPTED_V2", "secret-data", "--key"],
            sqlite_db=db,
            data_dir=data_dir,
            passphrase="test-pass",
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "ENCRYPTED_V2", "--print", "--raw"],
            sqlite_db=db,
            data_dir=data_dir,
            passphrase="test-pass",
        )
        assert code == 0
        wrapper = json.loads(stdout.strip())
        assert wrapper["schema"] == "modiase-secrets/v2"
        assert wrapper["keyAlgo"] == "pbkdf2"
        assert wrapper["algo"] == "aes-256-cbc"
        assert wrapper["rounds"] == 100000
        assert wrapper["salt"] is not None
        assert len(wrapper["salt"]) == 32  # 16 bytes hex-encoded

    def test_v2_unencrypted_has_null_key_algo(self, tmp_path: Path) -> None:
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        code, _, _ = run_command(
            ["store", "PLAIN_V2", "plain-data"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0

        code, stdout, _ = run_command(
            ["get", "PLAIN_V2", "--print", "--raw"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        wrapper = json.loads(stdout.strip())
        assert wrapper["schema"] == "modiase-secrets/v2"
        assert wrapper["keyAlgo"] is None
        assert wrapper["algo"] is None

    def test_v1_backward_compatibility(self, tmp_path: Path) -> None:
        """Test that v1 secrets without keyAlgo can still be read."""
        db = tmp_path / "secrets.db"
        data_dir = tmp_path / "secretslib"

        # Manually insert a v1-style secret directly into sqlite
        import sqlite3

        db.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(db))
        conn.execute(
            "CREATE TABLE IF NOT EXISTS secrets (name TEXT PRIMARY KEY, value TEXT NOT NULL)"
        )
        v1_secret = '{"schema":"modiase-secrets/v1","value":"legacy-value","algo":null,"rounds":null}'
        conn.execute(
            "INSERT INTO secrets (name, value) VALUES (?, ?)", ("V1_SECRET", v1_secret)
        )
        conn.commit()
        conn.close()

        code, stdout, _ = run_command(
            ["get", "V1_SECRET", "--print"],
            sqlite_db=db,
            data_dir=data_dir,
        )
        assert code == 0
        assert stdout.strip() == "legacy-value"
