---
name: adding-skills
description: How to add skills for Claude Code. Use when creating new skill files.
---

# Adding Skills

## Global Skills (all projects)

1. Create `nix/nixpkgs/agents-config/skills/<name>/SKILL.md`
2. Register in `agents-config/default.nix`:
   ```nix
   home.file.".agents/skills/<name>/SKILL.md".source = ./skills/<name>/SKILL.md;
   ```
3. Deployed via home-manager to `~/.agents/skills/` then symlinked to `~/.claude/skills/`

## Project Skills (single repo)

1. Create `.agents/skills/<name>/SKILL.md` at the repo root
2. Loaded automatically by Claude when working in that project

## Skill Format

```markdown
---
name: my-skill
description: When to use this skill. Shown in skill listings.
allowed-tools: [Bash, Read]  # optional: restrict available tools
---

# Skill Title

Markdown body with instructions, examples, and context.
```

The YAML frontmatter requires `name` and `description`. The `allowed-tools` field is optional and restricts which tools the skill can use.
