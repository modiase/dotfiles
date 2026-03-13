#!/usr/bin/env python3
"""Security scanner CLI - scan products for vulnerabilities and send alerts."""

import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path

import click
from loguru import logger

from .notifiers import EmailNotifier, GmailNotifier, NtfyNotifier, NtfyOptions
from .scanner import (
    CVE,
    scan_products,
)
from .utils import (
    configure_logging,
    get_last_check_date,
    load_products,
    load_seen_cves,
    save_last_check_date,
    save_seen_cve,
)


@click.group()
@click.version_option(version="1.0.0")
def cli():
    """Security scanner - scan products for vulnerabilities via NVD API."""
    pass


@cli.command()
@click.option(
    "--products",
    "-p",
    multiple=True,
    help="Products to scan (can be specified multiple times)",
)
@click.option(
    "--products-file",
    "-f",
    type=click.Path(exists=True, path_type=Path),
    help="File with products (one per line or Nix list format)",
)
@click.option(
    "--state-dir",
    type=click.Path(path_type=Path),
    envvar="CVE_STATE_DIR",
    default="/var/lib/security-scan",
    help="State directory for tracking seen CVEs",
)
@click.option(
    "--api-key",
    envvar="NVD_API_KEY",
    help="NVD API key for higher rate limits",
)
@click.option(
    "--cvss-threshold",
    type=float,
    default=9.0,
    help="Minimum CVSS score to report",
)
@click.option(
    "--since-days",
    type=int,
    default=7,
    help="Check CVEs from N days ago (if no state file)",
)
@click.option(
    "--dry-run",
    "-n",
    is_flag=True,
    help="Don't update state files",
)
@click.option(
    "--output",
    "-o",
    type=click.Choice(["json", "text"]),
    default="text",
    help="Output format",
)
@click.option(
    "--refresh",
    is_flag=True,
    help="Ignore not-found cache and re-query all products",
)
@click.option(
    "--debug",
    "-d",
    is_flag=True,
    help="Enable debug logging",
)
def scan(
    products: tuple[str, ...],
    products_file: Path | None,
    state_dir: Path,
    api_key: str | None,
    cvss_threshold: float,
    since_days: int,
    dry_run: bool,
    output: str,
    refresh: bool,
    debug: bool,
):
    """Scan products for CVEs via NVD API."""
    configure_logging(debug)

    all_products = list(products)
    if products_file:
        all_products.extend(load_products(products_file))

    if not all_products:
        logger.error("No products specified. Use -p or -f options.")
        sys.exit(1)

    state_dir.mkdir(parents=True, exist_ok=True)
    last_check = get_last_check_date(state_dir, since_days)
    seen_cves = load_seen_cves(state_dir)

    logger.info(f"Scanning {len(all_products)} products since {last_check}")

    cves = asyncio.run(
        scan_products(
            tuple(all_products),
            last_check=last_check,
            api_key=api_key,
            cvss_threshold=cvss_threshold,
            state_dir=state_dir,
            refresh_cache=refresh,
        )
    )

    new_cves = [c for c in cves if c.id not in seen_cves]

    if not dry_run:
        for cve in new_cves:
            save_seen_cve(state_dir, cve.id)
        save_last_check_date(state_dir)

    if output == "json":
        result = [
            {
                "id": c.id,
                "score": c.score,
                "product": c.product,
                "description": c.description,
            }
            for c in new_cves
        ]
        click.echo(json.dumps(result))
    else:
        if new_cves:
            for c in new_cves:
                logger.warning(f"NEW: {c.id} (CVSS {c.score}) - {c.product}")
        else:
            logger.info("No new critical CVEs found")

    logger.info(f"Scan complete. Found {len(new_cves)} new critical CVEs.")


