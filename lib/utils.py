#!/usr/bin/env python3
# vim: set filetype=python:

import os
import re
import shlex
import subprocess
import sys
import tempfile
from collections.abc import Mapping, Sequence
from contextlib import contextmanager
from contextvars import ContextVar
from pathlib import Path
from typing import Iterator

from google.cloud import storage
from loguru import logger

try:
    import pexpect

    HAS_PEXPECT = True
except ImportError:
    HAS_PEXPECT = False


_run_command_env: ContextVar[Mapping[str, str]] = ContextVar(
    "run_command_env", default={}
)

_STRUCTURED_LOG_RE = re.compile(r"^\d{2}:\d{2}:\d{2} \| .+ \| .+ \| .+")


def _looks_like_structured_log(line: str) -> bool:
    return bool(_STRUCTURED_LOG_RE.match(line))


@contextmanager
def run_command_env_context(**env_vars: str) -> Iterator[None]:
    """Context manager to set environment variables for all run_command calls within the context."""
    current_env = _run_command_env.get({})
    new_env = {**current_env, **env_vars}
    token = _run_command_env.set(new_env)
    try:
        yield
    finally:
        _run_command_env.reset(token)


def setup_logging(verbose: int) -> None:
    logger.remove()

    def format_with_task(record) -> str:
        task = record["extra"].get("task", "")
        level_name = record["level"].name.lower()
        time_full = record["time"].strftime("%Y-%m-%d %H:%M:%S")
        time_short = record["time"].strftime("%H:%M:%S")
        name = record["name"]
        function = record["function"]
        line_no = record["line"]
        message = record["message"]

        if verbose >= 2:
            base = f"<green>{time_full}</green> | <level>{level_name:<8}</level>"
            location = (
                f"<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line_no}</cyan>"
            )
            if task:
                return (
                    f"{base} | <yellow>{task}</yellow> | {location} - "
                    f"<level>{message}</level>\n"
                )
            return f"{base} | {location} - <level>{message}</level>\n"

        if verbose >= 1:
            base = f"<green>{time_short}</green> | <level>{level_name:<8}</level>"
            if task:
                return f"{base} | <yellow>{task}</yellow> | <level>{message}</level>\n"
            return f"{base} | <level>{message}</level>\n"

        time_part = f"<green>{time_short}</green>"
        if task:
            return f"{time_part} | <yellow>{task}</yellow> | <level>{message}</level>\n"
        return f"{time_part} | <level>{message}</level>\n"

    level = "TRACE" if verbose >= 2 else "DEBUG" if verbose >= 1 else "INFO"

    logger.add(sys.stderr, level=level, format=format_with_task, colorize=True)


def run_command(
    cmd: Sequence[str],
    description: str,
    capture_output: bool = False,
    check: bool = True,
    cwd: Path | str | None = None,
    stream_output: bool = True,
    env: Mapping[str, str] | None = None,
) -> tuple[str, int]:
    """Run a command with logging."""
    logger.debug(f"Running: {' '.join(cmd)}")

    context_env = _run_command_env.get({})
    merged_env = {**os.environ}
    if context_env:
        merged_env.update(context_env)
    if env:
        merged_env.update(env)
    final_env = merged_env if (context_env or env) else None

    try:
        if stream_output:
            if HAS_PEXPECT:
                try:
                    if isinstance(cmd, (list, tuple)):
                        cmd_str = shlex.join(cmd)
                    else:
                        cmd_str = str(cmd)

                    spawn_env = final_env or dict(os.environ)

                    child = pexpect.spawn(
                        cmd_str, cwd=cwd, env=spawn_env, encoding="utf-8"
                    )

                    output_lines = []

                    while True:
                        try:
                            line = child.readline()
                            if not line:
                                break

                            line = line.rstrip()
                            if line:
                                if _looks_like_structured_log(line):
                                    logger.opt(raw=True).log("DEBUG", f"{line}\n")
                                else:
                                    escaped_line = line.replace("{", "{{").replace(
                                        "}", "}}"
                                    )
                                    logger.debug(f"  {escaped_line}")
                                output_lines.append(line)

                        except pexpect.EOF:
                            break
                        except pexpect.TIMEOUT:
                            continue

                    child.close()
                    returncode = child.exitstatus if child.exitstatus is not None else 1

                    if returncode != 0 and check:
                        logger.error(f"Command failed: {description}")
                        sys.exit(1)
                    return "\n".join(output_lines), returncode

                except Exception as e:
                    logger.warning(f"Pexpect failed ({e}), falling back to subprocess")

            # Fallback to subprocess implementation
            with subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                cwd=cwd,
                env=final_env,
            ) as process:
                output_lines = []

                for line in iter(process.stdout.readline, ""):
                    if line:
                        line = line.rstrip()
                        if line:
                            if _looks_like_structured_log(line):
                                logger.opt(raw=True).log("DEBUG", f"{line}\n")
                            else:
                                escaped_line = line.replace("{", "{{").replace(
                                    "}", "}}"
                                )
                                logger.debug(f"  {escaped_line}")
                            output_lines.append(line)

                process.wait()
                if process.returncode != 0 and check:
                    logger.error(f"Command failed: {description}")
                    sys.exit(1)
                return "\n".join(output_lines), process.returncode
        elif capture_output:
            result = subprocess.run(
                cmd, capture_output=True, text=True, check=check, cwd=cwd, env=final_env
            )
            return result.stdout.strip(), result.returncode
        else:
            result = subprocess.run(cmd, check=check, cwd=cwd, env=final_env)
            return "", result.returncode
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {description}")
        if capture_output and e.stderr:
            logger.error(f"stderr: {e.stderr}")
        if check:
            sys.exit(1)
        return "", e.returncode


