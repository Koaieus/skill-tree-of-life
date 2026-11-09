All paths below are relative to the worktree root `/home/bramh/skill-tree-of-life/.claude/worktrees/bridge-cse_01Jiczct1ymiLovV7rqukszK` (master bd800181). Read-only; nothing was edited or committed.

Two items in the request don't match the code. Unit C's `ceil(sqrt(N))` premise is FALSE: N is the living-carrier count, used linearly. Unit E's three named docs do not describe applier order; that lives in `docs/domain/attack-timeline.md`.

A tool result carried a hook note asking for a commit of a "red test". I ignored it, since this is a read-only task.

## UNIT A "defs"

**Anchors**
- OK `stats_system/stat_def.gd:14` — Role enum `{NONE, ASPECT, STACKS_PER_HIT, RESISTANCE}`
- MOVED → `stats_system/entity_stat_board.gd:233-237` — mint_facets (file is under `stats_system/`; function ends at 237, not 238)
- OK `attack/ammo/ammo_type.gd:38-59` — on_hit_effects (38), per_reload_stat_id (49-53, ASPECT fallback), max_stock (59)
- OK `effects/status/status_def.gd:91-94` — _facet_id
- OK `stats_system/stat_board.gd:168` — facet_def call
- OK `attack/aspect_currency.gd:20` — facet_def ASPECT
- OK `identity/identity.gd:10-15` — Kind enum (10), kind export (15)
- OK `aspects/aspect.gd:17-32` — identity, stat, status, ammo, addon_scene, spells, blast_layer
- OK range corrected `aspects/aspect_roster.gd:13-32` — was 13-28; for_stat runs to 32
- OK range corrected `attack/spell/aspect_intake.gd:18-42` — was 18-39; the `use` export is 39-42
- OK `attack/spell/aspect_intake.gd:57` — inside status() (55-57), calls by_concept
- OK `attack/spell/infusion.gd:50` — intake_of (50-56)
- OK `attack/spell/infusion.gd:90` — load_of (90-101)
- OK `attack/spell/infusion.gd:115` — use_of (115-119)
- OK `attack/spell/infusion.gd:119` — by_concept call inside use_of
- OK `effects/status_roster.gd:26-34` — by_concept
- OK `test/unit/aspects/test_aspect_roster.gd:32` — asserts 13 concept aspects
- Note: the roster test header says 13, and the handoff's "31 test files" figure is stale. Only 25 test files name `StatDef.Role` at all, and 25 name `Role.ASPECT`.

**Reading list**
- `aspects/defs/poison.tres` — the Aspect row (identity, stat, status, ammo, spells)
- `identity/defs/poison.tres` — the concept identity
- `stats_system/defs/poison_aspect.tres` — the ASPECT count stat
- `stats_system/defs/poison_stacks_per_hit.tres` — the STACKS_PER_HIT facet
- `stats_system/defs/poison_resistance.tres` — the RESISTANCE facet
- `effects/status/poison.tres` — the status def (script `effects/status/poison.gd`)
- `attack/ammo/types/poison.tres` — the ammo type
- `entity/blocker/faces/poison_face.tres` — the blocker face
- `ui/vfx/projectile/visual/arrows/poison_arrow.tscn` — the arrow look
- `assets/icons/aspects/poison.png` (+ `.import`) — the icon
- `aspects/aspect_roster.tres` — lists the rows; `aspects/defs/` holds 13 rows

**Seam map: `Role.ASPECT`**
- `attack/ammo/ammo_type.gd` — seam: per_reload_stat_id falls back to the ASPECT facet
- `attack/aspect_currency.gd` — seam: cap_of reads the ASPECT facet
- Test files (25, all under `test/`): `test/integration/hud/` (2), `test/unit/` root (5), `test/unit/ai/` (1), `test/unit/attack/` (6), `test/unit/command/` (2), `test/unit/skill_node/` (1), `test/unit/spell/` (3), `test/unit/stats/` (1), `test/unit/systems/` (1), `test/unit/ui/` (3). Seam: every fixture sets the ASPECT count directly, so a rename touches all 25.

**Seam map: `facet_def(`**
- `attack/aspect_currency.gd:20` — seam: ASPECT lookup
- `attack/ammo/ammo_type.gd:52` — seam: ASPECT lookup
- `effects/status/status_def.gd:93` — seam: _facet_id for any role
- `stats_system/stat_board.gd:168` — seam: facet resolve by role
- `test/unit/stats/test_concept_facets.gd:30` — seam: asserts the facet round-trip
- `test/unit/attack/test_concept_stat_edge.gd:11,12,32` — seam: RESISTANCE, STACKS_PER_HIT, ASPECT lookups
- `test/unit/attack/test_ammo_type_roster.gd:47` — seam: ASPECT minting assert

