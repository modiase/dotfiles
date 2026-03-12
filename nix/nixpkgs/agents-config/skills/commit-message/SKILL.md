---
name: commit-message
description: Write git commit messages. Use when committing changes or drafting commit messages.
---

# Commit Messages

## Title

`scope: verb-phrase`

- **Lowercase**, no trailing period, imperative mood
- Scope = affected component or area (e.g. `nvim`, `ding`, `infra`, `claude-code/gemini`)
- Keep short — if scope + verb are self-evident, nothing more is needed: `fish: make gpf safer`

## Body

Not every commit needs a body. Omit it when the title and diff are self-explanatory.

When present:

1. **Open with the problem or motivation** — why, not what
2. **Describe what changed** — factual, concise, no diff restatement
3. **State trade-offs** explicitly when the change has known downsides
4. **Format**: prose for single-concept changes, bullets for multi-point changes

## Style

- British English (`summarise`, `behaviour`, `modularise`)
- Em dashes (—) not hyphens for parenthetical clauses
- No emoji, no self-referential language ("this commit", "I", "we")
- Technical but not verbose — assume the reader knows the codebase

## Anti-patterns

- Restating the diff: ~~"Change X from A to B"~~ → explain *why* X needed changing
- Filler words: ~~"This commit updates the configuration to..."~~ → `config: update ...`
- Scope-less titles: ~~"Fix bug"~~ → `ding: fix bell on Linux`
- Body when unnecessary: a rename or one-liner doesn't need three paragraphs

## Examples

```
ding: replace ntfy with OSC 9 for remote notifications

Agent hooks previously detected SSH and routed notifications through a 5-hop
chain (ntfy-me → Pub/Sub → ntfy server → ntfy-listen → ding). OSC 9 escape
sequences travel back through the existing terminal connection, making this
infrastructure unnecessary for interactive sessions.

Trade-off: notifications are lost when tmux is detached or SSH drops mid-task.
Acceptable since agents run interactively and results are visible on reattach.
```

```
nvim: fix pane selection

Fix a bug where the select pane functionality 'reaches across' windows. This
means if a plan completes in another window it opens in a neovim in the active
window even if it's not the appropriate window.
```

```
fish: make gpf safer
```

```
infra: add amex-otp lambda
```
