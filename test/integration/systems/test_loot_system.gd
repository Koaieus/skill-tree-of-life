extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## LootSystem (#68 XP reward + #69 SkillDust loot). On `Events.entity_died`:
##   * the killing-blow entity (attributed via TurnManager.current_entity at the
##     synchronous death) gains XP scaled by every node the attack REMOVED from
##     the victim, core included — never by its level — fed through the normal xp
##     pool (so it converts to SP / levels), with a per-node trickle paid off
##     BattleSystem's `cascade_started` as the attack goes;
##   * the victim's former core node becomes a relic carrying a SkillDustAddon
##     whose payload is a snapshot of the victim's modifiers; allocating that
##     relic pours the payload onto the collector's core.
##
## Death is triggered via the realistic core-overflow path (not bare die()), so
## the synchronous "snapshot-before-strip" ordering is actually exercised.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _loot: LootSystem
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _victim: Entity
var _killer: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	# Line: N0 (killer core) – N1 (victim core) – N2 (victim node).
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	# LootSystem listens to the pre-cleanup `entity_dying` phase, so its add order
	# relative to AllocationSystem (on `entity_died`) doesn't matter — the phase
	# split guarantees the snapshot reads still-owned nodes before the strip.
	_loot = LootSystem.new()
	_loot.turn_manager = _tm  # killer attribution source
	# XP tests set `xp_per_node_killed` explicitly; the core bonus
	# (`core_kill_xp`, #774) is zeroed below once the victim's board exists —
	# these tests pin the TERRITORY term; the bonus term has its own file
	# (test_entity_tier_rewards.gd).
	add_child_autofree(_loot)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	# BattleSystem runs the forced-dealloc cascade (chip damage) off
	# skill_node_depleted — needed for the mid-cascade death path.
	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)
	# The removal ledger rides BattleSystem's cascade/attack signals. LootSystem
	# is already in the tree, so wire it the way game_root.tscn's NodePath does
	# and re-run the hookup.
	_loot.battle_system = _battle
	_battle.attack_launched.connect(_loot._on_attack_launched)
	_battle.cascade_started.connect(_loot._on_cascade_started)

	_killer = autofree(Entity.new())
	_killer.display_name = "Killer"
	_killer.faction = _PLAYER_FACTION  # #384/#386: HOSTILE to the victim's default npc faction
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)

	_victim = autofree(Entity.new())
	_victim.display_name = "Victim"
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_victim.core_class = _BALANCED  # +10 STR/DEX/INT — the core-mod source
	_graph.add_child(_victim)

	await get_tree().process_frame  # _ready: navigators, health wiring, core_class.apply
	_victim.stat_board.core_kill_xp.base_value = 0.0  # isolate the territory term; see above

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]

	var node_mods: Array[StatModifier] = [_mk_mod(&"armor", 3.0)]  # set X
	_nodes[2].modifiers = node_mods
	_alloc.force_allocate(_victim, _nodes[1])
	_alloc.force_allocate(_victim, _nodes[2])
	_victim.core_location = _nodes[1]


func _kill_victim() -> void:
	_tm.start_turn(_killer)
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)  # overflow → health 0 → die()


# ── #68: XP reward ───────────────────────────────────────────────────────────

func test_killer_gains_xp_on_kill() -> void:
	# Victim holds N1 (core) + N2 → 2 nodes destroyed by the killing blow.
	_loot.xp_per_node_killed = 2.0
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before + 4.0,
			"kill XP = per_node * (held + core)")


func test_entity_death_wave_awards_no_trickle_xp() -> void:
	# The core-outward death wave (#837) reuses `cascade_started` on purpose (so
	# AllocationVFX needs no change) — but LootSystem also listens to
	# `cascade_started` for its per-node trickle (#182). Without the
	# `defender.is_dead` guard in `_on_cascade_started`, this wave's own
	# emission would trickle-pay the victim's nodes AGAIN on top of the kill's
	# already-covers-the-whole-board `_kill_xp_total`, over-paying the kill.
	_loot.xp_per_node_killed = 2.0
	var waves: Array = []
	_battle.cascade_started.connect(func(layers: Array, _d: Entity) -> void: waves.append(layers))
	var before := _killer.stat_board.xp.current
	_kill_victim()  # direct core kill: no node-cascade precedes it, so the death wave is the ONLY wave
	assert_gt(waves.size(), 0, "precondition: the entity-death wave actually fired")
	assert_eq(_killer.stat_board.xp.current, before + 4.0,
			"kill XP is exactly the whole-board total — the wave must not trickle on top of it")


