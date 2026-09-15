---
description: a skill/agent instruction file is derived from its charter in docs/charters/ — change the charter, then re-derive; the file cites no incidents or issue numbers
paths:
  - ".claude/skills/**"
  - ".claude/agents/**"
---
A `.claude/skills/<name>/SKILL.md` or `.claude/agents/<name>.md` is the *build*; `docs/charters/<name>.md` is the *source* — laws numbered, cost model, incident corpus, what the file must not contain. Change the wish in the charter, then re-derive the file; never patch a lesson into the file and leave the charter stale, and never put issue numbers, incidents or reasoning-behind in the file. See docs/charters/README.md
