extends GutTest

## WatchtowerAddon grants a node-local +250 vision_range on its carrier only —
## same localization contract as SpikeRing on blade_damage
## (test_blade_damage_localization.gd), but for VisionSystem's per-node read
## (systems/vision_system.gd get_local_value(&"vision_range")).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _WATCHTOWER_SCENE := preload("res://skill_node/addons/watchtower_addon.tscn")

const _WATCHTOWER_VISION := 250.0


func _spawn_node(graph: Node, nm: String) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = nm
	graph.skill_nodes_container.add_child(node)
	return node


func _setup() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	graph.add_child(entity)

	var source := _spawn_node(graph, "Source")
	var tower := _spawn_node(graph, "Tower")
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, source)
	alloc.force_allocate(entity, tower)

	tower.add_child(_WATCHTOWER_SCENE.instantiate())

	return {"graph": graph, "entity": entity, "source": source, "tower": tower}


func test_watchtower_grants_node_local_vision_bonus() -> void:
	var ctx: Dictionary = await _setup()
	var source: SkillNode = ctx.source
	var tower: SkillNode = ctx.tower
	var base_vision: float = float(source.get_local_value(&"vision_range"))
	var tower_vision: float = float(tower.get_local_value(&"vision_range"))
	assert_almost_eq(tower_vision, base_vision + _WATCHTOWER_VISION, 0.001,
			"watchtower node must see wielder base + 250 vision")


func test_watchtower_removed_reverts_vision() -> void:
	var ctx: Dictionary = await _setup()
	var source: SkillNode = ctx.source
	var tower: SkillNode = ctx.tower
	var addon := tower.get_addons()[0]
	addon.free()
	await get_tree().process_frame
	assert_almost_eq(float(tower.get_local_value(&"vision_range")),
			float(source.get_local_value(&"vision_range")), 0.001,
			"removing the watchtower must revert to the bare wielder value")