func test_kill_xp_ignores_victim_level() -> void:
	# The rework: level is no longer an axis. D-19 already pins enemy level to
	# starting node count, so paying for both double-counted one fact.
	_loot.xp_per_node_killed = 1.0
	_victim.level = 17
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 2.0,
			"a level-17 victim holding 2 nodes pays exactly the 2 nodes")


func test_kill_xp_scales_with_territory_held_at_death() -> void:
	# Strip N2 first: the same victim, one node smaller, pays proportionally less.
	_alloc.force_deallocate(_nodes[2])
	_loot.xp_per_node_killed = 1.0
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 1.0, "core-only victim pays for its core alone")


func test_core_kill_bonus_is_additive_not_multiplicative() -> void:
	# #774: `entity_kill_bonus` (a multiplier on the WHOLE payout) is gone —
	# the core bonus is now `core_kill_xp`, added flat on top of the territory
	# term, never multiplying it.
	_loot.xp_per_node_killed = 1.0
	_victim.stat_board.core_kill_xp.base_value = 2.0
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 4.0, "2 nodes * 1 XP + 2 core bonus, not (2+1)*bonus")


func test_xp_award_routes_through_level_up() -> void:
	# Award >= xp cap (5) → fills the pool → the normal replenished cascade
	# levels the killer and mints 1 SP (proves we go through the pool, not a
	# raw set_current that would skip it).
	_loot.xp_per_node_killed = 5.0
	var lvl_before := _killer.level
	var sp_before := _killer.stat_board.skill_points.current
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 1, "kill XP filling the pool levels the killer")
	# #271: a level-up mints `sp_gain_on_levelup` (default 2), not a hardcoded 1.
	var sp_gain := float(_killer.stat_board.get_value(&"sp_gain_on_levelup"))
	assert_eq(_killer.stat_board.skill_points.current, sp_before + sp_gain,
			"level-up mints sp_gain_on_levelup SP")


func test_a_big_kill_cascades_through_several_levels() -> void:
	# A big award needs to cascade through multiple level-ups on a pool whose
	# cap starts at 5. That only works because the xp def is OVERFLOW mode —
	# `on_pool_filled` re-enters `set_current` with the excess and cascades. If
	# that ever regresses to KEEP or RESET, a 20 XP kill silently pays ONE
	# level and bins the rest.
	_loot.xp_per_node_killed = 10.0
	var lvl_before := _killer.level
	# Victim holds 2 nodes → 2 * 10 = 20 XP. Caps run 5 then 10 (growth_flat 5),
	# consuming 15 across two level-ups; the remaining 5 sits in the new cap-15 pool.
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 2, "a 20 XP award cascades through both level-ups")
	assert_eq(_killer.stat_board.xp.current, 5.0, "the remainder carries in, nothing is binned")
	assert_eq(float(_killer.stat_board.xp.get_value()), 15.0, "cap grew once per level")


func test_self_death_grants_no_xp() -> void:
	# No entity holds the turn → no killer attribution → no reward.
	_tm.adopt_turn(null, _tm.turns_taken)
	var before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "no killer → no XP")


func test_ally_kill_grants_no_xp() -> void:
	# #384/#386: the HOSTILE gate on the kill-bonus path. Same faction as the
	# victim → ALLIED, so even a real killing blow earns nothing.
	_killer.faction = _NPC_FACTION
	_loot.xp_per_node_killed = 1.0
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before, "an ally kill pays no XP")
	assert_not_null(_find_dust(_nodes[1]), "SkillDust is a world drop — stays ungated")


