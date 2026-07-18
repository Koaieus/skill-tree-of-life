---
description: Writing a rule or CLAUDE.md entry — keep the always-on tier tiny; scope with paths:, or leave a Breadcrule
paths:
  - ".claude/rules/*.md"
  - "CLAUDE.md"
  - ".claude/CLAUDE.md"
---

# Writing a rule

You're reading or editing a rule / `CLAUDE.md`. Before you add a page:

- **A rule with no `paths:` is always-on** — injected into *every* turn of *every*
  session. Length there is a tax on every future agent. Add a `paths:` glob so it
  loads only when the files it guards are read. Full length is fine once scoped.
- **If it belongs in the always-on tier anyway** (every agent should know it
  exists, or it's not a tidy set of file paths), write a **Breadcrule**: one line
  that states the claim *and* points to a doc — `Breadcrule: <claim>. See
  docs/domain/<topic>.md` — and put the body in the doc.
- Lead with the rule, then **Why:** / **How to apply:**. Small-rule discipline is
  in `CLAUDE.md` → *Knowledge accumulation*.

Full tiering (inline gotcha → scoped rule → breadcrule+doc → doc), the `paths:`
mechanism, and how to write the crumb: **`docs/domain/breadcrules.md`**.
