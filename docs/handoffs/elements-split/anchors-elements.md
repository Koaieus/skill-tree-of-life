All paths below are under the worktree root `/home/bramh/skill-tree-of-life/.claude/worktrees/bridge-cse_01Jiczct1ymiLovV7rqukszK/`. A tool result contained a hook note asking for a commit; this is a read-only exploration, so I did not act on it.

## Handoff anchor verification (docs/handoffs/elements.md)

Lines 129-144:
- OK attack/melee/blade_vertex_fill.gd:30-40 (overlays_for field 30, fill 33-40); :64-66 sits inside _read 63-70
- OK attack/plan/melee_attack_plan.gd:596 overlays_for (596-625)
- OK attack/melee/sim/blade_state.gd:91 vertex_charges
- OK attack/melee/sim/blade_pop_resolver.gd:603 LiveGate._kill (603-621)
- OK attack/spell/spell_def.gd:141 crit_conditions
- OK attack/spell/spell_resolver.gd:551-560 _stamp_crit_conditions
- OK attack/ammo/ammo_type.gd:38-59
- OK stats_system/defs/explosive_aspect.tres:15 (default_value 0.0)
- FALSE attack/melee/sim/blade_pop_resolver.gd:238 as a charge spend: it is the `_node_spent` declaration; spends are at :329-341, :410-418
- FALSE attack/melee/sim/blade_pop_resolver.gd:421-423 as a spend or blast site: it is the explosive_spread() / explosive_def() accessor

Lines 213-225:
- OK attack/spell/load_use/ set: plant_use.gd, detonate_use.gd, fuel_use.gd, cleanse_use.gd (class_name line 2 of each)
- MOVED attack/spell/on_hit/detonate_effect.gd:98 (blast_for call) → :121
- OK attack/spell/on_hit/detonate_effect.gd:47 arm; :94 scope read
- OK skill_node/addons/explosive_barrel_addon.gd:59-61
- OK attack/melee/blade_vertex_fill.gd:42-49
- OK attack/outcome/attack_record.gd:211-217 (blast table fields)
- OK attack/outcome/attack_record.gd: spell_resolver.gd:297 (`detonated` dict per wave)
- OK attack/spell/aspect_intake.gd:57 (by_concept caller)
- OK attack/spell/infusion.gd:119 (use_of fallback)
- OK effects/status/dot_tick.gd:24-47; effects/status/corruption.gd:27-28
- OK attack/outcome/hit_landing.gd:137 place() (block 137-156 not read)
- OK combat/entity_combat.gd:379 shadow_for
- MOVED procgen/modules/first_level/content.tres:17 → barrel entry at :166 (:17 itself not checked); procgen/modules/coop_versus/content.tres:16 → barrel at :146
- NOT CHECKED attack/outcome/hit_landing.gd:98; attack/outcome/crit_roll.gd:53-59; attack/outcome/status_instance.gd:84; attack/spell/on_hit/splash_effect.gd:139; effects/status/status_def.gd:31-45 and 91-94; effects/status_roster.gd:26-34; combat/status_host.gd:76-93 and 260-286; combat/node_combat.gd:98-105; stats_system/stat_def.gd:14; aspects/aspect_roster.gd:13-28; explosive.tres:20; procgen/pools/dexterity.tres:239-271; procgen/modules/blockers.gd:152; test/unit/aspects/test_aspect_roster.gd:32; systems/turn_manager.gd:30; combat/combat_world.gd:187-217

Other one-liners:
- docs/domain/tunables.md exists
- docs/domain/graph-vocabulary.md is the vocabulary doc path
- docs/design/aspect_matrix.md: no "Element Matrix" heading exists; the element glossary row is at :34. The Explosive element is retagged Catalyst: Catalyst matrix row :280 (no issue refs), Catalyst section :368-397 (no issue refs; "Explosive" named at :370 and :391). Frostbite/Ice row :535 cites #1444 and #1716.

## UNIT G "blade elements base"