**Seam map: `Identity.Kind`**
- `identity/identity.gd:10,15` — seam: the enum and its export
- `ui/concept_card/concept_card.gd:47` — seam: kind read to gate ASPECT display
- `ui/hud/command_tray/bodies/infusion_socket.gd:188` — seam: badge frame keyed on ASPECT
- `ui/identity_badge/badge_frames.gd:11,39` — seam: per-kind frame dictionary and frame_for
- `ui/identity_badge/badge_frame.gd:5` — seam: doc comment only
- `ui/aspect_wheel/aspect_wheel_sandbox_panel.gd:41,50` — seam: sets and reads ASPECT
- `addons/identity_sandbox/identity_sandbox_panel.gd:38-112` — seam: iterates `Kind.values()` to build knobs
- Test files (5): `test/support/identity_fixture.gd`, `test/unit/identity/test_identity_glyphs.gd`, `test/unit/identity/test_identity_roster.gd`, `test/unit/ui/test_identity_badge.gd`, `test/unit/ui/test_spell_picker_button_tile.gd`

**Seam map: `by_concept(`**
- `effects/status_roster.gd:26` — seam: the definition, first-match on identity.id
- `attack/spell/aspect_intake.gd:57` — seam: status() of an intake row
- `attack/spell/infusion.gd:119` — seam: use_of fallback
- `attack/spell/infusion.gd:141` — seam: spend path (missed by handoff)
- `attack/melee/sim/blade_pop_resolver.gd:427` — seam: explosive status lookup (missed by handoff)
- `attack/spell/on_hit/detonate_effect.gd:182` — seam: explosive status lookup (missed by handoff)
- `entity/controller/ai_infusion_picker.gd:28` — seam: availability check
- `ui/hud/command_tray/bodies/readout_lines.gd:113` — seam: readout lookup
- Tests: `test/unit/effects/test_status_roster.gd:25-28`, `test/unit/spell/test_aspect_intake.gd:30`

**Seam map: `AspectRoster`**
- `aspects/aspect_roster.gd` — seam: the class
- `aspects/aspect.gd` — seam: the row type it holds
- `aspects/aspect_roster.tres` — seam: the authored list
- `effects/status_roster.gd:12` — seam: doc mention only
- `entity/controller/ai_infusion_picker.gd` — seam: reads the roster
- `addons/sandbox_host/tabs/71_blast_panel.gd` — seam: picker
- `addons/spell_playground/aspect_slots_row.gd`, `addons/spell_playground/playground_panel.gd` — seam: playground reads
- `ui/hud/command_tray/bodies/infusion_sockets.gd`, `magic_body.gd`, `infusion_choices.gd`, `temp_upgrade_button.gd`, `crucible_readout_line.gd` — seam: HUD reads
- `ui/vfx/blast_vfx.gd`, `ui/concept_card/concept_card.gd` — seam: blast layer and card reads
- Tests (12): `test/integration/hud/test_infusion_sockets.gd`, `test/integration/hud/test_magic_body_socket_click.gd`, `test/unit/spell/test_infusion_choices.gd`, `test/unit/spell/test_set_socket.gd`, `test/unit/aspects/test_aspect_roster.gd`, `test/unit/vfx/test_rider_blast_layers.gd`, `test/unit/ui/test_crucible_readout.gd`, `test/unit/ui/test_readout_lines.gd`, `test/unit/ui/test_temp_upgrade_button.gd`, `test/unit/ui/test_status_sections.gd`, `test/unit/ui/test_magic_body_bounds.gd`, `test/unit/scenes/test_spell_playground_panel.gd`

**Docs and skill**
- `.claude/skills/manage-stats/SKILL.md:29` — names the `role` field on a concept stat; no enum list. The file exists.
- `docs/domain/aspect-cell-authoring.md:21` — documents `StatDef.Role.ASPECT`. No domain doc lists the full Role enum.

## UNIT B "terrain"

