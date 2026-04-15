---
priority: 95
---

## Definition of Done

A task is complete ONLY when ALL applicable checks pass:

1. Changed nix files parse cleanly (`nix-instantiate --parse <file>`)
2. If nix code was changed: `nix-build` succeeds for the affected derivation (not the entire flake)
3. If shell scripts were changed: `shellcheck` reports no violations in modified files
4. Comment cleanup pass completed per Code Quality Guidelines
5. All changes are staged with `git add -u` + explicit `git add` for new files
6. `git diff --cached` reviewed — no secrets, debug prints, or unrelated changes

Do NOT report completion until these are verified. If a check fails after 3 fix attempts, report the failure and ask for guidance rather than looping.