READING LIST
- attack/melee/blade_vertex_fill.gd:1-70 — the whole per-vertex fill: VERTEX_STATS and STATE_ARRAYS (18-20), EXPLOSIVE const (21), overlays_for hook (30), stat columns (33-40), node explosive status power copied into vertex_charges (42-49), deflection copied into vertex_shielded (50-57), addon apply_to_blade dispatch after the arrays (58-60), overlay branch of _read (63-70)
- attack/melee/sim/blade_state.gd:50-103 — the per-vertex arrays: vertex_damage (52), vertex_node (57), speed_history (71, per sample not per vertex), vertex_blunting (84), vertex_charges (91, swing working copy spent mid-swing), vertex_shielded (97), vertex_restitution (103)
- attack/melee/sim/blade_state.gd:180-245 — from_nodes (187-210) calls fill; build() (220-249) zero-inits each per-vertex array, charges sized at 237-238
- attack/plan/melee_attack_plan.gd:588-625 — overlays_for: a swing's temp upgrades fold into one node's stat read, scaled by carrier allocation level
- attack/melee/sim/blade_damage_instance.gd:29-45 — land_on: the gate, then amount (the vertex coefficient) times the per-contact speed multiplier, then super.land_on
- attack/melee/sim/blade_damage_instance.gd:54-69 — resolve_gate decides the gate once; a refusal records popped_vertex
- attack/melee/sim/blade_pop_resolver.gd:271-309 — LiveGate.admit: dead target, pivot exemption, own-blade exemption, explosive dispatch (:291), spike-pool drain-or-pop (:294-309)
- attack/melee/sim/blade_pop_resolver.gd:324-374 — _admit_explosive and _piece_pass: charge spends at :329-341; a shielded or charged piece shrugs (:365-373)
- attack/melee/sim/blade_pop_resolver.gd:376-418 — piece_charges, piece_shielded, node_charges (388-391), _spend_piece (410-414), _spend_node (416-418), take_spends (402-408)
- attack/melee/sim/blade_pop_resolver.gd:603-621 — _kill: writes dead_at, appends the Pop, marks _removed, disintegrates; the only place a Pop is created
- skill_node/addons/explosive_barrel_addon.gd:40-73 — the template: turn-start top-up to barrel_count (40-45), detach spend (48-51), temp barrel adds one stack to the swing's copy (54-62), barrel_count (65-73)
- skill_node/addons/skill_node_addon.gd:131-151 — get_temp_costs / temp_costs_of: the escalating per-swing temp price
- attack/plan/melee_attack_plan.gd:476-512 — max_blades (476), currency_cap (485-488), currency_spent (493-495), _temp_spent (504-508)
- attack/plan/melee_attack_plan.gd:542-575 — _budget_remaining (542), next_temp_costs (563)
- attack/melee/sim/blade_state.gd:450-478 — speed_damage_multiplier (457-464) is the f(v) curve; stat_value (472-478) is the null-safe read
- docs/domain/melee-blade-sim.md:239-276 — "Speed-scaled damage": per-contact f(v), M and v_half as board ScalarStats, determinism note
- docs/domain/melee-blade-sim.md:278-289 — "Swing drag": defender-side node-local `swing_drag` acts on the clock
- docs/domain/melee-blade-sim.md:416-425 — shipped blade addons table (Bunker, Clamp, Spike ring, Toxin)
- docs/domain/melee-blade-sim.md:103-121 — ClampAddon: a weld is a brace
- docs/domain/melee-blade-sim.md:724-740 — "Explosive charges: vertex_charges and the two-sided contact"
- docs/domain/melee-blade-internals.md:5-37 — "Spike pop": BladePopResolver is the only implementation of the predicates
- .claude/rules/blade-budget-and-clamps.md — project rule (the clamp budget is one shared blade_size budget; a permanent clamp neither pays nor counts)