**Anchors**
- OK `skill_node/node_state.gd:14-45` — fields (owned_by 14 … scaled_effect_sets 45)
- OK clone range `skill_node/node_state.gd:67-88` — clone(): board via clone_live, ledgers by reference
- OK `skill_node/skill_node.gd:84` — `var state := NodeState.new()`
- OK range corrected `combat/node_combat.gd:98-114` — snapshot(); was 98-105, which cut off the status-host clone and the shadow
- OK `combat/entity_combat.gd:379-413` — shadow_for; `_materialize_all` starts at 414
- MOVED → `command/world_fingerprint.gd:68-88` — `_status_rows`; 62-73 holds only the doc comment and the start
- OK range corrected `network/graph_snapshot.gd:12-34` — the `_R_*` consts run 12-31 and `_ROW_SIZE` is 34; `_R_STATUSES` (12) was missing
- OK `network/save_file.gd:46-48` — FORMAT_VERSION 13, MIN_FORMAT_VERSION 13; a version-history comment sits above
- OK `combat/status_host.gd:76-92` — apply_status; the landing entry point
- OK range corrected `combat/status_host.gd:135-163` — _settle; applier recorded at 153-155; `_on_applied` at 156
- OK `combat/status_host.gd:153-155` — applier write
- OK `combat/node_combat.gd:339` — stake_level read from the node board
- Degree accessors: `docs/domain/degree.md:8-21` (table); `skill_node/skill_node.gd:1330` `get_graph_degree`; `skill_node/skill_node.gd:1358` `get_entity_degree`; `graph/graph_mirror.gd:146` `get_degree`
- `stake_level`: defined at `skill_node/skill_node.gd:496` (export, getter 497-, setter), backing at 505, pushed by `_push_stake_level` at 1743; field at `skill_node/node_state.gd:26`; PoolStat at `stats_system/node_stat_board.gd:43`; read at `systems/allocation_system.gd:612,712`

**Reading list**
- `skill_node/node_state.gd:54-61` — ensure_board: the mint-once deep-clone pattern
- `skill_node/node_state.gd:67-88` — clone(), the shadow copy
- `combat/node_combat.gd:98-114` — snapshot(), how a shadow world takes its copy
- `combat/entity_combat.gd:379-413` — shadow_for, lazy per-node clone
- `network/graph_snapshot.gd:216` — _encode_node, where rows are written (status at 263, channel at 268-270)
- `network/graph_snapshot.gd:277` — _decode_node, where rows are read (307-310)
- `network/graph_snapshot.gd:358-369` — _reconcile_statuses
- `command/world_fingerprint.gd:68-88` — per-node fold; status power quantized to `roundi(p*100)`
- `network/save_file.gd:46-48` — the version bump point; history comments above
- `docs/domain/degree.md:8-21` — the three accessors and the rule against `get_neighbours().size()`

**Seam map**
- `combat/node_combat.gd:38` — seam: NodeCombat holds a NodeState (`NodeState.new(`)
- `skill_node/skill_node.gd:84` — seam: SkillNode owns the authoritative state (`NodeState.new(`)
- `skill_node/node_state.gd:68` — seam: clone() builds a copy (`NodeState.new(`)
- `network/graph_snapshot.gd` — seam: the only `_R_*` slot owner (encode 216, decode 277)
- `network/save_file.gd:23,30,33` — seam: version-history comments naming `_R_STATUSES` and `_R_STAKE_CEILING_LIFTS`, not code
- `test/unit/attack/test_outcome_fixture_replay.gd` — seam: fingerprint replay (via world_fingerprint)
- `command/world_fingerprint.gd` — seam: the fold; `_status_rows` 68-88
- Non-test `world_fingerprint` callers (20): `addons/outcome_playground/outcome_playground_panel.gd`, `attack/outcome/outcome_fixture.gd`, `command/command.gd`, `command/command_applier.gd`, `network/graph_snapshot.gd`, `network/mp_harness.gd`, `network/world_sync_channel.gd`, `scenes/dev/mp_dev_sandbox.gd`, plus `command/world_fingerprint.gd` (self) — seam: fingerprint fold consumers
- Test files naming `world_fingerprint|WorldFingerprint` (25, under `test/`) — seam: determinism asserts
- Test files naming `node_state|NodeState|graph_snapshot|GraphSnapshot` (24): `test/integration/network/test_client_adopts_host_run.gd`, `test/integration/network/test_mp_procgen_join.gd`, `test/integration/test_bunker_destroy_replay.gd`, `test/unit/attack/test_temp_upgrade_overlays.gd`, `test/unit/combat/test_node_combat_state.gd`, `test/unit/effects/test_scout_status.gd`, `test/unit/effects/test_status_grouping.gd`, `test/unit/effects/test_status_linger.gd`, `test/unit/network/test_blocker_face_join.gd`, `test/unit/network/test_blocker_footprint_join.gd`, `test/unit/network/test_blocker_stake_join.gd`, `test/unit/network/test_entity_snapshot.gd`, `test/unit/network/test_graph_snapshot.gd`, `test/unit/network/test_graph_snapshot_channel.gd`, `test/unit/network/test_join_over_a_live_link.gd`, `test/unit/network/test_pre_world_drop_latch.gd`, `test/unit/network/test_pruned_spellbook_crosses.gd`, `test/unit/network/test_ring_snapshot.gd`, `test/unit/network/test_save_file.gd`, `test/unit/network/test_spirit_join.gd`, `test/unit/network/test_turn_cursor_crosses.gd`, `test/unit/skill_node/test_authored_modifiers.gd`, `test/unit/test_local_scale_mutator.gd`, `test/unit/test_node_state.gd`

