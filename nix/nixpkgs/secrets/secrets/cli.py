"""Command-line interface for secrets management."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import click
from rich.console import Console
from rich.prompt import Confirm, Prompt
from rich.table import Table

from .backends import Backend, GCPBackend, KeychainBackend, PassBackend, SQLiteBackend
from .clipboard import copy_to_clipboard
from .crypto import DEFAULT_ROUNDS, MasterKey
from .history import History
from .schema import SchemaError, encrypt_and_wrap, unwrap_secret, wrap_secret

console = Console()
error_console = Console(stderr=True)

DEFAULT_DATA_DIR = Path.home() / ".secretslib"
PREFIX = "secrets"


def get_data_dir(ctx: click.Context) -> Path:
    return ctx.obj.get("data_dir", DEFAULT_DATA_DIR)


def get_backend(ctx: click.Context) -> Backend:
    backend_type = ctx.obj.get("backend", "local")
    sqlite_db = ctx.obj.get("sqlite_db")

    if sqlite_db:
        return SQLiteBackend(sqlite_db)

    if backend_type == "network":
        project = ctx.obj.get("project", "modiase-infra")
        return GCPBackend(project)

    if sys.platform == "darwin":
        return KeychainBackend()
    return PassBackend()


def prompt_passphrase(prompt_text: str = "Enter passphrase") -> str:
    """Prompt for a passphrase using rich."""
    return Prompt.ask(f"[cyan]{prompt_text}[/cyan]", password=True)


def _get_local_backend(ctx: click.Context) -> Backend:
    """Get the local backend (SQLite for testing, Keychain/Pass for real use)."""
    sqlite_db = ctx.obj.get("sqlite_db")
    if sqlite_db:
        return SQLiteBackend(sqlite_db)
    if sys.platform == "darwin":
        return KeychainBackend()
    return PassBackend()


def _resolve_secret(
    name: str,
    local_backend: Backend,
    network_backend: Backend,
    backend: str | None,
    read_through: bool,
    update_local: bool,
    store_local: bool,
) -> tuple[str | None, str]:
    """Resolve a secret from the appropriate backend(s)."""
    if update_local:
        network_value = network_backend.get(name)
        if network_value is None:
            return None, "network"
        local_value = local_backend.get(name)
        if local_value != network_value:
            local_backend.store(name, network_value)
        return network_value, "network"

    if read_through:
        local_value = local_backend.get(name)
        if local_value is not None:
            return local_value, local_backend.name
        network_value = network_backend.get(name)
        if network_value is not None and store_local:
            local_backend.store(name, network_value)
        return network_value, "network"

    if backend == "network":
        network_value = network_backend.get(name)
        if network_value is not None and store_local:
            local_backend.store(name, network_value)
        return network_value, "network"

    return local_backend.get(name), local_backend.name


@click.group()
@click.option(
    "--data-dir", type=click.Path(path_type=Path), help="Secretslib directory"
)
@click.option(
    "--sqlite",
    "sqlite_db",
    type=click.Path(path_type=Path),
    help="SQLite database path",
)
@click.option("--debug", is_flag=True, help="Enable debug output")
@click.option("--force", is_flag=True, help="Skip confirmations")
@click.option("--passphrase", help="Passphrase for encryption (non-interactive)")
@click.pass_context
def cli(
    ctx: click.Context,
    data_dir: Path | None,
    sqlite_db: Path | None,
    debug: bool,
    force: bool,
    passphrase: str | None,
) -> None:
    """Secrets management with multiple backends and encryption support."""
    ctx.ensure_object(dict)
    ctx.obj["data_dir"] = data_dir or DEFAULT_DATA_DIR
    ctx.obj["sqlite_db"] = sqlite_db
    ctx.obj["debug"] = debug
    ctx.obj["force"] = force
    ctx.obj["passphrase"] = passphrase
    ctx.obj["backend"] = "sqlite" if sqlite_db else "local"


@cli.command()
@click.argument("name", required=False)
@click.option("--local", "backend", flag_value="local", help="Use local backend")
@click.option(
    "--network", "backend", flag_value="network", help="Use GCP Secret Manager"
)
@click.option(
    "--read-through", is_flag=True, help="Check local first, fall back to network"
)
@click.option(
    "--store-local", is_flag=True, help="Store network secret locally after reading"
)
@click.option(
    "--update-local", is_flag=True, help="Sync network secret to local if different"
)
@click.option("--print", "force_print", is_flag=True, help="Force print to stdout")
@click.option("--raw", is_flag=True, help="Return raw JSON wrapper")
@click.option("--no-env", is_flag=True, help="Skip environment variable check")
@click.option("--optional", is_flag=True, help="Don't error if not found")
@click.option("--pass", "passphrase", help="Passphrase for decryption")
@click.option("--project", default="modiase-infra", help="GCP project")
@click.pass_context
def get(
    ctx: click.Context,
    name: str | None,
    backend: str | None,
    read_through: bool,
    store_local: bool,
    update_local: bool,
    force_print: bool,
    raw: bool,
    no_env: bool,
    optional: bool,
    passphrase: str | None,
    project: str,
) -> None:
    """Retrieve a secret."""
    if store_local and not (backend == "network" or read_through or update_local):
        error_console.print(
            "[red]Error: --store-local requires --network, --read-through, or --update-local[/red]"
        )
        raise SystemExit(1)

    if update_local and backend == "local":
        error_console.print(
            "[red]Error: --update-local cannot be used with --local[/red]"
        )
        raise SystemExit(1)

    if update_local and read_through:
        error_console.print(
            "[red]Error: --update-local and --read-through are mutually exclusive[/red]"
        )
        raise SystemExit(1)

    ctx.obj["project"] = project
    data_dir = get_data_dir(ctx)
    history = History(data_dir)

    if not no_env and name:
        env_val = os.environ.get(name)
        if env_val:
            click.echo(env_val)
            return

    local_backend = _get_local_backend(ctx)
    network_backend = GCPBackend(project)

    if not name:
        if backend == "network":
            secrets = network_backend.list()
        elif read_through or update_local:
            secrets = sorted(set(local_backend.list()) | set(network_backend.list()))
        else:
            secrets = local_backend.list()
        if not secrets:
            error_console.print("[red]No secrets found[/red]")
            raise SystemExit(1)
        name = Prompt.ask("Select secret", choices=secrets)

    value, source_backend = _resolve_secret(
        name,
        local_backend,
        network_backend,
        backend=backend,
        read_through=read_through,
        update_local=update_local,
        store_local=store_local,
    )

    if value is None:
        if optional:
            return
        error_console.print(f"[red]Error: {name} not found[/red]")
        raise SystemExit(1)

    history.log("get", name, source_backend)

    if raw:
        output = value
    else:
        key = passphrase or ctx.obj.get("passphrase")
        try:
            output = unwrap_secret(
                value,
                passphrase=key,
                prompt_passphrase=lambda: prompt_passphrase(
                    "Enter decryption passphrase"
                ),
            )
        except SchemaError as e:
            error_console.print(f"[red]Error: {e}[/red]")
            raise SystemExit(1)

    if force_print or not sys.stdout.isatty():
        click.echo(output)
    else:
        copy_to_clipboard(output)
        error_console.print(f"[green]Copied {name} to clipboard[/green]")


@cli.command()
@click.argument("name")
@click.argument("value", required=False)
@click.option("--local", "backend", flag_value="local", help="Use local backend")
@click.option(
    "--network", "backend", flag_value="network", help="Use GCP Secret Manager"
)
@click.option("--pass", "encrypt", is_flag=True, help="Encrypt with passphrase")
@click.option("--algo", default="aes-256-cbc", help="Encryption algorithm")
@click.option("--rounds", default=DEFAULT_ROUNDS, type=int, help="PBKDF2 iterations")
@click.option("--project", default="modiase-infra", help="GCP project")
@click.pass_context
def store(
    ctx: click.Context,
    name: str,
    value: str | None,
    backend: str | None,
    encrypt: bool,
    algo: str,
    rounds: int,
    project: str,
) -> None:
    """Store a secret."""
    if backend:
        ctx.obj["backend"] = backend
    ctx.obj["project"] = project

    data_dir = get_data_dir(ctx)
    history = History(data_dir)
    force = ctx.obj.get("force", False)

    backend_obj = get_backend(ctx)

    if value is None:
        passphrase = ctx.obj.get("passphrase")
        if passphrase:
            error_console.print("[red]Error: No value provided[/red]")
            raise SystemExit(1)
        value = Prompt.ask(f"[cyan]Enter secret value for {name}[/cyan]", password=True)
        if not value:
            error_console.print("[red]Error: No value provided[/red]")
            raise SystemExit(1)

    existing = backend_obj.get(name)
    if existing is not None and not force:
        if not sys.stdin.isatty():
            error_console.print(
                f"[red]Error: Secret '{name}' already exists (use --force to overwrite)[/red]"
            )
            raise SystemExit(1)
        if not Confirm.ask(
            f"[yellow]Secret '{name}' already exists. Overwrite?[/yellow]"
        ):
            error_console.print("[yellow]Cancelled[/yellow]")
            raise SystemExit(1)

    if encrypt:
        passphrase = ctx.obj.get("passphrase")
        if passphrase is None:
            passphrase = prompt_passphrase("Enter encryption passphrase")
            confirm = prompt_passphrase("Confirm passphrase")
            if passphrase != confirm:
                error_console.print("[red]Error: Passphrases do not match[/red]")
                raise SystemExit(1)

        wrapped = encrypt_and_wrap(value, passphrase, rounds)
    else:
        wrapped = wrap_secret(value)

    backend_obj.store(name, wrapped)
    history.log("store", name, backend_obj.name)
    error_console.print(f"[green]Stored {name}[/green]")


@cli.command()
@click.argument("name")
@click.option("--local", "backend", flag_value="local", help="Use local backend")
@click.option(
    "--network", "backend", flag_value="network", help="Use GCP Secret Manager"
)
@click.option("--project", default="modiase-infra", help="GCP project")
@click.pass_context
def delete(
    ctx: click.Context,
    name: str,
    backend: str | None,
    project: str,
) -> None:
    """Delete a secret."""
    if name == "undo":
        _undo(ctx)
        return

    if backend:
        ctx.obj["backend"] = backend
    ctx.obj["project"] = project

    data_dir = get_data_dir(ctx)
    history = History(data_dir)
    master_key = MasterKey(data_dir)
    force = ctx.obj.get("force", False)

    backend_obj = get_backend(ctx)

    if not force:
        if not Confirm.ask(
            f"[yellow]Delete secret '{name}' from {backend_obj.name}?[/yellow]"
        ):
            error_console.print("[yellow]Cancelled[/yellow]")
            raise SystemExit(1)

    current = backend_obj.get(name)
    backup = master_key.encrypt(current) if current else None

    if not backend_obj.delete(name):
        error_console.print(f"[red]Error: {name} not found[/red]")
        raise SystemExit(1)

    history.log("delete", name, backend_obj.name, backup)
    error_console.print(f"[green]Deleted {name}[/green]")


def _undo(ctx: click.Context) -> None:
    """Restore the last deleted secret."""
    data_dir = get_data_dir(ctx)
    history = History(data_dir)
    master_key = MasterKey(data_dir)

    last_delete = history.get_last_delete()
    if not last_delete:
        error_console.print("[red]Error: No delete operations to undo[/red]")
        raise SystemExit(1)

    if not last_delete.backup:
        error_console.print("[red]Error: No backup available for last delete[/red]")
        raise SystemExit(1)

    restored = master_key.decrypt(last_delete.backup)

    ctx.obj["backend"] = last_delete.backend
    backend_obj = get_backend(ctx)
    backend_obj.store(last_delete.name, restored)

    history.log("undo", last_delete.name, last_delete.backend)
    error_console.print(f"[green]Restored {last_delete.name} from backup[/green]")


@cli.command("list")
@click.option("--local", "backend", flag_value="local", help="Use local backend")
@click.option(
    "--network", "backend", flag_value="network", help="Use GCP Secret Manager"
)
@click.option("--all", "list_all", is_flag=True, help="List from local and network")
@click.option("--project", default="modiase-infra", help="GCP project")
@click.pass_context
def list_secrets(
    ctx: click.Context,
    backend: str | None,
    list_all: bool,
    project: str,
) -> None:
    """List available secrets."""
    if backend:
        ctx.obj["backend"] = backend
    ctx.obj["project"] = project

    data_dir = get_data_dir(ctx)
    history = History(data_dir)

    backend_obj = get_backend(ctx)
    secrets = backend_obj.list()

    if list_all and ctx.obj["backend"] == "local":
        gcp = GCPBackend(project)
        secrets = sorted(set(secrets) | set(gcp.list()))

    history.log("list", "-", backend_obj.name)

    for name in secrets:
        click.echo(name)


@cli.command()
@click.pass_context
def log(ctx: click.Context) -> None:
    """Show operation history."""
    data_dir = get_data_dir(ctx)
    history = History(data_dir)

    if history.is_empty():
        error_console.print("[yellow]No operations logged yet[/yellow]")
        return

    table = Table(show_header=True, header_style="bold")
    table.add_column("Operation", style="cyan")
    table.add_column("Timestamp")
    table.add_column("Name")
    table.add_column("Backend")

    op_styles = {
        "get": "green",
        "list": "green",
        "store": "yellow",
        "delete": "red",
        "undo": "cyan",
    }

    for entry in history.entries():
        style = op_styles.get(entry.operation, "")
        table.add_row(
            f"[{style}]{entry.operation}[/{style}]",
            entry.timestamp,
            entry.name,
            entry.backend,
        )

    console.print(table)


def main() -> None:
    """Entry point for the secrets CLI."""
    cli()


if __name__ == "__main__":
    main()
