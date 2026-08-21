extends GutTest

## The melee sandbox's hand-authored world. Every position and edge is authored
## in the .tscn (owner call: no programmatic placement), so the thing worth
## pinning is that the authored content is still THERE and still shaped like a
## blade — a scene edit that silently drops a node or an `owned_by` NodePath
## produces a sandbox that looks fine and swings wrong.

const _WORLD := preload("res://scenes/dev/melee_sandbox_graph.tscn")

var _graph: Graph


func before_each() -> void:
	_graph = _WORLD.instantiate() as Graph
	add_child_autofree(_graph)


func _owned_by(name_: String) -> Array[SkillNode]:
	var entity := _graph.entities_container.get_node_or_null(NodePath(name_)) as Entity
	var out: Array[SkillNode] = []
	for n in _graph.get_skill_nodes():
		if n.owned_by == entity:
			out.append(n)
	return out


func test_authored_population() -> void:
	assert_eq(_graph.get_skill_nodes().size(), 20, "15 wielder nodes + 5 quarry nodes")
	assert_eq(_graph.get_edges().size(), 19, "14 wielder edges + 5 quarry edges")
	assert_eq(_owned_by("Wielder").size(), 15, "the blade material")
	assert_eq(_owned_by("Quarry").size(), 5, "something to swing at")


func test_cores_point_at_authored_nodes() -> void:
	var wielder := _graph.entities_container.get_node("Wielder") as Entity
	var quarry := _graph.entities_container.get_node("Quarry") as Entity
	assert_eq(wielder.core_location.name, &"Hilt", "the pivot the blade hangs off")
	assert_eq(quarry.core_location.name, &"E_Core")


func test_quarry_carries_spikes_so_the_pop_path_fires() -> void:
	var spiked := 0
	for n in _owned_by("Quarry"):
		for addon in n.get_addons():
			if addon is SpikeRingAddon:
				spiked += 1
	assert_eq(spiked, 2,
			"two spiked defenders — without them a swing can never pop a blade vertex, "
			+ "which is exactly what the de-lit look exists to show")


func test_wielder_territory_is_connected_and_reaches_the_quarry() -> void:
	# A blade is grown hop by hop from the pivot, so a disconnected wielder node
	# is unreachable material; and a quarry out of the swept annulus is a target
	# no swing can ever touch. Both are silent authoring mistakes.
	var hilt := _graph.skill_nodes_container.get_node("Hilt") as SkillNode
	var reach := 0.0
	for n in _owned_by("Wielder"):
		reach = maxf(reach, hilt.position.distance_to(n.position))
	for n in _owned_by("Quarry"):
		assert_lt(hilt.position.distance_to(n.position), reach + n.radius,
				"%s must sit inside the blade's sweep radius" % n.name)
