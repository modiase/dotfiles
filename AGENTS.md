# Agent Guidelines for Effective System Configuration

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

## Deployment Efficiency

- **Research completely before deploying** - avoid deploy-error-fix-redeploy cycles (currently at 191!)
- **Validate locally when possible** before remote deployment
- **Check service logs** to confirm actual success
- **Batch related changes** into single deployments
- **Trace root causes** - symptoms mislead; find actual problems

## Core Principles

- **Be Precise**: State facts from documentation, not assumptions
- **Be Thorough**: Research complete solution before acting
- **Be Efficient**: Learn patterns to anticipate issues rather than discover through trial-and-error
