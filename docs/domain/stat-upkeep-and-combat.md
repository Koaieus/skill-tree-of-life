# Stat upkeep and combat flow

What moves a pool's `current` across a turn and a hit — turn-start upkeep, damage mitigation, forced-dealloc damage, DoT stacks and resistance, and the heal doors. The cap side (what moves `.value`, the cap-change policy, the pool classes) is `docs/domain/stats-system.md` § "Pool stats"; the status-effect model behind the DoT stats is `docs/domain/status-effects.md`; per-node HP is `docs/domain/node-hp.md`.

## Turn-start upkeep

`Entity.begin_turn` runs, in order: pool replenishment (one declarative sweep), wound healing (bespoke), node HP refill, the class hook.

"Per turn" is four verbs, set by `PoolStatDef.per_turn_mode` (default `NONE`):

| `PerTurnMode` | Operation | Pools |
|---|---|---|
| `REFILL` | `restore_to_full()` | `action_points`, `deallocation_points`, `movement_points`, `tempo` |
| `ADD` | `current += <rate stat>.value` (clamped) | `xp` (+`xp_per_turn`) |
| `HOST_ADD` | the pool does nothing; `Entity._apply_turn_upkeep` reads `PoolStat.host_upkeep_amount` and calls `EntityCombat.heal(amount, rate_id)` | `health` (+`core_healing`) |
| `CUSTOM` | `PoolStat._custom_turn_upkeep(board)` | `skill_points` (heals `wound_heal_per_turn` wounds) |

`StatBoard.apply_per_turn_upkeep()` enumerates every `PoolStat` field (`get_pool_stats()`) and calls `pool.run_turn_upkeep(self)`. **A new pool opts into upkeep by setting `per_turn_mode` on its def, not by editing `begin_turn`.** ADD resolves its rate through `PoolStatDef.resolved_per_turn_stat_id()` and `push_warning`s if missing. `initiative` is `NONE` (TurnManager ticks it).