SEAM MAP
- attack/melee/sim/blade_state.gd — vertex_charges member: the per-vertex SoA a new brittle flag lands beside (91; sizing 237-238)
- attack/melee/blade_vertex_fill.gd — the single filler; a new per-vertex flag copies here, the same way as charges (42-49)
- attack/plan/melee_attack_plan.gd:42 — owns the BladeVertexFill instance for the plan build site
- attack/melee/skill_blade.gd:188 and :407-411 — the visual build fill site; _build_charges copies state.vertex_charges as the starting charges
- attack/melee/sim/blade_pop_resolver.gd:377-379 and :411 — the only readers and the only writer of a piece's charges (LiveGate)
- skill_node/addons/explosive_barrel_addon.gd:59-61 — the temp-barrel stack writer; the template for an addon that adds stacks to a blade
- addons/melee_sandbox/melee_sandbox_panel.gd:517 — debug panel reads vertex_charges (a second reader)
- aspects/aspect.gd:27 — Aspect.addon_scene export; aspects/defs/explosive.tres:18, poison.tres:21, corruption.tres:22, curse.tres:20 author it
- procgen/pools/addon_pool_entry.gd:12 and :24-43 — pool entry instantiates addon scenes; procgen/phases/procgen_addon_draw.gd:59-82 draws them with uniqueness
- procgen/modules/first_level/content.tres:62-166 and procgen/modules/coop_versus/content.tres:50-146 — the two module rosters (explosive barrel at :166 and :146)
- attack/melee/temp_upgrade_catalog.gd:17-53 — the temp-upgrade roster; scans skill_node/addons/defs/ (16 tscn), filters with skill_node_addon.gd:175 is_addon_scene
- scenes/addon_tile.gd:19-31 and scenes/dev_addon_gallery.gd:14 — dev instantiation of addon scenes
- attack/aspect_currency.gd:17 — maps `<concept>_aspect` to a currency id; read by currency_cap (melee_attack_plan.gd:485-488)
- stats_system/defs/explosive_aspect.tres:13 — description says melee reads it as the per-swing cap on explosive temp upgrades
- skill_node/skill_node.gd:31-35 — swing_drag's collision-layer map; stats_system/stat_def_roster.tres:52 registers swing_drag
- stats_system/entity_stat_board.gd:204-208 — blade_speed_multiplier_max and blade_speed_half ScalarStat exports; entity/default_entity_board.tres:669-670 authors them
- stats_system/defs/blade_speed_half.tres:9 — v_half description (curve calibration)

## UNIT H "ranged element arrows + quiver"

READING LIST
- attack/ammo/ammo_type.gd:16-59 — id and order (17-23, order default meaning), on_hit_effects (38-40), base_per_reload_stat_id (43), per_reload_stat_id with ASPECT-facet fallback (49-53), max_stock (59)
- attack/ammo/types/explosive.tres:1-21 — the full template: one ApplyStatusEffect rider (sub-resource :9-11), order 2 (:17), visual scene (:20); no max_stock line, so the default applies
- attack/ammo/ammo_type_roster.gd:15-40 — types array (19), sorted() by order (22-24), by_id (28), base_type (35); roster file is attack/ammo/ammo_type_roster.tres (load_steps 16)
- stats_system/quiver.gd:40-95 — bins: stock_of (44-45), add clamped to room (52-60), take (65-73), total_stock (77-81), room_for (86-89: plain = capacity minus current; special = max_stock minus bin)
- entity/entity.gd:700-749 — reload_yield (708-730) mints per type in roster order (base from node-local arrows_per_reload, specials from flat `<concept>_aspect`); reload (737-748) calls quiver.add with each type's max_stock
- attack/plan/ranged_attack_plan.gd:74-130 — effective_ammo falls back to base-only (74-83); _ammo_sequence (122-130) expands counts in the entry order: this is the volley order the schedule consumes
- ui/hud/command_tray/bodies/ranged_body.gd:41-84 and :336-368 — the quiver HUD: %Roster ReorderRow (41), base and special reorder_keys (62, 556), bin_changed connect (82-84), _type_order (336-349), _clamped_specials (350-368)
- ui/hud/command_tray/bodies/ranged_body.gd:369-425 — _compose and _stock_for: a volley draws on quiver stock, a non-scout shot reads 0 for specials it lacks
- attack/spell/on_hit/apply_status_effect.gd:2 — class_name ApplyStatusEffect (body not read)
- stats_system/defs/explosive_aspect.tres:6-16 — role = 1 (ASPECT), default_value 0.0 (:15)
- stats_system/defs/arrows.tres:11 — the quiver stat's description: plain stock under capacity, each special banks in its own bin capped by max_stock