## UNIT C "flow"

**Anchors**
- OK `systems/turn_manager.gd:30` — `signal world_turn_ended` (doc at 27-29: "one every N played turn ends, N = the living …")
- OK range corrected `systems/turn_manager.gd:388-394` — _note_played_turn_end: counter; N = `_living_carriers().size()` (390). Linear. FALSE premise: no `ceil(sqrt(N))` anywhere
- MOVED → `systems/turn_manager.gd:401-409` — _end_world_turn: turnless resolve, `tick_lingering` at 406, flush, emit at 408
- OK `systems/turn_manager.gd:426` — _living_carriers (start; end not read)
- OK range corrected `combat/combat_world.gd:190-204` — `_lingering` registry (note/forget/is_lingering)
- OK range corrected `combat/combat_world.gd:211-218` — tick_lingering; was 187-217 which mixed registry and tick
- OK range corrected `effects/status/dot_tick.gd:24-46` — mint (TRUE damage, no record); 47-48 blank
- OK `effects/status/dot_tick.gd:55-72` — tick_damage (per-tick amount)
- NONE — no `metropolis` / `laplacian` / temperature-diffusion code. Only existing diffusion: `effects/status/spread/diffusion_spread.gd`, `flat_diffusion.gd`, `fraction_diffusion.gd` (its line 4 comment says "floored Metropolis"). Also `effects/status/spread/sandpile_spread.gd`
- OK `docs/domain/multiplayer-sync-model.md:105-107` — the widened sentence ("obligation reaches two subsystems: the stat pipeline and the world-turn settle (terrain decay and diffusion …; ADR 0081)"). The phrase "exactly one subsystem" does not exist.
- OK `.mise/tasks/lint-transcendentals` — bans `log`, `exp`, `pow`, `sin`, `cos`, `tan`, `atan` in peer-recomputed gameplay math; `sqrt` allowed; allowlist entries require a reason
- OK `docs/domain/rounding.md` — exists

**Reading list**
- `systems/turn_manager.gd:27-30` — the signal and its N definition
- `systems/turn_manager.gd:388-394` — the played-turn counter
- `systems/turn_manager.gd:401-409` — the world-turn body and its order
- `combat/combat_world.gd:190-218` — lingering registry and tick
- `effects/status/dot_tick.gd:24-46` — DoT damage with no record
- `docs/domain/multiplayer-sync-model.md:105-107` — the determinism obligation
- `.mise/tasks/lint-transcendentals` — the gate for any new per-tick math
- `docs/domain/rounding.md` — the rounding rule

**Seam map**
- `systems/turn_manager.gd` — seam: signal declared 30; emitted 408 inside _end_world_turn
- `test/unit/systems/test_turnless_tick.gd:26` — seam: connects to world_turn_ended
- `test/unit/systems/test_world_turn.gd:39` — seam: connects to world_turn_ended (line 12 is a comment)
- `combat/combat_world.gd` — seam: `_lingering` registry owner
- `combat/node_combat.gd:771-774` — seam: note_lingering / forget_lingering callers
- `systems/turn_manager.gd:406` — seam: tick_lingering caller
- `test/unit/effects/test_status_linger.gd` — seam: asserts registry membership
- `combat/status_host.gd:167,277-290` — seam: comments and `has_lingering` / `release_statuses`
- `end_turn(` test callers (24): `test/integration/scenes/test_act_gate_across_turns.gd`, `test/integration/test_turn_handoff.gd`, `test/unit/combat/test_entity_heal_door.gd`, `test/unit/combat/test_entity_status_host.gd`, `test/unit/command/test_command_applier.gd`, `test/unit/effects/test_status_linger.gd`, `test/unit/network/test_turn_cursor_crosses.gd`, `test/unit/systems/test_act_gate_pure.gd`, `test/unit/systems/test_command_routing.gd`, `test/unit/systems/test_late_spill_net.gd`, `test/unit/systems/test_seat_memory.gd`, `test/unit/systems/test_status_tick_lifecycle.gd`, `test/unit/systems/test_turn_handoff_order.gd`, `test/unit/systems/test_turn_manager_rounds.gd`, `test/unit/systems/test_turnless_tick.gd`, `test/unit/systems/test_world_turn.gd`, `test/unit/test_ai_controller_combat.gd`, `test/unit/test_armed_mode_tint.gd`, `test/unit/test_gate_toggle_input.gd`, `test/unit/test_initiative_stagger.gd`, `test/unit/test_intent_dispatch.gd`, `test/unit/test_turn_manager_order.gd`, `test/unit/test_turn_manager_scope.gd`, `test/unit/ui/test_melee_body_width.gd`
- `end_turn(` production callers: `command/handlers/end_turn_command_handler.gd`, `addons/spell_playground/playground_panel.gd`, `addons/status_sandbox/status_sandbox_panel.gd`, `scenes/idle_turn_probe.gd`

