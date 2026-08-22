extends GutTest

## The melee sandbox's hand-authored world. Every position and edge is authored
## in the .tscn (owner call: no programmatic placement), so this pins only the
## STRUCTURAL invariants a swing needs — hostility, connectivity, cores that
## resolve — each of which produces a sandbox that looks fine and swings wrong,
## with no error to read.
##
## [b]Nothing here counts or measures the layout.[/b] It is a scratchpad: the
## owner rearranges it, and a test that goes red on a rearrange is reporting the
## edit, not a defect. The node/edge tallies and the swept-reach bound both lived
## here and both failed that way. What the reach bound knew — a swung blade WHIPS,
## so a target at the static span is never touched — is fixture-authoring
## knowledge and lives in `.claude/rules/melee-fixtures.md`, where it applies to
## every melee fixture instead of policing one toy.

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
	# At least one, not exactly two: how many defenders carry a ring is layout,
	# and layout is the owner's to rearrange. Zero is the defect — a swing can
	# then never pop a blade vertex, which is what the de-lit look exists to show.
	assert_gt(spiked, 0,
			"a quarry with no spikes cannot pop a blade vertex")


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