func test_ally_node_kill_pays_no_trickle() -> void:
	# Same gate on the cascade trickle path (`_on_cascade_started`).
	_killer.faction = _NPC_FACTION
	_loot.xp_per_node_killed = 3.0
	_tm.start_turn(_killer)
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "no XP for whittling an ally's territory")


func test_bystander_enemy_gains_no_xp_from_anothers_kill() -> void:
	# A third HOSTILE entity must not be credited just because it's also hostile
	# to the victim — only the entity holding the turn (the actual killer) is paid.
	var bystander: Entity = autofree(Entity.new())
	bystander.display_name = "Bystander"
	bystander.faction = _PLAYER_FACTION  # hostile to the npc-faction victim too
	bystander.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(bystander)
	await get_tree().process_frame

	_loot.xp_per_node_killed = 1.0
	var bystander_before: float = bystander.stat_board.xp.current
	_kill_victim()  # _tm.current_entity = _killer, not bystander
	assert_eq(bystander.stat_board.xp.current, bystander_before,
			"only the attributed killer is paid, not every hostile entity")


func test_destroying_a_node_pays_the_trickle() -> void:
	# #182: whittling a limb pays per node, without an entity dying. Riding the
	# cascade (not `skill_node_depleted`) is what makes the defender readable —
	# the strip clears `owned_by` in that same loop.
	_loot.xp_per_node_killed = 3.0
	_tm.start_turn(_killer)
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)  # leaf, victim survives
	assert_false(_victim.is_dead, "the victim is only losing a limb here")
	assert_eq(_killer.stat_board.xp.current, before + 3.0, "one destroyed node → one trickle")


func test_destroying_your_own_node_pays_nothing() -> void:
	_loot.xp_per_node_killed = 3.0
	_tm.start_turn(_victim)  # the victim is the one acting
	var before := _victim.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_victim.stat_board.xp.current, before, "no XP for destroying your own territory")


func test_node_kill_switch_suppresses_the_trickle() -> void:
	_loot.award_xp_on_node_kill = false
	_loot.xp_per_node_killed = 3.0
	_tm.start_turn(_killer)
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "trickle disabled → no XP")


# ── Per-side-effect kill-switches (sandbox modularity) ───────────────────────

func test_drop_skill_dust_off_suppresses_relic() -> void:
	_loot.drop_skill_dust_on_death = false
	_loot.xp_per_node_killed = 1.0  # sub-cap → no level-up reset, current is observable
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_null(_find_dust(_nodes[1]), "dust drop disabled → no relic on former core")
	# Other side-effects untouched: XP still awarded.
	assert_eq(_killer.stat_board.xp.current, before + 2.0, "XP reward still fires when only dust is off")


func test_award_xp_off_suppresses_xp() -> void:
	_loot.award_xp_on_kill = false
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before, "xp award disabled → no XP")
	# Other side-effects untouched: dust still drops.
	assert_not_null(_find_dust(_nodes[1]), "dust still drops when only XP is off")


# ── #69/#173: SkillDust loot drop (CORE-ONLY) ────────────────────────────────

func test_skilldust_dropped_on_former_core() -> void:
	_kill_victim()
	var dust := _find_dust(_nodes[1])  # victim's former core
	assert_not_null(dust, "former core should carry a SkillDustAddon relic")
	assert_false(dust.candidates.is_empty(), "dust holds the core-mod candidates")


func test_loot_draws_from_all_three_provenance_buckets() -> void:
	# #323 re-cut: provenance replaces "scales with level" as the lootability
	# axis. N2's armor (a node grant) MUST now appear — node mods are LENT by
	# the graph and still return to it on death (the strip is untouched), but a
	# DUPLICATED copy is now an honest loot candidate, not excluded outright.
	_victim.level = 5
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	var stat_ids: Array[StringName] = []
	for m in dust.candidates:
		stat_ids.append(m.stat_id)
	assert_true(&"armor" in stat_ids, "node-grant bucket is now part of the draw")
	assert_true(&"strength" in stat_ids or &"dexterity" in stat_ids
			or &"intelligence" in stat_ids, "class/register bucket is still drawn")
	var innate_ids: Array[StringName] = []
	for m in _victim.stat_board.intrinsic_modifiers:
		innate_ids.append((m as StatModifier).stat_id)
	var saw_innate := false
	for m in dust.candidates:
		if m.stat_id in innate_ids:
			saw_innate = true
			break
	assert_true(saw_innate, "board-innate bucket is drawn too")


