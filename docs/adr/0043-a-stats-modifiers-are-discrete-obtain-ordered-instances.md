---
id: 0043
title: A stat's modifiers are discrete instances in obtain order — an equal-priority SET clash is an authoring error, a load restores the order, and only a lossless fuse happens in game
status: accepted
date: 2026-10-03
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "Long runs accumulate enough discrete static modifiers to matter, or a mechanic for losing modifiers arrives (compaction between floors / rest areas)"
sources:
  - "#1355"
  - "#1334"
  - "#1362"
  - "#775"
  - "stats_system/stat.gd"
  - "stats_system/modifier_bins.gd"
  - "entity/entity.gd"
tags: [stats, save-load, multiplayer, loot, architecture]
---

# ADR 0043 — A stat's modifiers are discrete instances in obtain order

## Context

A stat's `_modifiers` list order is semantic in one place: two SETs at equal priority resolve last-in. Live, the list is in obtain order. A save load or a resync rebuilds it in stable_id order, so the entity half of a `WorldImage` re-encoded to different bytes (#1334), and a tied SET could resolve differently on a peer. `WorldFingerprint` does not fold stat totals, so nothing caught that. Separately, `Entity.absorb_core_modifier` (#775) fused every looted modifier by `value +=` whatever its op, so stealing SET 5 twice read SET 10, and ×1.5 twice read ×3.0. Only `pacifist_core.tres` authors SETs.

## Decision drivers

- A save, a load and a resync must reproduce every stat exactly, with no new wire field if possible.
- Intent between SETs is carried by `priority`. The stat system must not judge content (which SET is "better").
- Every granted modifier stays individually revocable unless fusing it is provably lossless.

## Decision

- Owner, 2026-10-03, on SET ties: *"Maybe disallow SETs that conflict having same prio? It's an authoring failure."* Then: *"still error but use obtain order instead of max"*. An equal-priority SET pair with different wire forms `push_error`s at bind, and the last-obtained one wins. A load's final `_reconcile_modifiers` re-sequences the list to the saved order. Any rebuild of a modifier list must preserve obtain order.
- Owner, 2026-10-03: *"How about a test that checks authored SETs for unique prio per stat? All SETs are hand authored so far, likely forever."*
- Owner, 2026-10-03: *"SETs should've never be absorbed except during procgen. And during game they need to stay for they can be revoked"*. Then: *"only ones carrying formulas should merge into same stat same formula modifiers and adjust base value; in game."* In game, a modifier fuses only if it carries a formula, its op is ADD_BASE / INCREASE / ADD_BONUS, and its merge key matches. Static modifiers, MULTIPLY and SET are their own grants.

## Consequences

- Bit-exact round trips: a load replays the live order, MULTIPLY products included. No `FORMAT_VERSION` bump, because the wire already carries obtain order.
- List order is load-bearing state. #1334's byte-identity assert is the tripwire for any rebuild that loses it.
- A fuse is lossless by construction (`v₁·f + v₂·f = (v₁+v₂)·f`). Everything else stays discrete and revocable, at the cost of more modifier instances per entity.
- Supersedes #775 decision 10 ("static modifiers merge too"). #775's own example, a formula rule going 1.0 → 1.25, still fuses.

## Alternatives considered

### Higher value wins a SET tie, with a canonical (sorted) encode
Made list order dead, the neatest invariant. Lost on the content-judgment driver: `StatDef.is_improvement` would make it max-or-min, and a SET of 0 ("stat off") against ∞ has no value-neutral winner. Owner: *"if it really was that important that it should overrule the inf then shoulda set higher prio"*. **Most likely to be revived** if order preservation proves fragile.

### Accept the reorder and compare modulo order
The smallest change, but it leaves a silent tied-SET desync on resync. Dead.

### Carry provenance (a source id / sequence number) on each modifier
`StatModifier` is deliberately provenance-free (shared across boards, #377). This needs a wire field and a format bump to restore what the list order already carries. Dead.

### Fuse every looted modifier per op (sums add, MULTIPLY multiplies), or never fuse
Fusing everything loses revocability for statics and is lossy for a formula MULTIPLY. Never fusing reverts #775's rate merge, which #792's display relies on.