**ADD's rate stat is `<id>_per_turn` by convention, overridable via `per_turn_stat_id`** — `health`'s rate is `core_healing`, named for the mechanic (D-25 and the #268 balance invariant use that name). Override only for that reason. A `CoreClass.on_turn_started` hook is not the place for pool upkeep.

**Every heal enters through one door per host:** `NodeCombat.heal_damage` for `node_health`, `EntityCombat.heal` for `health`; each multiplies by `healing_received` once, `raw := true` is the only bypass, and `test/unit/test_heal_door_drift.gd` scans the tree for a `replenish`/`set_current`/`.current +=` on either pool outside the two door bodies. That is why `health` is `HOST_ADD` rather than `ADD`: an entity-hosted Wither inverts the core's own trickle exactly as it inverts node heals.

**The hook split: behaviour lives where its data lives.** `on_pool_filled` is on the **def** (cap-shape varies by def archetype); `_custom_turn_upkeep` is on the **stat** (it touches the stat's own extra state). Wound healing transfers SP from `wounded` back to `current` — a bin move, so `skill_points` is `CUSTOM`; a stray `REFILL`/`ADD` there would corrupt the `wounded`/`staked` bins (`test_per_turn_upkeep` guards it). `wound_heal_per_turn` defaults to 1.

**Fractional rates accumulate.** `SkillPointStat.wound_heal_progress` (0..1, runtime-only) banks `wound_heal_per_turn` each upkeep; once it crosses 1.0 and `wounded > 0` it heals 1 SP and drains by 1.0, so a 0.5 rate heals one SP per two turns. While `wounded == 0` it holds at a capped 1.0, so the next turn after a wound heals immediately. `wound_heal_progress_changed(progress)` feeds `turn_resources_panel.gd`'s sliver.

**`health`'s upkeep (`core_healing`)** is an integer heal, placeholder `1`/turn, **ungated and unramped**: a gate only exists to make a ramp meaningful, and a ramping out-of-combat heal rewards the camping the forced-dealloc cascade is engineered to punish. Node regen does ramp and is gated — don't unify them. `test_core_healing.gd` pins the no-gate/no-ramp contracts. Invariant (#268): `core_healing >= dealloc_damage × nodes_lost_per_turn` makes camping viable again; `1` is break-even against a 1-node chip.

**Turn end:** `Entity.finish_turn` transfers each unused action point into next turn's `deallocation_points`/`movement_points` surplus: `boost = roundi(unused_ap × ap_transfer_rate)` (ScalarStat, default 2; a Pacifist raises it, a Berserker drops it to 0). It runs at turn end because unused AP is only known then; `set_surplus` overwrites, so a turn that spends all AP self-clears the prior boost. `Entity.DEFAULT_AP_TRANSFER_RATE` is the fallback for sparse/test boards.

Then, for each owned node `SkillNode.refill()`, and `core_class.on_turn_started(self)` (default no-op).

## Damage mitigation, DoT and healing

`Mitigation.apply(raw, defender_node)` (`attack/formulas/mitigation.gd`) runs inside `SkillNode.take_damage` before HP soak: `final = max(min_damage_taken, raw.amount - armor)`. `TRUE` damage bypasses it; `raw.amount <= 0` returns 0. `armor` (default 0) and `min_damage_taken` (default 3) are board stats; a defensive core can drive `min_damage_taken` below 0 so damage heals nodes. The floor is not a cap: at `raw=1, armor=-1` you take 3. **Both are read node-locally** through `defender.get_local_value(...)`, which merges the node's bins with the owner's, so a node-scoped modifier (`bunker_addon.tscn`'s `armor ADD_BONUS +5`, a core aura) reaches the formula. A formula that takes a board instead of a node would discard node-local `armor` while `combat_readout_card.gd` still displays it — the failure mode is a stat that displays right and computes wrong.

**Forced-dealloc damage.** When a node's combat HP hits 0, `BattleSystem._on_node_depleted` runs the cascade; each cascaded node costs the defender, bypassing `Mitigation`: `skill_points.wound(1)` (SP moves `used` → `wounded`, reserved until `wound_heal_per_turn` ticks it back; hardcoded 1) and `health.deplete(dealloc_damage.value)` (default 1; a fragile-core class raises it, Glass Cannon = 3). A 5-node cascade at `dealloc_damage = 2` deals 5 wounds + 10 HP, ignoring armor.

**DoT stacks and resistance.** Each status folds through one attacker-side stacks stat and one defender-side resistance. Stacks (FLOAT, entity-scope, default 0): `poison_`/`corruption_`/`curse_`/`wither_stacks_per_hit` (parent `dot_stacks_per_hit`) plus parentless `blindness_`, `bleeding_` and `hex_stacks_per_hit`; `bleeding_resistance` (parent `status_resistance`); identity stats `bleeding_aspect` / `hex_aspect` (parent `aspects`). A `StatusDef` names its stat in `stacks_stat_id` (armor-break: blank); `StatusDef.stacks_per_hit(board, authored)` is the one fold — the authored per-hit power is a `base_add` overlay in one `get_value_with` read, never floored (1 × +49% lands 1.49); a null board, blank id or unknown stat answers the authored power. `StatusInstance.land_on` lands that once (`power_resolved`) and `AttackRecord.rebuild` marks the hit resolved so a peer replays the landed number flat.

Resistances (FLOAT fraction, default 0.0: `poison_`, `corruption_`, `curse_`, `blindness_resistance`; Wither has none) are read on the host via `get_local_value` like armor. They are a **live filter at effect time** (ADR 0031): `StatusHost.effective_power` hands every apply/tick `row − ⌈row × res − ½⌉` (half-down, clamped to `[0, row]`) while the row decays raw; `>= 1.0` blocks landing and a standing row deals 0 but decays. `DotTick.tick_damage` floors each projected tick through `HitPoints.land`. Procgen: each family lives in one attribute pack (poison DEX, corruption STR, curse CON, wither INT, blindness PER); resistance (wither excepted) rolls on blessed nodes only, ADD_BASE unit 0.05, T2–T4; the stacks INCREASE row (unit 7 → +7/+21/+49%) on blighted nodes only; `dot_stacks_per_hit` ADD_BASE on blighted WIS. See `docs/domain/status-effects.md` § "The DoT model".

**`healing_received`** (FLOAT, default 1.0) is read node-locally once at the top of `NodeCombat.heal_damage` (turn regen, the core aura, healing spells) and entity-locally once at the top of `EntityCombat.heal` (the `core_healing` HOST_ADD upkeep). `raw := true` is the only bypass. Product `<= 0` heals and cures nothing; `< 0` lands as TRUE damage flagged `DamageInstance.from_withered_heal`, the one damage path that does not set `_damaged_since_upkeep`, so the regen ramp keeps climbing and the node heals itself to death. `WitherStatus` plants an unclamped UNSCALED MULTIPLY of `1 − 0.1·stacks` on it.
