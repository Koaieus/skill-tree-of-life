extends GutTest

## [WeaknessStatus]: a ×factor on the node-local `ranged_damage`,
## `blade_damage` and `spell_damage` — the damage dealt by attacks
## originating from the host — on Blindness's saturating curve of the TOTAL
## power. A node host cuts that node; an entity host (a core's status, read
## entity-wide) cuts every owned node, and the two fold multiplicatively.
## The curve knobs are set on a hand-built def; no authored magnitude is
## pinned here.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

const _STATS: Array[StringName] = [&"ranged_damage", &"blade_damage", &"spell_damage"]
const _BASE := 1000.0

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _def: WeaknessStatus


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Feeble"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	# Path graph N0 – N1 – N2.
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 600.0, 0.0)
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 2:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = _nodes[i]
		e.to = _nodes[i + 1]
		_graph.edges_container.add_child(e)
	await get_tree().process_frame

	for n in _nodes:
		_alloc.force_allocate(_entity, n)
	_entity.core_location = _nodes[0]

	_def = WeaknessStatus.new()
	_def.id = &"weakened"
	_def.power_max = 0.0
	_def.decay = FractionDecay.new(0.25)
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	_def.half_depth = 4.0
	_def.floor_factor = 0.1

	for stat_id in _STATS:
		_set_local(stat_id, _BASE)


## The damage stats are INT and may be derived, so solve the affine map
## entity base → node-local EFFECTIVE value that lands N0's read on [param target].
func _set_local(stat_id: StringName, target: float) -> void:
	var s: Stat = _entity.stat_board.get_stat(stat_id)
	assert_not_null(s, "fixture: %s on the entity board" % stat_id)
	s.base_value = 0.0
	var at_zero := _read(0, stat_id)
	s.base_value = 1000.0
	var slope := (_read(0, stat_id) - at_zero) / 1000.0
	s.base_value = (target - at_zero) / slope
	assert_almost_eq(_read(0, stat_id), target, 0.001,
		"fixture: effective local %s should be %s" % [stat_id, target])


func _read(i: int, stat_id: StringName) -> float:
	return float(_nodes[i].get_local_value(stat_id))


func _weak_mods_on(board: StatBoard, stat_id: StringName) -> int:
	var s: Stat = board.get_stat(stat_id) if board != null else null
	if s == null:
		return 0
	var n := 0
	for m in s.bins.multipliers:
		if m is WeaknessStatus.WeaknessModifier:
			n += 1
	return n


# ── 1. The curve ─────────────────────────────────────────────────────────────

func test_curve_is_one_at_zero_half_at_half_depth_decreasing_and_floored() -> void:
	for k in [2.0, 4.0, 5.0, 9.0]:
		_def.half_depth = k
		assert_almost_eq(_def.factor_for(0.0), 1.0, 0.0001, "k %s: untouched at zero" % k)
		assert_almost_eq(_def.factor_for(k), 0.5, 0.0001, "k %s: halved at half_depth" % k)
		var prev := _def.factor_for(0.0)
		var p := 0.25
		var floored := false
		while p <= 400.0:
			var f := _def.factor_for(p)
			assert_true(f >= _def.floor_factor - 0.000001, "k %s: never below the floor at %s" % [k, p])
			if f > _def.floor_factor + 0.000001:
				assert_lt(f, prev, "k %s: strictly decreasing above the floor at %s" % [k, p])
			else:
				floored = true
			prev = f
			p += 0.25
		assert_true(floored, "k %s: the curve saturates to the floor" % k)


# ── 2. Node host ─────────────────────────────────────────────────────────────

func test_weakened_node_cuts_its_three_damage_reads_and_not_a_neighbours() -> void:
	var before_n1: Dictionary = {}
	for stat_id in _STATS:
		before_n1[stat_id] = _read(1, stat_id)
	_nodes[0].get_combat().apply_status(_def, 4.0)
	for stat_id in _STATS:
		assert_almost_eq(_read(0, stat_id), _BASE * 0.5, 0.01, "%s halved at half_depth" % stat_id)
		assert_eq(_weak_mods_on(_nodes[0].node_board, stat_id), 1, "%s: one modifier" % stat_id)
		assert_almost_eq(_read(1, stat_id), before_n1[stat_id], 0.001, "%s: neighbour unchanged" % stat_id)


