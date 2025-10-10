import os
import subprocess
import sys
from pathlib import Path

import click
import inquirer
from google.cloud import secretmanager
from loguru import logger

sys.path.insert(0, str(Path(__file__).parent))
from utils import (
    build_nix_image,
    check_gcloud_config,
    check_nix,
    check_ssh_access,
    run_command,
    run_command_env_context,
    setup_logging,
)


def get_wireguard_key(
    project_id: str, secret_name: str = "hekate-wireguard-private-key"
) -> str:
    try:
        client = secretmanager.SecretManagerServiceClient()
        logger.debug(f"Fetching secret: projects/{project_id}/secrets/{secret_name}/versions/latest")
        response = client.access_secret_version(request={"name": f"projects/{project_id}/secrets/{secret_name}/versions/latest"})

        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logger.error(f"Failed to fetch WireGuard key from Secret Manager: {e}")
        logger.info("Falling back to gcloud command...")

        output, returncode = run_command(
            [
                "gcloud",
                "secrets",
                "versions",
                "access",
                "latest",
                f"--secret={secret_name}",
                f"--project={project_id}",
            ],
            "fetch WireGuard key",
            capture_output=True,
            stream_output=False,
            check=False,
        )

        if returncode != 0:
            logger.error("Failed to fetch WireGuard key")
            sys.exit(1)

        return output


def get_flash_instructions(image_file: Path) -> str:
    return f"zstd -d -c {image_file} | sudo dd of=/dev/sdX bs=4M status=progress"


def check_secret_access(project_id: str, secret_name: str) -> bool:
    logger.info(f"Checking access to secret: {secret_name}")

    try:
        client = secretmanager.SecretManagerServiceClient()
        logger.debug(f"Testing secret access: projects/{project_id}/secrets/{secret_name}/versions/latest")
        response = client.access_secret_version(request={"name": f"projects/{project_id}/secrets/{secret_name}/versions/latest"})

        if response.payload.data:
            logger.info(f"✓ Secret {secret_name} is accessible")
            return True
        else:
            logger.error(f"Secret {secret_name} exists but has no data")
            return False

    except Exception as e:
        logger.error(f"Cannot access secret {secret_name}: {e}")
        logger.info("Falling back to gcloud test...")

        _, returncode = run_command(
            [
                "gcloud",
                "secrets",
                "versions",
                "access",
                "latest",
                f"--secret={secret_name}",
                f"--project={project_id}",
            ],
            "test secret access",
            capture_output=True,
            stream_output=False,
            check=False,
        )

        if returncode == 0:
            logger.info(f"✓ Secret {secret_name} is accessible via gcloud")
            return True
        else:
            logger.error(f"Cannot access secret {secret_name} via gcloud")
            return False


def perform_hekate_dry_run(
    repo_root: Path, project_id: str, remote_host: str, secret_name: str
) -> bool:
    logger.info("🔍 Performing hekate dry run checks...")

    checks = [
        (
            "Nix flake",
            lambda: check_nix(
                repo_root, "nixosConfigurations.hekate.config.system.build.sdImage"
            ),
        ),
        ("Secret access", lambda: check_secret_access(project_id, secret_name)),
        ("gcloud config", lambda: check_gcloud_config(project_id)),
        ("SSH access", lambda: check_ssh_access(remote_host)),
    ]

    all_passed = True

    for check_name, check_func in checks:
        try:
            if not check_func():
                all_passed = False
        except Exception as e:
            logger.error(f"Check '{check_name}' failed with exception: {e}")
            all_passed = False

    if all_passed:
        logger.success("✅ All hekate dry run checks passed!")
    else:
        logger.error("❌ Some hekate dry run checks failed")

    return all_passed