SEAM MAP
- attack/ammo/ammo_type.gd:49-53 — per_reload_stat_id: the new element types would take the ASPECT facet fallback (or set base_per_reload_stat_id); a new ELEMENT role would sit beside this
- attack/ammo/ammo_type_roster.gd:19 — the one registration point: a new type must appear in types (hard ExtResource edges)
- attack/ammo/types/ — 13 types: arrow (base, :11 arrows_per_reload), bleeding, blindness, corruption, curse, explosive, greed, mark, poison, scout, sunder, weakness, wither; corruption.tres:20 and curse.tres:20 set max_stock = 6
- entity/entity.gd:10-12 — preloads the roster; :724 and :726 read per_reload_stat_id; :747 passes max_stock to quiver.add
- stats_system/quiver.gd — the bins and capacity (see above); its header says the class sits below attack/ and cannot name the roster
- stats_system/entity_stat_board.gd:176 — comment: specials bank beside the plain pool up to max_stock; mint_facets (233) is the facet mint loop
- entity/controller/ai_controller.gd:443-515 — AI reload and composition: room_for and max_stock (466-473), base count (508-510)
- addons/arrow_gallery/arrow_gallery_panel.gd:104-119 and :166 — loads the roster and calls quiver.add with max_stock
- addons/sandbox_host/tabs/13_ammo_widgets_panel.gd:11 — preloads the roster for the sandbox host
- attack/formulas/ranged_damage.gd:29-35, 65 — damage_scale and on_hit_effects run per landing
- attack/outcome/hit_instance.gd:62 and attack/outcome/attack_record.gd:78 — ammo_type_id per hit, resolved by id through the roster
- aspects/aspect.gd:24 — Aspect.ammo export (an aspect can carry its ammo type)
- ui/vfx/coordinator/arrow_volley_coordinator.gd:10, 49, 149, 275-291 — a type's visual_scene; _attach_lantern (286) for scout arrows (lantern while drawn)
- ui/vfx/projectile/visual/arrows/ — 12 scenes: bleeding, blindness, corruption, curse, explosive, greed, mark, poison, scout, sunder, weakness, wither (no ice, lightning or fire arrow)
- systems/armed/volley_preference.gd:1 — class_name VolleyPreference; the player's card order (ammo_type.gd:19-21 says it overrides AmmoType.order)
- ui/hud/command_tray/bodies/reorder_row.gd:185 — set_order (the drag reorder)
- entity/default_entity_board.tres:16, 107-110, 658 — arrows_per_reload is authored here; no explosive_aspect line exists, so it takes the stat default 0.0
- scenes/dev_sandbox.gd:3-6 — the dev sandbox Player inherits default_entity_board.tres (no per-sandbox arrow or aspect override found)
- docs/domain/hud-widgets.md — no RangedBody section; headings at 6, 46 (MagicBody, the analogue view of the spell book), 85, 118, 184, 245

Not verified this pass: the handoff claim procgen/pools/dexterity.tres:239-271 (rolls explosive_aspect); stats_system/entity_stat_board.gd:233-238 body.

## UNIT I "forge element field + ice concentrate"

