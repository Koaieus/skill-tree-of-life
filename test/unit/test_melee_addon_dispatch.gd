extends GutTest

## #405 — MeleeAttackPlan.build_blade_state() must dispatch node addons
## (apply_to_blade) the same way SkillBlade.build_from_skill_nodes does, so
## Clamp's weld constraint applies to the actual hit-resolution path, not just
## the live visual swing.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/clamp_addon.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = Entity.new()
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)


func test_build_blade_state_dispatches_clamp_addon() -> void:
	# source - joint - tip, joint carries Clamp (degree-2 in this selection).
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, source)
	_alloc.force_allocate(_entity, joint)
	_alloc.force_allocate(_entity, tip)

	var clamp := _CLAMP_SCENE.instantiate() as ClampAddon
	joint.add_child(clamp)
	await get_tree().process_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = _entity
	plan.source = source
	var members: Array[SkillNode] = [joint, tip]
	plan.blade_nodes = members

	var state := plan.build_blade_state()
	assert_not_null(state)
	# selection order is [source, joint, tip] -> indices 0, 1, 2.
	var found_brace := false
	for c in state.constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			if (dc.a == 0 and dc.b == 2) or (dc.a == 2 and dc.b == 0):
				found_brace = true
	assert_true(found_brace,
			"build_blade_state must dispatch Clamp's apply_to_blade and append the weld brace between the joint's neighbors")
