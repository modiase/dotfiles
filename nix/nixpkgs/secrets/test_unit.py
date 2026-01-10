"""Unit tests for secrets modules."""

from pathlib import Path

import pytest

from secrets.backends.sqlite import SQLiteBackend
from secrets.crypto import (
    CryptoError,
    MasterKey,
    decrypt,
    encrypt,
    generate_salt,
)
from secrets.history import History
from secrets.schema import (
    CURRENT_SCHEMA,
    SchemaError,
    SecretWrapper,
    encrypt_and_wrap,
    unwrap_secret,
    wrap_secret,
)


class TestCrypto:
    """Test cryptographic operations."""

    def test_generate_salt_is_32_hex_chars(self) -> None:
        salt = generate_salt()
        assert len(salt) == 32
        int(salt, 16)

    def test_generate_salt_is_random(self) -> None:
        salts = [generate_salt() for _ in range(100)]
        assert len(set(salts)) == 100

    def test_encrypt_decrypt_roundtrip(self) -> None:
        value = "test-secret-value"
        passphrase = "test-passphrase"

        encrypted, salt = encrypt(value, passphrase)
        decrypted = decrypt(encrypted, passphrase, salt)

        assert decrypted == value

    def test_encrypt_produces_different_output_each_time(self) -> None:
        value = "same-value"
        passphrase = "same-passphrase"

        encrypted1, salt1 = encrypt(value, passphrase)
        encrypted2, salt2 = encrypt(value, passphrase)

        assert encrypted1 != encrypted2
        assert salt1 != salt2

    def test_decrypt_wrong_passphrase_fails(self) -> None:
        value = "secret"
        encrypted, salt = encrypt(value, "correct")

        with pytest.raises(CryptoError):
            decrypt(encrypted, "wrong", salt)

    def test_decrypt_wrong_salt_fails(self) -> None:
        value = "secret"
        encrypted, _ = encrypt(value, "passphrase")
        wrong_salt = generate_salt()

        with pytest.raises(CryptoError):
            decrypt(encrypted, "passphrase", wrong_salt)

    def test_encrypt_with_custom_salt(self) -> None:
        value = "test"
        passphrase = "pass"
        custom_salt = generate_salt()

        encrypted, returned_salt = encrypt(value, passphrase, salt=custom_salt)

        assert returned_salt == custom_salt
        assert decrypt(encrypted, passphrase, custom_salt) == value


class TestMasterKey:
    """Test master key operations."""

    def test_master_key_is_created_on_first_access(self, tmp_path: Path) -> None:
        mk = MasterKey(tmp_path)

        assert not mk.key_file.exists()
        key = mk.get()
        assert mk.key_file.exists()
        assert len(key) > 0

    def test_master_key_is_consistent(self, tmp_path: Path) -> None:
        mk = MasterKey(tmp_path)

        key1 = mk.get()
        key2 = mk.get()

        assert key1 == key2

    def test_master_key_encrypt_decrypt_roundtrip(self, tmp_path: Path) -> None:
        mk = MasterKey(tmp_path)
        value = "secret-backup-data"

        encrypted = mk.encrypt(value)
        decrypted = mk.decrypt(encrypted)

        assert decrypted == value

    def test_master_key_file_has_restricted_permissions(self, tmp_path: Path) -> None:
        mk = MasterKey(tmp_path)
        mk.ensure_exists()

        mode = mk.key_file.stat().st_mode & 0o777
        assert mode == 0o600


