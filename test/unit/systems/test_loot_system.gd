extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## LootSystem (#68 XP reward + #69 SkillDust loot). On `Events.entity_died`:
##   * the killing-blow entity (attributed via TurnManager.current_entity at the
##     synchronous death) gains XP scaled by the TERRITORY the victim held at
##     death (core included) — never by its level — fed through the normal xp
##     pool (so it converts to SP / levels), plus a per-node trickle off
##     `Events.skill_node_destroyed`;
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
		_graph.skill_nodes_container.add_child(sn)
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
	# XP tests set `xp_per_node_killed` / `entity_kill_bonus` explicitly; the
	# core loot draw is level-scaled, so keep-count tests pin its knobs too.
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

	_killer = autofree(Entity.new())
	_killer.display_name = "Killer"
	_killer.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_killer)

	_victim = autofree(Entity.new())
	_victim.display_name = "Victim"
	_victim.stat_board = _BOARD.duplicate(true) as StatBoard
	_victim.core_class = _BALANCED  # +10 STR/DEX/INT — the core-mod source
	_graph.add_child(_victim)

	await get_tree().process_frame  # _ready: navigators, health wiring, core_class.apply

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]

	var node_mods: Array[StatModifier] = [_mk_mod(&"armor", 3.0)]  # set X
	_nodes[2].modifiers = node_mods
	_alloc.force_allocate(_victim, _nodes[1])
	_alloc.force_allocate(_victim, _nodes[2])
	_victim.core_location = _nodes[1]


func _kill_victim() -> void:
	_tm.current_entity = _killer
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)  # overflow → health 0 → die()


# ── #68: XP reward ───────────────────────────────────────────────────────────

func test_killer_gains_xp_on_kill() -> void:
	# Victim holds N1 (core) + N2 → 2 nodes destroyed by the killing blow.
	_loot.xp_per_node_killed = 2.0
	_loot.entity_kill_bonus = 1.0  # isolate the node term
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before + 4.0,
			"kill XP = per_node * (held + core)")


func test_kill_xp_ignores_victim_level() -> void:
	# The rework: level is no longer an axis. D-19 already pins enemy level to
	# starting node count, so paying for both double-counted one fact.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	_victim.level = 17
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 2.0,
			"a level-17 victim holding 2 nodes pays exactly the 2 nodes")


func test_kill_xp_scales_with_territory_held_at_death() -> void:
	# Strip N2 first: the same victim, one node smaller, pays proportionally less.
	_alloc.force_deallocate(_nodes[2])
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 1.0, "core-only victim pays for its core alone")


func test_entity_kill_bonus_multiplies_the_payout() -> void:
	# The premium that makes going for the throat worth more than grinding limbs.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 2.0
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 4.0, "2 nodes * 1 XP * 2.0 bonus")


func test_xp_award_routes_through_level_up() -> void:
	# Award >= xp cap (5) → fills the pool → the normal replenished cascade
	# levels the killer and mints 1 SP (proves we go through the pool, not a
	# raw set_current that would skip it).
	_loot.xp_per_node_killed = 5.0
	_loot.entity_kill_bonus = 1.0
	var lvl_before := _killer.level
	var sp_before := _killer.stat_board.skill_points.current
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 1, "kill XP filling the pool levels the killer")
	# #271: a level-up mints `sp_gain_on_levelup` (default 2), not a hardcoded 1.
	var sp_gain := float(_killer.stat_board.get_value(&"sp_gain_on_levelup"))
	assert_eq(_killer.stat_board.skill_points.current, sp_before + sp_gain,
			"level-up mints sp_gain_on_levelup SP")


func test_a_big_kill_cascades_through_several_levels() -> void:
	# The rework multiplied award SIZE by ~40x: at defaults, a first_level enemy
	# (20 nodes) pays 20 * 5 * 2 = 200 XP into a pool whose cap starts at 5. That
	# only works because the xp def is OVERFLOW mode — `on_pool_filled` re-enters
	# `set_current` with the excess and cascades. If that ever regresses to KEEP
	# or RESET, a 200 XP kill silently pays ONE level and bins the rest.
	_loot.xp_per_node_killed = 5.0
	_loot.entity_kill_bonus = 2.0
	var lvl_before := _killer.level
	# Victim holds 2 nodes → 2 * 5 * 2 = 20 XP. Caps run 5 then 10 (growth_flat 5),
	# consuming 15 across two level-ups; the remaining 5 sits in the new cap-15 pool.
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 2, "a 20 XP award cascades through both level-ups")
	assert_eq(_killer.stat_board.xp.current, 5.0, "the remainder carries in, nothing is binned")
	assert_eq(float(_killer.stat_board.xp.get_value()), 15.0, "cap grew once per level")