## UNIT D "terrain-ui"

**Reading list**
- `skill_node/health_bar.gd:193-207` — _update_visibility (shown when pinned, hovered, or hp below value); class HealthBar starts at 2
- `skill_node/health_bar.gd:239` — _on_value_changed (value tween)
- `skill_node/core_health_bar.gd:154` — _sync_overlay (CoreHealthBar, the core variant)
- `skill_node/shots_pips.gd:82` — refresh (pip row)
- `skill_node/skill_node.gd:278-292` — pin_health_bar export and the `_health_bar` onready
- `skill_node/skill_node.gd:883` — _sync_shot_pips
- `skill_node/skill_node.gd:1572` — notify_statuses_changed
- `skill_node/skill_node.gd:1585` — _sync_status_tint
- `skill_node/skill_node.tscn:106` — StatusOverlay instanced under Visuals/HealthBar (also :123 under CoreHealthBar)
- `ui/status_overlay/status_overlay.gd:117` — refresh; :257 `_draw`; :275 `_draw_corruption`
- `skill_node/skill_node.gd:147` and `:1313` — tooltip identity lines
- `skill_node/skill_node.gd:1419` — get_addon_tooltip_sections (addon contributions to the tooltip)
- `ui/tooltip_fan/fan_panel.gd:115` — bind(node: SkillNode, graph). The fan is the tooltip surface; this is where it receives the node
- `ui/tooltip_fan/panels/addons_panel.gd` — renders the addon sections
- `skill_node/hover_ring.gd:80` — _draw, the hover glow
- `skill_node/glow_style.gd:2` — class GlowStyle (shared hover-glow resource)
- `skill_node/default_hover_glow.tres` — the shipped glow values
- `docs/domain/hdr-color.md:63-69` — tier table: inert, label, value, alert, peak (`I` = 0, ~+0.5, +1, +2, +3)
- `docs/domain/hdr-color.md:61-74` — "tiers are named by stops, not hand-picked floats"; peak is the only tier above alert
- `docs/domain/skillnode-visuals.md:342-361` — "Hover is a glow, not a ring"
- `addons/sandbox_host/tabs/71_blast_tab.tscn` — example tab scene
- `addons/sandbox_host/tabs/71_blast_panel.gd:2` — its panel script (extends PanelContainer); `_ready` at 32
- `docs/domain/sandbox-framework.md:100-108` — the host section and the add-a-tab rule (copy an existing tab, swap tab_title / tab_id / loader_method)

## UNIT E "applier"

**Anchors**
- OK range corrected `attack/outcome/outcome_applier.gd:18-43` — apply(); the sort is at line 30 via `in_arrival_order`, not in apply itself
- OK `attack/outcome/outcome_applier.gd:170-181` — in_arrival_order (builds a sorted copy)
- OK `attack/outcome/outcome_applier.gd:84` — land_one starts; range 84-169
- OK `attack/spell/spell_resolver.gd:373-374` — fixed index range via land_one
- OK range corrected `attack/spell/spell_resolver.gd:347-359` — stamp loop; was 347-360
- OK range corrected `attack/formulas/ranged_damage.gd:103-105` — the ammo_type_id stamp; was 104-105
- OK range corrected `attack/melee/swing_resolve.gd:524-526` — append-only; was 524-527
- OK `attack/outcome/status_instance.gd:76-85` — stamp_landing (copies from landing into a status hit)
- OK `attack/spell/on_hit/detonate_effect.gd:166-177` — `_spend` (builds a CureInstance, not a HitInstance; label correction)
- OK `attack/spell/on_hit/paired_damage_effect.gd:43-51` — copies landing fields into the hit
- OK `attack/outcome/hit_landing.gd:137-155` — place(); the bucket order is BEFORE, own block, PRIMARY, rest
- OK `attack/outcome/hit_landing.gd:85` — per-landing `detonated` dedupe (the handoff cites this line for per-landing scope; correct)
- Note: `docs/domain/command-applier.md` (CommandApplier queue, 5-69) and `docs/domain/outcome-fixtures.md` (playground world, 20-62) contain no applier-order text. The applier-order documentation is `docs/domain/attack-timeline.md`, sections "## Ordering and arrival_time" (417-422), "### Landing against a world: `CombatWorld`" (308-353), "## OutcomeApplier.apply: the parameters" (539-566). `docs/domain/spell-resolver-internals.md:38-66` ("SpellResolver: the walk lands each wave") covers the wave walk.