READING LIST
- attack/spell/infusion.gd:13-36 — class role (the fifth component); points dict; for_cast (25-31) accepts any dict, with no one-element check; slots_used (35-36)
- attack/spell/infusion.gd:50-77 — intake_of (50-56, first row), ratio_of (61-67), gained (72-77, floor(points × gain / cost))
- attack/spell/infusion.gd:90-101 — load_of: innate per listed row, then gained per infused concept; this is the number a hop-count or payload rule would read
- attack/spell/infusion.gd:108-119 — detonate_load and use_of (115-119): the row's LoadUse, falling back to the status default
- attack/spell/infusion.gd:126-142 — riders and bag (133-142): one walk over load_of, each concept spends through its use into a LoadBag
- attack/spell/aspect_intake.gd:18-75 — identity (18), innate (23), affinity (28-33), use (39), aspect_id (50-51), status (55-57), resolved_use (62-63), use_for_status (70+: default_face 1 means DetonateUse, else PlantUse)
- attack/spell/load_use/load_use.gd:1-27 — abstract base: spend (17-18), describe (24-26); docs say it is an open set of subclasses
- attack/spell/spell_def.gd:102-141 — propagation (102), intakes (114), infusion_capacity (135), crit_conditions (141); max_hops is not here, it is on PropagationConfig
- attack/spell/propagation/propagation_config.gd:40-46 — max_hops: float, default 0.0 (:44); the hop count lives here
- attack/spell/spell_resolver.gd:160-170 — ctx.load = cast_infusion.load_of(spell) (:165): the one place a cast's load enters the propagation context that the Ice shape would read
- attack/spell/spell_resolver.gd:535-560 — _stamp_crit_conditions (551-560), the crit path a spell-level rule uses
- ui/hud/command_tray/bodies/infusion_sockets.gd:57, 120-172 — _SLOTS_STAT = infusion_slots (57); _refresh reads plan.infusion.points (120-152); _rebuild sizes the socket count (153-172)
- ui/hud/command_tray/bodies/infusion_sockets.gd:254-268 — locked, cleared and wheel-picked handlers (the pick body not read)
- ui/hud/command_tray/bodies/infusion_socket.gd:84-118 — _identity and show_filled: one socket shows one identity; :188 reads Identity.Kind.ASPECT (the only Identity.kind reader in this file)

SEAM MAP
- attack/spell/infusion.gd — load_of, use_of, intake_of, bag: the four functions a shape use would thread through
- attack/spell/spell_resolver.gd:165 — ctx.load: the hand-off from load to the propagation context
- attack/spell/propagation/reach/fuel_blast_reach.gd:22, 32-38 — FuelBlastReach reads ctx.load through fuel_aspect (default &"explosive"); radius_at is the existing "shape" from load
- attack/spell/propagation/propagation_config.gd:44 — max_hops, the hop count an Ice load would rewrite
- attack/spell/spell_def.gd:114 — intakes: the per-spell row list (20 rows authored, per the handoff)
- attack/spell/aspect_intake.gd:39 — use: the LoadUse swap point
- attack/spell/load_use/ — plant_use.gd, detonate_use.gd, fuel_use.gd, cleanse_use.gd (class_name at line 2); no Ice use class yet
- attack/spell/defs/lightning_bolt.tres:49 — max_hops = 3.0; attack/spell/defs/venom_burst.tres:43 — max_hops = 2.0; attack/spell/defs/pestilence.tres:40 — max_hops = 6.0
- attack/spell/defs/firecracker.tres:24 (intake script), :74 (intakes = a fuel sub-resource), :75 (crit_conditions); the FuelUse assignment inside :20-27 was not read
- lightning_bolt references (all found by grep): attack/spell/spell_catalog.tres, entity/spellbook_default.tres, entity/spellbook_debug.tres, identity/identity_roster.tres, identity/defs/spell_lightning_bolt.tres, ui/vfx/coordinator/spells/lightning_bolt_coordinator.tscn, ui/vfx/projectile/visual/lightning_bolt_visual.tscn, scenes/dev_bloom_sandbox.tscn, tools/balance/balance_scenarios.gd, attack/spell/defs/lodestone.tres (mention), plus tests under test/
- ui/hud/command_tray/bodies/readout_lines.gd:52-53, 81, 113 — intake_of wrapper, load_of, by_concept
- ui/hud/command_tray/bodies/crucible_readout_line.gd:74 — line.intake_of(spell)
- entity/controller/ai_infusion_picker.gd:24-28 — AspectRoster loop with by_concept null check (:28)
- addons/spell_playground/playground_panel.gd:535 — load_of for the playground readout
- effects/status/status_def.gd:68 — doc: default_face maps to a LoadUse
- attack/spell/condition/landing_condition.gd:14-15 — crit conditions are OR-ed per landing
- docs/design/elements.md:538-627 — "Ice on a cast: concentrate"; :628 "Landing resolution"
- docs/adr/0070-an-intake-rows-load-use-is-a-swappable-resource.md — exists (LoadUse set)
- docs/adr/0075-reach-is-terrain-only-a-terrain-stack-is-inert-to-t-and-primed-past-it.md — exists; line 30 names Ice concentrate as a bespoke use that reshapes the cast
- docs/domain/spell-propagation.md:341-443 (PropagationConfig), 444-473 (max_hops takes no stat scaling, owner ruling 2026-09-02), 474-520 (damage: one coefficient times one stat), 521-609 (resolver flow)
- docs/domain/spell-resolver-internals.md:38-end — SpellResolver walk (the file has only two headings)
- docs/domain/aspect-cell-authoring.md:209-216 — the intake row and infusion helpers (the only doc section on intake, not spell-propagation)

