# Agent Workflow Notes

- Use `bin/activate` to apply configuration changes. It automatically selects the right rebuild tool (e.g. `darwin-rebuild`, `nixos-rebuild`, `home-manager`) with the correct flags.
- Do **not** call `darwin-rebuild`, `nixos-rebuild`, or `home-manager` directly; the script handles sequencing, logging, core counts, and sudo prompts for you.
- Before running, ensure the expected deploy key is available so the helper can access remote builders/hosts if needed.
- Treat this repository as source-only automation—build, lint, or test inside the activate shell, but avoid out-of-band host mutations.
