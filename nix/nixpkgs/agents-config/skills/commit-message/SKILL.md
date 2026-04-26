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
- **Aim for ≤50 characters; 72 is a hard limit.** If you can't fit the change in 72 chars, the scope is wrong or the commit is doing too much — split it
- Imperative mood test: the title should complete the sentence "If applied, this commit will \_\_\_"

## Body

Not every commit needs a body. Omit it when the title and diff are self-explanatory.

When present:

1. **Separate from the title with a single blank line**
2. **Wrap at 72 characters** so `git log` renders cleanly in an 80-col terminal (URLs and code blocks excepted)
3. **Open with the problem or motivation** — why, not what
4. **Describe what changed** — factual, concise, no diff restatement
5. **State trade-offs** explicitly when the change has known downsides
6. **Format**: prose for single-concept changes, bullets for multi-point changes
7. **Reference issues/commits by hash or ID** when relevant — don't paraphrase their content

## Style

- British English (`summarise`, `behaviour`, `modularise`)
- Em dashes (—) not hyphens for parenthetical clauses
- No emoji, no self-referential language ("this commit", "I", "we")
- Technical but not verbose — assume the reader knows the codebase

## Anti-patterns

- Restating the diff: ~~"Change X from A to B"~~ → explain _why_ X needed changing
- Filler words: ~~"This commit updates the configuration to..."~~ → `config: update ...`
- Scope-less titles: ~~"Fix bug"~~ → `ding: fix bell on Linux`
- Body when unnecessary: a rename or one-liner doesn't need three paragraphs
- Past/present tense: ~~"fixed"~~ / ~~"fixes"~~ → `fix`
- Overflowing the title: if the verb-phrase needs >50 chars, the body should carry the detail
- Walls of unwrapped prose: a 400-character single line in the body wrecks `git log` output

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
