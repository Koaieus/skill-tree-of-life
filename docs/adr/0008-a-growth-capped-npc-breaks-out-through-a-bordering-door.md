---
id: 0008
title: A growth-capped NPC breaks out through a bordering door, at every AI tier
status: accepted
date: 2026-08-26
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#604"
  - "docs/domain/dormant-core.md"
tags: [ai, dormant-core, allocation, balance]
---

# ADR 0008 — A growth-capped NPC breaks out through a bordering door

> **Backfilled 2026-09-07** from `docs/domain/dormant-core.md`, which recorded
> this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

A Dormant Core authors `targeted_by_ai = false` on its `Faction`, so NPCs treat
one as scenery and never spend AP on it. That filter has an edge case with teeth:
an NPC whose territory is walled in entirely by things it refuses to look at is
**growth-capped** — it has no unowned node adjacent to its territory, so it banks
SP forever and its turn does nothing. Visibly stuck, for the rest of the run.

The fix had to answer two questions that are separable, and both were put to the
owner on 2026-08-26.

1. **Which cores does being stuck unlock?** The naive answer is "all of them".
2. **How hard does the unlocked door compete?** Making a core merely *targetable*
   only helps when it is the only thing in sight. A capped NPC that also sees a
   real hostile scores both on raw EV, the distant enemy wins, and the wall beside
   it is never hit — the same stuck complaint in a different costume. A LARGE core
   (high HP, no kill bonus available) loses that comparison every turn forever.

## Decision

**Being growth-capped unlocks, for that turn only, the cores that border the
capped entity's territory — and a bordering target is scored so far above ordinary
EV that a capped NPC is door-first at every `ai_tier`.**

**Bordering, not global.** The wall is adjacent by definition; a core further out
only becomes reachable once a node beside it is allocated, which a capped entity
cannot do anyway.

> **Owner call 2026-08-26:** *"beware that if surrounded by friendlies, there is
> no door available"*

That is the case the border test exists for: an entity capped by its own allies
has nothing to break through, and without the test it would unlock some core
across the map and spend AP opening a door it cannot walk through.

**Door-first at every tier.** `AiCombatScorer` carries a breakout bonus of
`_BREAKOUT_WEIGHT` (500) on any target that `borders_territory()` while
`ai_growth_capped`. It is ungated by `ai_tier` — like the kill bonus, being stuck
is not a tactical subtlety a naive brain is allowed to miss — and it is
deliberately **not** ordered against the tier terms (cut-vertex 25/tier,
weak-point 5/tier, 75 at most). At 500 it outranks all of them. **Owner call
2026-08-26**, weighing exactly that: being unable to grow is existential, where
those terms are refinements for winning a fight you can already fight.

It sits *below* `_KILL_BONUS` on a non-door target, since a kill that is right
there is still worth taking and the next AP re-evaluates back onto the door.

## Consequences

- **The tier layer keeps its meaning *among* doors.** Every door carries the same
  +500, so cut-vertex / weak-point preference still decides *which* door — the
  bonus flattens the choice between door and not-door, not between doors.
- **The rule is not blocker-specific, and that is the point.** Depleting a node
  force-deallocates it, so any bordering node is a door; a capped NPC walled in by
  a real camp punches through it on exactly the same reasoning.
- **One predicate, two readers.** `borders_territory()` drives both the unlock and
  the scoring bonus, so the two can never disagree about what a door is.
- **Both consumers of `is_ai_target` must unlock** — the target list *and*
  `AiCombatScorer.expected_damage`'s per-hit filter. Unlocking only the list
  enumerates candidates that score 0 EV, so the AI would attack only cores it
  could one-shot.
- **The stance is per-turn and always assigned, never only set**, or an NPC that
  broke out once keeps shooting scenery forever after.

## Alternatives considered

### Move the filter into `Entity.attitude_to`

Express "NPCs ignore this" as an attitude relation rather than a `Faction` flag.
Rejected because a blocker stays `HOSTILE` to everyone by design — that is what
lets the *player* clear one, and what makes the forced-dealloc cascade and XP
gating treat a cleared blocker as a real kill. An attitude-level filter would
silently disarm the player too.

### Unlock every core when capped, without the border test

Simpler to state and wrong in the owner's own case above. It also spends AP on
targets that cannot become reachable. Self-limiting in practice — candidate
enumeration only ever yields in-reach targets — but "self-limiting" is not the
same as correct, and the friendly-surround case is the one that exposes it.

### Analyse *which* faction is capping the NPC

Rejected as machinery for no behavioural difference. If an NPC is walled in by
camps rather than by cores there is no adjacent core to unlock, so
frontier-empty is behaviourally identical and far simpler.

### A proximity filter on which cores unlock

Rejected as a second mechanism for a job already done: preference *among* unlocked
candidates is the breakout bonus's, and the border test has already bounded the
set to things that are adjacent.

### Gate the breakout bonus on `ai_tier`

The consistent-looking option — the tier terms are how this scorer expresses
"smarter brains see more". Rejected on the ground above: a low-tier NPC that stays
stuck forever is not a legible expression of low intelligence, it is a broken
turn.
