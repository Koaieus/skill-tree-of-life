extends GutTest

## One [BladeVertexFill], two build sites: the plan's
## [method MeleeAttackPlan.build_blade_state] and the visual
## [method SkillBlade.build_from_skill_nodes] must come out with the same
## per-vertex numbers and the same addon constraints for the same nodes —
## including a spiked vertex and a clamped one.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

var _graph: Graph
var _entity: Entity


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


## source - joint(Clamp) - tip(SpikeRing), all selected; selection order is
## [source, joint, tip] -> particle indices 0, 1, 2.
func _setup() -> MeleeAttackPlan:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	await get_tree().process_frame
	for sn in [source, joint, tip]:
		alloc.force_allocate(_entity, sn)
	joint.add_child(_CLAMP_SCENE.instantiate())
	tip.add_child(_SPIKE_SCENE.instantiate())
	await get_tree().process_frame

	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	plan.source = source
	var members: Array[SkillNode] = [joint, tip]
	plan.blade_nodes = members
	return plan


func _build_visual(plan: MeleeAttackPlan) -> BladeState:
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [plan.source]
	nodes.append_array(plan.blade_nodes)
	blade.build_from_skill_nodes(
			nodes, plan.source, plan.get_induced_edges(), _entity, plan.vertex_fill)
	return blade.state


func _constraint_pairs(state: BladeState) -> Array:
	var pairs: Array = []
	for c in state.constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			pairs.append([mini(dc.a, dc.b), maxi(dc.a, dc.b)])
	pairs.sort()
	return pairs


func test_plan_and_visual_blade_fill_identically() -> void:
	var plan: MeleeAttackPlan = await _setup()
	var resolve_state := plan.build_blade_state()
	var visual_state := _build_visual(plan)

	assert_eq(visual_state.vertex_damage, resolve_state.vertex_damage,
			"one fill: per-vertex damage identical on both build sites")
	assert_eq(visual_state.vertex_blunting, resolve_state.vertex_blunting,
			"one fill: per-vertex blunting identical on both build sites")
	assert_eq(_constraint_pairs(visual_state), _constraint_pairs(resolve_state),
			"one fill: addon constraints identical on both build sites")


func test_fill_reads_each_vertex_own_localized_stats() -> void:
	var plan: MeleeAttackPlan = await _setup()
	var state := plan.build_blade_state()
	var tip: SkillNode = plan.blade_nodes[1]
	var source := plan.source

	assert_almost_eq(state.vertex_damage[2], float(tip.get_local_value(&"blade_damage")), 0.001,
			"spiked vertex carries its own localized blade_damage")
	assert_gt(state.vertex_damage[2], state.vertex_damage[0],
			"the spike raises the tip above the bare pivot")
	assert_almost_eq(state.vertex_blunting[2], float(tip.get_local_value(&"blunting")), 0.001,
			"spiked vertex carries its own localized blunting")
	assert_almost_eq(state.vertex_blunting[0], float(source.get_local_value(&"blunting")), 0.001)
	assert_true(_constraint_pairs(state).has([0, 2]),
			"the clamped joint welds its neighbours (Clamp's apply_to_blade dispatched)")


func test_vertex_stats_pair_with_blade_state_arrays() -> void:
	assert_eq(BladeVertexFill.VERTEX_STATS.size(), BladeVertexFill.STATE_ARRAYS.size(),
			"every per-vertex stat names the BladeState array it lands in")
	var state := BladeState.new()
	var props: Array[StringName] = []
	for p in state.get_property_list():
		props.append(StringName(p.name))
	for arr in BladeVertexFill.STATE_ARRAYS:
		assert_true(props.has(arr), "%s must be a real BladeState member" % arr)