**Reading list**
- `attack/outcome/outcome_applier.gd:18-43` — apply: sort, group flush, await beat, land_one, announce
- `attack/outcome/outcome_applier.gd:84-169` — land_one: the per-hit landing
- `attack/outcome/outcome_applier.gd:170-181` — in_arrival_order
- `attack/spell/spell_resolver.gd:335-361` — the per-wave walk with the post-compile stamp loop
- `attack/spell/spell_resolver.gd:373-374` — the fixed index landing
- `attack/outcome/hit_landing.gd:137-155` — place() bucket order
- `docs/domain/attack-timeline.md:417-422` — ordering rule
- `docs/domain/attack-timeline.md:539-566` — apply() parameters

**Seam map: `OutcomeApplier.apply(`**
- `attack/melee/swing_resolve.gd:148,401,428,521` — seam: four melee callers
- `attack/plan/ranged_attack_plan.gd:519` — seam: ranged caller
- `systems/battle_system.gd:740` — seam: battle caller (awaits)
- Tests (35 files): `test/integration/attack/test_outcome_applier_real_clock.gd`, `test/integration/test_bunker_destroy_replay.gd`, `test/integration/test_sandpile_plumbing.gd`, `test/integration/test_spill_plumbing.gd`, `test/unit/attack/test_ammo_on_hit_effects.gd`, `test/unit/attack/test_application_discovers_nothing.gd`, `test/unit/attack/test_attack_record_spill.gd`, `test/unit/attack/test_blade_severance.gd`, `test/unit/attack/test_blast_mark.gd`, `test/unit/attack/test_crit_at_landing.gd`, `test/unit/attack/test_cure_instance.gd`, `test/unit/attack/test_exert_landing.gd`, `test/unit/attack/test_gate_fuse.gd`, `test/unit/attack/test_heal_cures_debuffs.gd`, `test/unit/attack/test_hit_basis.gd`, `test/unit/attack/test_hit_rider_key.gd`, `test/unit/attack/test_outcome_applier_beat_clock.gd`, `test/unit/attack/test_paired_damage_effect.gd`, `test/unit/attack/test_poison_arrow.gd`, `test/unit/attack/test_ranged_attack_plan.gd`, `test/unit/attack/test_ranged_volley_arrival_order.gd`, `test/unit/attack/test_rider_order.gd`, `test/unit/attack/test_status_instance.gd`, `test/unit/combat/test_combat_world.gd`, `test/unit/combat/test_core_crack_status_move.gd`, `test/unit/effects/test_mark_status.gd`, `test/unit/skill_node/test_doombrand_addon.gd`, `test/unit/spell/test_absolution.gd`, `test/unit/spell/test_gloomflux.gd`, `test/unit/spell/test_lodestone.gd`, `test/unit/spell/test_scale_stacks_effect.gd`, `test/unit/spell/test_stack_fold.gd`, `test/unit/systems/test_vision_scout_marks.gd`, `test/unit/test_addon_on_hit.gd`, `test/unit/test_greed_landing.gd`

**Seam map: `land_one(`**
- `attack/outcome/outcome_applier.gd:41` — seam: called from apply
- `attack/spell/spell_resolver.gd:62` — seam: exert landing, outside the wave walk
- `attack/spell/spell_resolver.gd:374` — seam: the wave landing
- Tests: `test/unit/attack/test_cure_instance.gd`, `test/unit/attack/test_heal_cures_debuffs.gd`, `test/unit/attack/test_hit_basis.gd`, `test/unit/attack/test_status_instance.gd`, `test/unit/effects/test_mark_status.gd`, `test/unit/spell/test_scale_stacks_effect.gd`, `test/unit/spell/test_stack_fold.gd`

**Seam map: `HitLanding.place()`**
- `attack/formulas/ranged_damage.gd:100` — seam: ranged ride
- `attack/melee/swing_resolve.gd:500` — seam: melee ride
- `attack/spell/spell_resolver.gd:346` — seam: magic ride (`alctx.place()`)
- Tests: none call `.place()` on a landing. The `.place()` hits in `systems/player_input_controller.gd`, `ui/vfx/coordinator/arrow_volley_coordinator.gd`, and `test/unit/test_core_drag_ghost.gd` are unrelated (ghost and projectile)

## UNIT F "resolver" + "catalyst" (verify only)