func test_lootable_supply_is_the_union_of_all_three_buckets() -> void:
	# Supply = |node grants| + |class register| + |board innates|, expanded for
	# loot the same way each bucket's own reader would report it. Computed from
	# the fixture rather than a hardcoded literal, so it doesn't rot when the
	# shared default board's intrinsic set changes.
	var expected := _loot._expand_for_loot(_loot._node_grant_modifiers(_victim)).size() \
			+ _loot._expand_for_loot(_loot._core_modifiers(_victim)).size() \
			+ _loot._expand_for_loot(_loot._innate_modifiers(_victim)).size()
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.candidates.size(), expected, "M = union of the three buckets")


func test_keep_count_is_constant_regardless_of_tier() -> void:
	# #775: round count is now a constant (loot_rounds), no longer scaled by
	# victim.entity_tier (the reduced per-round VALUE is compensated by more
	# rounds, not by tier-scaled round count).
	_victim.entity_tier = 2
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.rounds, _loot.loot_rounds, "N = loot_rounds regardless of tier")


func test_keep_count_never_saturates_the_supply() -> void:
	# A keep-count that reaches M turns pick-1-of-3-per-round into "take
	# everything" — the picker never pops. The draw must always leave at least
	# one on the table, so an absurdly high loot_rounds is still capped below M.
	_loot.loot_rounds = 100
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_lt(dust.rounds, dust.candidates.size(),
			"N is capped below M so the choice survives")


# ── #775: loot value scales with victim tier, merge on equivalent grants ────

func test_loot_candidates_are_scaled_by_the_victims_loot_fraction() -> void:
	# Tier 1 (small blocker) draws every candidate at 0.25x the victim's own
	# value; the victim's own modifiers are untouched.
	_victim.entity_tier = 1
	var original_wis := _find_victim_core_mod(&"wisdom")
	assert_not_null(original_wis, "precondition: BalancedCore grants +10 Wisdom")
	var original_value := original_wis.value
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	var scaled: StatModifier = null
	for m in dust.candidates:
		if m.stat_id == &"wisdom" and m.operation == StatModifier.Operation.ADD_BASE and m.formula == null:
			scaled = m
	assert_not_null(scaled, "the wisdom grant is still a candidate")
	assert_eq(scaled.value, original_value * 0.25, "candidate value is scaled by tier-1's 0.25 fraction")
	assert_eq(original_wis.value, original_value, "the victim's OWN modifier is never scaled")


func test_loot_fraction_scales_every_leaf_of_a_composite_that_survives_whole() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = true
	pack.children = [_mk_mod(&"deallocation_points", 4.0), _mk_mod(&"skill_points", -2.0)]
	_victim.core_modifiers.append(pack)
	_victim.stat_board.add_modifier(pack)

	_victim.entity_tier = 2  # fraction 0.5
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	var found: CompositeStatModifier = null
	for m in dust.candidates:
		if m is CompositeStatModifier:
			found = m
	assert_not_null(found, "the true pack survives whole as one candidate")
	assert_eq(found.children[0].value, 2.0, "leaf 1 scaled: 4.0 * 0.5")
	assert_eq(found.children[1].value, -1.0, "leaf 2 scaled: -2.0 * 0.5")


func test_player_tier_loots_at_full_value() -> void:
	# entity_tier default 3 -> loot_fraction_by_tier[2] == 1.0 -> unchanged.
	var original_wis := _find_victim_core_mod(&"wisdom")
	var original_value := original_wis.value
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	var scaled: StatModifier = null
	for m in dust.candidates:
		if m.stat_id == &"wisdom" and m.operation == StatModifier.Operation.ADD_BASE and m.formula == null:
			scaled = m
	assert_not_null(scaled)
	assert_eq(scaled.value, original_value, "tier 3 (default) loots at the full 1.0 rate")


