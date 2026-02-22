---
name: cli-tools
description: Modern CLI tool alternatives (fd, rg, tldr). Use instead of find/grep/man in Bash.
---

# Modern CLI Tools

## fd (replaces find)
- Find by name: `fd pattern`
- Find by extension: `fd -e ext`
- Find directories only: `fd --type d pattern`
- Find files only: `fd --type f pattern`
- Execute on results: `fd pattern --exec cmd {}`
- Include ignored/hidden: `fd --unrestricted pattern`
- Search specific dir: `fd pattern /path`

## rg (replaces grep)
- Search pattern: `rg pattern`
- Search in file type: `rg pattern --type py`
- Fixed string (no regex): `rg -F 'literal string'`
- With context lines: `rg -C 3 pattern`
- Files with matches only: `rg -l pattern`
- Count matches: `rg -c pattern`
- Search specific dir: `rg pattern /path`
- Multiline: `rg -U 'pattern.*\n.*continuation'`

## tldr (supplements man)
- Quick reference: `tldr command`
- Update cache: `tldr --update`

## Notes
- fd and rg respect .gitignore by default; use --unrestricted/-u to bypass
- fd uses smart case (case-insensitive unless pattern has uppercase)
- rg uses smart case with --smart-case flag (or -S)