@click.command()
@click.option(
    "-v", "--verbose", count=True, help="Increase verbosity (use multiple times)"
)
@click.option(
    "--project-id", default="modiase-infra", envvar="PROJECT_ID", help="GCP project ID"
)
@click.option(
    "--remote-host", default="herakles", envvar="REMOTE_HOST", help="Remote build host"
)
@click.option("--interactive", is_flag=True, help="Interactive mode with prompts")
@click.option(
    "--secret-name",
    default="hekate-wireguard-private-key",
    help="Name of the WireGuard key secret",
)
@click.option("--verify", is_flag=True, help="Check all prerequisites without building")
def cli(
    verbose: int,
    project_id: str,
    remote_host: str,
    interactive: bool,
    secret_name: str,
    verify: bool,
):

    setup_logging(verbose)

    repo_root = Path(os.environ.get("REPO_ROOT", Path(__file__).parent.resolve().parent))

    with run_command_env_context(
        CI="1", TERM="dumb", NO_COLOR=os.environ.get("NO_COLOR", "false")
    ):
        if verify:
            with logger.contextualize(task="checking-prerequisites"):
                logger.info("🔍 Running hekate dry run checks")
                sys.exit(0 if perform_hekate_dry_run(repo_root, project_id, remote_host, secret_name) else 1)

    action = "build"
    copy_command = False

    if interactive:
        questions = [
            inquirer.List(
                "action",
                message="What would you like to do?",
                choices=[
                    ("Build hekate image", "build"),
                    ("Verify (check only)", "verify"),
                ],
            )
        ]

        if verbose == 0:
            questions.append(
                inquirer.List(
                    "verbosity",
                    message="Select verbosity level:",
                    choices=[("Normal", 0), ("Debug", 1), ("Trace", 2)],
                )
            )

        answers = inquirer.prompt(questions)
        action = answers["action"]

        if "verbosity" in answers:
            verbose = answers["verbosity"]
            setup_logging(verbose)

    if action == "verify":
        with logger.contextualize(task="checking-prerequisites"):
            sys.exit(0 if perform_hekate_dry_run(repo_root, project_id, remote_host, secret_name) else 1)

    if action != "build":
        logger.info("Build cancelled")
        return

    with logger.contextualize(task="fetching-secrets"):
        logger.info("Fetching WireGuard private key from Google Secret Manager")
        os.environ["HEKATE_WG_KEY"] = get_wireguard_key(project_id, secret_name)
    logger.debug("WireGuard key set in environment")

    with logger.contextualize(task="building-sd-image"):
        logger.info("Building hekate NixOS SD card image")
        image_file = Path(build_nix_image(
            repo_root,
            "nixosConfigurations.hekate.config.system.build.sdImage",
            "aarch64-linux",
            remote_host,
            ["--verbose"] if verbose >= 2 else None,
        ))
        image_file = list(image_file.glob("**/*.img.zst"))[0]

    with logger.contextualize(task="preparing-flash-command"):
        image_size = subprocess.run(
            ["du", "-h", str(image_file)], capture_output=True, text=True
        ).stdout.split()[0]

        logger.success("Hekate SD card image built successfully")
        logger.info(f"Image location: {image_file}")
        logger.info(f"Image size: {image_size}")

        logger.info(f"Flash with: {get_flash_instructions(image_file)}")

    if interactive:
        copy_answers = inquirer.prompt([
            inquirer.Confirm(
                "copy_command",
                message="Copy flash command to clipboard?",
                default=False,
            ),
        ])
        copy_command = copy_answers and copy_answers["copy_command"]

    if copy_command:
        try:
            subprocess.run(["pbcopy"], input=get_flash_instructions(image_file), text=True, check=True)
            logger.info("Flash command copied to clipboard!")
        except (subprocess.CalledProcessError, FileNotFoundError):
            try:
                subprocess.run(
                    ["xclip", "-selection", "clipboard"],
                    input=get_flash_instructions(image_file),
                    text=True,
                    check=True,
                )
                logger.info("Flash command copied to clipboard!")
            except (subprocess.CalledProcessError, FileNotFoundError):
                logger.warning(
                    "Could not copy to clipboard (pbcopy/xclip not available)"
                )


if __name__ == "__main__":
    cli()