class TestSecretWrapper:
    """Test secret wrapper serialization."""

    def test_to_json_includes_all_fields(self) -> None:
        wrapper = SecretWrapper(
            value="test",
            algo="aes-256-cbc",
            rounds=100000,
            key_algo="pbkdf2",
            salt="abc123",
        )

        json_str = wrapper.to_json()

        assert '"value": "test"' in json_str
        assert '"algo": "aes-256-cbc"' in json_str
        assert '"rounds": 100000' in json_str
        assert '"keyAlgo": "pbkdf2"' in json_str
        assert '"salt": "abc123"' in json_str

    def test_from_json_parses_wrapped_secret(self) -> None:
        json_str = '{"schema":"modiase-secrets/v2","value":"test","algo":"aes-256-cbc","rounds":100000,"keyAlgo":"pbkdf2","salt":"abc"}'

        wrapper = SecretWrapper.from_json(json_str)

        assert wrapper.value == "test"
        assert wrapper.algo == "aes-256-cbc"
        assert wrapper.rounds == 100000
        assert wrapper.key_algo == "pbkdf2"
        assert wrapper.salt == "abc"

    def test_from_json_with_plain_string_returns_wrapper(self) -> None:
        wrapper = SecretWrapper.from_json("plain-value")

        assert wrapper.value == "plain-value"
        assert wrapper.is_encrypted is False

    def test_is_encrypted_when_algo_set(self) -> None:
        encrypted = SecretWrapper(value="x", algo="aes-256-cbc")
        plain = SecretWrapper(value="x")

        assert encrypted.is_encrypted is True
        assert plain.is_encrypted is False


class TestSchema:
    """Test schema wrapping/unwrapping functions."""

    def test_wrap_secret_plain(self) -> None:
        wrapped = wrap_secret("test-value")
        wrapper = SecretWrapper.from_json(wrapped)

        assert wrapper.value == "test-value"
        assert wrapper.schema == CURRENT_SCHEMA
        assert wrapper.is_encrypted is False

    def test_wrap_secret_encrypted(self) -> None:
        wrapped = wrap_secret(
            "encrypted-data",
            encrypted=True,
            algo="aes-256-cbc",
            rounds=50000,
            key_algo="pbkdf2",
            salt="deadbeef",
        )
        wrapper = SecretWrapper.from_json(wrapped)

        assert wrapper.value == "encrypted-data"
        assert wrapper.is_encrypted is True
        assert wrapper.rounds == 50000
        assert wrapper.salt == "deadbeef"

    def test_unwrap_secret_plain(self) -> None:
        wrapped = wrap_secret("my-secret")

        result = unwrap_secret(wrapped)

        assert result == "my-secret"

    def test_unwrap_secret_encrypted_requires_passphrase(self) -> None:
        wrapped = encrypt_and_wrap("secret", "passphrase")

        with pytest.raises(SchemaError, match="Passphrase required"):
            unwrap_secret(wrapped)

    def test_encrypt_and_wrap_then_unwrap(self) -> None:
        passphrase = "test-pass"
        wrapped = encrypt_and_wrap("my-secret", passphrase)

        result = unwrap_secret(wrapped, passphrase=passphrase)

        assert result == "my-secret"

    def test_v1_backward_compatibility(self) -> None:
        v1_json = (
            '{"schema":"modiase-secrets/v1","value":"legacy","algo":null,"rounds":null}'
        )

        result = unwrap_secret(v1_json)

        assert result == "legacy"


