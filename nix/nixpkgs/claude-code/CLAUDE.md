# Code Quality Guidelines

## Mandatory Review
After EVERY round of changes, review your work against these guidelines before finalising.

## Context Maintenance
- After conversation compaction, re-read any `CLAUDE.md` and `AGENTS.md` files in the repo
- Periodically reconsider repo-specific rules to ensure continued compliance
- When in doubt about conventions, check these files rather than assuming

## Comments
- Comments may be used during implementation to track ideas and intent
- During code quality review (after each round of changes), **remove all obvious comments**
- **ONLY keep comments that explain**: workarounds, non-obvious behaviour, security implications
- **PRESERVE identifying labels** when names can't be inferred from context

### Examples

```bash
# BAD: Obvious comments
# Fetch the user data
user_data=$(curl "$url")
# Check if successful
if [[ $? -eq 0 ]]; then
    # Parse the JSON response
    name=$(echo "$user_data" | jq -r '.name')
fi

# GOOD: No obvious comments, only non-obvious behaviour documented
user_data=$(curl "$url")
if [[ $? -eq 0 ]]; then
    # jq returns "null" string (not empty) for missing keys
    name=$(echo "$user_data" | jq -r '.name // empty')
fi
```

```nix
# BAD: Comment states the obvious
# Enable fish shell
programs.fish.enable = true;

# GOOD: Comment explains WHY (non-obvious)
# Required for proper TERM handling in tmux
programs.fish.interactiveShellInit = "set -gx TERM xterm-256color";
```

## Shell Scripting Style

### Prefer `&&` chaining over if/else
```bash
# BAD: Verbose if/else
if [[ "$condition" ]]; then
    do_something
else
    fallback_action
fi

# GOOD: Chain with && and early return
[[ "$condition" ]] && do_something && return
fallback_action
```

### Use conditional assignment
```bash
# BAD: if/else for variable assignment
if [[ "$condition" ]]; then
    local output="$alternate"
else
    local output="$default"
fi

# GOOD: Conditional assignment
local output="$default"
[[ "$condition" ]] && output="$alternate"
```

### CRITICAL: `set -e` with `[[ ]] &&`
When using `set -e`, a bare `[[ condition ]] && cmd` exits with code 1 if false.

```bash
# WRONG: Script exits if LOG_LEVEL < 4
set -e
[[ ${LOG_LEVEL:-2} -ge 4 ]] && set -x

# CORRECT: Use if statement
if [[ ${LOG_LEVEL:-2} -ge 4 ]]; then set -x; fi

# CORRECT: Add || true fallback
[[ ${LOG_LEVEL:-2} -ge 4 ]] && set -x || true
```

## Configuration Best Practices
- **Research defaults first** - only specify values that differ
- **Extract shared config** into variables when used 2+ times
- **Inline single-use variables** - except when aiding readability

## Language
- Use **British English** spelling (summarise, colour, organisation)

## Pre-commit
- After each round of changes, check if the project has a `.pre-commit-config.yaml`
- If present, run `pre-commit run` on staged files before considering work complete
- Fix any issues reported by hooks, then re-run until clean

## Git Commits
- **NEVER commit to main** unless explicitly instructed
- Exception: when working on a separate Claude-authored branch, commits are permitted
- When in doubt, wait for user approval before committing

## Adhoc Files
- Prefer outputting to /tmp when writing or running code that produces
adhoc outputs. - Examples to be mindful of are the outputs of nix-build -E,
tables, json files and images.
- This should be the default unless another obvious target is presenet
(output/data directory) or you are explicitly otherwise instructed.

## Preferred Tools
| Instead of | Use | Why |
|------------|-----|-----|
| `find` | `fd` | Faster, respects .gitignore (less noise) |
| `grep` | `rg` | Faster, respects .gitignore (less noise) |

## Core Principles
- **Be Precise**: State facts, not assumptions
- **Be Thorough**: Research completely before acting
- **Be Efficient**: Anticipate issues rather than discover through trial-and-error