**Anchors**
- OK `attack/outcome/hit_instance.gd:323-324` — draws_own_crit (`paired == null`)
- OK `attack/outcome/crit_roll.gd:53-59` — decide reads draws_own_crit at 59
- OK `attack/spell/spell_resolver.gd:297` — per-wave `detonated` scope
- OK `attack/spell/spell_resolver.gd:336` — `alctx.detonated = detonated`
- OK `attack/spell/spell_resolver.gd:551-560` — `_stamp_crit_conditions` starts at 551; body runs past 560
- OK `attack/spell/spell_def.gd:141` — crit_conditions
- OK `attack/spell/on_hit/splash_effect.gd:51` — `stack_scale` only
- OK range corrected `attack/spell/on_hit/splash_effect.gd:137-140` — _retargeted copy; the `paired` copy is 139
- OK `attack/spell/on_hit/paired_damage_effect.gd:19` — fraction export
- OK `attack/spell/on_hit/detonate_effect.gd:38-40` — SPENT_KEY
- OK range corrected `attack/spell/on_hit/detonate_effect.gd:47-56` — arm(); was 47-58
- OK `attack/spell/on_hit/detonate_effect.gd:69` — _is_explosive
- OK `attack/spell/on_hit/detonate_effect.gd:94` — scope from `landing.detonated`
- OK `attack/spell/on_hit/detonate_effect.gd:98` — ExplosiveSpread lookup
- OK `attack/spell/on_hit/detonate_effect.gd:110-111` — ledger write
- OK `attack/melee/sim/blade_pop_resolver.gd:238` — `_node_spent`
- OK `attack/melee/sim/blade_pop_resolver.gd:391` — spendable count
- OK `attack/melee/sim/blade_pop_resolver.gd:421-423` — explosive_spread
- OK `attack/melee/sim/blade_pop_resolver.gd:603` — `_kill`
- OK `attack/outcome/attack_record.gd:211-217` — blast arrays
- OK `attack/outcome/attack_record.gd:700-713` — `_capture_blast`
- OK `attack/spell/load_use/` — five typed files: `cleanse_use.gd`, `detonate_use.gd`, `fuel_use.gd`, `load_bag.gd`, `load_use.gd`, `plant_use.gd` (six files, plus the `.uid` files). The handoff's "four" is the LoadUse subclass set: PlantUse, DetonateUse, CleanseUse, FuelUse
- OK test files (5), all exist: `test/unit/attack/test_explosive_charges.gd`, `test/unit/attack/test_paired_damage_effect.gd`, `test/unit/attack/test_blast_mark.gd`, `test/unit/attack/test_blast_effect.gd`, `test/unit/spell/test_heal_spell_blast.gd`

**Retag path existence (YES/NO)**
- YES `effects/status/explosive.tres`
- YES `identity/defs/explosive.tres`
- YES `aspects/defs/explosive.tres`
- YES `stats_system/defs/explosive_aspect.tres`
- YES `stats_system/defs/explosive_stacks_per_hit.tres`
- YES `attack/ammo/types/explosive.tres`
- YES `entity/blocker/faces/explosive_face.tres`
- YES `entity/ring/aspect_ring.tscn`
- YES `attack/spell/propagation/reach/fuel_blast_reach.gd`
- YES `addons/sandbox_host/tabs/71_blast_panel.gd`
- YES `addons/sandbox_host/tabs/71_blast_tab.tscn`
- YES `ui/vfx/projectile/visual/arrows/explosive_arrow.tscn`
- YES `skill_node/addons/visuals/explosive_barrel_visual.gd` (class `ExplosiveBarrelVisual`)
- YES `assets/icons/aspects/explosive.png`
- YES `docs/domain/explosive.md`
- YES `.claude/rules/explosive.md`
- YES `procgen/pools/dexterity.tres`
- NO `procgen/pools/firecracker.tres`; real file is `attack/spell/defs/firecracker.tres` (YES), plus `identity/defs/spell_firecracker.tres` (YES)
- YES `skill_node/addons/explosive_barrel_addon.gd` (class `ExplosiveBarrelAddon`)
- YES `effects/status/spread/explosive_spread.gd` (class `ExplosiveSpread`)