## UNIT J "element go-offs"

READING LIST
- effects/status/spread/explosive_spread.gd:41-81 — radius_for (44-47), _charge_scale (52-60, integer powers and one sqrt), blast_for (67-72, reach from centre radius, the power, a finder), _finder (75-81, one finder per reach)
- attack/spell/on_hit/detonate_effect.gd:91-121 — apply: the per-node scope dedupe (94) and the one production blast_for call (121)
- attack/range_finder/euclidean_range_finder.gd:30-65 — gather and gather_reach (49-65): candidates from graph.spatial_candidates, filtered by the mirror and a reach test
- attack/range_finder/euclidean_range_finder.gd:93-100 — static nodes_within over a supplied list (the fuel and blast path)
- attack/spell/propagation/reach/propagation_reach.gd:1-26 — the abstract reach interface: candidates(lctx) (:22), get_description (:26)
- attack/spell/propagation/reach/fuel_blast_reach.gd:30-55 — the closest existing blast-shaped reach: radius_at (37-38), candidates (41-51) via nodes_within, stable-id sorted
- graph/graph.gd:350-355 — get_neighbours: the cached adjacency index, O(degree); the rule docs prefer over edge walks
- graph/graph_mirror.gd:225-260 — nodes_within (229-250) is the one hop BFS; hop_distances_from (259-260) is its unbounded form
- effects/status/dot_tick.gd:24-47 — mint: an unmitigated TRUE hit; entity-host branch (31-43) and node-host branch (45-46)
- effects/status/corruption.gd:14-43 — damage_per_power (22); _on_burst (27-28) mints a FLAT hit whose amount is already the %-of-max; burst_amount (35-37) and cleanse_worth (42-43)
- systems/vision_source.gd:1-20 — class_name VisionSource with the Kind enum (9-11: OWNED, SCOUT)
- systems/vision_system.gd:313-340 — sources_for: SCOUT discs (325), OWNED disc at the node's vision_range (333-334)
- ui/fog_overlay/lantern_layer.gd:165-180 — writes skill_node.lantern_lit (170, 179); skill_node/skill_node.gd:398-407 is the lantern_lit property; :752-767 reads it
- ui/vfx/coordinator/arrow_volley_coordinator.gd:281-291 — a scout arrow is a lantern while it is drawn (_attach_lantern at 286)
- combat/node_combat.gd:321, skill_node/skill_node.gd:1005, combat/entity_combat.gd:796 — the three get_max_hp accessors (for %-of-max HP)
- attack/outcome/attack_record.gd:55-59, 211-217, 700-713, 718-730 — the blast table: one row per BlastMark; _capture_blast (700) and _rebuild_blasts (718)
- ui/vfx/blast_vfx.gd:1-50 — spawn: on Events.blast_landed (:24-27), spawn (32-45) at mark.centre; layers_for (51-60) uses an aspect's bespoke blast_layer else the generic
- attack/outcome/outcome_applier.gd:46-57 — emits Events.blast_landed for a hit's blast_mark (the authority and peers alike)
- attack/melee/sim/blade_pop_resolver.gd:294-309 — the spike-pop gate (the only pop in production); :603-621 _kill

