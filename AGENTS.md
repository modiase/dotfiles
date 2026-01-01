# Agent Guidelines for Effective System Configuration

## **MANDATORY REQUIREMENTS**

**CRITICAL: These instructions are MANDATORY and must be followed without exception:**

1. **Read AGENTS.md after EVERY round of changes** - You MUST re-read this file after completing any set of modifications to ensure continued compliance
2. **Apply guidelines before finalizing** - Every change must be reviewed against these guidelines before completion
3. **No exceptions permitted** - These are not suggestions but requirements that must be enforced

**When compacting or refactoring code, you MUST:**

- Re-read AGENTS.md completely before making any changes
- Apply ALL guidelines during the compacting process
- Verify compliance after completion

## Existing Workflow Notes

- Use `bin/activate` to apply configuration changes. It automatically selects the right rebuild tool (e.g. `darwin-rebuild`, `nixos-rebuild`, `home-manager`) with the correct flags.
- Do **not** call `darwin-rebuild`, `nixos-rebuild`, or `home-manager` directly; the script handles sequencing, logging, core counts, and sudo prompts for you.
- Before running, ensure the expected deploy key is available so the helper can access remote builders/hosts if needed.
- Treat this repository as source-only automation—build, lint, or test inside the activate shell, but avoid out-of-band host mutations.

## Research Before Implementation

- **Consult official documentation first** - identify ALL required fields before starting
- **Never guess** - if unclear, search for clarification
- **State only what's documented** - avoid assumptions and hallucinations
- **Read errors completely** - they often specify exactly what's missing
- **Be precise in claims** - say "documentation states" not "might be"

## Configuration Best Practices

- **Research defaults first** - only specify values that differ from defaults
- **Extract shared config** into variables when used multiple times
- **Inline single-use variables** - except when they aid readability
- **Avoid redundant comments** - document only non-obvious behavior (workarounds, complex logic, hidden dependencies)
- **NEVER add obvious comments** - do not explain what standard shell commands do (e.g., "# Fetch secrets", "# Generate configuration")
- **PRESERVE identifying labels** - keep comments that identify resources by name when the name cannot be inferred from context (e.g., "# iris", "# pegasus" for peer configurations)
- **PRESERVE security warnings** - keep comments that explain critical security decisions or non-obvious security implications (e.g., "!!! KEY SECURITY: Embed WireGuard key in initrd, NOT the Nix store !!!")

## Deployment Efficiency

- **Research completely before deploying** - avoid deploy-error-fix-redeploy cycles (currently at 191!)
- **Validate locally when possible** before remote deployment
- **Check service logs** to confirm actual success
- **Batch related changes** into single deployments
- **Trace root causes** - symptoms mislead; find actual problems

## Pre-commit Checks

- Default: run `pre-commit run` (checks only staged files). Stage your edits before running to lint exactly what will be committed.
- If you need to lint without staging: run `pre-commit run --files $(git diff --name-only)` to check only your working changes.
- When `.pre-commit-config.yaml` changes or after adding new hooks: run `pre-commit run --all-files` (aka `-a`) once to baseline the repo, then revert to the default flow above.
- Address all issues reported by hooks, then re-run the relevant `pre-commit run` until clean.
- Run checks inside the activate shell when applicable to ensure the correct environment.
- Do not bypass or disable hooks; fix code to satisfy them unless explicitly instructed otherwise.

## Shell Scripting Style

- **Prefer `&&` chaining over if/else** for simple conditionals:
  ```bash
  # Good: chain with && and early return
  [[ "$condition" ]] && do_something && return
  fallback_action

  # Avoid: verbose if/else
  if [[ "$condition" ]]; then
      do_something
  else
      fallback_action
  fi
  ```
- **Use conditional assignment** instead of if/else for variable values:
  ```bash
  # Good
  local output="$default"
  [[ "$condition" ]] && output="$alternate"

  # Avoid
  if [[ "$condition" ]]; then
      local output="$alternate"
  else
      local output="$default"
  fi
  ```

## Fish Functions

- **Do NOT include function wrapper** - home-manager's `programs.fish.functions` automatically wraps the body
- **Files in `fish/functions/` should contain ONLY the function body**, not `function name ... end`
- Example - for a function `gst`, the file `fish/functions/gst.fish` should contain just: `git status $argv`
- **Prefer command construction over if/else** - build commands with `set` and execute with `eval`:
  ```fish
  # Good: construct command, then eval
  set -l cmd mycommand
  test -n "$SOME_VAR"; and set -a cmd --some-flag
  eval $cmd $argv

  # Avoid: if/else branching
  if test -n "$SOME_VAR"
      mycommand --some-flag $argv
  else
      mycommand $argv
  end
  ```

## Language

- **Use British English spelling** - e.g., "summarise" not "summarize", "colour" not "color", "organisation" not "organization"

## Core Principles

- **Be Precise**: State facts from documentation, not assumptions
- **Be Thorough**: Research complete solution before acting
- **Be Efficient**: Learn patterns to anticipate issues rather than discover through trial-and-error

## **COMPLIANCE VERIFICATION**

After reading AGENTS.md, you MUST emit this exact statement:

```
Cleaning up per code quality guidelines...
```

You MUST follow the guidlines for code quality and make additional clean up changes.
This MUST be followed for every and all instructions unless no code changes have been made since the last clean up.

When compacting code, you MUST emit this statement:

```
🔄 Re-reading AGENTS.md before compacting to ensure guideline compliance.
```