func test_self_death_grants_no_xp() -> void:
	# No entity holds the turn → no killer attribution → no reward.
	_tm.current_entity = null
	var before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "no killer → no XP")


func test_destroying_a_node_pays_the_trickle() -> void:
	# #182: whittling a limb pays per node, without an entity dying. Riding
	# `skill_node_destroyed` (not `skill_node_depleted`) is what makes the
	# defender readable — BattleSystem's cascade handler has already cleared
	# `owned_by` by the time a depleted-listener would run.
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _killer
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)  # leaf, victim survives
	assert_false(_victim.is_dead, "the victim is only losing a limb here")
	assert_eq(_killer.stat_board.xp.current, before + 3.0, "one destroyed node → one trickle")


func test_destroying_your_own_node_pays_nothing() -> void:
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _victim  # the victim is the one acting
	var before := _victim.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_victim.stat_board.xp.current, before, "no XP for destroying your own territory")


func test_node_kill_switch_suppresses_the_trickle() -> void:
	_loot.award_xp_on_node_kill = false
	_loot.xp_per_node_killed = 3.0
	_tm.current_entity = _killer
	var before := _killer.stat_board.xp.current
	_nodes[2].take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "trickle disabled → no XP")


# ── Per-side-effect kill-switches (sandbox modularity) ───────────────────────

func test_drop_skill_dust_off_suppresses_relic() -> void:
	_loot.drop_skill_dust_on_death = false
	_loot.xp_per_node_killed = 1.0  # sub-cap → no level-up reset, current is observable
	_loot.entity_kill_bonus = 1.0
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


func test_loot_draws_only_core_mods_never_node_mods() -> void:
	# The #173 correction: node mods are LENT by the graph and return to it on
	# death, so looting them would duplicate live, re-claimable mods. N2's armor
	# (a node mod) must NEVER appear in the draw; only core-identity mods do.
	_victim.level = 5
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	for m in dust.candidates:
		assert_true(m.stat_id in [&"strength", &"dexterity", &"intelligence",
				&"constitution", &"wisdom"],
			"candidates are core-identity mods only")
		assert_ne(m.stat_id, &"armor", "node-granted mods are not lootable")


func test_keep_count_scales_with_victim_level() -> void:
	# N = round(core_keep_base + core_keep_per_level * level), clamped to the core
	# supply (5 identity mods since #271). M is always the full core set.
	_loot.core_keep_base = 1.0
	_loot.core_keep_per_level = 0.5
	_victim.level = 2
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.candidates.size(), 5, "M = full core supply")
	assert_eq(dust.pick_count, 2, "N = round(1 + 0.5*2) = 2")


func test_keep_count_never_saturates_the_core_supply() -> void:
	# A keep-count that reaches M turns pick-N-from-M into "take everything" —
	# SkillDustAddon's no-choice branch auto-grants and the picker never pops.
	# That's what a D-19 level-20 enemy did against a 5-mod core (1 + 0.25*20 = 6),
	# and it's why the loot modal looked absent in first_level. The draw now
	# always leaves at least one modifier on the table.
	_loot.core_keep_base = 100.0  # absurdly generous — still must not saturate
	_loot.core_keep_per_level = 1.0
	_victim.level = 20
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.candidates.size(), 5, "M = full core supply")
	assert_eq(dust.pick_count, 4, "N is capped at M-1 so the choice survives")


