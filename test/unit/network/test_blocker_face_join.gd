extends GutTest

## #1654 acceptance 4 — a faced Dormant Core survives a join: the face class by
## path (the CORE_CLASS row) and the face's stats by value (the board payload).
## The host's +N / ×N potency roll therefore never needs to cross.
##
## [member Entity.core_modifiers] itself does NOT cross for any entity —
## `EntitySnapshot._decode_identity` assigns the class without re-applying and
## the board reconcile re-syncs only intrinsics — so the client's register is
## empty. Harmless today: the loot draw runs on the attack authority only.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _POISON := preload("res://entity/blocker/faces/poison_face.tres")
const _FACE_STATS: Array[StringName] = [&"poison_aspect", &"poison_stacks_per_hit", &"poison_resistance"]


func _side(count: int) -> Dictionary:
	var s := {"nodes": [] as Array[SkillNode]}
	var graph := autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	for i in count:
		var node: SkillNode = _NODE_SCENE.instantiate()
		node.name = "N%d" % i
		node.position = Vector2(i * 100.0, 0.0)
		graph.add_skill_node(node)
		graph.restore_stable_id(node, i + 1)
		(s["nodes"] as Array[SkillNode]).append(node)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var factory := EntityFactory.new()
	autofree(factory)
	factory.graph = graph
	factory.allocation_system = alloc
	await get_tree().process_frame
	s["graph"] = graph
	s["factory"] = factory
	return s


func test_a_faced_blocker_crosses_with_its_face() -> void:
	var host: Dictionary = await _side(3)
	var client: Dictionary = await _side(3)
	var blocker: Entity = (host["factory"] as EntityFactory).spawn_blocker(
			EntityFactory.BlockerSize.LARGE, host["nodes"][1], [], 0, 0.0, 0, 1, 0.25, _POISON, 7)
	await get_tree().process_frame
	assert_gt(float(blocker.stat_board.get_value(&"poison_aspect")), 0.0, "the host blocker wears its face")

	var entity_bytes := EntitySnapshot.encode(host["graph"] as Graph)
	var graph_bytes := GraphSnapshot.encode(host["graph"] as Graph)
	var spawner := Callable(client["factory"], "spawn_snapshot_entity")
	EntitySnapshot.decode(entity_bytes, client["graph"] as Graph, spawner)
	GraphSnapshot.decode(graph_bytes, client["graph"] as Graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, client["graph"] as Graph, spawner)
	await get_tree().process_frame

	var rebuilt: Entity = (client["graph"] as Graph).get_by_entity_id(blocker.entity_id)
	assert_not_null(rebuilt, "the client rebuilt the blocker")
	if rebuilt == null:
		return
	assert_eq(rebuilt.core_class.resource_path, _POISON.resource_path, "the face crosses by path")
	for id in _FACE_STATS:
		assert_eq(float(rebuilt.stat_board.get_value(id)), float(blocker.stat_board.get_value(id)),
				"%s reads the same on both peers" % id)
