extends GutTest

## The decay SHAPE per authored status family (#1091, hub #1060) — a law over
## `effects/status/*.tres`, pinning the [member StatusDef.decay] member —
## [FlatDecay] vs [FractionDecay] — never the magnitude (its knob is the
## owner's). Why each family has its shape:
## docs/domain/effect-system.md, "Status effects — the DoT model".

const _DIR := "res://effects/status/"

## Corruption authors no slot: it does not decay (owner, 2026-10-01; interim
## until #1203) — pinned separately below. Poison loses one whole stack a tick.
var _SHAPES := {
	&"poison": FlatDecay,
	&"wither": FractionDecay,
	&"blindness": FractionDecay,
	&"curse": FlatDecay,
	&"armor_break": FlatDecay,
}


func _authored() -> Dictionary:
	var out := {}
	for f in ResourceLoader.list_directory(_DIR):
		if not f.ends_with(".tres"):
			continue
		var def := load(_DIR + f) as StatusDef
		if def != null:
			out[def.id] = def
	return out


func test_every_family_is_authored() -> void:
	var defs := _authored()
	for id in _SHAPES:
		assert_true(defs.has(id), "%s.tres is authored under %s" % [id, _DIR])
	assert_true(defs.has(&"corruption"), "corruption.tres is authored under %s" % _DIR)


func test_corruption_does_not_decay() -> void:
	var defs := _authored()
	if defs.has(&"corruption"):
		assert_null((defs[&"corruption"] as StatusDef).decay, "corruption: no decay slot")


func test_each_family_decays_in_its_shape() -> void:
	var defs := _authored()
	for id in _SHAPES:
		if not defs.has(id):
			continue
		var def: StatusDef = defs[id]
		assert_true(is_instance_of(def.decay, _SHAPES[id]), "%s decays %s" % [id,
			_SHAPES[id].get_global_name()])
		var rate: float = (def.decay as FractionDecay).fraction if def.decay is FractionDecay \
			else (def.decay as FlatDecay).per_tick if def.decay is FlatDecay else 0.0
		assert_gt(rate, 0.0, "%s actually decays" % id)
		if def.decay is FractionDecay:
			assert_lt(rate, 1.0, "%s: a fraction below 1 leaves a tail" % id)


# ── RampDecay: the row's stored step ramps the removal ───────────────────────

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _ramp_def(start: float, step: float) -> StatusDef:
	var d := StatusDef.new()
	d.id = &"ramping"
	d.reapply = StatusDef.Reapply.ACCUMULATE
	d.power_max = 0.0
	d.decay = RampDecay.new(start, step)
	return d


## One allocated node on a deep pool, so nothing dies mid-assert.
func _host_node() -> SkillNode:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = TestBoards.flat_entity_board()
	graph.add_child(entity)
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = "N0"
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame
	alloc.force_allocate(entity, node)
	entity.core_location = node
	return node


func test_ramp_removes_start_then_one_step_more_each_rest_tick() -> void:
	var node := await _host_node()
	var start := 1.0
	var step := 1.0
	var def := _ramp_def(start, step)
	node.get_combat().apply_status(def, 33.0)
	var power := 33.0
	var k := 1
	while power > 0.0 and k < 20:
		node.get_combat().tick_statuses()
		var now := node.get_combat().get_status_power(&"ramping")
		assert_eq(power - now, minf(start + (k - 1) * step, power),
				"tick %d removes start + (k-1)·step" % k)
		power = now
		k += 1
	assert_eq(k - 1, 8, "33 under RampDecay(1,1) is gone on the 8th tick")


func test_exert_resets_the_ramp() -> void:
	var node := await _host_node()
	node.get_combat().apply_status(_ramp_def(1.0, 1.0), 33.0)
	for i in 3:
		node.get_combat().tick_statuses()  # removes 1, 2, 3 → 27, row at step 3
	assert_eq(node.get_combat().get_statuses()[0].decay_step, 3)
	node.get_combat().exert()
	node.get_combat().tick_statuses()
	assert_eq(node.get_combat().get_status_power(&"ramping"), 26.0, "exerted: the next tick removes 1")


func test_projection_walks_the_ramp() -> void:
	var def := _ramp_def(1.0, 1.0)
	var row := NodeStatus.new(def, 10)
	var series := []
	var p := 10.0
	var scratch := row.clone()
	while p > 0.0:
		p = def.decayed(p, scratch)
		scratch.decay_step += 1
		series.append(p)
	assert_eq(series, [9.0, 7.0, 4.0, 0.0])
	assert_eq(row.decay_step, 0, "walking a clone leaves the row's step alone")


func test_flat_and_fraction_ignore_the_row() -> void:
	var row := NodeStatus.new(null, 10)
	row.decay_step = 5
	assert_eq(FlatDecay.new(2.0).decayed(10.0, row), 8.0)
	assert_eq(FractionDecay.new(0.5).decayed(10.0, row), 5.0)
