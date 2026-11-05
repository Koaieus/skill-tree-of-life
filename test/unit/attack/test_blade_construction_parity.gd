extends GutTest

## The resolve's blade ([method MeleeAttackPlan.build_blade_state] /
## [method MeleeAttackPlan.build_drivers]) and the visual blade
## ([method SkillBlade.build_from_skill_nodes] and its swing drivers) are one
## construction: same selection in, field-for-field the same state and drivers
## out. A drift between the two is a preview that lies about the resolve.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func _spawn(nm: String, inner_r: float) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.base_inner_radius = inner_r
	return sn


func before_each() -> void:
	_graph = TestWorld.create(self).graph
	_alloc = TestWorld.around(_graph).allocator()
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)


## source hub with a branch (a) and a chain (b - c), so the pivot has two
## driven neighbours and one member is driven only through the constraints.
func _setup_plan(swing_cw: bool) -> MeleeAttackPlan:
	_entity.stat_board.blade_size.base_value = 6.0
	var source := _spawn("Source", 9.0)
	var a := _spawn("A", 11.0)
	var b := _spawn("B", 13.0)
	var c := _spawn("C", 15.0)
	source.position = Vector2(0, 0)
	a.position = Vector2(120, 10)
	b.position = Vector2(-40, 110)
	c.position = Vector2(-60, 230)
	_graph.add_edge(source, a)
	_graph.add_edge(source, b)
	_graph.add_edge(b, c)
	await get_tree().process_frame
	for sn in [source, a, b, c]:
		_alloc.force_allocate(_entity, sn)
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	plan.set_pivot(source)
	plan.toggle_member(a)
	plan.toggle_member(b)
	plan.toggle_member(c)
	plan.swing_cw = swing_cw
	assert_true(plan.apply_temp_upgrade(b, _CLAMP_SCENE))
	assert_true(plan.apply_temp_upgrade(c, _SPIKE_SCENE))
	return plan


func _blade_for(plan: MeleeAttackPlan) -> SkillBlade:
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	blade.swing_cw = plan.swing_cw
	var nodes: Array[SkillNode] = [plan.source]
	nodes.append_array(plan.blade_nodes)
	blade.build_from_skill_nodes(nodes, plan.source, plan.get_induced_edges(), _entity, plan.vertex_fill)
	return blade


func test_plan_and_skill_blade_build_the_same_state() -> void:
	var plan: MeleeAttackPlan = await _setup_plan(false)
	var resolve := plan.build_blade_state()
	var view := _blade_for(plan).state
	assert_eq(view.positions, resolve.positions, "positions")
	assert_eq(view.pivot_index, resolve.pivot_index, "pivot index")
	assert_eq(view.radii, resolve.radii, "radii")
	assert_eq(view.inner_radii, resolve.inner_radii,
			"inner_radii — the resolve state carries the true inner radii too")
	assert_eq(view.edges, resolve.edges, "edges")
	assert_eq(view.vertex_damage, resolve.vertex_damage, "vertex_damage")
	assert_eq(view.vertex_blunting, resolve.vertex_blunting, "vertex_blunting")
	assert_eq(view.vertex_charges, resolve.vertex_charges, "vertex_charges")
	assert_eq(_constraint_pairs(view), _constraint_pairs(resolve), "constraint set")


func test_plan_and_skill_blade_build_the_same_drivers_ccw() -> void:
	await _assert_same_drivers(false)


func test_plan_and_skill_blade_build_the_same_drivers_cw() -> void:
	await _assert_same_drivers(true)


func _assert_same_drivers(cw: bool) -> void:
	var plan: MeleeAttackPlan = await _setup_plan(cw)
	var resolve := plan.build_drivers(plan.build_blade_state())
	var blade := _blade_for(plan)
	var view := blade._build_swing_drivers(MeleeAttackPlan.SWING_DURATION)
	assert_eq(view.size(), resolve.size(), "driver count")
	assert_eq(resolve.size(), 2, "one driver per pivot neighbour")
	for i in mini(view.size(), resolve.size()):
		var v := view[i] as BladeArcDriver
		var r := resolve[i] as BladeArcDriver
		assert_eq(v.particle, r.particle, "particle")
		assert_eq(v.center, r.center, "pivot centre")
		assert_almost_eq(v.radius, r.radius, 0.0001, "radius")
		assert_almost_eq(v.start_angle, r.start_angle, 0.0001, "angle")
		assert_eq(v.sweep, r.sweep, "sweep")
		assert_eq(v.duration, r.duration, "duration")


func _constraint_pairs(state: BladeState) -> Array:
	var pairs: Array = []
	for cn in state.constraints:
		if cn is BladeDistanceConstraint:
			var dc := cn as BladeDistanceConstraint
			pairs.append(Vector2i(mini(dc.a, dc.b), maxi(dc.a, dc.b)))
	pairs.sort()
	return pairs