class TestHistory:
    """Test history/event log with SQLite backend."""

    @pytest.fixture
    def history(self, tmp_path: Path) -> History:
        return History(tmp_path)

    def test_log_creates_db(self, history: History) -> None:
        history.log("get", "test-secret", "keychain")

        assert history.db_path.exists()

    def test_log_appends_entries(self, history: History) -> None:
        history.log("store", "secret1", "keychain")
        history.log("get", "secret1", "keychain")

        entries = history.entries()
        assert len(entries) == 2
        assert entries[0].operation == "store"
        assert entries[1].operation == "get"

    def test_get_last_delete_finds_most_recent(self, history: History) -> None:
        history.log("delete", "first", "keychain", backup="backup1")
        history.log("store", "other", "keychain")
        history.log("delete", "second", "keychain", backup="backup2")

        last = history.get_last_delete()

        assert last is not None
        assert last.name == "second"
        assert last.backup == "backup2"

    def test_get_last_delete_returns_none_when_empty(self, history: History) -> None:
        assert history.get_last_delete() is None

    def test_is_empty_true_for_new_history(self, history: History) -> None:
        assert history.is_empty() is True

    def test_is_empty_false_after_logging(self, history: History) -> None:
        history.log("get", "x", "y")

        assert history.is_empty() is False

    def test_entries_have_auto_incrementing_ids(self, history: History) -> None:
        history.log("store", "a", "keychain")
        history.log("get", "b", "keychain")
        history.log("delete", "c", "keychain")

        entries = history.entries()

        assert entries[0].id == 1
        assert entries[1].id == 2
        assert entries[2].id == 3

    def test_entries_in_chronological_order(self, history: History) -> None:
        history.log("store", "first", "keychain")
        history.log("get", "second", "keychain")
        history.log("delete", "third", "keychain")

        entries = history.entries()

        assert entries[0].name == "first"
        assert entries[1].name == "second"
        assert entries[2].name == "third"

    def test_get_last_delete_ignores_deletes_without_backup(
        self, history: History
    ) -> None:
        history.log("delete", "with-backup", "keychain", backup="encrypted")
        history.log("delete", "without-backup", "keychain")

        last = history.get_last_delete()

        assert last is not None
        assert last.name == "with-backup"

    def test_sqlite_schema_has_correct_columns(self, history: History) -> None:
        import sqlite3

        history.log("test", "name", "backend", backup="backup")

        with sqlite3.connect(history.db_path) as conn:
            cursor = conn.execute("PRAGMA table_info(events)")
            columns = {row[1]: row[2] for row in cursor.fetchall()}

        assert columns == {
            "id": "INTEGER",
            "timestamp": "TEXT",
            "operation": "TEXT",
            "name": "TEXT",
            "backend": "TEXT",
            "backup": "TEXT",
        }

    def test_sqlite_index_exists_for_delete_queries(self, history: History) -> None:
        import sqlite3

        with sqlite3.connect(history.db_path) as conn:
            cursor = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
                ("idx_delete_with_backup",),
            )
            assert cursor.fetchone() is not None

    def test_append_only_no_updates_occur(self, history: History) -> None:
        import sqlite3

        history.log("delete", "secret", "keychain", backup="v1")
        history.log("delete", "secret", "keychain", backup="v2")

        with sqlite3.connect(history.db_path) as conn:
            cursor = conn.execute("SELECT COUNT(*) FROM events")
            count = cursor.fetchone()[0]

        assert count == 2

    def test_entries_preserve_all_fields(self, history: History) -> None:
        history.log("delete", "my-secret", "gcp", backup="encrypted-data")

        entry = history.entries()[0]

        assert entry.operation == "delete"
        assert entry.name == "my-secret"
        assert entry.backend == "gcp"
        assert entry.backup == "encrypted-data"
        assert entry.timestamp is not None
        assert "T" in entry.timestamp

    def test_undo_twice_returns_none(self, history: History) -> None:
        history.log("delete", "secret", "keychain", backup="backup-data")

        first_undo = history.get_last_delete()
        assert first_undo is not None
        assert first_undo.name == "secret"

        history.log("undo", "secret", "keychain")

        second_undo = history.get_last_delete()
        assert second_undo is None

    def test_undo_different_secrets_independently(self, history: History) -> None:
        history.log("delete", "first", "keychain", backup="backup1")
        history.log("delete", "second", "keychain", backup="backup2")

        history.log("undo", "second", "keychain")

        last = history.get_last_delete()
        assert last is not None
        assert last.name == "first"

        history.log("undo", "first", "keychain")

        assert history.get_last_delete() is None


