---
id: 0002
title: Host-authoritative intent-up / confirmed-command-down, not lockstep on a shared seed
status: accepted
date: 2026-08-24
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#473"
  - "#463"
  - "#529"
  - "#521"
  - "#534"
  - "#540"
  - "docs/domain/multiplayer-sync-model.md"
tags: [multiplayer, netcode, architecture]
---

# ADR 0002 — Host-authoritative intent-up / confirmed-command-down, not lockstep on a shared seed

> **Backfilled 2026-09-07** from `docs/domain/multiplayer-sync-model.md`, which
> recorded this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> decision date above is the date of the call, not of this file. The domain doc
> remains authoritative for **how the model works**; this record holds **why it
> was chosen and what lost**.

## Context

The game needed a networked model to hang every multiplayer and hot-seat feature
off, ahead of the `LAN 2026-09-04` milestone. Two credible models: **lockstep on
a shared seed** (every peer derives the same world from the same inputs) and
**host-authoritative record-down** (one peer decides, everyone else applies what
it says).

The decision was made **2026-08-18 in #473**, **re-opened by the owner on
2026-08-22**, **measured by #529**, and **re-decided unchanged on 2026-08-24** —
on entirely different grounds. The conclusion did not move; every premise did.
That six-day loop is the reason this record exists in the form it does.

Four facts about the codebase framed the choice:

1. **The mutation surface is ~9 verbs**, not the whole input controller —
   `allocate`, `deallocate`, `deallocate_set`, `stake`, `extract`, `move_core`,
   `launch_attack`, `apply_armed_temp_upgrade_to`, `end_turn`, plus loot picks.
   Every one is synchronous, gated, and already wire-shaped. A small, explicit
   mutation surface is exactly what a command model wants.
2. **Mutation was entangled with animation, and #504 had just fixed that** —
   damage used to land inside an `await` on the VFX. That fix is a prerequisite
   under *every* model, so it did not discriminate, but it is what made either
   model possible at all.
3. **Combat is nearly RNG-free, but not entirely** — three real sources: crit RNG
   with a `randomize()` fallback, unseeded global `Array.shuffle()` in the loot
   system and dust addon, and the same null-RNG fallback in `random_pick_step`.
4. **The AI is frame-shaped** — it awaits real timers between decisions. Its
   *decisions* are deterministic; its *timing* is not.

And one fact about the players, which turned out to decide it:

> **Owner, 2026-08-24**, on whether a mixed lobby was likely: *"Yes —
> Windows/Linux mix likely."*

## Decision

**Host-authoritative, intent-up / confirmed-command-down.**

One peer — the host — decides everything. A client sends an *intent*. The host
validates it, broadcasts the *confirmed command* plus a resolved payload for
anything the client cannot recompute, and **then** applies it. Every peer, the
host included, applies world changes through the same applier and through the
same *post-confirmation* half of it, so the authority is never structurally a
mutation window ahead of the peers it is telling.

> **Owner call 2026-08-24:** *"getting that whole list of things cross platform
> deterministic would take more time than i'd now want to spend on that, this
> game doesn't do that much crazy stuff, nor a lot of commands (1 at a time with
> massive margins before and after mostly)"*

Single-player and hot-seat are not special cases: they run the same path over a
loopback transport, so offline play continuously exercises the networked path.

The rule that falls out of this, and which is carried as an always-on breadcrule:
**a peer either *receives* a result or *reproduces* it — never both, and the list
of things it receives is longer than it looks.** Command references, unseeded
rolls, transcendentals and the turn cursor alike: a mirror never opens its own
turn.

## Consequences

- **Cross-platform floating point stops being a correctness problem.** A peer
  re-simulating the melee blade does so only to *draw* it; every damage number
  and the hit set itself come off the `AttackRecord`. The same 1-ulp difference
  that would be a desync under lockstep is invisible here.
- **The unseeded rolls became legal.** Host-only rolls are exempt because the
  *result* crosses the wire. That retired a whole class of would-be cleanup work.
- **A client is always at least one round trip behind on its own action.** The
  confirm sits between validate and apply for every verb without exception —
  #540, finished by #545. The earlier `validate → apply → broadcast` shape was
  filed for deletion as #534 precisely because it put the host a mutation window
  ahead.
