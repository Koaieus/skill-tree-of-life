# Stat → surface map

One row per `stats_system/defs/*.tres` id (`ls stats_system/defs/*.tres`).
"Surface" names the scene/script that renders the id — file only, no line
numbers. A `hidden` row's reason is the id's own `.tres` description read as a
proposal, not a decided call.

This is a map, not a test: code mentioning an id doesn't prove it's visible,
and a genuinely hidden stat (a pure formula input) is a valid, intended state.
Register a new stat here when you add its `.tres` (the HUD has no
metadata-driven stat panel — see `.claude/rules/stats-system.md` → Gotchas).
Out of date? grep `get_stat`/`get_local_value`/`bind.*stat` in `ui/` and
cross-check the tables.

## Attributes & senses

| id | surface |
|---|---|
| `strength` | `ui/hud/attributes_panel/attributes_panel.gd` (`ATTR_IDS`) |
| `dexterity` | `ui/hud/attributes_panel/attributes_panel.gd` (`ATTR_IDS`) |
| `intelligence` | `ui/hud/attributes_panel/attributes_panel.gd` (`ATTR_IDS`) |
| `constitution` | `ui/hud/attributes_panel/attributes_panel.gd` (`ATTR_IDS`) |
| `wisdom` | `ui/hud/attributes_panel/attributes_panel.gd` (`ATTR_IDS`) |
| `perception` | `ui/hud/attributes_panel/attributes_panel.gd` (`ATTR_IDS`) |
| `vision_range` | `ui/hud/attributes_panel/attributes_panel.gd` (Senses row) |
| `sensor_range` | `ui/hud/attributes_panel/attributes_panel.gd` (Senses row) |
| `core_health_scaling` | `ui/hud/attribute_rules.gd` (`AttributeRules.describe`), surfaced via `ui/hud/attributes_panel/attributes_panel.gd`'s radar-axis hover tooltip — hovering the CON axis lists `mod_con_to_health` ("+1 Max Health per CON × core scaling", `entity/default_entity_board.tres`), a live `intrinsic_modifiers` entry formula'd off this stat. Indirect: the coefficient itself isn't printed, its effect is |
| `node_health_scaling` | Same radar-axis-hover path as `core_health_scaling`, via `mod_con_to_node_health` |

## Combat readout cards

A plain stat row is scene-authored — a `CombatValueRow`
instanced in the card's `.tscn` with its own `stat_id`, self-binding; the
card's `.gd` no longer names the id for these. Cited file is the `.tscn`
below unless noted otherwise.

| id | surface |
|---|---|
| `armor` | `ui/hud/combat_readout/combat_card_defense.tscn` (`stat_id = &"armor"`) |
| `min_damage_taken` | `ui/hud/combat_readout/combat_card_defense.tscn` (`stat_id = &"min_damage_taken"`) |
| `spike_regen` | `ui/hud/combat_readout/combat_card_defense.tscn` (`stat_id = &"spike_regen"`) |
| `blade_damage` | `ui/hud/combat_readout/combat_card_melee.tscn` (`stat_id = &"blade_damage"`) |
| `blade_size` | `ui/hud/combat_readout/combat_card_melee.gd` — derived row (blade pips), stays custom code, not scene `stat_id` |
| `blunting` | `ui/hud/combat_readout/combat_card_melee.tscn` (`stat_id = &"blunting"`) |
| `ranged_damage` | `ui/hud/combat_readout/combat_card_ranged.tscn` (`stat_id = &"ranged_damage"`) |
| `range` | `ui/hud/combat_readout/combat_card_ranged.tscn` (`stat_id = &"range"`) |
| `crit_chance` | `ui/hud/combat_readout/combat_card_crit.tscn` (`stat_id = &"crit_chance"`) |
| `crit_multiplier` | `ui/hud/combat_readout/combat_card_crit.tscn` (`stat_id = &"crit_multiplier"`) |
| `spell_damage` | `ui/hud/combat_readout/combat_card_magic.tscn` (`stat_id = &"spell_damage"`) — the potency row, the caster's bare stat |

## Turn resources / hero sigil / XP

