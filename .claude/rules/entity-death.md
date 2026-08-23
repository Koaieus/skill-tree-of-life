---
description: Entity death sequencing — health-depletion trigger, two-phase Events bus, synchronous cleanup ordering
paths:
  - "systems/allocation_system.gd"
  - "systems/battle_system.gd"
  - "systems/loot_system.gd"
  - "scenes/game_root.gd"
---

# Entity death (#18)

How an entity dies and gets cleaned up. Touches Entity, AllocationSystem,
BattleSystem, GameRoot, LootSystem, and the `Events` bus — keep this current if
the flow changes.

## Core HP **is** the `health` PoolStat — the core SkillNode never depletes

There is no separate "core node HP = 0 → die" path. The core SkillNode's combat
HP is bottomless in the death sense: `SkillNode.take_damage` routes any overflow
past the core's combat HP into the owner's `health` pool (`health.deplete(overflow)`)
and **returns without ever emitting `depleted`** (skill_node.gd, the
`owned_by.core_location == self` branch). The battle cascade's chip damage also
lands on `health`. So "core destroyed" == `health` pool hits 0 → `health.depleted`
→ `Entity._on_health_depleted` → `Entity.die()`.

Don't wire death to a core-node `depleted` signal; it never fires.

## Entity stays dumb; systems react off the bus

`Entity.die()` latches `is_dead` (idempotent — death can re-fire mid-cascade)
and announces death in **two phases** — `Events.entity_dying(self)` then
`Events.entity_died(self)` — doing nothing else itself (**not even killer
attribution** — that lives in LootSystem). The two-phase split sequences
consumers by **phase, not connection order**: `emit()` is synchronous, so every
`entity_dying` handler finishes before any `entity_died` handler runs. Don't
reintroduce a tree-order dependency — the editor freely reorders `Systems`
children, which is exactly what the phases immunise against.

1. **`entity_dying` → LootSystem** (#68/#69) — runs while the corpse still owns
   its nodes; it needs that pre-strip world to snapshot loot + reward the killer.
   The mechanics (the loot draw, killer attribution) are LootSystem's own concern
   — see `loot_system.gd` / `docs/domain/loot-system.md`, not duplicated here.
2. **`entity_died` → AllocationSystem** force-deallocates every owned node (core
   last) via the `force_deallocate` primitive — VFX shatter fires per node. This
   is the only path that force-deallocates a core. (The SkillDust addon survives
   this — it's an addon child, not a `node.modifiers` entry.)
3. **`entity_died` → GameRoot** owns the player-vs-NPC split. The turn-loop-
   critical half runs SYNCHRONOUSLY here, and applies to **every** corpse,
   player included (#460): removed from `Entity.GROUP` / `READY_GROUP` (so
   TurnManager skips it that frame), and cleared off `current_entity` if it
   somehow held the turn. Skipping the player was safe only while player death
   ended play on the spot; it no longer does, and a corpse left in the groups
   stalls the loop on a `PlayerController` waiting for input. GameRoot fires
   after AllocationSystem on the **child-before-parent** ready order (it's the
   root), so the strip never races the group removal.
   The VISUAL half — NPC `queue_free` — rides `Events.entity_death_shown`,
   which **`Entity.die()` emits itself, last**, after both bus phases above.
   See `GameRoot._on_entity_died` / `_on_entity_death_shown`.

   **Death no longer ends the run; `VictorySystem` decides that (#460).** The
   player's corpse is deliberately NOT freed (the camera/HUD still point at
   it), and the run-end surface comes up off `Events.run_ended` — not off
   player death — because in hot-seat coop a dead player with a living ally
   must not end anything. VictorySystem rides the same
   `entity_death_shown` phase, coalesced one-per-frame. See
   `docs/domain/victory-system.md`.

   **That signal is an ORDERING seam, not a delay (#504).** Under design B the
   world mutates on the reveal clock, so the entity dies at the moment it is
   drawn dying — there is no reveal to wait for and no fallback branch. It
   stays a separate signal purely so despawn lands *after* AllocationSystem's
   strip; a despawn that raced ahead would leave nodes owned by a freed entity.
   `test_death_strips_nodes_before_the_despawn_signal_fires` pins it.

   The old presentation-hold machinery (`Entity.release_health_presentation`,
   the "if nothing ever held health presentation, reveal immediately" fallback,
   `RevealRecorder` / `PresentationPlayer`) is **gone** — see
   `presentation/README.md` for why those classes are parked on disk.

## Death cleanup is SYNCHRONOUS, deliberately (not deferred)

Death fires synchronously mid-cascade (`health.deplete` inside BattleSystem's
`for n in cascade` loop). The instinct is to `call_deferred` the cleanup to let
the cascade unwind — **don't**. Two reasons:

1. **Synchronous is already safe.** BattleSystem guards every cascade step with
   `if n.owned_by != defender: continue`, so nodes the death cleanup deallocates
   are simply skipped when control returns to the loop. The loop never restarts;
   there is no re-entry.
2. **Deferring introduces a worse bug.** A deferred `deallocate_all_owned(entity)`
   races GameRoot's `queue_free(entity)`, and **a deferred call whose Object
   argument has been freed is silently dropped by Godot** — so the deallocate
   never runs and the corpse's nodes stay `owned_by` a freed entity (orphaned
   territory). This passed a direct-`die()` test while failing the real-bus path.

`test/unit/test_entity_death.gd` triggers death via the realistic paths (core
overflow + cascade chip damage), never bare `die()`, so the re-entrancy and the
deallocate-before-free ordering are actually exercised — a direct-`die()` test
hides both.
