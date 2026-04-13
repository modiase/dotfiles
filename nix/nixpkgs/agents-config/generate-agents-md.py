#!/usr/bin/env python3
"""Assemble AGENTS.md from sections based on agent type and conditions."""

import argparse
import re
import sys
from pathlib import Path
from typing import Final

try:
    from devlogs import setup_logging

    log = setup_logging("generate-agents-md")
except ImportError:
    import logging

    log = logging.getLogger("generate-agents-md")
    log.addHandler(logging.NullHandler())


DEFAULT_PRIORITY: Final = 50
DEFAULT_AGENTS: Final = ("claude", "gemini")


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Parse YAML-like frontmatter delimited by --- lines.

    Returns (metadata dict, body text).
    """
    if not text.startswith("---"):
        return {}, text

    end = text.find("\n---", 3)
    if end == -1:
        return {}, text

    header = text[4:end]
    body = text[end + 4 :].lstrip("\n")
    meta: dict = {}
    for line in header.splitlines():
        line = line.strip()
        if not line:
            continue
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()

        if key == "priority":
            meta[key] = int(val)
        elif key == "agents":
            meta[key] = re.findall(r"\w+", val)
        elif key == "conditions":
            meta[key] = {}
        else:
            # Indented key under conditions
            pass

    # Second pass for conditions (indented key: value under conditions:)
    in_conditions = False
    for line in header.splitlines():
        stripped = line.strip()
        if stripped.startswith("conditions"):
            in_conditions = True
            continue
        if in_conditions and line.startswith("  ") and ":" in stripped:
            k, _, v = stripped.partition(":")
            meta.setdefault("conditions", {})[k.strip()] = v.strip().lower()
        elif not line.startswith(" "):
            in_conditions = False

    return meta, body


def load_sections(dirs: list[Path]) -> list[tuple[str, dict, str]]:
    """Load all .md files from given directories."""
    sections = []
    seen = set()
    for d in dirs:
        if not d.is_dir():
            log.warning("sections dir not found: %s", d)
            continue
        for f in sorted(d.glob("*.md")):
            if f.name in seen:
                log.debug("skipping duplicate %s from %s", f.name, d)
                continue
            seen.add(f.name)
            text = f.read_text()
            meta, body = parse_frontmatter(text)
            log.debug(
                "loaded %s: priority=%d agents=%s conditions=%s",
                f.name,
                meta.get("priority", DEFAULT_PRIORITY),
                meta.get("agents", list(DEFAULT_AGENTS)),
                meta.get("conditions", {}),
            )
            sections.append((f.name, meta, body))
    return sections


def matches_conditions(
    section_conditions: dict[str, str], passed_conditions: dict[str, str]
) -> bool:
    """Check if all section conditions match the passed condition values.

    Conditions not passed are treated as false.
    """
    for name, required in section_conditions.items():
        actual = passed_conditions.get(name, "false")
        if actual != required:
            return False
    return True


def assemble(
    agent: str,
    conditions: dict[str, str],
    section_dirs: list[Path],
) -> str:
    sections = load_sections(section_dirs)
    filtered = []
    for name, meta, body in sections:
        agents = meta.get("agents", list(DEFAULT_AGENTS))
        if agent not in agents:
            log.debug("excluded %s: agent %s not in %s", name, agent, agents)
            continue
        sect_conditions = meta.get("conditions", {})
        if not matches_conditions(sect_conditions, conditions):
            log.debug(
                "excluded %s: conditions %s vs %s",
                name,
                sect_conditions,
                conditions,
            )
            continue
        priority = meta.get("priority", DEFAULT_PRIORITY)
        filtered.append((priority, name, body))

    filtered.sort(key=lambda x: (x[0], x[1]))
    log.debug("assembly order: %s", [(name, pri) for pri, name, _ in filtered])
    return "\n".join(body for _, _, body in filtered if body)


def parse_condition(s: str) -> tuple[str, str]:
    if "=" not in s:
        raise argparse.ArgumentTypeError(f"condition must be name=value, got: {s}")
    k, _, v = s.partition("=")
    return k.strip(), v.strip().lower()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--agent",
        required=True,
        choices=["claude", "gemini"],
        help="Target agent",
    )
    parser.add_argument(
        "--condition",
        action="append",
        type=parse_condition,
        default=[],
        dest="conditions",
        metavar="NAME=VALUE",
        help="Pre-evaluated condition (repeatable)",
    )
    parser.add_argument(
        "--extra-sections-dir",
        action="append",
        type=Path,
        default=[],
        dest="extra_dirs",
        metavar="DIR",
        help="Additional sections directory (repeatable)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write to file instead of stdout",
    )
    args = parser.parse_args()

    conditions = dict(args.conditions)
    sections_dir = Path(
        __import__("os").environ.get(
            "AGENTS_SECTIONS_DIR",
            str(Path(__file__).resolve().parent / "sections"),
        )
    )
    section_dirs = [sections_dir] + args.extra_dirs

    result = assemble(args.agent, conditions, section_dirs)

    tmp = Path(f"/tmp/agents-md-{args.agent}.md")
    tmp.write_text(result)
    log.debug("wrote agents.md output to %s", tmp)

    if args.output:
        args.output.write_text(result)
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