class TestSQLiteBackend:
    """Test SQLite backend."""

    def test_store_and_get(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")

        backend.store("test-key", "test-value")
        result = backend.get("test-key")

        assert result == "test-value"

    def test_get_nonexistent_returns_none(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")

        assert backend.get("nonexistent") is None

    def test_store_overwrites_existing(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")

        backend.store("key", "original")
        backend.store("key", "updated")

        assert backend.get("key") == "updated"

    def test_delete_existing_returns_true(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")
        backend.store("to-delete", "value")

        result = backend.delete("to-delete")

        assert result is True
        assert backend.get("to-delete") is None

    def test_delete_nonexistent_returns_false(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")

        result = backend.delete("nonexistent")

        assert result is False

    def test_list_returns_sorted_names(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")
        backend.store("charlie", "c")
        backend.store("alpha", "a")
        backend.store("bravo", "b")

        names = backend.list()

        assert names == ["alpha", "bravo", "charlie"]

    def test_list_empty_database(self, tmp_path: Path) -> None:
        backend = SQLiteBackend(tmp_path / "test.db")

        assert backend.list() == []


class TestClipboard:
    """Test clipboard module."""

    def test_is_ssh_session_detects_ssh_tty(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        from secrets.clipboard import _is_ssh_session

        monkeypatch.delenv("SSH_TTY", raising=False)
        monkeypatch.delenv("SSH_CONNECTION", raising=False)
        monkeypatch.delenv("SSH_CLIENT", raising=False)
        assert _is_ssh_session() is False

        monkeypatch.setenv("SSH_TTY", "/dev/pts/0")
        assert _is_ssh_session() is True

    def test_is_ssh_session_detects_ssh_connection(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        from secrets.clipboard import _is_ssh_session

        monkeypatch.delenv("SSH_TTY", raising=False)
        monkeypatch.delenv("SSH_CONNECTION", raising=False)
        monkeypatch.delenv("SSH_CLIENT", raising=False)

        monkeypatch.setenv("SSH_CONNECTION", "192.168.1.1 12345 192.168.1.2 22")
        assert _is_ssh_session() is True


class TestResolveSecret:
    """Test _resolve_secret logic for cross-backend resolution."""

    @pytest.fixture
    def local_backend(self, tmp_path: Path) -> SQLiteBackend:
        return SQLiteBackend(tmp_path / "local.db")

    @pytest.fixture
    def network_backend(self, tmp_path: Path) -> SQLiteBackend:
        return SQLiteBackend(tmp_path / "network.db")

    def test_default_reads_local_only(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        local_backend.store("secret", "local-value")
        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=False,
            update_local=False,
            store_local=False,
        )

        assert value == "local-value"
        assert source == "sqlite"

    def test_network_backend_reads_network(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        local_backend.store("secret", "local-value")
        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend="network",
            read_through=False,
            update_local=False,
            store_local=False,
        )

        assert value == "network-value"
        assert source == "network"

    def test_read_through_prefers_local(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        local_backend.store("secret", "local-value")
        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=True,
            update_local=False,
            store_local=False,
        )

        assert value == "local-value"
        assert source == "sqlite"

    def test_read_through_falls_back_to_network(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=True,
            update_local=False,
            store_local=False,
        )

        assert value == "network-value"
        assert source == "network"
        assert local_backend.get("secret") is None

    def test_read_through_with_store_local(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=True,
            update_local=False,
            store_local=True,
        )

        assert value == "network-value"
        assert local_backend.get("secret") == "network-value"

    def test_network_with_store_local(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend="network",
            read_through=False,
            update_local=False,
            store_local=True,
        )

        assert value == "network-value"
        assert local_backend.get("secret") == "network-value"

    def test_update_local_syncs_from_network(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        local_backend.store("secret", "old-local")
        network_backend.store("secret", "new-network")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=False,
            update_local=True,
            store_local=False,
        )

        assert value == "new-network"
        assert source == "network"
        assert local_backend.get("secret") == "new-network"

    def test_update_local_creates_local_if_missing(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        network_backend.store("secret", "network-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=False,
            update_local=True,
            store_local=False,
        )

        assert value == "network-value"
        assert local_backend.get("secret") == "network-value"

    def test_update_local_no_change_when_equal(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        local_backend.store("secret", "same-value")
        network_backend.store("secret", "same-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=False,
            update_local=True,
            store_local=False,
        )

        assert value == "same-value"
        assert local_backend.get("secret") == "same-value"

    def test_update_local_returns_none_if_network_missing(
        self, local_backend: SQLiteBackend, network_backend: SQLiteBackend
    ) -> None:
        from secrets.cli import _resolve_secret

        local_backend.store("secret", "local-value")

        value, source = _resolve_secret(
            "secret",
            local_backend,
            network_backend,
            backend=None,
            read_through=False,
            update_local=True,
            store_local=False,
        )

        assert value is None
        assert source == "network"
