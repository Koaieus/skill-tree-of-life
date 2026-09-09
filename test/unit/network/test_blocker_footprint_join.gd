extends GutTest

## #777 acceptance 9 — a multi-node Dormant Core survives a join with ZERO new
## serialization. Everything the footprint needs is already on the wire:
## per-node ownership rides [GraphSnapshot]'s `owner_id`, the core rides
## [EntitySnapshot]'s `core_location`, and the falloff aura rides the entity's
## effect list — where the re-grant is idempotent ([method
## EntitySnapshot._has_grant]) and the `core_location` assignment in pass 2 is
## what re-derives the caps on this side.
##
## The joining peer runs NO procgen (#715), so its blocker is rebuilt by
## [method GameRoot.spawn_snapshot_entity] — which spawns with an empty
## footprint by design. If the aura did not re-derive from the decoded world,
## every footprint node on the client would draw a health bar 5-per-hop too
## tall, and the client would disagree with the host about what a kill costs.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")


## A line of `count` nodes with matching stable ids on both sides, plus the
## GameRoot + AllocationSystem `spawn_blocker` needs. A Dictionary rather than
## an inner class: an `await`ing helper's declared return type is the coroutine,
## not the value, so a typed one will not parse.
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


func _caps(side: Dictionary) -> Array[float]:
	var out: Array[float] = []
	for node: SkillNode in (side["nodes"] as Array[SkillNode]):
		out.append(node.get_max_hp())
	return out


func test_a_multi_node_blocker_crosses_with_its_falloff_intact() -> void:
	var host: Dictionary = await _side(5)
	var client: Dictionary = await _side(5)
	var footprint: Array[SkillNode] = [host["nodes"][2], host["nodes"][3], host["nodes"][4]]
	var blocker: Entity = (host["root"] as GameRoot).spawn_blocker(
			GameRoot.BlockerSize.MEDIUM, host["nodes"][1], footprint)
	await get_tree().process_frame
	assert_eq(_caps(host), [0.0, 40.0, 35.0, 30.0, 25.0] as Array[float],
			"host: an unowned node never mints a pool at all (0), then 40 − 5 per hop")

	# The join, in the order the real one runs it. The client spawns nothing
	# up front — the blocker arrives through the spawner, exactly as on a peer
	# that ran no procgen.
	var entity_bytes := EntitySnapshot.encode(host["graph"] as Graph)
	var graph_bytes := GraphSnapshot.encode(host["graph"] as Graph)
	var spawner := Callable(client["root"], "spawn_snapshot_entity")
	EntitySnapshot.decode(entity_bytes, client["graph"] as Graph, spawner)
	GraphSnapshot.decode(graph_bytes, client["graph"] as Graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, client["graph"] as Graph, spawner)
	await get_tree().process_frame

	var rebuilt: Entity = (client["graph"] as Graph).get_by_entity_id(blocker.entity_id)
	assert_not_null(rebuilt, "the client rebuilt the blocker from the snapshot")
	assert_eq(rebuilt.entity_tier, 2, "tier survives, and the tier names the board")
	assert_eq(rebuilt.core_location, client["nodes"][1], "core_location survives")
	for i in range(1, 5):
		assert_eq(client["nodes"][i].owned_by, rebuilt,
				"node %d owned by the rebuilt blocker" % i)
	assert_eq(_caps(client), _caps(host),
			"every footprint node caps identically on both peers")
