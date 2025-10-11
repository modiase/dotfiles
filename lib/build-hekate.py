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


def _get_secret_with_fallback(project_id: str, secret_name: str, action: str) -> str:
    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"

    try:
        client = secretmanager.SecretManagerServiceClient()
        logger.debug(f"Fetching secret: {secret_path}")
        response = client.access_secret_version(request={"name": secret_path})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logger.error(f"Failed to {action} from Secret Manager: {e}")
        logger.info("Falling back to gcloud command...")

        output, returncode = run_command(
            ["gcloud", "secrets", "versions", "access", "latest", f"--secret={secret_name}", f"--project={project_id}"],
            action, capture_output=True, stream_output=False, check=False
        )

        if returncode != 0:
            logger.error(f"Failed to {action}")
            sys.exit(1)

        return output


def get_wireguard_key(project_id: str, secret_name: str = "hekate-wireguard-private-key") -> str:
    return _get_secret_with_fallback(project_id, secret_name, "fetch WireGuard key")


def get_flash_instructions(image_file: Path) -> str:
    return f"zstd -d -c {image_file} | sudo dd of=/dev/sdX bs=4M status=progress"


def _check_removable_darwin(device_path: str) -> bool:
    result = subprocess.run(["diskutil", "list", device_path], capture_output=True, text=True, check=False)
    return result.returncode == 0 and "(external, physical)" in result.stdout


def _check_removable_linux(device_path: str) -> bool:
    device_name = Path(device_path).name
    if device_name.startswith("sd"):
        removable_file = Path(f"/sys/block/{device_name}/removable")
        if removable_file.exists():
            return removable_file.read_text().strip() == "1"
    return False


def is_removable_device(device_path: str) -> bool:
    try:
        if platform.system() == "Darwin":
            return _check_removable_darwin(device_path)
        else:
            return _check_removable_linux(device_path)
    except Exception as e:
        logger.error(f"Failed to check if device is removable: {e}")
        return False


def validate_flash_device(device_path: str) -> bool:
    """Validate that the device is safe to flash."""
    device = Path(device_path)

    if not device.exists():
        logger.error(f"Device does not exist: {device_path}")
        return False

    if not device.is_block_device():
        logger.error(f"Device is not a block device: {device_path}")
        return False

    if not is_removable_device(device_path):
        logger.error(f"Device is not removable/external: {device_path}")
        logger.error("For safety, only removable devices can be flashed automatically")
        return False

    logger.info(f"✓ Device {device_path} validated as removable/external")
    return True


def _run_disk_command(cmd: list, action: str) -> bool:
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode == 0:
        logger.info(f"✅ {action} successful")
        return True
    else:
        logger.warning(f"Failed to {action.lower()}: {result.stderr}")
        return False


def flash_image_to_device(image_file: Path, device_path: str) -> bool:
    logger.warning(f"⚠️  About to flash {image_file} to {device_path}")
    logger.warning("⚠️  This will DESTROY ALL DATA on the target device!")

    try:
        logger.info("Unmounting device before flashing...")
        if platform.system() == "Darwin":
            _run_disk_command(["diskutil", "unmountDisk", device_path], "Unmount")
        else:
            _run_disk_command(["sudo", "umount", f"{device_path}*"], "Unmount")

        logger.info("Starting flash process...")
        flash_cmd = f"zstd -d -c {image_file} | sudo dd of={device_path} bs=4M status=progress"
        result = subprocess.run(flash_cmd, shell=True, check=False, text=True)

        if result.returncode == 0:
            logger.success(f"✅ Successfully flashed {image_file} to {device_path}")

            logger.info("Ejecting device...")
            if platform.system() == "Darwin":
                _run_disk_command(["diskutil", "eject", device_path], "Device eject")
            else:
                _run_disk_command(["sudo", "eject", device_path], "Device eject")

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
        _get_secret_with_fallback(project_id, secret_name, "test secret access")
        logger.info(f"✓ Secret {secret_name} is accessible")
        return True
    except SystemExit:
        logger.error(f"Cannot access secret {secret_name}")
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
    "-d",
    "--device",
    help="Device to flash image to (e.g., /dev/disk2). Must be removable/external.",
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

    repo_root = Path(
        os.environ.get("REPO_ROOT", Path(__file__).parent.resolve().parent)
    )

    if device:
        logger.info(f"Validating specified {device=} ")
        if not validate_flash_device(device):
            logger.error(f"❌ Device validation failed for {device}")
            logger.error("Fix the device issue before proceeding with build")
            sys.exit(1)
        logger.info(f"✅ Device {device} validated successfully")

    with run_command_env_context(
        CI="1", TERM="dumb", NO_COLOR=os.environ.get("NO_COLOR", "false")
    ):
        if verify:
            with logger.contextualize(task="checking-prerequisites"):
                logger.info("🔍 Running hekate dry run checks")
                sys.exit(
                    0
                    if perform_hekate_dry_run(
                        repo_root, project_id, remote_host, secret_name
                    )
                    else 1
                )

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
            sys.exit(
                0
                if perform_hekate_dry_run(
                    repo_root, project_id, remote_host, secret_name
                )
                else 1
            )

    if action != "build":
        logger.info("Build cancelled")
        return

    with logger.contextualize(task="fetching-secrets"):
        if "HEKATE_WG_KEY" not in os.environ or not os.environ["HEKATE_WG_KEY"]:
            logger.info("Fetching WireGuard private key from Google Secret Manager")
            os.environ["HEKATE_WG_KEY"] = get_wireguard_key(project_id, secret_name)
        else:
            logger.info("Using existing WireGuard key from environment")
    logger.debug("WireGuard key set in environment")

    with logger.contextualize(task="building-sd-image"):
        logger.info("Building hekate NixOS SD card image")
        image_file = Path(
            build_nix_image(
                repo_root,
                "nixosConfigurations.hekate.config.system.build.sdImage",
                "aarch64-linux",
                remote_host,
                ["--verbose"] if verbose >= 2 else None,
            )
        )
        image_file = list(image_file.glob("**/*.img.zst"))[0]

    with logger.contextualize(task="preparing-flash-command"):
        image_size = subprocess.run(
            ["du", "-h", str(image_file)], capture_output=True, text=True
        ).stdout.split()[0]

        logger.success("Hekate SD card image built successfully")
        logger.info(f"Image location: {image_file}")
        logger.info(f"Image size: {image_size}")

        if device:
            with logger.contextualize(task="flashing-device"):
                if flash_image_to_device(image_file, device):
                    logger.success(f"✅ Image successfully flashed to {device}")
                    return
                else:
                    logger.error(f"❌ Failed to flash image to {device}")
                    sys.exit(1)
        else:
            logger.info(f"Flash with: {get_flash_instructions(image_file)}")

    if interactive and not device:
        copy_answers = inquirer.prompt(
            [
                inquirer.Confirm(
                    "copy_command",
                    message="Copy flash command to clipboard?",
                    default=False,
                ),
            ]
        )
        copy_command = copy_answers and copy_answers["copy_command"]

        if copy_command:
            try:
                subprocess.run(
                    ["pbcopy"],
                    input=get_flash_instructions(image_file),
                    text=True,
                    check=True,
                )
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

