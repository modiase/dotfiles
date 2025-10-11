import os
import subprocess
import sys
import platform
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


def is_removable_device(device_path: str) -> bool:
    """Check if a device is removable/external."""
    try:
        if platform.system() == "Darwin":
            # macOS: Use diskutil to check if device is external
            result = subprocess.run(
                ["diskutil", "list", device_path],
                capture_output=True,
                text=True,
                check=False
            )
            if result.returncode == 0:
                # Look for "(external, physical)" in the output
                return "(external, physical)" in result.stdout
            return False
        else:
            # Linux: Check /sys/block/*/removable
            device_name = Path(device_path).name
            if device_name.startswith("sd"):
                # For SCSI devices like /dev/sdb, check /sys/block/sdb/removable
                removable_file = Path(f"/sys/block/{device_name}/removable")
                if removable_file.exists():
                    return removable_file.read_text().strip() == "1"
            return False
    except Exception as e:
        logger.error(f"Failed to check if device is removable: {e}")
        return False


def validate_flash_device(device_path: str) -> bool:
    """Validate that the device is safe to flash."""
    device = Path(device_path)

    # Check device exists
    if not device.exists():
        logger.error(f"Device does not exist: {device_path}")
        return False

    # Check device is a block device
    if not device.is_block_device():
        logger.error(f"Device is not a block device: {device_path}")
        return False

    # Check device is removable
    if not is_removable_device(device_path):
        logger.error(f"Device is not removable/external: {device_path}")
        logger.error("For safety, only removable devices can be flashed automatically")
        return False

    logger.info(f"✓ Device {device_path} validated as removable/external")
    return True


def flash_image_to_device(image_file: Path, device_path: str) -> bool:
    """Flash the image to the specified device using dd."""
    logger.warning(f"⚠️  About to flash {image_file} to {device_path}")
    logger.warning("⚠️  This will DESTROY ALL DATA on the target device!")

    try:
        # Build the command: zstd -d -c image.img.zst | sudo dd of=device bs=4M status=progress
        logger.info("Starting flash process...")

        # Use subprocess.run with shell=True to handle the pipe
        flash_cmd = f"zstd -d -c {image_file} | sudo dd of={device_path} bs=4M status=progress"

        result = subprocess.run(
            flash_cmd,
            shell=True,
            check=False,
            text=True
        )

        if result.returncode == 0:
            logger.success(f"✅ Successfully flashed {image_file} to {device_path}")
            return True
        else:
            logger.error(f"❌ Flash failed with exit code {result.returncode}")
            return False

    except Exception as e:
        logger.error(f"❌ Flash failed with exception: {e}")
        return False


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
@click.option(
    "-d", "--device", help="Device to flash image to (e.g., /dev/disk2). Must be removable/external."
)
def cli(
    verbose: int,
    project_id: str,
    remote_host: str,
    interactive: bool,
    secret_name: str,
    verify: bool,
    device: str,
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

        if device:
            # Validate and flash to device
            if validate_flash_device(device):
                with logger.contextualize(task="flashing-device"):
                    if flash_image_to_device(image_file, device):
                        logger.success(f"✅ Image successfully flashed to {device}")
                        return
                    else:
                        logger.error(f"❌ Failed to flash image to {device}")
                        sys.exit(1)
            else:
                logger.error(f"❌ Device validation failed for {device}")
                sys.exit(1)
        else:
            # Show manual flash command
            logger.info(f"Flash with: {get_flash_instructions(image_file)}")

    if interactive and not device:
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