func test_loot_and_xp_fire_on_mid_cascade_death() -> void:
	# Deplete N2 (a leaf) with health at 1 and dealloc_damage 1: the forced-dealloc
	# cascade's chip damage drops health to 0, so die() — and thus LootSystem —
	# fires RE-ENTRANTLY while BattleSystem is still iterating the cascade loop.
	# The rewards must still land (and not crash) on this real combat trigger.
	_loot.xp_per_node_killed = 1.0
	_loot.entity_kill_bonus = 1.0
	_tm.current_entity = _killer
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
	# No HUD in this harness → the pick auto-resolves (random N of M). Exactly
	# pick_count core mods land on the collector's board, not its core node (#185).
	_loot.core_keep_base = 2.0
	_loot.core_keep_per_level = 0.0  # N = 2, M = 5 → a real choice
	_victim.level = 1
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.candidates.size(), 5, "M = full core (5 identity mods)")
	assert_eq(dust.pick_count, 2, "N = 2")
	_killer.stat_board.skill_points.grant(5)  # ensure SP to afford the allocation
	var attr_before := _attr_sum(_killer)
	# Killer allocates the neutral relic (adjacent to its N0 core).
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer can allocate the neutral relic node")
	var attr_gain := _attr_sum(_killer) - attr_before
	assert_eq(attr_gain, 20.0, "exactly 2 of 5 BalancedCore mods (+10 each) were granted")
	await get_tree().process_frame  # queue_free is deferred to frame end
	assert_null(_find_dust(_nodes[1]), "dust consumes itself on pickup")


# ── #173: the pick-N-from-M handshake at claim time ──────────────────────────
# Exercise the branch a trivial core can't: a REAL choice (M > N) where
# SkillDustAddon actually emits `loot_pick_requested`.


func test_no_handler_auto_resolves_a_strict_subset() -> void:
	# Real NPC play: nobody claims the pick → SkillDustAddon auto-resolves a
	# RANDOM N of M. Exactly N mods must land on the board (not all M, not zero).
	# XP is zeroed to isolate the loot grant: since #271 a level-up also moves
	# CON (+1/level, via the board's mod_level_to_con intrinsic), which would
	# otherwise drift _attr_sum by the killer's levels gained on this kill.
	_loot.xp_per_node_killed = 0.0
	_loot.core_keep_base = 2.0
	_loot.core_keep_per_level = 0.0
	_victim.level = 1
	var attr_before := _attr_sum(_killer)
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	assert_eq(dust.candidates.size(), 5, "M candidates offered (core identity)")
	assert_eq(dust.pick_count, 2, "N to keep")
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer allocates the relic")
	var attr_gain := _attr_sum(_killer) - attr_before
	assert_eq(attr_gain, 20.0, "auto-resolve grants exactly N=2 mods onto the board (+10 each)")


func test_handled_request_suppresses_auto_resolve_until_picker_resolves() -> void:
	# A UI consumer sets `handled = true` synchronously → the addon must NOT
	# auto-resolve. The loot stays pending until the picker calls resolve().
	# XP zeroed for the same reason as above — a level-up would move CON.
	_loot.xp_per_node_killed = 0.0
	_loot.core_keep_base = 2.0
	_loot.core_keep_per_level = 0.0
	_victim.level = 1
	var captured: Array[LootPickRequest] = []
	var handler := func(req: LootPickRequest) -> void:
		req.handled = true
		captured.append(req)
	Events.loot_pick_requested.connect(handler)

	var attr_before := _attr_sum(_killer)
	_kill_victim()
	_killer.stat_board.skill_points.grant(5)
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer allocates the relic")
	assert_eq(captured.size(), 1, "the pick request reached the handler")
	# Nothing granted yet — auto-resolve was suppressed, the pick is pending.
	assert_eq(_attr_sum(_killer), attr_before,
		"handled → loot still pending, no stats granted")
	assert_false(captured[0].is_resolved(), "request awaits the player's pick")

	# Now the "picker" resolves with the player's chosen N (2) → stats land.
	var chosen: Array[StatModifier] = [captured[0].candidates[0], captured[0].candidates[1]]
	captured[0].resolve(chosen)
	assert_eq(_attr_sum(_killer), attr_before + 20.0,
		"resolving the pick grants exactly N=2 mods onto the board (+10 each)")
	Events.loot_pick_requested.disconnect(handler)


# ── helpers ──────────────────────────────────────────────────────────────────

func _attr_sum(e: Entity) -> float:
	# All FIVE attributes — BalancedCore grants +10 to each since #271. Summing
	# only STR/DEX/INT would under-report whenever the random draw picks CON or
	# WIS, which reads as "fewer mods granted" rather than "wrong sum".
	var b := e.stat_board
	return (b.strength.value + b.dexterity.value + b.intelligence.value
			+ b.constitution.value + b.wisdom.value)


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
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
