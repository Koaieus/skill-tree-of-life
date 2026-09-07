---
id: 0001
title: ADRs record decisions; domain docs record behaviour
status: accepted
date: 2026-09-07
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "docs/domain/adr.md"
  - "docs/domain/breadcrules.md"
  - "docs/FOCUS.md"
tags: [meta, documentation]
---

# ADR 0001 — ADRs record decisions; domain docs record behaviour

## Context

By September 2026 this repo recorded engineering decisions in three places, none
of which was designed to hold them:

1. **GitHub issue comments.** `CLAUDE.md` says outright that *"the comments
   usually hold the decisions"*, and `issue-workflow.md` builds a whole
   attribution discipline on top of that. Issues are excellent provenance and
   terrible retrieval — finding a settled call means knowing which of 750+ issues
   it was settled on.
2. **`docs/domain/*.md`.** These describe how a system works, but the important
   ones had grown a decision layer on top. `multiplayer-sync-model.md` opens with
   *"Decided 2026-08-18 in #473. Re-opened by the owner 2026-08-22, measured by
   #529, and re-decided unchanged on 2026-08-24"*, and carries a `### Rejected:
   lockstep on the shared seed` section whose explicit purpose is to stop the
   decision being re-litigated a fourth time. That is an ADR wearing a domain-doc
   costume.
3. **`.claude/rules/*.md`.** Breadcrules point at decisions but cannot hold them —
   they are one line, by construction, and always-on context is taxed by the byte.

Two forces made this actively costly rather than merely untidy.

**Decisions were being re-argued.** The sync model was decided, re-opened,
measured and re-decided across six days. The doc that came out of it has to spend
a section explaining which arguments are *dead* so that nobody picks one up
again. That is the cost of having no place to write "we considered this and here
is why it lost, permanently."

**Mutable documents rot in a specific, documented way.** `docs/FOCUS.md` was
rewritten twice for the same cause, and diagnosed itself in the file: *"per-issue
prose is irresistible to append to and invisible to prune."* The second rewrite
cut 353 lines to one page after finding 81 references that read as live work but
had shipped. Any new prose tier put in a mutable document inherits that failure.

The forcing question was asked directly of the owner on 2026-09-07: should ADRs
*replace* the decision history currently living inside domain docs, or sit
alongside it?

> **Owner call 2026-09-07:** *"all three options speak to me. amount of work is
> no issue, i want what's cleanest going forward."*

## Decision

**Add `docs/adr/` as a fourth, immutable tier, and make the boundary between it
and `docs/domain/` total: ADRs hold *why*, domain docs hold *what*.**

- An ADR answers **why we chose this over that, on this date, knowing what we
  knew.** Past tense, dated, attributed.
- A domain doc answers **how the system works now.** Present tense, edited in
  place, always current, and it *links* the ADRs behind it rather than restating
  them.
- An ADR is **written once and never edited.** When the decision changes, a new
  ADR supersedes it; the old one keeps its original text, because the Context
  section of a decision you later reversed is the most valuable part of the
  record.
- The only edit an accepted ADR ever receives is the two frontmatter fields that
  mark it superseded.

The discriminating test for any candidate: **does a future agent need this to
avoid re-arguing a settled call?**

Given "cleanest going forward", the split is a **migration, not just a new
tier** — decision prose already sitting in domain docs moves out, per page,
mechanically. `mise run adr-hygiene` reports the remaining pages, so the
migration is a number that goes to zero rather than an intention.

Three things make the tier self-maintaining rather than aspirational, on the
grounds that FOCUS.md's rot was survivable-by-checker and had no checker:

- **`mise run adr-hygiene`** — the same report-and-fix-nothing contract as
  `rules-hygiene` and `gh-project hygiene`.
- **A one-line always-on breadcrule** at `.claude/rules/adr.md`, so every agent
  stumbles on the tier's existence without paying for its body.
- **A read-only librarian subagent** that answers "has this been decided?" with a
  citation, and that deliberately **cannot write ADRs**.

## Consequences

**What this buys.**

- A settled call has an address. "See ADR 0002" replaces re-deriving an argument
  from a 900-line domain doc, which is what an agent under context pressure will
  not do.
- The rejected alternatives get a permanent home, with their *grounds* attached —
  including grounds that have since died. That is the specific artefact that stops
  a fourth re-litigation.
- Domain docs get shorter and stay current, because the part of them that was
  historical no longer needs maintaining in place.
- The knowledge survives a wrong decision. A superseded ADR explains why the
  current shape looks the way it does, which nothing else in the repo does.

**What it costs.**

- **A fourth home is a fourth place to look**, and the boundary must be enforced
  or this becomes the parallel mirror it was created to remove. The boundary test
  is one sentence and `adr-hygiene` reports drift; that is the whole mitigation,
  and it is a real ongoing cost.
- **A migration.** Every domain doc carrying decision prose needs a per-page pass.
  Half-migrated pages are worse than unmigrated ones, so the pass is per-page and
  atomic.
- **Discipline at write time.** An immutable record only works if people supersede
  instead of editing. The hygiene check flags substantive commits to accepted
  ADRs, but it cannot force the habit.
- **One more always-on line** in the context budget. Held to a breadcrule, and
  `rules-hygiene` polices the tier's total.

**What it does not change.** Issues remain authoritative for status and for the
conversation. `docs/design/` remains the home of game design. ADRs are engineering
only.

## Alternatives considered

### Sit alongside, with no migration

Add `docs/adr/` for *new* decisions and leave every existing domain doc exactly as
it is. Cheapest by far, zero risk of a half-done migration, and the boundary rule
still gets written.

**Why it lost:** it guarantees a permanent two-model period. An agent asking "was
this decided?" would have to check the ADR index *and* grep the domain docs, and
the answer to "where does decision prose live" would be "both, depending on age"
— which is precisely the parallel-mirror failure the repo already has a standing
rule against. The owner's *"amount of work is no issue, i want what's cleanest
going forward"* removes the only argument this option had.

### Alongside now, migrate opportunistically

Same as above, but the boundary rule says: when you next edit a domain doc's
decision prose, extract it to an ADR then.

**Why it lost:** gradual migrations tied to unrelated edits have no end date and
no visibility. The pages least likely to be edited are the settled ones, which are
exactly the pages whose decision prose is most valuable to extract. It converts a
bounded task into an unbounded half-state, and the number never reaches zero
because nobody is counting.

### No ADRs — put decisions in issue comments only, and index them better

Issues already hold the decisions and the attribution discipline already exists.
A label plus a saved query could serve as the index.

**Why it lost:** an issue is a conversation, and the verdict is buried in it —
often several comments deep, often after a reversal, often alongside arguments
that did not survive. Retrieval requires reading the whole thread and judging
which comment won, which is expensive and error-prone under exactly the context
pressure that makes an agent skip it. Issues also close, and a closed issue reads
as finished history rather than as a live constraint. **The issue stays the
provenance; what was missing was the extracted verdict.**

### Extend `docs/domain/` with a convention — a `## Decisions` section per doc

No new directory, no new tier, no migration. Each domain doc grows a section that
holds its own decision history.

**Why it lost:** the section is inside a mutable document, so it inherits the
FOCUS.md failure mode wholesale — appended to freely, pruned never, and edited in
place when a decision reverses, which destroys the record of what was originally
decided and why. It also cannot express a decision that spans several docs, and
supersession has nowhere to live. Immutability is the load-bearing property here,
and a section of a living document cannot have it.

### A heavier format — MADR, or ADRs with review workflow

MADR's template adds decision drivers, per-option pros/cons tables and a
confirmation section. A review workflow would add a `proposed` → review → accepted
gate.

**Why it lost:** the review gate already exists and is called `/swarmify` — an
issue in `Needs design` gets its forks settled with the owner and is promoted to
`Ready`. A second gate would compete with it. And plain Nygard —
Context / Decision / Consequences / Alternatives — is the smallest format that
still carries *Alternatives considered*, which is the section that earns the tier
in this repo. Everything MADR adds beyond that is ceremony that would be filled in
badly or not at all.
