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

## Activation and Deployment

When asked use `bin/activate` to apply configuration changes. Do **not** call
`darwin-rebuild`, `nixos-rebuild`, or `home-manager` directly; the script
handles sequencing, logging, core counts, and sudo prompts. If you are asked to
investigate an activate failure the logs on MacOS are found at
~/Library/Logs/dotfiles-activate.log.
MANDATORY: you must never call bin/activate without being explicitly asked to.

### Commands

| Command                      | Description                                                             |
| ---------------------------- | ----------------------------------------------------------------------- |
| `bin/activate`               | Activate current repo state on local machine                            |
| `bin/activate deploy`        | Deploy origin/main to localhost via worktree                            |
| `bin/activate deploy <host>` | Deploy origin/main to remote host via SSH                               |
| `bin/activate deploy all`    | Deploy to all hosts with `dotfiles.manageRemotely = true`               |
| `bin/activate show`          | Show activation status (hashes for origin/main, worktree, system, home) |
| `bin/activate show <host>`   | Show activation status on remote host                                   |

### Options

- `-l LEVEL` - Log level: 1=errors, 2=normal (default), 3=verbose, 4+=debug
- `-c CORES` - Max cores for parallel builds (default: ncpu - 1)
- `-t TIMEOUT` - Lock timeout in minutes (default: 30)

### When to Use Each

- **`bin/activate`** - Local development: test changes from your working tree immediately
- **`bin/activate deploy`** - Production: deploy committed, pushed changes from origin/main
- **`bin/activate deploy hestia`** - Deploy to a specific remote host (e.g., hestia)
- **`bin/activate deploy all`** - Batch update all managed hosts in parallel

### Important

- **Do NOT commit or deploy unless explicitly instructed** - only run `git commit`, `bin/activate`, or `bin/activate deploy` when the user asks for it

### Notes

- `deploy` and `show` commands use a git worktree at `worktrees/main` to ensure they run from the latest origin/main
- Treat this repository as source-only automation—build, lint, or test inside the activate shell, but avoid out-of-band host mutations

## Hekate (Locked-Down VPN Gateway)

Hekate is a Raspberry Pi 4 configured as a hardened WireGuard VPN gateway with minimal attack surface. It has special restrictions that differ from other hosts:

### What You Cannot Do

- **Cannot SSH interactively** - `ForceCommand` restricts all SSH sessions to the dashboard TUI only
- **Cannot deploy remotely** - `bin/activate deploy hekate` will NOT work
- **Cannot inspect system state** - No shell access means no `journalctl`, `systemctl status`, etc.
- **Cannot run arbitrary commands** - The system is intentionally locked down

### How to Deploy Changes

1. Build the SD card image locally: `nix build .#nixosConfigurations.hekate.config.system.build.sdImage`
2. Flash the image to an SD card
3. Insert the SD card into hekate and boot

### Debugging Approach

Since you cannot inspect hekate directly:
- **Reason from configuration** - Trace through Nix modules to understand behaviour
- **Test locally when possible** - Use `nix-instantiate` or `nix eval` to check configuration
- **Ask the user** - They may have physical access or alternative methods
- **Never suggest SSH commands** - They will not work

### Key Architecture Details

- Uses sops-nix for secrets with age key derived from device serial number
- Age key generated during NixOS activation (not systemd service) to `/etc/age/key.txt`
- WireGuard private key decrypted by sops-nix during activation
- Dashboard accessible via SSH with ForceCommand (TUI only)

## HTTP Requests

**Prefer HTTPie over curl** for HTTP requests. HTTPie provides human-friendly syntax, automatic JSON handling, and persistent sessions.

### Why HTTPie

- **Sessions** - Persist authentication, headers, and cookies across requests
- **Built-in auth** - `-A bearer -a TOKEN` for bearer auth, `-a user:pass` for basic auth
- **Intuitive syntax** - `key=value` for JSON body, `key:value` for headers
- **Automatic JSON** - Detects and pretty-prints JSON responses with syntax highlighting
- **Cleaner output** - Colourised, formatted responses readable at a glance

### Authentication

Use `-A` (auth-type) and `-a` (auth) flags for clean authentication:

```bash
# Bearer token auth (preferred for APIs)
http -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/states

# Basic auth
http -a "user:password" GET api.example.com/resource

# With session (auth persists across requests)
http --session=hestia -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/
http --session=hestia GET http://hestia.local/hass/api/states
```

### Common Patterns