| id | surface |
|---|---|
| `action_points` | `ui/hud/turn_resources_panel/turn_resources_panel.gd` |
| `deallocation_points` | `ui/hud/turn_resources_panel/turn_resources_panel.gd` |
| `movement_points` | `ui/hud/turn_resources_panel/turn_resources_panel.gd` |
| `skill_points` | `ui/hud/turn_resources_panel/turn_resources_panel.gd` |
| `wound_heal_per_turn` | `ui/hud/turn_resources_panel/turn_resources_panel.gd` |
| `health` | `ui/hud/hero_sigil_card/hero_sigil_card.gd`; also the live pool at `skill_node/core_health_bar.gd` |
| `core_healing` | `ui/hud/hero_sigil_card/hero_sigil_card.gd` |
| `level` | `ui/hud/hero_sigil_card/hero_sigil_card.gd` |
| `xp` | `ui/hud/xp_track/xp_track.gd` |
| `xp_per_turn` | `ui/hud/xp_track/xp_track.gd` |
| `sp_gain_on_levelup` | `ui/hud/xp_track/level_up_flourish.gd` (`stamp()`'s "+N SP — LEVEL L" detail line) — indirect: the SP total comes from `Entity.sp_minted_for_level()` (`entity/entity.gd`), which reads this stat plus the every-5th-level milestone bonus |
| `ap_transfer_rate` | `ui/hud/action_cluster/action_cluster.gd` (`_refresh_conversion()`, the "⇒ +N move · +N dealloc" line, scene-ordered directly above `EndTurnButton`) — indirect: shows the computed conversion, not the raw rate A named-rate hover sub-row is spec'd but unbuilt |

## Initiative

| id | surface |
|---|---|
| `initiative` | `ui/initiative_bar.gd` (the per-seat clock bar); also ordering only, via `TurnManager.forecast` (`systems/turn_manager.gd`, reads `initiative.current`), drawn by `ui/hud/turn_forecast/turn_forecast_strip.gd` — never a printed number there |
| `initiative_speed` | Ordering only, via `TurnManager.forecast` (`systems/turn_manager.gd`, reads `initiative_speed.value`), drawn by `ui/hud/turn_forecast/turn_forecast_strip.gd` — no direct numeric row anywhere |

## Node visuals & the tooltip-fan node panel

`ui/tooltip_fan/panels/node_stats_panel.gd` renders node_health, armor,
min_damage_taken unconditionally (`_ALWAYS_SHOWN_STAT_IDS`) plus every other
locally-borrowed or addon-granted stat dynamically, via
`StatBoard.get_dynamic_stat_ids()`, minus `_EXCLUDED_STAT_IDS`
(blade_damage/ranged_damage/range, already covered by the combat cards
above).

| id | surface |
|---|---|
| `stake_level` | `skill_node/visuals/node_visuals_composite.gd` (`_rim_ring.fill_max = stake_level`) |
| `addon_slots` | `ui/tooltip_fan/panels/node_stats_panel.gd`, dynamic — baked on every node board (#332); the row is omitted only when the node carries no addons |
| `deflection` | `ui/tooltip_fan/panels/node_stats_panel.gd`, dynamic — conditional on an addon granting it locally (`bunker_addon.tscn`) |
| `swing_drag` | `ui/tooltip_fan/panels/node_stats_panel.gd`, dynamic — conditional on an addon granting it locally (`fortification_addon.tscn`) |
| `spikes` | `ui/tooltip_fan/panels/node_stats_panel.gd`, dynamic — conditional on `skill_node/addons/spike_ring_addon.gd` granting it. On a node board the displayed pool is minted from the node_spikes def (`stats_system/node_stat_board.gd`'s `_mint_stat`, same split as node_health/node_combat_health below) |
| `node_health` | `ui/tooltip_fan/panels/node_stats_panel.gd` (always-shown); also the entity combat card's "Node Health" row, `ui/hud/combat_readout/combat_card_defense.tscn` (`stat_id = &"node_health"`); the live per-node pool also draws at `skill_node/health_bar.gd`. On a node board the pool is minted from the node_combat_health def, not requested by node_health's own def (`stats_system/node_stat_board.gd`'s `_mint_stat`) |
| `node_combat_health` | Not requested by its own id anywhere. It is the def `NodeStatBoard._mint_stat` substitutes in for node_health on a node board — surfaced only indirectly, via `skill_node/health_bar.gd` |
| `node_spikes` | Not requested by its own id anywhere. It is the def `NodeStatBoard._mint_stat` substitutes in for spikes on a node board — surfaced only indirectly, via `ui/tooltip_fan/panels/node_stats_panel.gd` (the same dynamic spikes row above) |

## Pending a design decision

| id | status |
|---|---|
| `cast_range_hops` | `ui/hud/combat_readout/combat_card_magic.gd` — the Hop reach row, always the describe tier (`resolve_with([]).describe()`, e.g. "(X+3) × 1.5"). Base 0 by contract — the spell's authored reach folds in as an overlay, so the card never prints a bare number |
| `cast_range_distance` | No surface drawn yet; base 0 by contract like `cast_range_hops` |

## Quiver, volleys, infusion, ammo aspects

| id | surface |
|---|---|
| `arrows` | `ui/hud/command_tray/bodies/ranged_body.gd` (base arrows are the remainder `N − Σ specials`) and `volley_bar.gd` |
| `arrows_per_reload` | node-local (`skill_node/addons/defs/watchtower_addon.tscn`); no row of its own |
| `max_shots_per_leaf` | `skill_node/shots_pips.gd` (per-leaf shot pips) |
| `volleys_per_turn` | no row; derived from `max_shots_per_leaf` (innate intrinsic) |
| `infusion_slots` | `ui/hud/command_tray/bodies/infusion_row.gd` ("slots used / infusion_slots") |
| `infusion_points` | `ui/hud/command_tray/bodies/infusion_row.gd` (points spent / `min(infusion_points, infusion_capacity)`) |
| `*_aspect` (`armor_break`, `bleeding`, `blindness`, `corruption`, `curse`, `explosive`, `greed`, `hex`, `poison`, `scout`, `weakness`, `wither`) | caster affinity in `ui/hud/command_tray/bodies/affinity_line.gd` and `infusion_row.gd`; also the per-reload stat of a special ammo type |
| `*_stacks_per_hit` (`bleeding`, `blindness`, `corruption`, `curse`, `greed`, `hex`, `poison`, `weakness`, `wither`) | `affinity_line.gd` (through `StatusDef.stacks_per_hit`) |
| `*_resistance` (`bleeding`, `blindness`, `corruption`, `curse`, `poison`) | `ui/tooltip_fan/panels/node_stats_panel.gd` (dynamic, when a node or its owner carries one); also `addons/status_sandbox/` |
| `healing_received` | no row; read at the heal doors (`NodeCombat.heal_damage`, `EntityCombat.heal`) |
| `bounty` | no row; read by `systems/loot_system.gd` as a node's payout overlay |

## Family parents

`aspects`, `attributes`, `damage`, `dot_stacks_per_hit` and `status_resistance` are parent stats (ADR 0029): they fold into their children and have no entity-panel row. When one is minted on a node board (a Ninja aura's `+20% damage`), `node_stats_panel.gd` renders its terms through `StatRegistry.is_parent` — bins, never a value.

## Hidden

None of these has a HUD row; each reads only as a formula input or a tuning lever. `tempo` and a richer `ap_transfer_rate` readout have unbuilt UI specs.

| id | reason |
|---|---|
| `blade_speed_half` | `v_half` in the speed-scaled blade damage curve — a raw curve constant in `attack/melee/skill_blade.gd`/`blade_damage_instance.gd`, no `StatModifier`. Becomes visible once curve stats can roll as procgen modifiers |
| `blade_speed_multiplier_max` | `M` in the same curve — same reasoning |
| `node_healing` | Base HP a node regenerates at turn start — node-local, read via `SkillNode.get_local_value`. When surfaced, pair it with `node_healing_ramp` parenthetically (`node_healing (+ramp)`, like `armor + (min_damage_taken)`) |
| `node_healing_ramp` | Extra HP `node_healing` gains per consecutive undamaged turn — same read path; display decided with `node_healing` |
| `tempo` | Once-per-turn kill-AP refund budget — a latch consumed by the kill-refund mechanic, distinct from the AP/DP/MP trio it refunds into. Spec'd as a lit/hollow pip trailing the AP gauge; unbuilt |
| `core_kill_xp` | XP bonus paid to the killer on this entity's core death — read once by `LootSystem`, not a standing stat |
| `dealloc_damage` | Flat HP damage per forced-dealloc in a battle cascade — a tuning lever read inside the cascade resolver; its chip surfaces in the cascade toast at the core (`Events.entity_cascade_charged`: summed chip, `+N W` wound suffix) |

## Stats in multiple UI locations

Review these for intentionality when adding a component that re-displays an already-visible stat.

| Stat | Locations | Why |
|---|---|---|
| `action_points` | `turn_resources_panel`, `action_cluster`, `command_tray` | pool overview, action readiness, spending gate |
| `strength` / `dexterity` | attributes panel (+radar), combat cards (effective), node stats panel (mods) | raw vs effective vs mod breakdown |
| `health` | `hero_sigil_card` (entity gauge), `skill_node/core_health_bar.gd` | entity-level vs node-level |
| `armor` | `combat_card_defense`, node stats panel | effective vs mod breakdown |
| `range` | `combat_card_ranged`, `ranged_body` | the tray shows it while planning a shot |
| `node_combat_health` | node tooltip (hover), node inspector card (selected) | hover vs persistent selection |

**New stat:** add its `StatDef` `.tres` (and its roster entry), then a row in the matching table above, or list it under Hidden with the consuming system. **New UI component:** add a column/row to the tables, and to "multiple locations" if it re-displays a visible stat.
