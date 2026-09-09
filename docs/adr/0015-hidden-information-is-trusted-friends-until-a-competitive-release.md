---
id: 0015
title: Hidden information is trusted-friends until a competitive release; the sync model keeps machine enforcement reachable, and lockstep is closed
status: accepted
date: 2026-09-09
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#463"
  - "#796"
  - "docs/adr/0002-host-authoritative-sync-not-lockstep.md"
  - "docs/domain/multiplayer-sync-model.md"
  - "https://mas-bandwidth.com/choosing-the-right-network-model-for-your-multiplayer-game/"
tags: [multiplayer, netcode, fog, hidden-information, architecture, melee]
---

# ADR 0015 — Hidden information is trusted-friends until a competitive release

## Context

[ADR 0002](0002-host-authoritative-sync-not-lockstep.md) chose host-authoritative
record-down over lockstep and recorded the owner's framing of fog as *"socially
real now, structured so this is reachable"* — without saying **when** "reachable"
would be cashed in, or what would trigger it. That left two things open enough to
be re-argued:

1. **Lockstep came back a third time** on 2026-09-09, from the melee side: the
   authoritative blade resolve is a compute burst before the swing (#796), and
   plan-down transport — the host okays a plan, every peer runs the same
   deterministic sim, no `AttackRecord` — reads as a way to make the swing play out
   as it goes. Since 0002 was written, two of its premises moved: a join-in-progress
   snapshot now exists (#527 `GraphSnapshot`, #560 `EntitySnapshot` +
   `StatBoard.to_dict`), so a lockstep desync would have a repair path; and the
   libm ground (0002's ground A) is now *tractable with work* rather than
   unfixable — the PBD solver is `+ − × ÷ sqrt` except the arc driver's trig, whose
   few rotation constants could be shipped from the host rather than reproduced.
   Ground B (lockstep cannot work with partial information) is the one that did
   not move — and whether it *bites* depends entirely on whether machine-enforced
   hidden information is ever wanted.

2. The owner flagged the same day that their earlier calls on unfamiliar
   infrastructure topics were *"whichever option spoke to me the most"* — so an
   attributed netcode ruling should not be read as a considered constraint until it
   is tied to a **game-design** consequence the owner can judge as a designer.

This record ties the netcode choice to that design consequence, so neither has to
be re-derived from the other again.

## Decision

> **Owner, 2026-09-09:** *"iff I ever want to release this as a serious game, on
> Steam or something, with actual PvP, and a somewhat competitive scene
> (non-competitive → you'd have to be a sad person to try and hack that;
> competitive → more incentive to maphack), then machine-hidden info becomes a
> must. I'm not sure if we ever get to that point. Would be awesome though. But
> feels like a pipe dream, so thus far I'd accept trusted-friends. Also because
> I feel like grinding game content development to a halt by spending months
> building an architecture we might not need might maybe be better spent
> otherwise: assume trusted friend and when we get to it, do a massive refactor
> to hidden info — where mostly all verbs and game logic and whatnot has been
> worked out in full (cuz we still adding things or concepts day by day)."*

Three things follow, and they are the decision:

1. **Fog is trusted-friends for the foreseeable future.** Every peer holds the
   full world; the UI declines to draw what fog does not cover; nothing enforces
   it. This is a design stance, not a shortcut: the threat model (maphacking) only
   exists with a competitive scene, and a competitive scene is a release-scale
   event, not a feature.

2. **Machine-enforced hidden information stays reachable, and is bought later as
   one refactor** — after the verb set and game logic have stopped growing daily.
   The record-down model of 0002 is kept **because** it is the model that makes
   that refactor a swap of *what the host broadcasts* (confirmed command →
   fog-filtered delta) behind one seam, rather than a rewrite of the sync layer.
   The insurance that keeps it a refactor is the existing breadcrule, held as
   verbs are added: **a peer receives a result or reproduces it, and never decides.**

3. **Lockstep is closed, not merely deferred.** It fails the *reachable-later*
   half regardless of what happens to ground A: it needs every peer to hold every
   input, which is the opposite of enforced hidden information, so adopting it now
   would convert the later refactor into a second sync model. Ground A's
   determinism engineering would be paid *now*, and the door would close *now*,
   for a game that has decided it wants the door.

## Consequences

- **The melee burst is a scheduling problem, not a transport problem.** With
  transport settled, #796's answer is to spread the authoritative resolve
  (`BladeSim.simulate_range`'s integer `step_offset` is already the primitive)
  behind a wind-up beat with a hard floor — and a peer, whose sim is draw-only
  under 0002, may step its resimulation just-in-time at any fidelity. Nothing here
  needs the sync model to change, and this record is the reason nobody should
  re-open the model to get it.
- **The wire shape stays one message per verb.** A peer's intent goes up; the
  host's validate *is* the resolve for an attack (#545: `prepare_launch_command`
  runs inside `_validate`); the confirmed command comes down with its
  `AttackRecord` embedded; everyone including the host replays that one payload.
  There is no ack-then-results pair, and no per-tick streaming.
- **0002's alternatives table is partially stale and this record is the errata:**
  the "no `StatBoard` wire format" ground under *Full state replication* is dead
  (#560 shipped one), and ground A is now "tractable with work" rather than
  "only fixed-point or deleting the trig". Neither revives lockstep — see the
  decision's point 3 — but nobody should cite them as still-live grounds.
- **When the competitive release becomes real**, the refactor is the *Fog-filtered
  state deltas* alternative 0002 marked "deferred, not rejected", and it should be
  recorded as the ADR that supersedes this one.

## Alternatives considered

### Lockstep on a shared plan (plan-down, every peer reproduces the result)

The 2026-08-22 proposal, back for the third time via #796. Rejected on point 3
above. **The grounds that were live in 0002 and are no longer sufficient on their
own:** ground A (libm) is tractable — ship the arc driver's trig constants, one
backend, `-ffp-contract=off`, `Geometry2D`-over-`stable_id`-sorted zones for the
hit set, seed the three unseeded rolls; ARM/mac FMA remains a risk. **The ground
that decides it is B, made concrete:** the owner wants enforced hidden information
to remain reachable, and lockstep forecloses it.

### Build fog-filtered deltas now

Machine-enforced fog today. Rejected by the owner on cost-of-delay: months of
architecture for a threat model that does not exist until a competitive release,
paid while the verb set is still growing daily — every new verb would have to be
built against the filtered shape from the start. Deferred to one refactor once the
game has stopped changing shape.

### Live melee on the engine physics, hits landing as they happen

Floated alongside lockstep. Rejected independently of transport: `GodotPhysics2D`
is not reproducible across machines (broadphase, island and signal order are
unspecified, and it steps on the engine clock), and a live engine swing beside a
shadow PBD resolve for the AI and preview is a parallel mirror — the AI would score
one swing and the game would play another, and #782's "the ghost *is* the swing"
would stop being true.

### Do nothing (leave 0002's "reachable" undated)

Rejected because it just happened: without a stated trigger, "reachable" was read
as "cheap to give up" by the third lockstep argument. The trigger is now on the
record.