```bash
# JSON POST with automatic Content-Type
http POST api.example.com/data name=value count:=42

# Headers use colon, JSON uses equals
http GET api.example.com X-Custom-Header:value

# Use --ignore-stdin when not piping data (avoids hangs)
http --ignore-stdin GET api.example.com/data

# Pipe JSON body
echo '{"key": "value"}' | http POST api.example.com/data

# Download file
http --download GET example.com/file.zip
```

### When to Use curl

Use curl only when HTTPie is unavailable or for specific features like:
- Binary uploads with precise control
- HTTP/2 or HTTP/3 specific testing
- Low-level protocol debugging

## Secrets Management

Use the `secrets` CLI to access credentials. It provides a consistent interface across platforms (macOS Keychain, Linux pass, GCP Secret Manager).

### Commands

| Command                             | Description                                    |
| ----------------------------------- | ---------------------------------------------- |
| `secrets get <name>`                | Retrieve a secret (copies to clipboard)        |
| `secrets get <name> --print`        | Print to stdout instead of clipboard           |
| `secrets get <name> --network`      | Force fetch from GCP Secret Manager            |
| `secrets get <name> --read-through` | Check local first, fall back to network        |
| `secrets get <name> --update-local` | Sync network secret to local if different      |
| `secrets get <name> --optional`     | Don't error if not found                       |
| `secrets store <name> <value>`      | Store a secret locally                         |
| `secrets store <name> --network`    | Store a secret in GCP Secret Manager           |
| `secrets list`                      | List local secrets                             |
| `secrets list --all`                | List from both local and network               |
| `secrets delete <name>`             | Delete a secret                                |
| `secrets delete undo`               | Restore last deleted secret                    |
| `secrets log`                       | Show operation history                         |

### Common Secrets

- `hestia-hass-api-access` - Home Assistant API token
- `ntfy-basic-auth-password` - ntfy.sh authentication
- `EXA_API_KEY` - Exa search API
- API tokens typically named `<service>-token` or `<service>-api-key`

### Usage in Scripts

```bash
# For scripts, use --print to get stdout output
http --ignore-stdin -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/states
```

### Usage with HTTPie Sessions

Sessions cache authentication at creation time. Recreate when tokens change:

```bash
# Create/recreate HASS session
rm -rf ~/.config/httpie/sessions/hestia.local
http --session=hass -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/

# Subsequent requests reuse stored auth
http --session=hass GET http://hestia.local/hass/api/states
```

**Note:** If you get 401 errors with an existing session, the cached token may be stale. Delete the session directory and recreate.

## Research Before Implementation

- **Consult official documentation first** - identify ALL required fields before starting
- **Never guess** - if unclear, search for clarification
- **State only what's documented** - avoid assumptions and hallucinations
- **Read errors completely** - they often specify exactly what's missing
- **Be precise in claims** - say "documentation states" not "might be"

## Configuration Best Practices

- **Research defaults first** - before writing any configuration, look up the default values from official documentation or source code. Only specify values that differ from defaults. Strenuously avoid restating defaults unless there is good reason to pin them (e.g., the default may change in future versions and you need stability).
- **Extract shared config** into variables when used multiple times
- **Inline single-use variables** - except when they aid readability
- **Avoid redundant comments** - document only non-obvious behavior (workarounds, complex logic, hidden dependencies)
- **NEVER add obvious comments** - do not explain what standard shell commands do (e.g., "# Fetch secrets", "# Generate configuration")
- **PRESERVE identifying labels** - keep comments that identify resources by name when the name cannot be inferred from context (e.g., "# iris", "# pegasus" for peer configurations)
- **PRESERVE security warnings** - keep comments that explain critical security decisions or non-obvious security implications (e.g., "!!! KEY SECURITY: Embed WireGuard key in initrd, NOT the Nix store !!!")
- **PRESERVE structural comments in HTML/templates** - comments that delineate sections of a template (e.g., `<!-- Start handle -->`, `<!-- Navigation -->`) aid readability and are acceptable

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

- **CRITICAL: `set -e` and `[[ ]] &&` pattern** - When using `set -e`, a bare `[[ condition ]] && cmd` returns exit code 1 if the condition is false, causing script termination. Fix with:

  ```bash
  # WRONG: exits with code 1 if LOG_LEVEL < 4 under set -e
  [[ ${LOG_LEVEL:-2} -ge 4 ]] && set -x

  # CORRECT: use if statement
  if [[ ${LOG_LEVEL:-2} -ge 4 ]]; then set -x; fi

  # CORRECT: add || true fallback
  [[ ${LOG_LEVEL:-2} -ge 4 ]] && set -x || true
  ```

  This is especially dangerous for:

  - Top-level code executed when sourcing files
  - Last statements in functions (function returns non-zero)

