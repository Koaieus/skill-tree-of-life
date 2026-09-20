---
id: 0024
title: Status effects have two hosts and fall through a cracked core; presentation composes hosts
status: accepted
date: 2026-09-20
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#994"
  - "#953"
  - "docs/design/damage_over_time.md"
  - "combat/node_combat.gd"
  - "attack/outcome/status_instance.gd"
tags: [combat, status, architecture, entity, ui]
---

# ADR 0024 — Status effects have two hosts and fall through a cracked core; presentation composes hosts

## Context

Status machinery (`_statuses`, `apply_status`, `tick_statuses`, `remove_status`,
`clear_statuses`, `get_statuses`, `get_status_power`; `combat/node_combat.gd:52,
603-661, 709-743`) lived only on `NodeCombat`. #994 asked two questions the owner
put as forks: does a status follow the core on a move, and where does a
core-node DoT tick land once the core is depleted (0 HP, still allocated — the
"cracked shell": `NodeCombat.take_damage` drains `hp` then, on `is_core()`,
overflows into the `health` pool and returns early, `combat/node_combat.gd:398-411`)?

Owner, on the framing fork (2026-09-20): *"I think application layer would solve
this, i.e. if something is applied to node, or to core, and the mechanics of
which one happens when is the real Q. A blinded core blinds the combined
readout. A poisoned core.. takes core damage ticks? Something like that."* And
on the crack: *"Depleting a core node then applying more poison and it the
actual status effect falls through to be suffered/hosted by the core could be a
legit mechanic."* This dissolved the original three forks (does it migrate,
transfer vs copy, arrival-merge) rather than answering them: the answer is a
host model, under which migration is not a question that arises.

## Decision

1. **`StatusHost` is one implementation, composed by two hosts.** The status
   machinery above is extracted from `NodeCombat` into `StatusHost`, which both
   `NodeCombat` and `EntityCombat` compose. Def hooks
   (`_on_applied/_on_tick/_on_removed`) take the host, never a node specifically.
   Never a second, parallel `apply_status` on the entity side.
2. **Nothing migrates on a core move.** A node-hosted status stays on the node
   because it is data on the node; an entity-hosted status travels with the
   entity because it is data on the entity. `docs/design/damage_over_time.md:91`
   ("move the core off a corrupted node") stays true as written — it describes
   the node-hosted case.
3. **Fall-through rule.** `StatusInstance.land_on` (`attack/outcome/status_instance.gd:57`)
   lands on the node host while `node.hp.current > 0`. When the target is its
   owner's core node AND `hp.current == 0` at the moment the instance lands
   (whatever landed earlier in `outcome.hits` — e.g. the same hit's damage,
   `RangedDamage.status_for`, `attack/formulas/ranged_damage.gd:61-68` — is what
   it sees), the status falls through to that owner's `EntityCombat` instead.
   A zero-damage status hit on an already-cracked shell falls through too. There
   is no migration back when the shell regens above 0; rows already node-hosted
   stay node-hosted; the two hosts never merge rows.
4. **Entity-hosted modifiers plant on the entity board**, so they are entity-wide
   by construction (every node's combined read sees them) — not scoped to the
   core node. Owner, on whether that scope is right: *"Option 1 unless it turns
   out damaging status fx on core are too powerful"* (2026-09-20). The tuning
   door is `<type>_resistance` authored on the **entity** board (#963 reads
   resistance from the host that received the status).
5. **Entity-hosted DoTs drain the `health` pool directly** through one
   `EntityCombat` pool-damage door that the core-overflow route and the cascade
   chip also call. `PERCENT_MAX` resolves against `health.value`.
6. **The chosen host is a landed fact, shipped on the `AttackRecord`** — same
   shape as `StatusInstance.power_resolved` (`attack/outcome/status_instance.gd:31-40`)
   — so a peer lands the recorded host and never re-derives it from live node HP.
7. **Presentation composes, never merges.** `core_health_bar.gd:47-56` reads only
   the entity `health` pool; the core bar (and the hero card's health gauge)
   mirrors the node bar's status treatment — icon row, projected DoT segment —
   fed by the entity's rows and projected against the pool, while node bars
   project node-hosted rows. The core node's readout concatenates both hosts'
   rows — the same composition `SkillNode.get_local_value` already does for stat
   bins (`.claude/rules/stats-system.md:42-46`) — the UI never merges the two
   hosts into one row set. Owner call on #953 (2026-09-20).

## Consequences

- `NodeCombat` loses its private status fields to `StatusHost`; `EntityCombat`
  gains one (`_statuses`, cloned in `snapshot()` exactly as `NodeCombat` clones
  at `node_combat.gd:108`). Entity-host ticks ride `Entity._on_turn_started`
  (`entity/entity.gd:519`), which already runs before node ticks per
  `test_status_tick_lifecycle.gd:6`.
- Entity-hosted Curse (raises `min_damage_taken` on every node) is, per the
  arithmetic worked in #994, the entity-wide effect most likely to need
  resistance tuning first — flagged, not yet re-litigated.
- A cracked core node vacated by a `move_core` sits allocated at 0 HP with
  nothing re-checking it — `move_core`/`_on_core_moved` has no HP handling. Not
  this decision's scope; tracked as its own issue per #994.
- Shipping the host on `AttackRecord` is one more field a replay consumer reads,
  not derives — consistent with ADR 0002's confirmed-command-down model.
- The fall-through moment is a presentation event (icon lands on the entity
  card / core bar on its own beat), never a row quietly appearing — #953.

## Alternatives considered

### Migrate statuses on core move
**Dead.** The host model dissolves the question rather than answering it: a
status never "migrates" because it was never tied to the core's location in the
first place — it is data on whichever host received it. Re-raising "should it
migrate" re-opens a fork the owner closed by reframing it.

### Core-only scope via a third bin layer
**Rejected by owner.** A core-local bin layer that travels with the core but
stays out of every other node's combined read was considered and set aside:
*"Option 1 unless it turns out damaging status fx on core are too powerful"* —
entity-wide is the default, tuned down via entity-board resistance if a specific
effect proves too strong, not architected away up front.

### DoT via the core node's `take_damage` door
**Rejected.** Routing an entity-hosted DoT tick through the existing node
`take_damage`/overflow path was considered against draining the `health` pool
directly. Rejected: it renders the one status on two different bars depending on
shell HP, and — the decisive cost — regenerating the shell (D-9's ramp) would
double as the antidote, making the premise ("the poison is already inside the
core, past the shell") false.

### A parallel entity `apply_status`
**Dead.** A second, entity-specific status-application implementation beside
`NodeCombat`'s is the parallel-mirror-of-logic failure mode the repo already
forbids — one implementation, two composed hosts, never two implementations of
the same contract.
