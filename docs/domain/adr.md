# Architecture Decision Records

**An ADR answers *why we chose this over that, on this date, knowing what we
knew*. It is written once and never edited.** When the decision changes, a new
ADR supersedes it; the old one stays exactly as it was, because the record of a
decision you later reversed is the most useful record you have.

Records live in [`docs/adr/`](../adr/), indexed by [`docs/adr/index.md`](../adr/index.md),
checked by `mise run adr-hygiene`.

Start with **[ADR 0001](../adr/0001-adrs-record-decisions-domain-docs-record-behaviour.md)** —
the ADR that establishes ADRs, and the worked example of the format.

---

## The boundary — which of the four homes does this belong in?

This repo already had three places a decision could land before ADRs existed, so
the boundary has to be sharp or the fourth becomes a parallel mirror of the other
three. The discriminating question:

> **Does a future agent need this to avoid re-arguing a settled call?**
> Yes → ADR. It only needs to know how the thing behaves today → domain doc.

| Home | Answers | Tense | Mutability |
|---|---|---|---|
| **`docs/adr/`** | *why we chose this over that, and what we rejected* | past — "on 2026-08-24 we decided" | **immutable**; superseded, never edited |
| **`docs/domain/`** | *how the system works now* | present — "the host validates, then confirms" | edited in place, always current |
| **GitHub issue** | *the conversation, the owner's call, and where the work stands* | live | live |
| **`.claude/rules/`** | *the one line an agent must not miss* | imperative | edited freely; a stale rule is worse than none |

**The issue is the provenance; the ADR is the extracted verdict.** Writing the
ADR does not close the issue or make it less authoritative — an ADR without a
`sources:` pointer back at the conversation that produced it is missing its
evidence.

### Domain docs are present-tense — that is the whole split

**Owner call 2026-09-07:** *"all three options speak to me. amount of work is no
issue, i want what's cleanest going forward."*

The cleanest end state is that a `docs/domain/` page describes **current
behaviour only**, and every "we decided X on date D, and here is why not Y" passage
in it has moved to an ADR that the page links. That is a real migration and it is
tracked — `mise run adr-hygiene` reports every domain doc still carrying decision
prose, so the migration has a number that goes to zero rather than a vibe.

Until a page is migrated, its decision prose remains authoritative. **The
migration is per-page and mechanical; do not half-migrate a page.**

### What is *not* an ADR

- **A choice with no rejected alternative.** If there was nothing to weigh, there
  is nothing to re-argue, and the domain doc suffices.
- **A bug fix**, however clever. The commit is the record.
- **A design decision about the game** — melee model, spell identity, class
  balance. Those are `docs/design/` and issues. ADRs are engineering: how the
  code is shaped, not what the game is.
- **Something still being argued.** That is an issue in `Needs design`. An ADR
  can be written as `proposed` to *frame* the fork, but the repo's design gate is
  `/swarmify`, not an ADR review — prefer the issue.

---

## Writing one

Filename: `docs/adr/NNNN-kebab-slug.md`, `NNNN` zero-padded, allocated by taking
the highest existing number and adding one. Never renumber and never reuse.

```markdown
---
id: 0007
title: One sentence naming the decision, not the topic
status: accepted            # proposed | accepted | superseded | rejected
date: 2026-09-07            # when the DECISION was made — not when the file was written
deciders: owner             # owner | owner+agent | agent
supersedes: []              # ids this replaces, e.g. [0002]
superseded-by: null         # id that replaced this, once one does
sources:                    # provenance — issues, commits, docs. Never empty.
  - "#473"
  - "docs/domain/multiplayer-sync-model.md"
tags: [multiplayer, netcode]
---

# ADR 0007 — <title>

## Context
What was true, and what forced a choice. The constraints as they were **at the
time** — including the ones that have since evaporated. This is the section that
makes a superseded ADR worth keeping.

## Decision
The call, in the imperative, in as few words as it takes. Quote the owner
verbatim and dated where they made it.

## Consequences
What this buys and what it costs — both, honestly. What it makes hard. What
downstream work it implies.

## Alternatives considered
**The section that earns the format here.** One subsection per rejected option:
what it was, and why it lost. Where a ground for rejection has since been
retired, say so and say it is dead — the whole failure mode this prevents is an
agent picking up a dead argument and re-running a settled decision on it.
```

### The title is the decision, not the topic

*"Host-authoritative sync, not lockstep on a shared seed"* — you can act on that
without opening the file. *"Multiplayer sync"* is a topic and tells you nothing.

### Attribute the owner, verbatim, dated

Same rule as issues, for the same reason: agents resolve contradictions by
authority, and a decision written up as an agent's own conclusion re-enters the
record at the bottom of that ladder. **Owner call 2026-08-24:** *"…"* — quote,
date, label. See [issue-workflow](issue-workflow.md) → *Attribute owner decisions
to the owner*.

---

## Superseding one

Never edit an accepted ADR to say something different. Instead:

1. Write the new ADR with `supersedes: [NNNN]`.
2. On the old one, set `status: superseded` and `superseded-by: MMMM`. **These
   two frontmatter fields are the only edit an accepted ADR ever receives.**
3. Add the new row to `docs/adr/index.md`.

`adr-hygiene` checks the link resolves in both directions, so a half-done
supersede is caught rather than leaving two live ADRs that contradict each other.

**A superseded ADR is not deleted and not hidden.** It is the reason the current
decision looks the way it does, and its *Context* section is the record of
constraints that no longer apply — which is exactly what someone proposing to go
back needs to read first.

---

## Hygiene

```
mise run adr-hygiene              # report; fixes nothing
mise run adr-hygiene -- --json    # machine-readable
mise run adr-hygiene -- --strict  # non-zero exit on any hard violation
```

Same contract as `rules-hygiene` and `gh-project hygiene`: **it reports and fixes
nothing.** Hard checks — frontmatter shape, id/filename agreement, status
vocabulary, supersede links resolving both ways, the index having exactly one row
per record and no orphans. Advisory checks — an `accepted` ADR that received
substantive commits after its acceptance date (an immutability breach), and
domain docs still carrying decision prose (the migration counter).

**Mechanical beats aspirational.** `docs/FOCUS.md` has been rewritten twice for
rot that a checker would have caught on day three; this tier gets its checker on
day one.

---

## The agent surface

`.claude/agents/adr-librarian.md` is a read-only Sonnet subagent for *"has this
already been decided?"*. Ask it before designing something that smells settled;
it answers with a citation or an honest no, and it will flag a domain doc that
contradicts an ADR.

**It does not write ADRs.** Authorship stays with the agent that made the
decision alongside the owner, because a librarian writing the record is exactly
the laundering of an owner call that `issue-workflow.md` forbids. The librarian
will hand you a *drafted body* to review, attribute and commit yourself.

---

## Why immutable — the specific failure this prevents

`docs/FOCUS.md` was rewritten twice, both times for the same cause, stated in the
file itself: **per-issue prose in a mutable document is "irresistible to append to
and invisible to prune."** It regrew to 353 lines in twelve days, and 81 of the 89
issues it described as live had already closed.

An append-only record set cannot fail that way. Nobody appends to a document that
is closed; a wrong ADR is visibly superseded rather than quietly edited into
something that no longer matches what was decided or why. Immutability here is not
ceremony — it is the one structural property that makes the tier maintenance-free.