func test_pickup_merges_equivalent_grants_instead_of_stacking_copies() -> void:
	# Two relics offering the SAME rule (same stat/op/formula, one candidate
	# each so the pick is deterministic) add coefficients into one modifier
	# on claim rather than holding two — the SkillDustAddon claim path routes
	# through Entity.absorb_core_modifier (#775), not grant_core_modifier.
	var relic_a := _SKILL_NODE_SCENE.instantiate() as SkillNode
	relic_a.name = "RelicA"
	_graph.add_skill_node(relic_a)
	_add_edge(_nodes[0], relic_a)
	var dust_a := SkillDustAddon.new()
	dust_a.candidates = [_mk_mod(&"armor", 5.0)]
	dust_a.weights = [1.0]
	dust_a.rounds = 1
	relic_a.add_child(dust_a)

	var relic_b := _SKILL_NODE_SCENE.instantiate() as SkillNode
	relic_b.name = "RelicB"
	_graph.add_skill_node(relic_b)
	_add_edge(_nodes[0], relic_b)
	var dust_b := SkillDustAddon.new()
	dust_b.candidates = [_mk_mod(&"armor", 5.0)]
	dust_b.weights = [1.0]
	dust_b.rounds = 1
	relic_b.add_child(dust_b)

	_killer.stat_board.skill_points.grant(5)
	assert_true(_alloc.allocate(relic_a, _killer), "killer claims relic A")
	assert_eq(_killer.core_modifiers.size(), 1, "first grant appends")
	var merged := _killer.core_modifiers[0]
	assert_eq(merged.value, 5.0)

	assert_true(_alloc.allocate(relic_b, _killer), "killer claims relic B")
	assert_eq(_killer.core_modifiers.size(), 1, "second equivalent grant merged, not appended")
	assert_eq(_killer.core_modifiers[0], merged, "merged into the SAME instance")
	assert_eq(merged.value, 10.0, "two +5 armor grants merged into one +10")


func test_loot_and_xp_fire_on_mid_cascade_death() -> void:
	# Deplete N2 (a leaf) with health at 1 and dealloc_damage 1: the forced-dealloc
	# cascade's chip damage drops health to 0, so die() — and thus LootSystem —
	# fires RE-ENTRANTLY while BattleSystem is still iterating the cascade loop.
	# The rewards must still land (and not crash) on this real combat trigger.
	_loot.xp_per_node_killed = 1.0
	_tm.start_turn(_killer)
	var xp_before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_nodes[2].take_damage(10000.0, null)  # deplete N2 → cascade → chip kill
	assert_true(_victim.is_dead, "chip damage should kill the victim mid-cascade")
	# 1 (N2 destroyed, the trickle) + 1 (the kill: core only, N2 already gone).
	assert_eq(_killer.stat_board.xp.current, xp_before + 2.0, "XP awarded despite re-entrant death")
	assert_not_null(_find_dust(_nodes[1]), "SkillDust dropped on the former core mid-cascade")


func test_addon_tooltip_sections_surface_skilldust_payload() -> void:
	# The hover-tooltip content contract: a node aggregates its addons' tooltip
	# sections; SkillDust contributes its candidate list under a titled section.
	_victim.level = 3
	_kill_victim()
	var sections := _nodes[1].get_addon_tooltip_sections()
	assert_eq(sections.size(), 1, "one addon section (the SkillDust relic)")
	assert_eq(sections[0]["title"], "SkillDust loot", "section is titled")
	var dust := _find_dust(_nodes[1])
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), dust.candidates.size(), "section mirrors the candidates")
	assert_false(mods.is_empty(), "candidates are listed for the tooltip")


