"""Devlogs logging library — unified syslog logging for Python scripts."""

import contextlib
import logging
import os
import subprocess
from typing import Final

PRIORITY_MAP: Final = {
    logging.DEBUG: "user.info",  # macOS drops user.debug from history
    logging.INFO: "user.info",
    logging.WARNING: "user.warning",
    logging.ERROR: "user.err",
    logging.CRITICAL: "user.crit",
}


class SyslogHandler(logging.Handler):
    """Log via /usr/bin/logger for macOS unified logging."""

    def emit(self, record: logging.LogRecord) -> None:
        priority = PRIORITY_MAP.get(record.levelno, "user.info")
        msg = self.format(record)
        with contextlib.suppress(FileNotFoundError, subprocess.TimeoutExpired, OSError):
            subprocess.run(
                ["logger", "-t", "devlogs", "-p", priority, msg],
                timeout=2,
            )


def setup_logging(component: str) -> logging.Logger:
    """Create a logger that writes to syslog in devlogs format.

    Reads TARGET_WINDOW env var for tmux window context.
    """
    window = os.environ.get("TARGET_WINDOW", "")
    tag = f"{component}(@{window})" if window else component
    logger = logging.getLogger(f"devlogs.{component}")
    logger.setLevel(logging.DEBUG)
    handler = SyslogHandler()
    handler.setFormatter(
        logging.Formatter(f"[devlogs] %(levelname)s {tag}: %(message)s")
    )
    logger.addHandler(handler)
    return logger
