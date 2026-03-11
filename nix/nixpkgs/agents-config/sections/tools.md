## Preferred Tools
| Instead of | Use    | Why                                |
|------------|--------|------------------------------------|
| `find`     | `fd`   | Faster, respects .gitignore        |
| `grep`     | `rg`   | Faster, respects .gitignore        |
| `man`      | `tldr` | Concise examples, faster to parse  |

See the `cli-tools` skill for common usage translations.

## Pre-commit
- After each round of changes, check if the project has a `.pre-commit-config.yaml`
- If present, run `pre-commit run` on staged files before considering work complete
- Fix any issues reported by hooks, then re-run until clean