def get_gcs_hash(bucket_name: str, object_name: str, project_id: str) -> str | None:
    try:
        client = storage.Client(project=project_id)
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(object_name)

        if not blob.exists():
            return None

        blob.reload()
        return blob.crc32c
    except Exception as e:
        logger.debug(f"Failed to get GCS hash: {e}")
        return None


def get_local_hash(file_path: str) -> str:
    if not Path(file_path).exists():
        raise ValueError(f"Local file does not exist: {file_path}")

    cmd = ["gsutil", "hash", "-c", file_path]
    output, returncode = run_command(
        cmd,
        f"get local hash for {file_path}",
        capture_output=True,
        stream_output=False,
        check=False,
    )

    if returncode != 0:
        raise ValueError(f"Failed to calculate hash for {file_path}")

    for line in output.split("\n"):
        if "Hash (crc32c):" in line:
            return line.split(":", 1)[1].strip()

    raise ValueError(f"Could not find CRC32C hash in gsutil output for {file_path}")


def parse_gcs_uri(uri: str) -> tuple[str, str]:
    if not uri.startswith("gs://"):
        raise ValueError(f"Invalid GCS URI: {uri}")

    path = uri[5:]
    parts = path.split("/", 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid GCS URI format: {uri}")

    return parts[0], parts[1]


def image_up_to_date(local_path: str, dest_uri: str, project_id: str) -> bool:
    logger.debug(f"Checking if image is up to date: {local_path} vs {dest_uri}")

    bucket_name, object_name = parse_gcs_uri(dest_uri)
    remote_hash = get_gcs_hash(bucket_name, object_name, project_id)
    if not remote_hash:
        logger.debug("No remote image found")
        return False

    local_hash = get_local_hash(local_path)

    logger.debug(f"Remote hash: {remote_hash}")
    logger.debug(f"Local hash: {local_hash}")

    return local_hash == remote_hash


def upload_to_gcs(local_path: str, dest_uri: str, project_id: str) -> None:
    """Upload a file to Google Cloud Storage."""
    bucket_name, object_name = parse_gcs_uri(dest_uri)

    file_size = subprocess.run(
        ["du", "-h", local_path], capture_output=True, text=True
    ).stdout.split()[0]
    logger.info(f"Uploading {file_size} tarball to {dest_uri}")

    try:
        client = storage.Client(project=project_id)
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(object_name)

        blob.upload_from_filename(local_path)
        logger.info(f"Upload completed: {dest_uri}")

    except Exception as e:
        logger.error(f"Failed to upload to GCS: {e}")
        sys.exit(1)


def check_nix(repo_root: Path, nix_attr: str | None = None) -> bool:
    """Check Nix flake configuration and optionally a specific attribute."""
    logger.info("Checking Nix flake configuration")

    flake_nix = repo_root / "flake.nix"
    if not flake_nix.exists():
        logger.error(f"flake.nix not found: {flake_nix}")
        return False

    _, returncode = run_command(
        ["nix", "--version"],
        "check nix version",
        capture_output=True,
        stream_output=False,
        check=False,
    )
    if returncode != 0:
        logger.error("Nix not found in PATH")
        return False

    logger.debug("Checking Nix flake")
    _, returncode = run_command(
        ["nix", "flake", "check", str(repo_root)], "nix flake check", check=False
    )
    if returncode != 0:
        logger.error("Nix flake check failed")
        return False

    if nix_attr:
        logger.debug(f"Checking Nix attribute: {nix_attr}")
        _, returncode = run_command(
            [
                "nix",
                "eval",
                "--raw",
                f"{repo_root}#{nix_attr}.name",
            ],
            f"check {nix_attr}",
            capture_output=True,
            stream_output=False,
            check=False,
        )
        if returncode != 0:
            logger.error(f"Nix attribute {nix_attr} not found or invalid")
            return False

    logger.info("✓ Nix flake configuration is valid")
    return True


def check_gcloud_config(project_id: str) -> bool:
    """Check gcloud configuration."""
    logger.info("Checking gcloud configuration")

    _, returncode = run_command(
        ["gcloud", "--version"],
        "check gcloud version",
        capture_output=True,
        stream_output=False,
        check=False,
    )
    if returncode != 0:
        logger.error("gcloud not found in PATH")
        return False

    logger.debug("Checking gcloud authentication")
    _, returncode = run_command(
        ["gcloud", "auth", "list", "--filter=status:ACTIVE"],
        "check gcloud auth",
        check=False,
    )
    if returncode != 0:
        logger.error("No active gcloud authentication found. Run: gcloud auth login")
        return False

    logger.debug(f"Checking access to project: {project_id}")
    _, returncode = run_command(
        ["gcloud", "projects", "describe", project_id],
        "check project access",
        capture_output=True,
        stream_output=False,
        check=False,
    )
    if returncode != 0:
        logger.error(
            f"Cannot access project {project_id}. Check permissions or run: gcloud config set project {project_id}"
        )
        return False

    logger.debug("Checking required APIs")
    apis_to_check = [
        "compute.googleapis.com",
        "storage.googleapis.com",
        "secretmanager.googleapis.com",
    ]

    for api in apis_to_check:
        output, returncode = run_command(
            [
                "gcloud",
                "services",
                "list",
                "--enabled",
                f"--filter=name:{api}",
                "--format=value(name)",
            ],
            f"check {api}",
            capture_output=True,
            stream_output=False,
            check=False,
        )

        if returncode != 0 or api not in output:
            logger.error(f"Required API not enabled: {api}")
            logger.info(f"Enable with: gcloud services enable {api}")
            return False

    logger.debug("Checking GCS bucket access")
    bucket_name = "modiase-infra"
    _, returncode = run_command(
        ["gsutil", "ls", f"gs://{bucket_name}/"],
        "check bucket access",
        capture_output=True,
        stream_output=False,
        check=False,
    )
    if returncode != 0:
        logger.error(f"Cannot access GCS bucket: gs://{bucket_name}/")
        return False

    logger.info("✓ gcloud configuration is valid")
    return True


def check_ssh_access(remote_host: str) -> bool:
    """Check SSH access to remote build host."""
    logger.info(f"Checking SSH access to {remote_host}")

    _, returncode = run_command(
        [
            "ssh",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "BatchMode=yes",
            f"moye@{remote_host}",
            'echo "SSH connection successful"',
        ],
        f"test SSH to {remote_host}",
        capture_output=True,
        stream_output=False,
        check=False,
    )

    if returncode != 0:
        logger.error(
            f"Cannot SSH to {remote_host}. Check SSH keys and host availability."
        )
        return False

    logger.info(f"✓ SSH access to {remote_host} is working")
    return True


def build_nix_image(
    repo_root: Path,
    nix_attr: str,
    system: str,
    remote_host: str | None = None,
    extra_args: Sequence[str] | None = None,
    env: Mapping[str, str] | None = None,
) -> str:
    """Build a Nix image using nix build and return the result path."""
    logger.info(f"Building {nix_attr}")
    if extra_args is None:
        extra_args = ()

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        result_link = tmpdir_path / "result"

        nix_cmd = [
            "nix",
            "build",
            f"{repo_root}#{nix_attr}",
        ]

        if system:
            nix_cmd.extend(["--system", system])

        if remote_host:
            nix_cmd.extend(
                [
                    "--store",
                    f"ssh-ng://moye@{remote_host}",
                    "--eval-store",
                    "auto",
                ]
            )

        nix_cmd.extend(["--out-link", str(result_link)])

        if extra_args:
            nix_cmd.extend(extra_args)

        run_command(nix_cmd, f"build {nix_attr}", env=env)

        if not result_link.exists():
            logger.error(f"Build result not found: {result_link}")
            sys.exit(1)

        real_image_path = result_link.resolve()
        logger.info(f"Built: {real_image_path}")
        return str(real_image_path)


def build_gce_image(
    repo_root: Path, nix_attr: str, remote_host: str, verbose: int = 0
) -> str:
    """Build a GCE image using the custom build script and return the tarball path."""
    logger.info(f"Building GCE image for {nix_attr}")

    build_script = repo_root / "bin" / "build-gce-nixos-image.sh"

    cmd = [
        "env",
        "LOGGING_NO_PREFIX=1",
        str(build_script),
        "--attr",
        nix_attr,
        "--remote-host",
        remote_host,
    ]

    if verbose > 0:
        cmd.extend(["-v", str(verbose)])

    output, returncode = run_command(
        cmd, f"build GCE image for {nix_attr}", check=False
    )

    if returncode != 0:
        logger.error("Failed to build GCE image")
        sys.exit(1)

    for line in output.split("\n"):
        if line.startswith("BUILD_RESULT: "):
            tarball_path = line[14:]  # Skip "BUILD_RESULT: "
            if Path(tarball_path).exists():
                logger.info(f"Built GCE image: {tarball_path}")
                return tarball_path
            else:
                logger.error(
                    f"Build script returned invalid tarball path: {tarball_path}"
                )
                sys.exit(1)

    logger.error("Build script did not return a tarball path")
    sys.exit(1)


def check_terraform(repo_root: Path) -> bool:
    """Check Terraform configuration validity."""
    logger.info("Checking Terraform configuration")

    infra_dir = repo_root / "infra"
    tf_var_file = infra_dir / "tofu.tfvars"

    if not infra_dir.exists():
        logger.error(f"Infrastructure directory not found: {infra_dir}")
        return False

    if not tf_var_file.exists():
        logger.error(f"Terraform variables file not found: {tf_var_file}")
        return False

    _, returncode = run_command(
        ["tofu", "--version"],
        "check tofu version",
        capture_output=True,
        stream_output=False,
        check=False,
    )
    if returncode != 0:
        logger.error("OpenTofu (tofu) not found in PATH")
        return False

    logger.debug("Initializing Terraform")
    _, returncode = run_command(
        ["tofu", "init"], "terraform init", check=False, cwd=infra_dir
    )
    if returncode != 0:
        logger.error("Terraform init failed")
        return False

    logger.debug("Validating Terraform configuration")
    _, returncode = run_command(
        ["tofu", "validate"], "terraform validate", check=False, cwd=infra_dir
    )
    if returncode != 0:
        logger.error("Terraform validation failed")
        return False

    logger.debug("Planning Terraform changes")
    _, returncode = run_command(
        ["tofu", "plan", f"-var-file={tf_var_file}"],
        "terraform plan",
        check=False,
        cwd=infra_dir,
    )
    if returncode != 0:
        logger.error("Terraform plan failed")
        return False

    logger.info("✓ Terraform configuration is valid")
    return True


def deploy_with_terraform(
    repo_root: Path, verbose: int, taint_resources: tuple[str, ...] = ()
) -> None:
    """Deploy with OpenTofu/Terraform."""
    logger.info("Deploying with OpenTofu")

    infra_dir = repo_root / "infra"
    tf_var_file = repo_root / "infra" / "tofu.tfvars"

    for resource in taint_resources:
        logger.debug(f"Tainting resource: {resource}")
        run_command(
            ["tofu", "taint", resource],
            f"taint {resource}",
            check=False,
            cwd=infra_dir,
        )

    logger.info(f"Applying terraform configuration with var-file: {tf_var_file}")

    env = os.environ.copy()
    if verbose >= 2:
        env["TF_LOG"] = "TRACE"
    elif verbose >= 1:
        env["TF_LOG"] = "DEBUG"

    subprocess.run(
        ["tofu", "apply", "-auto-approve", f"-var-file={tf_var_file}"],
        env=env,
        check=True,
        cwd=infra_dir,
    )
