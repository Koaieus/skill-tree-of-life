extends GutTest

## #916 seam — a PRE-STAKED Dormant Core survives a join with zero new
## serialization. `GraphSnapshot` already carries `stake_level` and
## `allocation_level` per node, so the adopting peer's node reads 3/3 off its
## row; the adoption path ([method GameRoot.spawn_snapshot_entity]) spawns
## with NO core and the default stake, so nothing there re-runs
## `force_allocate` (which hardcodes a 1) or `force_fill` over the row.
## `mp:e2e` cannot see this (default chance 0), hence the unit test.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")


func _side(count: int) -> Dictionary:
	var s := {"nodes": [] as Array[SkillNode]}
	var graph := autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var previous: SkillNode = null
	for i in count:
		var node: SkillNode = _NODE_SCENE.instantiate()
		node.name = "N%d" % i
		node.position = Vector2(i * 100.0, 0.0)
		graph.add_skill_node(node)
		graph.restore_stable_id(node, i + 1)
		if previous != null:
			var e := _EDGE_SCENE.instantiate() as Edge
			e.from = previous
			e.to = node
			graph.edges_container.add_child(e)
		previous = node
		(s["nodes"] as Array[SkillNode]).append(node)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var root := GameRoot.new()
	autofree(root)
	root.graph = graph
	root.allocation_system = alloc
	await get_tree().process_frame
	s["graph"] = graph
	s["root"] = root
	return s


func test_a_3_of_3_blocker_core_crosses_the_join_as_3_of_3() -> void:
	var host: Dictionary = await _side(3)
	var client: Dictionary = await _side(3)
	var blocker: Entity = (host["root"] as GameRoot).spawn_blocker(
			GameRoot.BlockerSize.SMALL, host["nodes"][1],
			[host["nodes"][2]] as Array[SkillNode], 0, 0.0, 0, 3)
	await get_tree().process_frame
	var host_core: SkillNode = host["nodes"][1]
	assert_eq(host_core.stake_level, 3, "host: cap stamped")
	assert_eq(host_core.allocation_level, 3, "host: filled")

	var entity_bytes := EntitySnapshot.encode(host["graph"] as Graph)
	var graph_bytes := GraphSnapshot.encode(host["graph"] as Graph)
	var spawner := Callable(client["root"], "spawn_snapshot_entity")
	EntitySnapshot.decode(entity_bytes, client["graph"] as Graph, spawner)
	GraphSnapshot.decode(graph_bytes, client["graph"] as Graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, client["graph"] as Graph, spawner)
	await get_tree().process_frame

	var rebuilt: Entity = (client["graph"] as Graph).get_by_entity_id(blocker.entity_id)
	assert_not_null(rebuilt, "the client rebuilt the blocker")
	var client_core: SkillNode = client["nodes"][1]
	assert_eq(client_core.owned_by, rebuilt, "core owned by the rebuilt blocker")
	assert_eq(client_core.stake_level, 3, "client: the row's cap lands")
	assert_eq(client_core.allocation_level, 3,
			"client: the row's 3/3 fill lands and nothing re-runs force_allocate over it")
	assert_eq((client["nodes"][2] as SkillNode).allocation_level, 1, "footprint node stays 1/1")
	assert_eq(client_core.get_max_hp(), host_core.get_max_hp(), "core cap agrees across the join")
	assert_eq(client_core.get_current_hp(), host_core.get_current_hp(),
			"core HP agrees across the join")
	# Deliberately NOT a whole-world fingerprint: in this bare fixture (no
	# aura re-derivation pass) the FOOTPRINT node's current HP already drifts
	# on the join at stake 1 (client 10/15 vs host 15/15) — pre-existing and
	# unrelated to the stake, see #916's comments.
