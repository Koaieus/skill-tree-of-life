---
description: Writing a rule or CLAUDE.md entry — keep the always-on tier tiny; scope with paths:, or leave a Breadcrule
paths:
  - ".claude/rules/*.md"
  - "CLAUDE.md"
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
- **Extension globs work** — `paths: ["**/*.tscn"]` matches, verified by probe
  (2026-08-03). Directory prefixes (`graph/**`) are convention, not a constraint,
  so a gotcha tied to a *file format* should be scoped to that format rather than
  to a list of directories that happens to contain it.
- **A gotcha you got bitten by that was already in the doc is a CRUMB bug, not a
  doc bug.** You didn't open the doc because the crumb didn't tell you to. Fix the
  crumb's trigger wording — name the failure mode, not the topic — and don't add a
  paragraph to the doc that nobody was going to reach either.
- Run **`mise run rules-hygiene`** whenever you touch this tier. It reports
  over-budget always-on rules, docs-wearing-a-rule's-hat, dead crumbs, stale
  references, and **dead globs** — a `paths:` matching zero files makes a rule that
  silently never loads, which nothing else can catch.
- Lead with the rule, then **Why:** / **How to apply:**. Small-rule discipline is
  in `CLAUDE.md` → *Knowledge accumulation*.

## You are carrying this payload, so you may cut it

A rule is not a diary. Every line you add is loaded into future agents who are
working on something else, and the agent writing a rule is the one worst placed
to judge it: fresh from hours on one problem, maximum recency bias, and it never
pays the cost — every *later* session does. So the incentive is broken by
construction, and the correction has to be a habit, not good intentions.

**When you open a rule to add to it, you have also opened it to cut.** You have
the source in one hand and the rule in the other; you are, right now, the best-
qualified reader that file will get. Use it:

- **Delete what's stale or wrong.** A rule describing code that moved is worse
  than no rule — it actively misleads.
- **Delete what's now obvious**, enforced by a test, or apparent from the code.
- **Cut the narrative.** War stories, "we tried X then Y", and debugging
  chronology are the doc's job. The rule keeps the claim and the fix.
- **Compress.** A paragraph that survives as one sentence should be one sentence.
- **Demote by size.** A rule past ~150 lines has stopped being a rule and become
  a doc wearing a rule's hat. Move the body to `docs/domain/<topic>.md`, leave the
  gotchas. If it's *also* always-on, leave a breadcrule.

**Adding "just one paragraph" is the failure mode**, because it's true every
time and it compounds. Treat a rule like a fixed budget: if your paragraph earns
its place, something else can lose its place. Land net-neutral or smaller unless
the addition genuinely outweighs what's there.

Ask the deciding question honestly: *will an agent who is not me, working on
something else, be better off carrying this?* Rules exist for the 99% who never
hit your bug — not for the one who just did.

Full tiering (inline gotcha → scoped rule → breadcrule+doc → doc), the `paths:`
mechanism, and how to write the crumb: **`docs/domain/breadcrules.md`**.
