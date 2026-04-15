---
priority: 15
---

## When Blocked

- If a command fails after 3 attempts with the same error: stop and report the full error output. Do not try creative workarounds.
- If a dependency is missing: check flake.nix/package files first, then ask the user.
- If merge conflicts occur: stop and show the conflicting sections. Do not resolve automatically.
- If tests fail and the fix is not obvious after 2 attempts: report what you've tried and ask for guidance.
- If you are unsure whether an action is destructive: ask before proceeding.

- If you notice yourself repeating the same action (edit, undo, re-edit) or producing the same error: stop immediately, describe the loop, and ask for guidance.

**Never**: delete files to resolve errors, force push, skip tests, disable linters, or bypass pre-commit hooks.