## Nix Shell Packages

- **Prefer separate script files** over inline scripts in `default.nix` so they can be properly linted by shellcheck
- **Structure**: Create `script-name.sh` alongside `default.nix`, then read it in Nix:
  ```nix
  writeShellApplication {
    name = "my-script";
    runtimeInputs = [ ... ];
    text = builtins.readFile ./my-script.sh;
  }
  ```
- **Exception**: Only inline trivial scripts (< 10 lines) when explicitly requested

## NixOS Systemd Services

### Users and Permissions

- **Prefer `DynamicUser = true`** for better security isolation
- **Set config paths via environment**: `Environment = "XDG_CONFIG_HOME=%S/my-service"` (`%S` = StateDirectory)
- **Use `ReadWritePaths`/`ReadOnlyPaths`** to control filesystem access
- **Only create static users** when DynamicUser won't work (e.g., stable UIDs for NFS, pre-existing directories)

### State Management

- **Use `StateDirectory`** for persistent state - works seamlessly with DynamicUser
- **Use `CacheDirectory`** for ephemeral cache data
- **Use `tmpfiles.rules`** only when StateDirectory is insufficient

### GCP Secrets on GCE VMs

- **Use gcloud directly** - the metadata service provides automatic authentication
- **No pre-auth needed** - any user can access secrets via the VM's service account
- **Secrets are JSON-wrapped** - unwrap with `| jq -r '.value'`
- **Pattern**:
  ```nix
  gcloud = "${pkgs.google-cloud-sdk}/bin/gcloud";
  gcpProject = "modiase-infra";
  getSecret = name:
    "${gcloud} secrets versions access latest --secret=${name} --project=${gcpProject} | jq -r '.value'";
  ```

### Service Scripts

- **Use `writeShellApplication`** with `runtimeInputs` for dependency management
- **Use full paths** (`${pkgs.foo}/bin/foo`) in scripts for reproducibility
- **Service ordering**: Use `after`, `wants`, `before`, `requires` appropriately

## Python Style

- **Prefer immutable types**:
  - `tuple` over `list` for function returns and parameters
  - `Mapping` over `dict` for read-only dict parameters
  - `@dataclass(frozen=True)` for data containers
- **Mark constants with `Final`**: Use `from typing import Final` and annotate module-level constants as `CONSTANT: Final = value`
- **Benefits**: Prevents accidental mutation, enables hashing, clearer intent, type checkers catch reassignment

## Fish Functions

- **Do NOT include function wrapper** - home-manager's `programs.fish.functions` automatically wraps the body
- **Files in `fish/functions/` should contain ONLY the function body**, not `function name ... end`
- Example - for a function `gst`, the file `fish/functions/gst.fish` should contain just: `git status $argv`
- **Avoid eval** - build commands as arrays and execute directly:

  ```fish
  set -l cmd mycommand
  test -n "$SOME_VAR"; and set -a cmd --some-flag
  $cmd $argv
  ```

## Language

- **Use British English spelling** - e.g., "summarise" not "summarize", "colour" not "color", "organisation" not "organization"

## Core Principles

- **Be Precise**: State facts from documentation, not assumptions
- **Be Thorough**: Research complete solution before acting
- **Be Efficient**: Learn patterns to anticipate issues rather than discover through trial-and-error

## Planning Requirements

When creating implementation plans, you MUST include an explicit cleanup step at the end:

1. **Final step: "Run pre-commit checks and clean up per AGENTS.md"** - Every plan must end with verification
2. **Apply code quality guidelines** - Review changes against Shell Scripting Style, Configuration Best Practices, etc.
3. **Verify no regressions** - Ensure fixes don't introduce new issues (e.g., `set -e` compatibility)

## **COMPLIANCE VERIFICATION**

You MUST follow the guidelines for code quality and make additional clean up changes.
This MUST be followed for every and all instructions unless no code changes have been made since the last clean up.

**Comment cleanup pass**: After implementing changes, take an extra pass specifically to identify and remove obvious comments. Comments may help during implementation but should be removed before finalising. Only keep comments that explain non-obvious behaviour, workarounds, or security implications. **This instruction MUST be highlighted in any compaction or summarisation of this file.**

When compacting code, you MUST emit this statement:

```
🔄 Re-reading AGENTS.md before compacting to ensure guideline compliance.
```