func test_pickup_auto_resolves_picked_core_mods_to_collector_core() -> void:
	# No HUD in this harness → each round auto-resolves (random 1 of up to 3).
	# Exactly `rounds` mods land on the collector (#185/#323 — a looted grant
	# is re-lootable through the register), not the relic's core node.
	#
	# Counted via `stat_modifier_changed`, not `core_modifiers.size()` (#775):
	# the killer's board is the SAME default board template as the victim's,
	# so an innate-bucket pick can legitimately MERGE into the killer's own
	# matching intrinsic instead of appending a register entry — decision 9
	# guarantees exactly one event per landed grant either way.
	_loot.loot_rounds = 2  # N = 2 rounds → a real choice (#775: constant, not tier-scaled)
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.rounds, 2, "N = 2")
	_killer.stat_board.skill_points.grant(5)  # ensure SP to afford the allocation
	var grants: Array = []
	var handler := func(_e: Entity, m: StatModifier, _k: ModifierBinding.Kind, _a: bool) -> void:
		grants.append(m)
	Events.stat_modifier_changed.connect(handler)
	# Killer allocates the neutral relic (adjacent to its N0 core).
	var ok := _alloc.allocate(_nodes[1], _killer)
	Events.stat_modifier_changed.disconnect(handler)
	assert_true(ok, "killer can allocate the neutral relic node")
	assert_eq(grants.size(), 2, "exactly N=2 rounds each land one grant on the collector")
	await get_tree().process_frame  # queue_free is deferred to frame end
	assert_null(_find_dust(_nodes[1]), "dust consumes itself once every round has resolved")


# ── #173: the pick-N-from-M handshake at claim time ──────────────────────────
# Exercise the branch a trivial core can't: a REAL choice (M > N) where
# SkillDustAddon actually emits `loot_pick_requested`.


func test_no_handler_auto_resolves_a_strict_subset() -> void:
	# Real NPC play: nobody claims the pick → SkillDustAddon auto-resolves a
	# RANDOM 1-of-3 each round. Exactly N rounds' worth of grants must land on
	# the collector (not the whole pool, not zero). XP is zeroed so a level-up
	# doesn't also mutate the board via mod_level_to_con mid-test.
	#
	# Counted via `stat_modifier_changed`, not `core_modifiers.size()` (#775):
	# the killer's board is the SAME default board template as the victim's,
	# so an innate-bucket pick can legitimately MERGE into the killer's own
	# matching intrinsic instead of appending a register entry — decision 9
	# guarantees exactly one event per landed grant either way.
	_loot.xp_per_node_killed = 0.0
	_loot.loot_rounds = 2
	var grants: Array = []
	var handler := func(_e: Entity, m: StatModifier, _k: ModifierBinding.Kind, _a: bool) -> void:
		grants.append(m)
	Events.stat_modifier_changed.connect(handler)
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.rounds, 2, "N rounds to run")
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	Events.stat_modifier_changed.disconnect(handler)
	assert_true(ok, "killer allocates the relic")
	assert_eq(grants.size(), 2, "auto-resolve grants exactly N=2 rounds' worth of mods")


func test_claimed_request_suppresses_auto_resolve_until_picker_resolves() -> void:
	# A UI consumer sets `claim = LOCAL` synchronously → the addon must NOT
	# auto-resolve THAT ROUND. The round stays pending until the picker calls
	# resolve() — and the NEXT round's request doesn't fire until it does,
	# since `_grant_and_advance` (the resolver) is what drives `_advance_round`.
	_loot.xp_per_node_killed = 0.0
	_loot.loot_rounds = 2
	var captured: Array[LootPickRequest] = []
	var handler := func(req: LootPickRequest) -> void:
		req.claim = LootPickRequest.Claim.LOCAL
		captured.append(req)
	Events.loot_pick_requested.connect(handler)
	# See the note above: a pick can merge rather than append, so count grants
	# via the event, not `core_modifiers.size()`.
	var grants: Array = []
	var grant_handler := func(_e: Entity, m: StatModifier, _k: ModifierBinding.Kind, _a: bool) -> void:
		grants.append(m)
	Events.stat_modifier_changed.connect(grant_handler)

	_kill_victim()
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer allocates the relic")
	assert_eq(captured.size(), 1, "only round 1's request reached the handler so far")
	assert_gt(captured[0].candidates.size(), 1,
		"a round offers a real choice — one survivor auto-grants instead")
	# Nothing granted yet — auto-resolve was suppressed, round 1 is pending.
	assert_eq(grants.size(), 0, "claimed → round 1 still pending, nothing granted yet")
	assert_false(captured[0].is_resolved(), "request awaits the player's pick")

	# Resolve round 1 → round 2's request fires (still connected to `handler`).
	captured[0].resolve([captured[0].candidates[0]])
	assert_eq(grants.size(), 1, "round 1's pick landed")
	assert_eq(captured.size(), 2, "resolving round 1 drove round 2's request")

	captured[1].resolve([captured[1].candidates[0]])
	assert_eq(grants.size(), 2, "round 2's pick landed too — N=2 rounds total")
	Events.loot_pick_requested.disconnect(handler)
	Events.stat_modifier_changed.disconnect(grant_handler)