func test_reapply_accumulates_into_one_replaced_modifier() -> void:
	_nodes[0].get_combat().apply_status(_def, 6.0)
	_nodes[0].get_combat().apply_status(_def, 6.0)
	for stat_id in _STATS:
		assert_eq(_weak_mods_on(_nodes[0].node_board, stat_id), 1, "%s: replaced, never stacked" % stat_id)
		assert_almost_eq(_read(0, stat_id), _BASE * 0.25, 0.01, "%s: the curve on the total 12" % stat_id)


# ── 3. Entity host ───────────────────────────────────────────────────────────

func test_entity_host_cuts_every_owned_node() -> void:
	_entity.get_combat().apply_status(_def, 4.0)
	for i in _nodes.size():
		for stat_id in _STATS:
			assert_almost_eq(_read(i, stat_id), _BASE * 0.5, 0.01, "N%d %s halved entity-wide" % [i, stat_id])
	for stat_id in _STATS:
		assert_eq(_weak_mods_on(_entity.stat_board, stat_id), 1, "%s: planted on the entity board" % stat_id)


func test_node_and_entity_stacks_multiply() -> void:
	_nodes[1].get_combat().apply_status(_def, 4.0)  # ×0.5
	_entity.get_combat().apply_status(_def, 12.0)  # ×0.25
	for stat_id in _STATS:
		assert_almost_eq(_read(1, stat_id), _BASE * 0.125, 0.01, "%s: N × M fold" % stat_id)
		assert_almost_eq(_read(2, stat_id), _BASE * 0.25, 0.01, "%s: entity alone elsewhere" % stat_id)


# ── 4. Removal and decay ─────────────────────────────────────────────────────

func test_remove_restores_the_three_reads_exactly() -> void:
	_nodes[0].get_combat().apply_status(_def, 7.0)
	_entity.get_combat().apply_status(_def, 3.0)
	_nodes[0].get_combat().remove_status(&"weakened")
	_entity.get_combat().remove_status(&"weakened")
	for stat_id in _STATS:
		assert_almost_eq(_read(0, stat_id), _BASE, 0.001, "%s restored" % stat_id)
		assert_eq(_weak_mods_on(_nodes[0].node_board, stat_id), 0, "%s: no node leftover" % stat_id)
		assert_eq(_weak_mods_on(_entity.stat_board, stat_id), 0, "%s: no entity leftover" % stat_id)


func test_decay_to_zero_restores_the_three_reads_exactly() -> void:
	var c := _nodes[0].get_combat()
	c.apply_status(_def, 10.0)
	var guard := 0
	while c.get_status_power(&"weakened") > 0.0 and guard < 50:
		c.tick_statuses()
		guard += 1
	assert_lt(guard, 50, "fractional decay reaches zero")
	assert_gt(guard, 1, "and takes more than one tick")
	for stat_id in _STATS:
		assert_almost_eq(_read(0, stat_id), _BASE, 0.001, "%s restored" % stat_id)
		assert_eq(_weak_mods_on(_nodes[0].node_board, stat_id), 0, "%s: no leftover" % stat_id)


# ── Authored def ─────────────────────────────────────────────────────────────

func test_authored_def_is_uncapped_accumulating_and_unresisted() -> void:
	var w := load("res://effects/status/weakened.tres") as WeaknessStatus
	assert_not_null(w, "weakened.tres is a WeaknessStatus")
	if w == null:
		return
	assert_eq(w.id, &"weakened")
	assert_eq(w.power_max, 0.0, "uncapped")
	assert_eq(w.reapply, StatusDef.Reapply.ACCUMULATE)
	assert_true(w.decay is FractionDecay, "fractional decay")
	assert_eq(w.resistance_stat_id, &"", "no weakness resistance (owner 2026-10-06)")
	assert_true(w.tags.has(&"debuff"))