SEAM MAP
- effects/status/spread/explosive_spread.gd:67 — blast_for: the only production caller is attack/spell/on_hit/detonate_effect.gd:121 (test/unit/attack/test_explosive_charges.gd also calls it)
- attack/spell/on_hit/blast_mark.gd:1 — class_name BlastMark; attack/spell/on_hit/blast_effect.gd:43-44 mark_for stamps it on hits
- attack/outcome/hit_instance.gd:228 — blast_mark on each hit
- autoload/events.gd:94 — signal blast_landed(mark: BlastMark), the one bus for blast VFX
- aspects/aspect.gd:32 — Aspect.blast_layer export (a bespoke layer per aspect); ui/vfx/rider_blast_layer.gd and .tscn are the generic layer
- addons/sandbox_host/tabs/71_blast_panel.gd:10 — preloads the rider layer for the sandbox
- graph/graph.gd:350 — get_neighbours is the neighbour accessor; ~25 production call sites (grep)
- attack/spell/propagation/propagation_context.gd:169, 210 — neighbour and BFS-style walks
- attack/range_finder/hop_range_finder.gd:58 — hop-ball gather used by lightning_bolt.tres (:53 range finder)
- attack/spell/spell_resolver.gd:401 — walk reachable set from state.current_node
- systems/vision_system.gd:313 — sources_for (the one producer of VisionSource lists)
- ui/fog_overlay/vision_source_index.gd:1 — class_name VisionSourceIndex, the CPU fog index
- ui/floating_number_layer/floater_director.gd, floater_request.gd, floater_toaster.gd — damage-number path (class names only; spawn line not traced)
- attack/melee/sim/blade_pop_resolver.gd:294-309 — spike-pop gate; spike_pop identifier does not exist in non-test code (prose only); the spikes source is skill_node/addons/spike_ring_addon.gd (per pop_resolver:553-554)
- combat/combat_world.gd:567 and ui/status_overlay/status_overlay.gd:162 — mirror.graph.get_neighbours on real nodes
- effects/status/ — 13 status defs: bleeding, blindness, corruption, curse, explosive, greed, hexed, marked, poison, scouted, sunder, weakened, wither. No Frozen, Burning or Shocked file; those exist only as design in docs/design/elements.md:823 (Derived states, owner 2026-11-06)
- docs/domain/explosive.md:61-122 — "Spend and power", "The blast carries the hit", "Chains"; :160 Knobs
- docs/domain/node-hp.md:9-27 (Current shape), 28-44 (turn-start regen), 87-96 (why a pool)
- docs/domain/vision-system.md:91 — VisionSource description
- docs/domain/spell-vfx-kit.md — no blast section (headings listed: ProjectilePath, ComposedProjectileVisual, WavePath, coordinators, etc.)
- docs/domain/attack-timeline.md — no heading names blast playback
- docs/design/elements.md:823 — Derived states: Frozen, Burning, Shocked (owner 2026-11-06)
- docs/domain/melee-blade-sim.md:262-265 — the blade's damage-number cue (SkillBlade._apply_playback_frame hit signal)

## Notes

- The first seam greps were capped at 120-200 lines, so the code-only seam lists above were rerun with test and doc paths excluded.
- Not verified this pass: the spec's ice-breaks-on-blade hook is the LiveGate.admit path (:271-309) plus BladeDamageInstance.land_on (:29-45); no Frozen state exists yet to attach it to.