- **Drift has no self-correcting mechanism**, so a repair had to be added
  separately: the resync backstop, settled in #521 and built in #560/#561, for
  the one bug class this model cannot notice — a client's number crept wrong and
  nothing will ever catch it.
- **Hidden information is social, not enforced.** Every peer holds the full world
  and the UI declines to draw what fog does not cover. The owner's framing was
  *"socially real now, structured so this is reachable"*.
- **Event sourcing comes free if ever wanted** — the confirmed-command stream
  *is* the event log.

## Alternatives considered

### Lockstep on the shared seed

Every peer derives the same world from the same inputs and the same seed; only
inputs cross the wire. Re-opened by the owner on 2026-08-22 as *lockstep +
snapshot recovery with the host still refereeing*, and measured by #529 before
being rejected again.

**The three original (2026-08-18) grounds for rejecting it are all dead. Do not
re-use them:**

1. *"There is no authority at all."* Aimed at pure P2P lockstep; the 2026-08-22
   proposal kept the host refereeing. **Dead.**
2. *The unseeded `Array.shuffle()` calls.* Host-only rolls are exempt under the
   chosen model. **Dead.**
3. *Hidden information / fog.* **Withdrawn by the owner on the record** in #463's
   2026-08-24 comment: fog withholds *derived* state, which is compatible with
   full replication of the lower tiers. **Dead as stated** — ground B below is a
   different claim at a different layer, not this one returning.

**What #529 measured, and what it did not.** Two clean sweeps — 773 commands,
then 478 — with zero divergences. Real, and narrower than it reads: both were
taken on **one machine, one binary, one libm**. They measure *pipeline order*,
not floating-point portability. The question that decides this model cannot be
asked on a single machine, which is why a clean probe did not carry the decision.

**The live grounds, as of 2026-08-24:**

**A. Cross-platform libm, unfixable by discipline.** IEEE 754 specifies
`+ - * / sqrt` to be correctly rounded and specifies **nothing** about `sin`,
`cos`, `tan`, `exp`, `log`, `pow`. Every platform ships its own approximation and
they disagree in the last bits. The blade arc driver uses `Vector2.from_angle`
and `cos`, the XPBD sim integrates those positions over dozens of substeps, and
the hitscan sorts by the result — so a 1-ulp difference flips two hits' order.
Under record-down that is cosmetic. Under lockstep it decides **who gets hit**.
Only fixed-point or deleting the trig would prevent it, and neither is worth a
LAN date. **A mixed Windows/Linux lobby was confirmed likely by the owner**,
which is what makes this ground bite rather than remain theoretical.

**B. Lockstep is contradictory with partial information — not merely awkward.**
Lockstep's defining property is that every peer derives the same result from the
same inputs; deny a peer an input and it cannot derive. The owner's own case:

> **Owner, 2026-08-24:** *"health bars of damaged nodes which are persistently
> shown and have a current + max ... max is a derivation of the entity stats x
> node-local stats, which **is information you might not have** yet these should
> not be question marks but real and correct values"*

### Full state replication / snapshots

The host serialises the world and ships it.

**Why it lost:** the largest model change on the table, for no gameplay gain. No
`StatBoard` wire format exists, `Stat._modifiers` is memory-only,
`EffectInstance` grant-ledgers carry no provenance for revocation, and addons are
dynamically-spawned children. Then it is 2000 nodes × boards × addons per sync.
Its one genuine upside is that the serialiser *is* save/load (#23) — but that is
a separate, parked feature, and buying it here to get versus is backwards.

### Fog-filtered state deltas — deferred, not rejected

The host sends each client only what its `InfoLevel` permits: the only model
where hidden information is *technically* enforced.

**Why not now:** it needs the same `StatBoard` wire format full replication needs.
**This is the intended destination and the chosen model is aimed at it** — because
the host already owns every decision and clients never mutate directly, moving
here later swaps *what gets broadcast* (confirmed command → filtered delta) behind
one seam, without touching input, AI, or the systems.

### Event sourcing — not a separate option

Effectively the chosen model plus persistence. The confirmed-command stream *is*
the event log; there is nothing extra to design.
