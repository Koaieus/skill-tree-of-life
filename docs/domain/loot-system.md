# Loot system (#68 XP reward + #69 SkillDust)

`systems/loot_system.gd` is the authority for **killing-blow rewards**. It reacts
to `Events.entity_died(victim)` and does two things:

1. **XP reward (#68)** — the killer gains XP scaled by the victim's level.
2. **SkillDust drop (#69)** — the victim's former core node becomes a claimable
   relic carrying a `SkillDustAddon` whose payload is a snapshot of the victim's
   modifiers.

This is the MVP slice of the design doc's *Killing Blow Resolution* /
*Loot Resolution* (`docs/design/combat_system.md`). Deferred for now:
STEAL/PROLIFERATE choice, the picker UI, node staining (`last_owner`),
proliferation, the DAP bonus, BLITZ. **Staining is shelved indefinitely** —
"find something better" before reviving it.

## Killer attribution — resolved here, not on Entity or the bus

Death fires **synchronously** inside the attacker's turn: core-HP overflow
(`SkillNode.take_damage`) and the cascade's chip damage
(`BattleSystem._on_node_depleted`) both run in the attacker's `launch_attack`
call stack. So `turn_manager.current_entity` at `entity_died` **is** the killer.

LootSystem holds an injected `@export var turn_manager` (DI per
`.claude/rules/scene-composition.md`, wired in `game_root.tscn`) and resolves the
killer itself. This was a deliberate choice over two alternatives:

- **Not on `Entity`** — keeps `Entity` dumb; it already only *announces* death
  (`entity_died`), it shouldn't also attribute it. (`Events.entity_died` stays a
  1-arg signal — no `killed_by` param, no churn across its other consumers.)
- **Not in `BattleSystem`** — BattleSystem owns *attacks*; folding reward
  attribution into it spreads reward logic across two systems. LootSystem is the
  rewards authority, so attribution lives with the rewards.

`_resolve_killer` self-guards (victim ≠ killer → non-attack death, no reward) and
null-guards a missing TurnManager (headless tests).

> **Thorns / counter-damage caveat:** those would deal a killing blow on the
> *defender's* turn, breaking the "turn holder == killer" assumption. They aren't
> implemented yet; when they land, attribution needs real source-threading
> (the `DamageInstance.source` is non-uniform today — plan / node / spell-state —
> so it can't carry the attacker cleanly without a dedicated pass).

## Ordering is load-bearing: snapshot before the strip

Three systems react to `Events.entity_died`, and **order matters**:

```
LootSystem        → snapshot victim modifiers + attach SkillDust to the core
AllocationSystem  → force-deallocate every owned node (incl. core → neutral relic)
GameRoot          → player game-over / NPC despawn
```

LootSystem must run **first** because the loot draw's node-modifier source (set X)
reads the victim's *still-owned* subgraph (`navigator.get_mirrored_nodes()`). Once
AllocationSystem strips the nodes they're gone from the mirror.

Guaranteed by **tree order**: LootSystem is the **first child** of `Systems` in
`game_root.tscn`, so its `_ready` connects to the bus before AllocationSystem's,
and Godot serves signal handlers in connection order. (This extends the existing
death-bus ordering contract — AllocationSystem already documents that it runs
before GameRoot's despawn.)

The XP grant and the dust *attach* are themselves order-independent — the addon
survives the strip (`force_deallocate` only pops `node.modifiers`, not addon
children), and the core-mod source comes off the `core_class` resource, not live
state. Only **set X** needs the pre-strip read.

## The loot draw (`_draw_payload`)

Total payload size = **victim level**. Composed from two sources:

| Source | What | Order |
|---|---|---|
| **Core** | `core_class.modifiers` (class identity, e.g. BalancedCore +10 STR/DEX/INT) + the core node's own `modifiers` (so previously-looted mods re-enter the loop) | First, **shuffled**, capped at `max_core_picks` (default 2) |
| **Node (set X)** | union of `modifiers` over every non-core node the victim still owns | Fills the remainder, **shuffled** |

`max_core_picks` is the key tuning knob: capping core picks below the full core
set means you don't always get the whole `+10/+10/+10` dump — more varied loot.
`xp_per_victim_level` (default 5) is the XP slope.

Every drawn modifier is `duplicate(true)`d so the dust owns independent copies
(formula-mod binding-state safety — see `.claude/rules/stats-system.md`).

Cascade-killed nodes are naturally excluded: they left the navigator mirror when
the finishing blow stripped them, so their mods don't enter the draw. (The
design alternative — snapshot enemy boards at *player turn start* — is shelved;
revive it if playtest wants "the spirit at turn start is what died".)

## SkillDust pickup (`skill_node/addons/skill_dust_addon.gd`)

`SkillDustAddon extends SkillNodeAddon`. It sits on the neutralised relic core
and subscribes to `carrier.owner_changed`. When **any** entity allocates the
relic (owner goes non-null), it pours its payload onto the **collector's core**
(appends to `core.modifiers` + `board.add_modifier` — STEAL semantics: permanent,
portable core modifiers) and `queue_free`s itself.

The `owner_changed` handler guards `owned_by == null` so the death-strip
(victim → null) doesn't trigger a premature grant — only a real pickup
(null → collector) does.

## XP must route through the pool

`_award_kill_xp` calls `board.xp.replenish(amount)` — **not** a raw
`set_current`. The pool's `on_pool_filled` → `replenished` cascade
(`Entity._on_xp_replenished`) is what mints SP and bumps the level. Bypassing it
would silently skip the level-up. See `.claude/rules/stats-system.md` (pool
upkeep / GrowablePoolStatDef).
