import os
import subprocess
import sys
import platform
from pathlib import Path

import click
import inquirer
from loguru import logger

sys.path.insert(0, str(Path(__file__).parent))
from utils import (
    build_nix_image,
    check_nix,
    check_ssh_access,
    copy_to_clipboard,
    run_command_env_context,
    setup_logging,
)


def get_flash_instructions(image_file: Path) -> str:
    return f"zstd -d -c {image_file} | sudo dd of=/dev/sdX bs=4M status=progress"


def _check_removable_darwin(device_path: str) -> bool:
    result = subprocess.run(
        ["diskutil", "list", device_path], capture_output=True, text=True, check=False
    )
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
        logger.info(f"{action} successful")
        return True
    else:
        logger.warning(f"Failed to {action.lower()}: {result.stderr}")
        return False


def flash_image_to_device(image_file: Path, device_path: str) -> bool:
    logger.warning(f"About to flash {image_file} to {device_path}")
    logger.warning("This will DESTROY ALL DATA on the target device!")

    try:
        logger.info("Unmounting device before flashing...")
        if platform.system() == "Darwin":
            _run_disk_command(["diskutil", "unmountDisk", device_path], "Unmount")
        else:
            _run_disk_command(["sudo", "umount", f"{device_path}*"], "Unmount")

        logger.info("Starting flash process...")
        flash_cmd = (
            f"zstd -d -c {image_file} | sudo dd of={device_path} bs=4M status=progress"
        )
        result = subprocess.run(flash_cmd, shell=True, check=False, text=True)

        if result.returncode == 0:
            logger.success(f"Successfully flashed {image_file} to {device_path}")

            logger.info("Ejecting device...")
            if platform.system() == "Darwin":
                _run_disk_command(["diskutil", "eject", device_path], "Device eject")
            else:
                _run_disk_command(["sudo", "eject", device_path], "Device eject")

            return True
        else:
            logger.error(f"Flash failed with exit code {result.returncode}")
            return False

    except Exception as e:
        logger.error(f"Flash failed with exception: {e}")
        return False


def perform_hestia_dry_run(repo_root: Path, remote_host: str) -> bool:
    logger.info("Performing hestia dry run checks")

    checks = [
        (
            "Nix flake",
            lambda: check_nix(
                repo_root, "nixosConfigurations.hestia.config.system.build.sdImage"
            ),
        ),
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
        logger.success("All hestia dry run checks passed")
    else:
        logger.error("Some hestia dry run checks failed")

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
    verify: bool,
    device: str,
):
    setup_logging(verbose)

    repo_root = Path(
        os.environ.get("REPO_ROOT", Path(__file__).parent.resolve().parent)
    )

    if device:
        logger.info(f"Validating specified device {device}")
        if not validate_flash_device(device):
            logger.error(f"Device validation failed for {device}")
            logger.error("Fix the device issue before proceeding with build")
            sys.exit(1)
        logger.info(f"Device {device} validated successfully")

    with run_command_env_context(
        CI="1", TERM="dumb", NO_COLOR=os.environ.get("NO_COLOR", "false")
    ):
        if verify:
            with logger.contextualize(task="checking-prerequisites"):
                logger.info("Running hestia dry run checks")
                sys.exit(0 if perform_hestia_dry_run(repo_root, remote_host) else 1)

    action = "build"
    copy_command = False

    if interactive:
        questions = [
            inquirer.List(
                "action",
                message="What would you like to do?",
                choices=[
                    ("Build hestia image", "build"),
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
            sys.exit(0 if perform_hestia_dry_run(repo_root, remote_host) else 1)

    if action != "build":
        logger.info("Build cancelled")
        return

    with logger.contextualize(task="building-image"):
        logger.info("Building hestia image")
        image_file = Path(
            build_nix_image(
                repo_root,
                "nixosConfigurations.hestia.config.system.build.sdImage",
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

        logger.success("Hestia image built successfully")
        logger.info(f"Image location: {image_file}")
        logger.info(f"Image size: {image_size}")

        if device:
            with logger.contextualize(task="flashing-device"):
                if flash_image_to_device(image_file, device):
                    logger.success(f"Image successfully flashed to {device}")
                    return
                else:
                    logger.error(f"Failed to flash image to {device}")
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
            if copy_to_clipboard(get_flash_instructions(image_file)):
                logger.info("Flash command copied to clipboard!")
            else:
                logger.warning("Could not copy to clipboard")


if __name__ == "__main__":
    cli()
