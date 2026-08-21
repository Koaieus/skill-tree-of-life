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


## Empirical, not geometric: a swung blade WHIPS. Its far vertices lag and pull
## inward, so effective reach is far shorter than the static span from pivot to
## tip (measured: a 5-member blade spanning 319px only reaches ~275px, and much
## less on the angles it has already passed). A quarry authored at the static
## span looks reachable and is never touched — the failure that produced this
## number. Keep the cluster inside it when editing the layout.
const _MEASURED_REACH := 250.0


func test_quarry_sits_inside_the_reach_a_swing_actually_has() -> void:
	var hilt := _graph.skill_nodes_container.get_node("Hilt") as SkillNode
	for n in _owned_by("Quarry"):
		assert_lt(hilt.position.distance_to(n.position), _MEASURED_REACH,
				"%s must sit inside the swept reach, not merely inside the blade's span" % n.name)


func test_wielder_material_is_one_connected_piece() -> void:
	# A blade grows hop by hop from the pivot, so a disconnected wielder node is
	# material no blade can ever pick up.
	var owned: Array[SkillNode] = _owned_by("Wielder")
	var seen: Dictionary = {}
	var frontier: Array[SkillNode] = [_graph.skill_nodes_container.get_node("Hilt") as SkillNode]
	while not frontier.is_empty():
		var n: SkillNode = frontier.pop_back()
		if seen.has(n):
			continue
		seen[n] = true
		for other in _graph.get_neighbours(n):
			if other.owned_by == n.owned_by:
				frontier.append(other)
	assert_eq(seen.size(), owned.size(), "every wielder node must hang off the hilt")


func test_wielder_and_quarry_are_hostile() -> void:
	# Both default to the `npc` faction, which reads as ALLIED — and an allied
	# node is EXCLUDED from the hit scan before a query is ever made, so a swing
	# silently passes through the whole quarry. Authoring the wielder's faction
	# is the fix; this pins it.
	var wielder := _graph.entities_container.get_node("Wielder") as Entity
	var quarry := _graph.entities_container.get_node("Quarry") as Entity
	assert_eq(wielder.attitude_to(quarry), Entity.Attitude.HOSTILE,
			"a same-faction quarry is unhittable, with no error to read")
