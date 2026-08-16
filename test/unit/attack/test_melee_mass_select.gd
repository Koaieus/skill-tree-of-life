extends GutTest

## Mass-select: left-clicking a node further out than the current blade set
## selects the shortest owned-territory path leading to it too, as one
## atomic toggle gated by the same blade_size budget as a single member.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

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


## pivot - joint - tip chain, all allocated to _entity. budget defaults large
## enough to fit the whole chain; override to exercise the reject-outright path.
func _setup_chain(budget: float = 3.0) -> Dictionary:
	_entity.stat_board.blade_size.base_value = budget
	var pivot := _spawn("Pivot")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_graph.add_edge(pivot, joint)
	_graph.add_edge(joint, tip)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, pivot)
	_alloc.force_allocate(_entity, joint)
	_alloc.force_allocate(_entity, tip)

	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = _entity
	return {"plan": plan, "pivot": pivot, "joint": joint, "tip": tip}


func test_clicking_a_far_node_mass_selects_the_path_to_it() -> void:
	var f := await _setup_chain()
	var plan: MeleeAttackPlan = f.plan
	plan._on_node_left_clicked(f.pivot)
	plan._on_node_left_clicked(f.tip)  # not adjacent to the pivot — joint is between
	assert_true(plan.blade_nodes.has(f.joint),
			"the connecting node is pulled in along with the clicked target")
	assert_true(plan.blade_nodes.has(f.tip), "the clicked target itself is selected")


func test_mass_select_is_rejected_outright_when_it_overruns_budget() -> void:
	var f := await _setup_chain(1.0)  # room for exactly one member
	var plan: MeleeAttackPlan = f.plan
	plan._on_node_left_clicked(f.pivot)
	plan._on_node_left_clicked(f.tip)  # needs joint + tip — two members, budget is one
	assert_false(plan.blade_nodes.has(f.joint), "no partial selection on reject")
	assert_false(plan.blade_nodes.has(f.tip), "no partial selection on reject")
	assert_true(plan.blade_nodes.is_empty())
