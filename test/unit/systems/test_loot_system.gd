extends GutTest

## LootSystem (#68 XP reward + #69 SkillDust loot). On `Events.entity_died`:
##   * the killing-blow entity (attributed via TurnManager.current_entity at the
##     synchronous death) gains XP scaled by the victim's level, fed through the
##     normal xp pool (so it converts to SP / levels);
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
	_loot.xp_per_victim_level = 2.0
	_victim.level = 1
	var before := _killer.stat_board.xp.current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, before + 2.0, "killer xp += per_level * victim.level")


func test_xp_scales_with_victim_level() -> void:
	_loot.xp_per_victim_level = 1.0
	_victim.level = 3  # 3 < cap (5) → no level-up, stays as current
	_kill_victim()
	assert_eq(_killer.stat_board.xp.current, 3.0, "award scales by victim level")


func test_xp_award_routes_through_level_up() -> void:
	# Award >= xp cap (5) → fills the pool → the normal replenished cascade
	# levels the killer and mints 1 SP (proves we go through the pool, not a
	# raw set_current that would skip it).
	_loot.xp_per_victim_level = 5.0
	_victim.level = 1
	var lvl_before := _killer.level
	var sp_before := _killer.stat_board.skill_points.current
	_kill_victim()
	assert_eq(_killer.level, lvl_before + 1, "kill XP filling the pool levels the killer")
	assert_eq(_killer.stat_board.skill_points.current, sp_before + 1.0, "level-up mints 1 SP")


func test_self_death_grants_no_xp() -> void:
	# No entity holds the turn → no killer attribution → no reward.
	_tm.current_entity = null
	var before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)
	assert_eq(_killer.stat_board.xp.current, before, "no killer → no XP")


# ── #69: SkillDust loot drop ─────────────────────────────────────────────────

func test_skilldust_dropped_on_former_core() -> void:
	_kill_victim()
	var dust := _find_dust(_nodes[1])  # victim's former core
	assert_not_null(dust, "former core should carry a SkillDustAddon relic")
	assert_false(dust.payload.is_empty(), "dust should hold a payload")


func test_payload_total_caps_core_and_includes_node_mods() -> void:
	_victim.level = 5
	_loot.max_core_picks = 2
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	# 2 capped core picks + 1 available node mod (N2 armor) = 3 (supply-limited).
	assert_eq(dust.payload.size(), 3, "draw = capped core (2) + available node mods (1)")
	var core_count := 0
	var has_node_mod := false
	for m in dust.payload:
		if m.stat_id in [&"strength", &"dexterity", &"intelligence"]:
			core_count += 1
		elif m.stat_id == &"armor":
			has_node_mod = true
	assert_eq(core_count, 2, "core picks capped at max_core_picks")
	assert_true(has_node_mod, "node-granted mod (set X) included in the draw")


func test_cascade_killed_nodes_excluded_from_draw() -> void:
	# N2 is deallocated BEFORE death here, so its modifiers must not appear in
	# the loot — mirrors a finishing-blow cascade stripping nodes pre-death.
	_alloc.force_deallocate(_nodes[2])
	_victim.level = 5
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	for m in dust.payload:
		assert_ne(m.stat_id, &"armor", "a pre-stripped node's mods are not lootable")


func test_loot_and_xp_fire_on_mid_cascade_death() -> void:
	# Deplete N2 (a leaf) with health at 1 and dealloc_damage 1: the forced-dealloc
	# cascade's chip damage drops health to 0, so die() — and thus LootSystem —
	# fires RE-ENTRANTLY while BattleSystem is still iterating the cascade loop.
	# The rewards must still land (and not crash) on this real combat trigger.
	_loot.xp_per_victim_level = 2.0
	_victim.level = 1
	_tm.current_entity = _killer
	var xp_before := _killer.stat_board.xp.current
	_victim.stat_board.health.set_current(1.0)
	_nodes[2].take_damage(10000.0, null)  # deplete N2 → cascade → chip kill
	assert_true(_victim.is_dead, "chip damage should kill the victim mid-cascade")
	assert_eq(_killer.stat_board.xp.current, xp_before + 2.0, "XP awarded despite re-entrant death")
	assert_not_null(_find_dust(_nodes[1]), "SkillDust dropped on the former core mid-cascade")


func test_addon_tooltip_sections_surface_skilldust_payload() -> void:
	# The hover-tooltip content contract: a node aggregates its addons' tooltip
	# sections; SkillDust contributes its drawn payload under a titled section.
	_victim.level = 3
	_kill_victim()
	var sections := _nodes[1].get_addon_tooltip_sections()
	assert_eq(sections.size(), 1, "one addon section (the SkillDust relic)")
	assert_eq(sections[0]["title"], "SkillDust loot", "section is titled")
	var dust := _find_dust(_nodes[1])
	var mods: Array = sections[0]["modifiers"]
	assert_eq(mods.size(), dust.payload.size(), "section mirrors the drawn payload")
	assert_false(mods.is_empty(), "payload is listed for the tooltip")


func test_pickup_grants_payload_to_collector_core() -> void:
	_victim.level = 5
	_kill_victim()
	var dust := _find_dust(_nodes[1])
	var payload_size := dust.payload.size()
	_killer.stat_board.skill_points.grant(5)  # ensure SP to afford the allocation
	var attr_before := _attr_sum(_killer)
	# Killer allocates the neutral relic (adjacent to its N0 core).
	var ok := _alloc.allocate(_nodes[1], _killer)
	assert_true(ok, "killer can allocate the neutral relic node")
	assert_eq(_killer.core_location.modifiers.size(), payload_size,
		"looted mods land on the collector's core node")
	assert_gt(_attr_sum(_killer), attr_before, "looted core mods raised the killer's stats")
	await get_tree().process_frame  # queue_free is deferred to frame end
	assert_null(_find_dust(_nodes[1]), "dust consumes itself on pickup")


# ── helpers ──────────────────────────────────────────────────────────────────

func _attr_sum(e: Entity) -> float:
	var b := e.stat_board
	return b.strength.value + b.dexterity.value + b.intelligence.value


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
	var e := Edge.new()
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)
