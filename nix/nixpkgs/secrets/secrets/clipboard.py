"""Clipboard operations for secrets."""

import base64
import os
import shutil
import subprocess
import sys


def _is_ssh_session() -> bool:
    return any(
        os.environ.get(var) for var in ("SSH_TTY", "SSH_CONNECTION", "SSH_CLIENT")
    )


def _osc52_copy(value: str) -> None:
    encoded = base64.b64encode(value.encode()).decode()
    sys.stdout.write(f"\033]52;c;{encoded}\007")
    sys.stdout.flush()


def copy_to_clipboard(value: str) -> None:
    """Copy a value to the system clipboard."""
    if _is_ssh_session():
        _osc52_copy(value)
        return

    if shutil.which("pbcopy"):
        subprocess.run(["pbcopy"], input=value.encode(), check=True)
    elif shutil.which("xclip"):
        subprocess.run(
            ["xclip", "-selection", "clipboard"], input=value.encode(), check=True
        )
    else:
        raise RuntimeError(
            "No clipboard tool available. Install pbcopy (macOS) or xclip (Linux)."
        )