# ── #323: sequential would_cycle filtering closes the joint-cycle gap ────────

func test_sequential_would_cycle_filtering_closes_the_joint_cycle_gap() -> void:
	# Two candidates, each individually cycle-safe, but jointly cyclic:
	# strength reads dexterity; dexterity reads strength. A single up-front
	# filter (checked once against the board as it stood at draw time) would
	# let BOTH through — the second `add_modifier` would then hit the board's
	# own last-resort rejection. The per-round claim-time filter must not: once
	# round 1 binds the first, round 2's `would_cycle` check sees it on the
	# board and excludes the second before it's ever offered.
	var mod_a := StatModifier.new()
	mod_a.stat_id = &"strength"
	var f_a := LinearFormula.new()
	f_a.source_stat_id = &"dexterity"
	mod_a.formula = f_a

	var mod_b := StatModifier.new()
	mod_b.stat_id = &"dexterity"
	var f_b := LinearFormula.new()
	f_b.source_stat_id = &"strength"
	mod_b.formula = f_b

	# A free relic adjacent to the killer's core to allocate onto.
	var relic := _SKILL_NODE_SCENE.instantiate() as SkillNode
	relic.name = "Relic"
	_graph.add_skill_node(relic)
	_add_edge(_nodes[0], relic)

	var dust := SkillDustAddon.new()
	dust.candidates = [mod_a, mod_b]
	dust.weights = [1.0, 1.0]
	dust.rounds = 2
	relic.add_child(dust)

	var captured: Array[LootPickRequest] = []
	var handler := func(req: LootPickRequest) -> void:
		req.claim = LootPickRequest.Claim.LOCAL
		captured.append(req)
	Events.loot_pick_requested.connect(handler)

	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(relic, _killer)
	assert_true(ok, "killer allocates the relic")

	assert_eq(captured.size(), 1, "round 1 offers a real 2-way choice")
	assert_eq(captured[0].candidates.size(), 2, "both are individually cycle-safe at round 1")
	captured[0].resolve([mod_a])  # bind "strength reads dexterity" first

	assert_eq(_killer.core_modifiers.size(), 1, "round 1's pick landed")
	assert_true(_killer.core_modifiers.has(mod_a))
	assert_eq(captured.size(), 1, "round 2 never emitted a request — no cycle-safe survivor left")
	assert_false(_killer.core_modifiers.has(mod_b),
			"the jointly-cyclic candidate is excluded once round 1 is bound, never granted")

	Events.loot_pick_requested.disconnect(handler)


# ── #323: enemies loot from players too (symmetry, not gated by faction) ─────

