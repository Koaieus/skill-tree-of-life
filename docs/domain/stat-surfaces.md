# Stat → surface map

One row per `stats_system/defs/*.tres` id (54 total, `ls stats_system/defs/*.tres |
wc -l`). "Surface" names the scene/script that renders the id — file only, no
line numbers (they rot). A `hidden` row's reason is a **proposal**: the drone's
best read of the id's own `.tres` `description`, not a decided call — the owner
confirms or re-homes each one in review (see #914).

This is a map, not a test: code mentioning an id doesn't prove it's visible,
and a genuinely hidden stat (a pure formula input) is a valid, intended state —
not a bug to fix. Register a new stat here when you add its `.tres`
(`.claude/rules/stats-system.md` → "No metadata-driven stat panel").

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
| `core_health_scaling` | `ui/hud/attribute_rules.gd` (`AttributeRules.describe`), surfaced via `ui/hud/attributes_panel/attributes_panel.gd`'s radar-axis hover tooltip — hovering the CON axis lists `mod_con_to_health` ("+1 Max Health per CON × core scaling", `entity/default_entity_board.tres`), a live `intrinsic_modifiers` entry formula'd off this stat. Indirect: the coefficient itself isn't printed, its effect is (owner-confirmed 2026-09-16, was proposed hidden) |
| `node_health_scaling` | Same radar-axis-hover path as `core_health_scaling`, via `mod_con_to_node_health` (owner-confirmed 2026-09-16, was proposed hidden) |

## Combat readout cards

Since #913 (a338840) a plain stat row is scene-authored — a `CombatValueRow`
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
| `spell_damage` | `ui/hud/combat_readout/combat_card_magic.gd` — indirect: the potency row reads `SpellResolver.impact_damage()`, not the raw stat value |

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
| `mana` | `ui/hud/hero_sigil_card/hero_sigil_card.gd` |
| `mana_per_turn` | `ui/hud/hero_sigil_card/hero_sigil_card.gd` |
| `level` | `ui/hud/hero_sigil_card/hero_sigil_card.gd` |
| `xp` | `ui/hud/xp_track/xp_track.gd` |
| `xp_per_turn` | `ui/hud/xp_track/xp_track.gd` |
| `sp_gain_on_levelup` | `ui/hud/xp_track/level_up_flourish.gd` (`stamp()`'s "+N SP — LEVEL L" detail line) — indirect: the SP total comes from `Entity.sp_minted_for_level()` (`entity/entity.gd`), which reads this stat plus the every-5th-level milestone bonus (owner-confirmed 2026-09-16, was proposed hidden) |
| `ap_transfer_rate` | `ui/hud/action_cluster/action_cluster.gd` (`_refresh_conversion()`, the "⇒ +N move · +N dealloc" line, scene-ordered directly above `EndTurnButton`) — indirect: shows the computed conversion, not the raw rate (owner-confirmed 2026-09-16, was proposed hidden). A named-rate hover sub-row is spec'd but unbuilt — see the follow-up issue below |

## Initiative

| id | surface |
|---|---|
| `initiative` | `ui/initiative_bar.gd` (the per-seat clock bar); also ordering only, via `TurnManager.forecast` (`systems/turn_manager.gd`, reads `initiative.current`), drawn by `ui/hud/turn_forecast/turn_forecast_strip.gd` — never a printed number there (#910) |
| `initiative_speed` | Ordering only, via `TurnManager.forecast` (`systems/turn_manager.gd`, reads `initiative_speed.value`), drawn by `ui/hud/turn_forecast/turn_forecast_strip.gd` — no direct numeric row anywhere (#910 drift since the #914 research pass) |

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
| `cast_range_hops` | No surface drawn yet. Base 0 by contract — the spell's authored reach folds in as an overlay, so a bare board read prints the bonus alone; the magic card's rows are #793's (display), don't guess a row ahead of that |
| `cast_range_distance` | Same as cast_range_hops, pending #793 |

## Hidden — owner-confirmed 2026-09-16

None of these have a HUD row anywhere in the tree; each reads only as a
formula input or a turn-upkeep tuning lever. `core_health_scaling`,
`node_health_scaling`, `sp_gain_on_levelup`, and `ap_transfer_rate` were
proposed hidden here too, but turned out to already have a real (if indirect)
surface on investigation — see the tables above. The two rows below were
settled with the owner in conversation (2026-09-16, see #914); UI specs for
`tempo` and a richer `ap_transfer_rate` readout exist but are unbuilt — see
the follow-up issues linked from #914.

| id | reason |
|---|---|
| `blade_speed_half` | `v_half` in the speed-scaled blade damage curve (#779) — not attribute-driven (no `StatModifier`, read as a raw curve constant in `attack/melee/skill_blade.gd`/`blade_damage_instance.gd`), so it can't ride the attribute-hover path either. Visibility matters once blade-speed curve stats can roll as procgen modifiers — not before (owner call, 2026-09-16) |
| `blade_speed_multiplier_max` | `M` in the same curve (#779) — same reasoning and same procgen-modifier condition as `blade_speed_half` |
| `node_healing` | Base HP a node regenerates at turn start (D-9, #268 TBD) — node-local, read via `SkillNode.get_local_value`, no `StatModifier`. Blocked on #268 today; once it gets a surface, pair it with `node_healing_ramp` parenthetically, e.g. `node_healing (+ramp)` (owner call, 2026-09-16, matching the `armor + (min_damage_taken)` pairing convention). Also matters more once it can roll as a procgen modifier, same condition as blade_speed_half/multiplier_max |
| `node_healing_ramp` | Extra HP `node_healing` gains per consecutive undamaged turn (D-9, #268 TBD) — same read path and #268 block as `node_healing`; display format decided alongside it above |
| `tempo` | Once-per-turn kill-AP refund budget (#888) — a latch/pool consumed by the kill-refund mechanic, distinct from the action_points/deallocation_points/movement_points trio it refunds into. Placement spec'd (a lit/hollow pip trailing the AP gauge, owner call 2026-09-16) but unbuilt, and gated on a real mechanic question — see the follow-up issue |

## Hidden — still needs an owner pass

Never brought up in the 2026-09-16 review pass; the original proposed reason
stands until the owner confirms or re-homes it.

| id | proposed reason |
|---|---|
| `core_kill_xp` | XP bonus paid to the killer on this entity's core death (#774) — a one-shot payout term, read once by `LootSystem`, not a standing stat with a row |
| `dealloc_damage` | Flat HP damage per forced-dealloc in a battle cascade — a tuning lever read only inside the cascade resolver |