@cli.command()
@click.option(
    "--backend",
    "-b",
    type=click.Choice(["ntfy", "email", "gmail"]),
    required=True,
    help="Notification backend",
)
@click.option(
    "--input",
    "-i",
    "input_file",
    type=click.File("r"),
    default="-",
    help="CVE data as JSON, or raw HTML with --raw",
)
@click.option(
    "--raw",
    is_flag=True,
    help="Send raw HTML content instead of CVE JSON",
)
@click.option(
    "--subject",
    "-s",
    help="Email subject (required with --raw)",
)
@click.option(
    "--dry-run",
    "-n",
    is_flag=True,
    help="Test credentials and print message without sending",
)
@click.option("--ntfy-topic", envvar="NTFY_TOPIC", help="ntfy topic")
@click.option("--email-to", envvar="EMAIL_TO", help="Recipient email")
@click.option("--email-from", envvar="EMAIL_FROM", help="Sender email")
@click.option("--smtp-host", envvar="SMTP_HOST", help="SMTP server")
@click.option(
    "--smtp-port", envvar="SMTP_PORT", type=int, default=587, help="SMTP port"
)
@click.option("--smtp-user", envvar="SMTP_USER", help="SMTP username")
@click.option("--smtp-pass", envvar="SMTP_PASS", help="SMTP password")
@click.option(
    "--gmail-client-id", envvar="GMAIL_CLIENT_ID", help="Gmail OAuth2 client ID"
)
@click.option(
    "--gmail-client-secret",
    envvar="GMAIL_CLIENT_SECRET",
    help="Gmail OAuth2 client secret",
)
@click.option(
    "--gmail-refresh-token",
    envvar="GMAIL_REFRESH_TOKEN",
    help="Gmail OAuth2 refresh token",
)
@click.option("--gmail-address", envvar="GMAIL_ADDRESS", help="Gmail address")
@click.option("--from-name", envvar="FROM_NAME", help="Sender display name")
@click.option("--debug", "-d", is_flag=True, help="Enable debug logging")
def send(
    *,
    backend: str,
    input_file,
    raw: bool,
    subject: str | None,
    dry_run: bool,
    ntfy_topic: str | None,
    email_to: str | None,
    email_from: str | None,
    smtp_host: str | None,
    smtp_port: int,
    smtp_user: str | None,
    smtp_pass: str | None,
    gmail_client_id: str | None,
    gmail_client_secret: str | None,
    gmail_refresh_token: str | None,
    gmail_address: str | None,
    from_name: str | None,
    debug: bool,
):
    """Send CVE alerts via ntfy, email, or gmail."""
    configure_logging(debug)

    if backend == "ntfy":
        if not ntfy_topic:
            logger.error("ntfy requires --ntfy-topic")
            sys.exit(1)
        notifier = NtfyNotifier(ntfy_topic)
    elif backend == "email":
        if (
            smtp_host is None
            or smtp_user is None
            or smtp_pass is None
            or email_from is None
            or email_to is None
        ):
            raise ValueError(
                "email requires --smtp-host, --smtp-user, --smtp-pass, "
                "--email-from, and --email-to"
            )
        notifier = EmailNotifier(
            smtp_host=smtp_host,
            smtp_port=smtp_port,
            user=smtp_user,
            password=smtp_pass,
            from_addr=email_from,
            to_addr=email_to,
        )
    else:  # gmail
        if (
            gmail_client_id is None
            or gmail_client_secret is None
            or gmail_refresh_token is None
            or gmail_address is None
        ):
            raise ValueError(
                "gmail requires --gmail-client-id, --gmail-client-secret, "
                "--gmail-refresh-token, and --gmail-address"
            )
        notifier = GmailNotifier(
            gmail_client_id,
            gmail_client_secret,
            gmail_refresh_token,
            gmail_address,
            from_name=from_name or "Security Scan",
        )

    if raw:
        if backend == "ntfy":
            logger.error("ntfy backend does not support --raw mode")
            sys.exit(1)

        html_content = input_file.read()
        if not html_content.strip():
            logger.info("No content to send")
            return

        if not subject:
            subject = f"CVE Scan Report - {datetime.now().strftime('%Y-%m-%d')}"

        logger.info(f"Sending raw HTML via {backend}")
        success = asyncio.run(notifier.send_raw(subject, html_content, dry_run=dry_run))
    else:
        try:
            data = json.load(input_file)
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON input: {e}")
            sys.exit(1)

        if not data:
            logger.info("No CVEs to send")
            if isinstance(notifier, NtfyNotifier):
                asyncio.run(
                    notifier.notify(
                        "No new vulnerabilities found",
                        NtfyOptions(
                            title="CVE Scan Complete",
                            priority=2,
                            tags="white_check_mark",
                        ),
                    )
                )
            return

        cves = [CVE(**item) for item in data]
        logger.info(f"Sending alerts for {len(cves)} CVEs via {backend}")
        success = asyncio.run(notifier.send(cves, dry_run=dry_run))

    if not success:
        sys.exit(1)


def main():
    cli()


if __name__ == "__main__":
    main()