func test_npc_loots_a_relic_dropped_by_a_player_victim() -> void:
	# "Do enemies loot from players?" — yes, already true by construction:
	# SkillDust loot goes to whoever ALLOCATES the relic (`carrier.owned_by`),
	# not the killer specifically, and nothing in the drop or claim path gates
	# on faction (only the XP reward does — see test_ally_kill_grants_no_xp).
	# Flip the usual fixture: the VICTIM is player-faction, the CLAIMANT is
	# npc-faction, same as an NPC scavenging a dead player's relic.
	_victim.faction = _PLAYER_FACTION
	_killer.faction = _NPC_FACTION
	_victim.entity_tier = 1
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_not_null(dust, "a player's death still drops a relic")

	# Counted via the event, not register growth (#775: a pick can legitimately
	# MERGE into a matching intrinsic on the killer's own — identical template —
	# board instead of appending a register entry).
	var grants: Array = []
	var handler := func(_e: Entity, m: StatModifier, _k: ModifierBinding.Kind, _a: bool) -> void:
		grants.append(m)
	Events.stat_modifier_changed.connect(handler)
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	Events.stat_modifier_changed.disconnect(handler)
	assert_true(ok, "an NPC entity can allocate a relic a player dropped")
	assert_gt(grants.size(), 0, "the NPC claimant receives the SkillDust payload like anyone else")


# ── D-27/#279: loots_as_unit pack expansion ───────────────────────────────────

func test_expand_for_loot_splits_a_false_pack_into_separate_candidates() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = false
	pack.children = [_mk_mod(&"strength", 10.0), _mk_mod(&"dexterity", 10.0)]

	var expanded: Array[StatModifier] = [pack]
	expanded = _loot._expand_for_loot(expanded)

	assert_eq(expanded.size(), 2, "a false pack expands into one candidate per child")
	assert_false(expanded[0] is CompositeStatModifier, "expanded entries are the leaves, not the pack")


func test_expand_for_loot_keeps_a_true_pack_as_one_candidate() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = true
	pack.children = [_mk_mod(&"deallocation_points", 2.0), _mk_mod(&"skill_points", -1.0)]

	var expanded: Array[StatModifier] = [pack]
	expanded = _loot._expand_for_loot(expanded)

	assert_eq(expanded.size(), 1, "a true pack stays a single all-or-nothing candidate")
	assert_same(expanded[0], pack, "the whole pack is the candidate, unflattened")


func test_level_scaling_no_longer_excludes_a_mod_from_the_pool() -> void:
	# #323 re-cut: `_is_lootable`'s old `scales_with(&"level")` exclusion is
	# GONE — stealing a level-scaler is the intended roguelite loop now, not a
	# hazard to filter out. A `+1 STR per level` child inside a `false` pack
	# (expanded to a per-leaf candidate, same as any static sibling) survives
	# right alongside the static one.
	var scaled := _mk_mod(&"strength", 1.0)
	var f := LinearFormula.new()
	f.source_stat_id = &"level"
	scaled.formula = f
	var static_mod := _mk_mod(&"dexterity", 10.0)

	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = false
	pack.children = [scaled, static_mod]

	var expanded: Array[StatModifier] = [pack]
	var out := _loot._expand_for_loot(expanded)

	assert_eq(out.size(), 2, "both children survive — no level filter anymore")
	var stat_ids: Array[StringName] = [out[0].stat_id, out[1].stat_id]
	assert_true(&"strength" in stat_ids, "the level-scaling child is now lootable")
	assert_true(&"dexterity" in stat_ids, "the static child stays lootable too")


# ── helpers ──────────────────────────────────────────────────────────────────

func _attr_sum(e: Entity) -> float:
	# All FIVE attributes — BalancedCore grants +10 to each since #271. Summing
	# only STR/DEX/INT would under-report whenever the random draw picks CON or
	# WIS, which reads as "fewer mods granted" rather than "wrong sum".
	var b := e.stat_board
	return (b.strength.value + b.dexterity.value + b.intelligence.value
			+ b.constitution.value + b.wisdom.value)


func _find_victim_core_mod(id: StringName) -> StatModifier:
	for m in _victim.core_modifiers:
		if m.stat_id == id:
			return m
	return null


func _find_dust(node: SkillNode) -> SkillDustAddon:
	for a in node.get_addons():
		if a is SkillDustAddon:
			return a as SkillDustAddon
	return null


func _mk_mod(id: StringName, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = v
	return m


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	# Graph.add_edge emits edge_added so the board Navigator mirrors it
	# (.claude/rules/graph.md); a container add_child is invisible to it.
	_graph.add_edge(a, b)
