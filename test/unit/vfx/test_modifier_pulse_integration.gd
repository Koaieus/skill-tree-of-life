extends GutTest

## #70 + #71 wiring, end-to-end through AllocationVFX:
##   - a VOLUNTARY allocation of a node carrying a modifier sends a pulse that,
##     on arrival, fires Events.stat_modifier_arrived (DEFAULT_NODE) for that
##     modifier at the allocator's core;
##   - a FORCED allocation (setup) fires NO modifier floater (the spawn-flurry
##     suppression the `forced` flag exists for).
##
## This exercises the real signal path the pure unit tests don't: the
## navigator route (path_between ordering), the Curve2DPath pulse, and the
## arrival→floater seam.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _vfx: AllocationVFX
var _player: Entity
var _core: SkillNode
var _leaf: SkillNode
var _seen: Array = []


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_core = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_core.name = "Core"
	_graph.skill_nodes_container.add_child(_core)
	_leaf = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_leaf.name = "Leaf"
	_graph.skill_nodes_container.add_child(_leaf)

	var e := Edge.new()
	e.from = _core
	e.to = _leaf
	_graph.edges_container.add_child(e)

	# The leaf grants +7 Strength when allocated.
	var mod := StatModifier.new()
	mod.stat_id = &"strength"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 7.0
	_leaf.modifiers = [mod]

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_vfx = AllocationVFX.new()
	_graph.add_child(_vfx)
	autofree(_vfx)
	_vfx.bind(_alloc, null)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_player)
	await get_tree().process_frame

	_alloc.force_allocate(_player, _core)
	_player.core_location = _core
	_player.stat_board.skill_points.base_value = 10.0
	_player.stat_board.skill_points.restore_to_full()

	_seen = []
	Events.stat_modifier_arrived.connect(_record)


func after_each() -> void:
	if Events.stat_modifier_arrived.is_connected(_record):
		Events.stat_modifier_arrived.disconnect(_record)


func _record(entity: Entity, modifier: StatModifier, kind: int) -> void:
	_seen.append({"entity": entity, "modifier": modifier, "kind": kind})


func test_voluntary_allocation_pulses_then_floats() -> void:
	assert_true(_alloc.allocate(_leaf, _player), "leaf is adjacent + SP available")
	# Nothing fires at the instant of allocation — the pulse must travel first.
	assert_eq(_seen.size(), 0, "floater is delayed until pulse arrival, not on allocate")
	await get_tree().create_timer(0.6).timeout
	assert_eq(_seen.size(), 1, "exactly one floater after the pulse lands")
	assert_eq(_seen[0]["modifier"], _leaf.modifiers[0], "floats the granted modifier")
	assert_eq(_seen[0]["entity"], _player)
	assert_eq(int(_seen[0]["kind"]), int(Events.ModifierFloater.DEFAULT_NODE))


func test_forced_allocation_does_not_float() -> void:
	var leaf2 := _SKILL_NODE_SCENE.instantiate() as SkillNode
	leaf2.name = "Leaf2"
	_graph.skill_nodes_container.add_child(leaf2)
	var e := Edge.new()
	e.from = _core
	e.to = leaf2
	_graph.edges_container.add_child(e)
	var mod := StatModifier.new()
	mod.stat_id = &"strength"
	mod.value = 3.0
	leaf2.modifiers = [mod]

	_alloc.force_allocate(_player, leaf2)  # setup path — forced=true
	await get_tree().create_timer(0.6).timeout
	assert_eq(_seen.size(), 0, "forced (setup) allocations fire no modifier floater")
