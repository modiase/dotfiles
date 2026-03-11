#!/usr/bin/env python3
"""Assemble AGENTS.md from sections based on agent type and environment."""

import argparse
import os
import shutil
import socket
import sys
from pathlib import Path

SECTIONS_DIR = Path(
    os.environ.get("AGENTS_SECTIONS_DIR", Path(__file__).resolve().parent / "sections")
)


def detect_google3() -> bool:
    return "/google/src/cloud/" in os.getcwd()


def detect_cloudtop() -> bool:
    return socket.getfqdn().endswith(".c.googlers.com")


def detect_nix() -> bool:
    return shutil.which("nix") is not None


def read_section(name: str) -> str:
    path = SECTIONS_DIR / name
    if not path.exists():
        print(f"Warning: section {name} not found at {path}", file=sys.stderr)
        return ""
    return path.read_text()


def assemble(agent: str, google3: bool, cloudtop: bool) -> str:
    parts = [read_section("base.md")]

    if agent == "claude":
        parts.append(read_section("lsp.md"))

    if google3:
        parts.append(read_section("google3.md"))
    else:
        parts.append(read_section("tools.md"))

    if detect_nix():
        parts.append(read_section("nix.md"))

    if cloudtop:
        parts.append(read_section("cloudtop.md"))

    return "\n".join(part for part in parts if part)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--agent",
        required=True,
        choices=["claude", "gemini"],
        help="Target agent",
    )
    parser.add_argument(
        "--google3",
        action="store_true",
        default=None,
        help="Force google3 mode (auto-detected from $PWD if omitted)",
    )
    parser.add_argument(
        "--cloudtop",
        action="store_true",
        default=None,
        help="Force cloudtop mode (auto-detected from hostname if omitted)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write to file instead of stdout",
    )
    args = parser.parse_args()

    google3 = args.google3 if args.google3 is not None else detect_google3()
    cloudtop = args.cloudtop if args.cloudtop is not None else detect_cloudtop()

    result = assemble(args.agent, google3, cloudtop)

    if args.output:
        args.output.write_text(result)
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
