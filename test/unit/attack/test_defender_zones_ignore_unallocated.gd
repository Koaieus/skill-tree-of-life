extends GutTest

## #864 — an UNALLOCATED node must not defend.
##
## `swing_drag` (Fortification) and `deflection` (Bunker) are authored as LOCAL
## modifiers the instant the addon is parented, and procgen attaches addons at
## generation time — on a board where every node is still unowned. Since #810
## the defender collision bit is minted off that local value alone, so
## [method BladeDefenderZones.query] happily returned a whole map's worth of
## unowned walls and plates: a blade swung across neutral ground was dragged and
## deflected by terrain nobody had paid for.
##
## The spike half of the same rule was already right — [BladePopResolver.admit]
## gates every pop on `node.is_allocated()` — so this pins the two stats that
## were not, at the one site that answers "who defends this swing".
##
## The collision BIT is deliberately left alone: #810's contract is that it
## means "this node carries the stat", keyed on the local value and nothing
## else (`test_skill_node_defender_collision_bits.gd` pins that on bare,
## unallocated nodes). Allocation is a second question, and it is asked here.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _FORTIFICATION_SCENE := preload("res://skill_node/addons/fortification_addon.tscn")
const _BUNKER_SCENE := preload("res://skill_node/addons/bunker_addon.tscn")

const _QUERY_RADIUS := 400.0

var _graph: Graph
var _alloc: AllocationSystem
var _wall: SkillNode
var _plate: SkillNode


func _spawn(nm: String, pos: Vector2, addon_scene: PackedScene) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	sn.add_child(addon_scene.instantiate() as SkillNodeAddon)
	return sn


func _make_entity() -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	_graph.add_child(entity)
	return entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_wall = _spawn("Wall", Vector2(120.0, 0.0), _FORTIFICATION_SCENE)
	_plate = _spawn("Plate", Vector2(-120.0, 0.0), _BUNKER_SCENE)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _query() -> BladeDefenderZones:
	var world := _graph.get_world_2d()
	assert_not_null(world, "fixture: the graph must be in a live World2D")
	return BladeDefenderZones.query(
			world.direct_space_state, Vector2.ZERO, _QUERY_RADIUS, [], _graph)


func test_fixture_actually_authors_both_defender_stats() -> void:
	assert_gt(float(_wall.get_local_value(&"swing_drag")), 0.0,
			"fixture: Fortification must author swing_drag")
	assert_true(bool(_plate.get_local_value(&"deflection")),
			"fixture: Bunker must author deflection")
	assert_false(_wall.is_allocated(), "fixture: the wall is unowned")
	assert_false(_plate.is_allocated(), "fixture: the plate is unowned")
	assert_true(_wall.get_collision_layer_value(SkillNode.DRAG_COLLISION_LAYER),
			"fixture: the drag bit is still minted off the local value (#810)")
	assert_true(_plate.get_collision_layer_value(SkillNode.DEFLECT_COLLISION_LAYER),
			"fixture: the deflect bit is still minted off the local value (#810)")


func test_unallocated_carriers_contribute_no_zones() -> void:
	var zones := _query()
	assert_true(zones.is_empty(),
			"#864: an unowned fortified/bunkered node must not defend — got %d zone(s)"
					% zones.size())
	assert_false(zones.has_drag(), "no unowned wall may drag the swing")
	assert_false(zones.has_deflection(), "no unowned plate may deflect the swing")


func test_allocating_a_carrier_makes_it_defend_again() -> void:
	var defender := _make_entity()
	_alloc.force_allocate(defender, _wall)
	await get_tree().physics_frame

	var zones := _query()
	assert_eq(zones.size(), 1,
			"the newly-owned wall defends; the still-unowned plate does not")
	assert_true(zones.defenders.has(_wall), "the owned wall is the zone that landed")
	assert_true(zones.has_drag(), "an owned fortification still drags")
	assert_false(zones.has_deflection(), "the unowned bunker still does not deflect")
