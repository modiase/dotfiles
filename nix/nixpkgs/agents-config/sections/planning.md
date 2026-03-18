---
priority: 85
agents: [gemini]
---

## Planning

When creating or presenting a plan:

- **State what will NOT be done** as clearly as what will be done. Explicit exclusions prevent scope creep and misunderstanding.
- **Flag ambiguities before planning**: If the user's request could be interpreted multiple ways, resolve the ambiguity first. Do not plan around an assumption — ask.
- **Each plan item must be concrete**: Specify the file, function, or component affected. Avoid vague items like "update the configuration" — say what changes and why.
- **End every plan-mode turn with one of two actions**: either ask a clarifying question (if ambiguity remains), or write the plan to the designated plan file using `write_file`. Do not present a plan in chat without also saving it — the plan file is how the user reviews and approves your proposal.
