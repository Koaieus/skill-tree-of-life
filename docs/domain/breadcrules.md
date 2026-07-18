# Breadcrules

*breadcrumb × rule* — a **one-line always-on rule that points to a fuller doc.**

A breadcrule is the smallest useful rule: a single line that costs almost no
context, findable by any agent, whose only job is to say *"there's more to this
than meets the eye — the full story is over there."* Interested agents follow the
crumb and get everything they need; uninterested agents skip one line instead of
wading through a page they didn't want.

**A breadcrule is its own rule *file*, not a line bolted into `CLAUDE.md`.** The
file *is* the breadcrumb rule — its content doesn't announce itself with a
literal `Breadcrule:` label; it's simply the tiny hint plus a "read more" crumb.
Create `.claude/rules/<topic>.md` whose entire body is the one line, with **no
`paths:` frontmatter** (no frontmatter at all) — that absence is exactly what
makes it always-on. Keeping each breadcrule a separate file keeps `CLAUDE.md`
itself lean and lets a stale crumb be deleted or re-scoped without touching the
seed. Don't paste the line into `CLAUDE.md`.

```
# .claude/rules/<topic>.md  — entire file, no frontmatter, no "Breadcrule:" label:
<the one-line claim / pointer>. See docs/domain/<topic>.md
```

## Why: the always-on tier costs context every turn

Rules load in two tiers, and the difference is the whole point:

| Tier | How | Cost |
|---|---|---|
| **Always-on** | global `~/.claude/rules/*.md`, or a project `.claude/rules/*.md` with **no `paths:`** | injected into **every** turn of **every** session — pure context tax whether or not it's relevant |
| **Scoped** | a project `.claude/rules/*.md` with a `paths:` glob | injected **only** when a file matching the glob is in play |

An always-on rule is paid for by every agent on every task. A long one is a long
tax. So the always-on tier should hold **only** what every agent benefits from
seeing unprompted — and it should hold it in as few tokens as possible. That's
the breadcrule: keep the always-on footprint to one discoverable line, and push
the body into a doc that only the interested agent pays to read.

The failure mode a breadcrule fixes: an invested agent writes a thorough,
correct, 300-line rule with no `paths:`. It's now always-on. Every future agent —
most of whom will never touch that subsystem — carries all 300 lines forever.
The knowledge was good; the *placement* taxed everyone.

## Where knowledge goes — the tiering

This extends the "Knowledge accumulation" taxonomy in `CLAUDE.md`; it doesn't
replace it. From cheapest-to-carry to richest:

1. **Inline gotcha** (<200 tokens) — belongs *inside* an existing rule file, under
   the section it qualifies. Lead with the rule, then **Why:** / **How to apply:**.
2. **Scoped rule** — a `.claude/rules/<module>.md` with a `paths:` glob naming the
   files it guards. Full length is fine here: it's only loaded when those files
   are touched, so length is paid for by the agent who's actually in that code.
   **This is the default home for a substantial, file-specific lesson.**
3. **Breadcrule + doc** — when the pointer genuinely belongs in the *always-on*
   tier (every agent should know the crumb exists, or the target isn't a single
   file a `paths:` glob can name), write one always-on line and put the body in
   `docs/domain/<topic>.md`.
4. **Full doc** — `docs/domain/<topic>.md` on its own, referenced from the
   relevant rule/CLAUDE.md, for multi-page engineering knowledge.

**Reach for a scoped rule before a breadcrule.** If the lesson is about specific
files, `paths:` scoping is strictly better than an always-on line — it's free
when irrelevant *and* fires automatically when relevant, no crumb-following
required. A breadcrule earns its always-on slot only when the trigger isn't a
tidy set of file paths, or when the mere existence of the topic is something
every agent should stumble on.

## The `paths:` scoping mechanism

Rule files carry YAML frontmatter:

```yaml
---
description: one-line summary — used to decide relevance
paths:
  - "systems/turn_manager.gd"
  - "entity/controller/**"
---
```

- `paths:` globs are **repo-relative** (no leading `/`): `test/**`,
  `stats_system/defs/*.tres`. Brace expansion works: `src/**/*.{ts,tsx}`.
- A rule with `paths:` loads **only** when a matching file is *read* — path-scoped
  rules "trigger when Claude reads files matching the pattern, not on every tool
  use." A rule with **no** `paths:` (or no frontmatter at all) is **always-on**,
  same priority as `.claude/CLAUDE.md`.
- `description:` is what an agent reads to decide whether the rule is relevant, so
  make it a real summary, not a title.

> **Scoping fires on *read*, so it can't catch a from-scratch author.** A brand-new
> rule written straight through the Write tool is never read first, so a rule
> scoped to `.claude/rules/*.md` won't have fired to advise the author. *Editing*
> an existing rule reads it first, so it fires there. This is why the always-on
> `CLAUDE.md` seed (not the scoped rule alone) is what carries the "keep it small /
> consider a breadcrule" lesson to the first-time author.
>
> **Dot-directory globs:** the dot-segment exclusion that stops `*`/`**` from
> matching names beginning with `.` only applies to **wildcard** segments. Spell
> the dot-directory **literally** (`.claude/rules/*.md`) and it matches fine — only
> the `*.md` filename part is a wildcard, and that filename has no leading dot.
> Don't rely on a bare `**` to *descend into* a dotdir; name the dot-segment
> yourself. A `paths:` glob that never matches is a silent no-op — no rule, no
> error — so if you scope somewhere unusual, confirm it fires (`/context`, or the
> `InstructionsLoaded` hook). See `.claude/rules/godot-workflow.md` for the house
> allergy to exactly this class of silent-nothing bug.

## Writing a good breadcrule

The line does two things: **state the claim** (so an agent knows whether to care)
and **point to the payload** (so a caring agent can dive). Both, in one line.

- **Bad:** `see docs/domain/foo.md` — no claim; every agent has to open the doc
  just to learn it's irrelevant. That's the spam the breadcrule was supposed to
  avoid.
- **Bad:** a full paragraph — that's just an always-on rule wearing a hat.
- **Good:** `node HP is stored on the addon, not the SkillNode — reads through
  the carrier lie. See docs/domain/node-hp.md` — the claim alone saves an
  uninterested agent the click, and hooks an interested one.

Same small-rule discipline as everywhere else: **lead with the rule.** The
difference is only *length* and *placement* — a breadcrule is a rule compressed
until only the hook and the crumb remain.
