---
id: 0077
title: AttackRecord is post-apply — the wire carries what each landing actually did, never what a peer should re-derive
status: accepted
date: 2026-08-21
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "#511"
  - "docs/domain/multiplayer-sync-model.md"
  - "attack/outcome/attack_record.gd"
tags: [multiplayer, netcode, combat, architecture]
---

# ADR 0077 — AttackRecord is post-apply, not resolve-time

Backfill, recorded 2026-11-08: the call was settled on #511 (2026-08-21) and
lived in code comments, then `multiplayer-sync-model.md` prose.

## Context
Attacks must reach every peer identically, but resolution is order-dependent
(an earlier beat's cascade changes what a later beat lands on), crits roll,
mitigation is read node-locally at land time, and a target may sit under fog a
client does not hold. ADR 0002 fixed intent-up / confirmed-command-down and
ADR 0011 one timeline contract; neither said *when* the record is cut.

## Decision drivers
- A peer must never compute a combat number it could get wrong.
- Fog: a client may lack the very nodes a cascade walked.
- One `OutcomeApplier` loop on every machine, no peer-only branches.

## Decision
The launch command crosses the wire "plus `AttackRecord`, a post-apply record
of what each landing actually did, stamped by `BattleSystem` during
application" (#511, 2026-08-21). Peers replay recorded deltas; they never
re-run a gate, never re-derive a number.

## Consequences
Buys: peers replay deltas through the same `OutcomeApplier` loop on the same
`BeatClock`; no re-simulation, no divergence. No latency is added: resolve and
apply run synchronously inside command validation, so the record ships with
the command itself — presentation stretches over time on each machine locally,
and the wire never waits on it. Costs: the record must encode every landing
(~100 for a long propagation), as parallel scalar arrays.

## Alternatives considered
### Resolve-time record (ship the plan's outcome before gates land)
Lost on the first driver: land-time mitigation and cascade order change what a
landing does; a resolve-time snapshot is wrong by construction.
### Peers re-simulate from the command
Lost on fog and determinism: a fogged client lacks the islanded nodes a
cascade needs, and the swing sim is order-dependent with rolled crits.
