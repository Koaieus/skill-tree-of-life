# Entity death (#18)

How an entity dies and gets cleaned up. Touches Entity, AllocationSystem,
BattleSystem, GameRoot, and the `Events` bus — keep this current if the flow
changes.

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

`Entity.die()` latches `is_dead` (idempotent — death can re-fire mid-cascade),
emits `died` + `Events.entity_died(self)`, and does nothing else — **not even
killer attribution** (that lives in LootSystem). Consequences live in systems
listening to `Events.entity_died`, mirroring `BattleSystem`←`skill_node_depleted`.
**Connection order is load-bearing** — the three handlers run in this order:

1. **LootSystem** (#68/#69) — snapshots the victim's modifiers for the SkillDust
   relic + attaches it to the core, and awards XP to the killer. Must run FIRST:
   the loot draw reads the victim's still-owned nodes, which AllocationSystem then
   strips. Guaranteed by tree order — LootSystem is the **first child** of
   `Systems` in `game_root.tscn`. Killer attribution is resolved here from its
   injected `turn_manager` (`current_entity` == killer, since death is synchronous
   inside the attacker's turn), NOT on the bus or Entity. See
   `docs/domain/loot-system.md`.
2. **AllocationSystem** force-deallocates every owned node (core last) via the
   `force_deallocate` primitive — VFX shatter fires per node. This is the only
   path that force-deallocates a core. (The SkillDust addon survives this — it's
   an addon child, not a `node.modifiers` entry.)
3. **GameRoot** owns the player-vs-NPC split: player → game-over stub; NPC →
   removed from `Entity.GROUP` / `READY_GROUP` synchronously (so TurnManager
   skips it that frame) then `queue_free`.

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
