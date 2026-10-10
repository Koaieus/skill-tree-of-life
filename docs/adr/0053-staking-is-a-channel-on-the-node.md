---
id: 0053
title: Staking and extracting are K-turn channels whose state lives on the node (Euclidean reach, leash checked on core arrival, explicit cancel), paid from the entity's own staked bucket, tuned by AllocationSystem exports
status: accepted
date: 2026-10-10
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "the owner targets the six channel knobs and the leash ratio from the board or core classes (stat defs), incl. the owner's '1 stat where the leash is always double the init'"
sources:
  - "#1524"
  - "#1536"
  - "#1539"
  - "systems/allocation_system.gd"
  - "systems/entity_factory.gd"
tags: [staking, allocation, economy, stats]
---

# ADR 0053 — Staking and extracting are K-turn channels whose state lives on the node

## Context
Stake and extract were instant: 1 SP + 1 AP, one hop from the core. The AP was the only deterrent to the stake, attack, undo cycle (`aspect_matrix.md`), so staking was a free, reversible buff. The owner wanted staking to be a long-term investment, not niche, with time as the cost.

## Decision drivers
- The stake-then-undo cycle must cost real turns, not just AP.
- State must be reproducible on every peer (host-authoritative sync), with no new cross-wire stream.
- No per-node stake owner and no foreign/self distinction.
- A ×2 keystone must not hit ×4 by accident of a global ceiling.
- Tuning values must be easy to move later.

## Decision
Owner calls, all 2026-10-10 (hub #1524, #1536 rev 2):
1. **Channels on the node.** *"just keep it 1SP 0AP + 2 turn timer for staking or 3 turn timer for extracting"*. The channel is a target cap plus a progress count on the node; every K owner turn starts it moves one level; the tick is per-served-turn upkeep reproduced on every peer; one direction per node.
2. **Extract is a currency exchange.** *"staked bucket is degenerate like any currency, and extracting is basically a currency exchange."* Each landed step moves 1 of the entity's own staked SP to wounded; there is no per-node stake owner. A stake pledges its SP current to staked at initiation; an abort wounds what is still pledged.
3. **Knobs are `@export`s on `AllocationSystem`**: `stake_reach_px`, `stake_leash_ratio`, `stake_channel_turns`, `extract_channel_turns`, `stake_sp_cost`, `extract_sp_refund`. Owner: *"constants or exports, ADR for this. to be superseded when we decide to target these values on the board or via core classes -> then the stat defs option switch is a quick and clean fix"*.
4. **The stake ceiling is a node-local stat**, default 3. Owner: *"the keystones dont need to set anything yet (they can keep default of 3 until we need this new handle to tweak it)"*. Procgen raises past it add an unscaled +1 ceiling lift (`EntityFactory.set_procgen_stake`).
5. **Reach and leash are Euclidean px**, leash = reach × a ratio held at or above 1 by construction. Owner: *"1 + an ADR. and leash ratio cannot be <1 by construction (else AT 1 it would instantly break the moment it's established)"*.
6. **Cancel is an explicit command equal to an abort.** Owner picked it over the alternatives (answer *"2"*); the opposite verb on a channelling node stays denied.
7. **The leash is checked on core arrival** (`move_core`), never at turn start or mid-slide. Owner: *"1, but only check on arrivals at nodes, not halfway?"*

## Consequences
- Time is the deterrent; the stake-undo cycle costs K turns each way and a visible commitment.
- State is one pair of ints on `NodeState`, cloned with it; the shadow world and peers get it for free, and the tick needs no wire traffic.
- Ratio below 1 is unrepresentable (setter clamp); a lasso can cross a chasm.
- Knobs live in the scene, not in data, until the stat-def switch; changing them is an edit, not a migration.
- A node's ceiling lifts are local modifiers that a snapshot does not carry by itself.
- ADR 0004's worked example ("5 SP and 2 AP" for 0/1 to 3/3) predates this: stake costs no AP now. Its ladder decision stands; ADRs are immutable, so the correction lives here.

## Alternatives considered
**Entity-side channel ledger.** Lost on reproducibility: state off the node is lost when the node changes hands or is forced off.
**Status-row channel.** Lost on the same driver; a channel is a fact about a node, not a buff on an entity.
**Per-node `staked_by` with minting.** Lost on "no owner": the bucket is a currency, so a foreign extract needs no mint.
**2-DP honest full-extract.** Lost to the owner's *"the stay with 1DP sounds best here, the time you need to wait anyway"*.
**Pin instead of leash.** Lost: the core keeps some movement and may start a second channel.
**Cost drain alone (2 SP / 1 refund).** Does not stop a one-turn stake; stays a knob edit away, and is the most likely to be revived.
**Tempo mastery (3/3 raises the kill-AP cap).** Parked, not rejected; lives on #887.
**Hop-distance reach/leash over the owned subgraph** (the hub's own earlier pick, superseded the same day by decision 5). Dead ground: Euclidean fits the board better and allows reach across a chasm.
**Two independent px knobs.** Lost on "ratio at or above 1 by construction": leash below reach could break a channel the moment it began.
**Opposite verb unwinds one step; no cancel.** Lost to decision 6; extract is its own channel, so unwinding collides with it.
**Turn-start-only leash check.** Dead: distance only changes on a move, so the tick never needs it. Mid-slide checks lose to arrival being the logical reassignment.
