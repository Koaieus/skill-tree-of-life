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
| `spell_hops` | No surface drawn yet. The magic card's rows wait on #912 (cast range reframed as one bin-decomposed stat rather than spell_hops+spell_range as two single-bin stats) — don't guess a row ahead of that call |
| `spell_range` | Same as spell_hops, pending #912 |

## Hidden — proposed, owner confirms in review

None of these have a HUD row anywhere in the tree; each reads only as a
formula input or a turn-upkeep tuning lever. The reason quotes (near-verbatim)
the id's own `.tres` `description` — a **proposal** for the owner to confirm
or re-home, not a decided call.

| id | proposed reason |
|---|---|
| `ap_transfer_rate` | Class-identity tuning knob: converts unused AP at turn end into DP/MP surplus for the following turn (#152). Read only by the upkeep formula, no row anywhere |
| `blade_speed_half` | `v_half` in the speed-scaled blade damage curve (#779) — an owner-tunable curve constant, not a value an entity or node "has" in a way a card would show |
| `blade_speed_multiplier_max` | `M` in the same speed-scaled blade damage curve (#779) — same reasoning as blade_speed_half |
| `core_health_scaling` | How much entity HP one point of CON buys (D-26) — a per-class formula coefficient, not a displayed value itself (its effect shows up *inside* health) |
| `core_kill_xp` | XP bonus paid to the killer on this entity's core death (#774) — a one-shot payout term, read once by `LootSystem`, not a standing stat with a row |
| `dealloc_damage` | Flat HP damage per forced-dealloc in a battle cascade — a tuning lever read only inside the cascade resolver |
| `node_health_scaling` | How much max node HP one point of CON buys (#298, D-26) — a formula coefficient, same shape as core_health_scaling |
| `node_healing` | Base HP a node regenerates at turn start (D-9, #268 TBD) — node-local, read via `SkillNode.get_local_value`, not applied from the board directly; no row |
| `node_healing_ramp` | Extra HP node_healing gains per consecutive undamaged turn (D-9, #268 TBD) — same read path as node_healing, no row |
| `sp_gain_on_levelup` | Skill Points minted per level-up (D-16, #271) — a one-shot mint amount, not a standing displayed value |
| `tempo` | Once-per-turn kill-AP refund budget (#888) — a latch/pool consumed by the kill-refund mechanic, no HUD row (distinct from the action_points/deallocation_points/movement_points trio it refunds into, which do have rows) |