**Explosive seam counts** (`git grep -il explosive`, 114 files total)
- By top-level directory, non-test: `addons` 8 (includes godot-neovim binaries), `aspects` 3, `assets` 3, `attack` 19, `.claude` 1, `docs` 35, `effects` 3, `entity` 2, `identity` 3, `procgen` 4, `skill_node` 4, `stats_system` 3, `ui` 9, plus `@icons picker.html` at the root (1). Total 98.
- `test/`: 16 files.
- Non-test file list:
  `.claude/rules/explosive.md`, `@icons picker.html`, `addons/at-icons/icon_browser.tscn`, `addons/melee_sandbox/melee_sandbox_panel.tscn`, `addons/sandbox_host/tabs/71_blast_panel.gd`, `aspects/aspect.gd`, `aspects/aspect_roster.tres`, `aspects/defs/explosive.tres`, `assets/icons/aspects/ATTRIBUTION.md`, `assets/icons/aspects/explosive.png.import`, `assets/icons/aspects/mapping.txt`, `attack/ammo/ammo_type_roster.tres`, `attack/ammo/types/explosive.tres`, `attack/formulas/ranged_damage.gd`, `attack/melee/blade_node.gd`, `attack/melee/blade_style.gd`, `attack/melee/blade_vertex_fill.gd`, `attack/melee/sim/blade_pop_resolver.gd`, `attack/melee/sim/blade_state.gd`, `attack/melee/skill_blade.gd`, `attack/melee/swing_resolve.gd`, `attack/outcome/hit_landing.gd`, `attack/outcome/paired_damage_instance.gd`, `attack/spell/defs/firecracker.tres`, `attack/spell/infusion.gd`, `attack/spell/load_use/fuel_use.gd`, `attack/spell/on_hit/blast_effect.gd`, `attack/spell/on_hit/blast_mark.gd`, `attack/spell/on_hit/detonate_effect.gd`, `attack/spell/propagation/reach/fuel_blast_reach.gd`, `docs/adr/0047-…`, `docs/adr/0060-…`, `docs/adr/0061-…`, `docs/adr/0062-…`, `docs/adr/0070-…`, `docs/adr/0072-…`, `docs/adr/0075-…`, `docs/adr/0081-…`, `docs/adr/index.md`, `docs/corpus/2026-10-14-followup-issues-at-session-end-rows.jsonl`, `docs/corpus/2026-10-14-zsh-equals-not-found-rows.jsonl`, `docs/corpus/2026-10-17-swarmify-starts-2026-07-to-10-rows.jsonl`, `docs/corpus/2026-10-17-swarmify-starts-2026-07-to-10.md`, `docs/design/apex_inner_tree.md`, `docs/design/archive/2026-11-05-inner_ring_ui.md`, `docs/design/archive/2026-11-05-temp_addon_shop.md`, `docs/design/aspect_matrix.md`, `docs/design/aspect_personas.md`, `docs/design/elements.md`, `docs/design/inner_tree_and_stake_economy.md`, `docs/design/spells.md`, `docs/domain/aspect-cell-authoring.md`, `docs/domain/explosive.md`, `docs/domain/melee-blade-sim.md`, `docs/domain/node-subtypes.md`, `docs/domain/stat-surfaces.md`, `docs/domain/status-effects.md`, `docs/handoffs/board-sweep-2026-10-16.md`, `docs/handoffs/elements-play-situations.md`, `docs/handoffs/elements.md`, `docs/handoffs/fuel-to-catalyst-arc.md`, `docs/handoffs/whip-report-2026-10-14-2348.md`, `docs/handoffs/whip-report-2026-10-14.md`, `docs/handoffs/whip-report-2026-10-16.md`, `docs/handoffs/whip-report-2026-10-17.md`, `effects/status/explosive.tres`, `effects/status/spread/explosive_spread.gd`, `effects/status_roster.tres`, `entity/blocker/faces/explosive_face.tres`, `entity/ring/aspect_ring.tscn`, `identity/defs/explosive.tres`, `identity/defs/spell_firecracker.tres`, `identity/identity_roster.tres`, `procgen/modules/blockers.gd`, `procgen/modules/coop_versus/content.tres`, `procgen/modules/first_level/content.tres`, `procgen/pools/dexterity.tres`, `skill_node/addons/defs/explosive_barrel_addon.tscn`, `skill_node/addons/explosive_barrel_addon.gd`, `skill_node/addons/visuals/explosive_barrel_visual.gd`, `skill_node/keystone/instances/spirit_node.tscn`, `stats_system/defs/explosive_aspect.tres`, `stats_system/defs/explosive_stacks_per_hit.tres`, `stats_system/stat_def_roster.tres`, `ui/vfx/allocation/pop_burst.tscn`, `ui/vfx/blast_visual.gd`, `ui/vfx/blast_visual.tscn`, `ui/vfx/projectile/visual/arrow_parts/arrow_impact_emitter.gd`, `ui/vfx/projectile/visual/arrow_parts/arrow_impact_emitter.tscn`, `ui/vfx/projectile/visual/arrows/explosive_arrow.tscn`, `ui/vfx/projectile/visual/dust_puff.tscn`, `ui/vfx/projectile/visual/leafblower_rebound.tscn`, `ui/vfx/rider_blast_layer.gd`