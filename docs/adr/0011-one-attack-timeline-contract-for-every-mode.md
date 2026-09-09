---
id: 0011
title: One attack timeline contract for every mode — resolve up front, gate at land time, never re-plan
status: accepted
date: 2026-08-20
deciders: owner+agent
supersedes: []
superseded-by: null
sources:
  - "#488"
  - "#511"
  - "#536"
  - "docs/domain/attack-timeline.md"
tags: [combat, attacks, architecture, timing]
---

# ADR 0011 — One attack timeline contract for every mode

> **Backfilled 2026-09-07** from `docs/domain/attack-timeline.md`, which recorded
> this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

Melee, magic and ranged each answered *"when does this happen"* in their own code
path. Every new question — an on-hit effect, an ammo type, a fourth mode — meant
re-deriving the answer three times and getting three subtly different ones. The
#488 discussion was that re-derivation happening once too often.

The specific thing that has to be pinned down is what world state each part of an
attack reads, and at which moment. A volley is not instantaneous: an early landing
can kill a node, force-deallocate an islanded arm, and change what a later landing
of the *same attack* arrives at.

## Decision

**One contract, which all three modes fulfil, stated as an invariant:**

> Resolution emits candidate landings in time order. One applier walks them in that
> order and re-evaluates each landing's gate against live state before applying it.

Two halves, both load-bearing:

- **Resolution is up front**, producing an `AttackOutcome` — the candidate set and
  the attacker-side arithmetic, settled once at launch.
- **Application is staged and live.** Each landing's gate — *is this target still
  allocated, still hostile, is this blade vertex still alive* — is re-checked at
  the moment the landing applies, not when it was planned.

**The gate is a veto, not a re-plan.** A landing that fails is dropped.
Application never *discovers new targets*: that would make resolution a lie and
break the preview. Re-aiming a wasted shot at another live target is explicitly
out — it is the one shape of this feature that breaks the contract.

The rule this yields: **kill state resolved at wave N is visible to every
expansion from wave N onward.**

## Consequences

- **A fourth mode, an on-hit effect or an ammo type becomes spec-satisfying**
  rather than archaeology across three code paths. That is the entire return.
- **`resolve()` stopped being pure (#536)** without breaking the contract. It now
  lands into the `CombatWorld` it was handed; what makes it safe as a preview, as
  AI scoring input and as #458's wire payload is not that it mutates nothing, but
  that what it mutates is a throwaway shadow.
- **A failed gate needs a per-mode visual answer, because the failure shapes
  differ** — melee has no concept of a dud (hit-scan either hits or does not);
  magic cannot fail a gate at all (candidates are queried live per wave); ranged is
  the only mode where the gate can fail *after* the visual has committed, so its
  arrow lands inert as a dud beat.
- **This is explicitly the AUTHORITY's timeline (#511).** A peer receives an
  `AttackRecord` and replays its deltas through the same applier loop; it re-runs
  no gate and computes no combat number, because it cannot — mitigation is
  node-local, an earlier beat's cascade changes what a later beat lands on, and a
  target may sit under fog it knows nothing about. That asymmetry is
  [ADR 0002](0002-host-authoritative-sync-not-lockstep.md)'s, applied here.

## Alternatives considered

### Resolve everything up front and apply it unconditionally

The simplest timeline: whatever `resolve()` said, happens. Rejected because it
contradicts the fiction the modes are built on — a blade sweeping across an arm it
already severed would still trigger the `SpikeAddon`s of dead nodes, and a
propagating bolt could bounce back into the corpse it just made. *You don't disarm
someone and then get shot by the gun falling to the floor.*

### Re-plan at land time — re-aim a wasted landing at another live target

Tempting, and the most "intelligent-looking" behaviour. Rejected outright: it makes
the arming preview a lie, since what the player was shown is no longer what
happens. The gate is a veto for exactly this reason.

### Let each mode keep its own timeline, and document the three

The status quo. It lost on the cost of every subsequent question — three answers to
maintain, and no way to tell an intentional difference from a divergence that crept
in.
