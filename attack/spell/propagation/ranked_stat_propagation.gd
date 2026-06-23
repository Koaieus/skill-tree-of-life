@tool
class_name RankedStatPropagation
extends SpellPropagation

## Propagates to the [member take_count] neighbours with the highest (or
## lowest) value of [member stat_id]. Reads each candidate via
## [method SkillNode.get_local_stat] so localized modifiers (addons) and
## entity bins compose correctly — same path [SkillNode] uses for its own
## max-HP read.
##
## Tiebreaker is stable scene order (first appearance in
## [method Graph.get_neighbours]); intentional so tests can author a known
## winner without ratchet logic.
##
## Use cases: smart bolt that homes in on the wounded core ("lowest
## node_health"), executioner that picks the tank ("highest node_health"),
## any future "smart-arc" that ranks by some board stat.

enum Direction {
	HIGHEST,
	LOWEST,
}

## Which stat to rank candidates by. Read via [method SkillNode.get_local_stat]
## so it composes the same way the node's own consumers read it.
@export var stat_id: StringName = &"node_health"
@export var direction: Direction = Direction.HIGHEST
## How many top-ranked neighbours to fan into. 1 = laser-focus (no fan-out).
@export_range(1, 16) var take_count: int = 1
## When true, candidates owned by the caster are excluded from ranking.
## Off → friendly fire is in play and your own nodes can win the rank.
@export var only_enemy: bool = true


func next_hops(state: CastSpell) -> Array[CastSpell]:
	if state.graph == null or state.current_node == null:
		return []
	var candidates: Array[SkillNode] = []
	for nb in state.graph.get_neighbours(state.current_node):
		if not revisit_visited and nb in state.visited:
			continue
		if only_enemy and nb.owned_by == state.caster:
			continue
		candidates.append(nb)
	if candidates.is_empty():
		return []
	# Stable sort: SkillNode array carries scene order, so equal scores
	# preserve that order — predictable for both tests and authors.
	var sign := 1 if direction == Direction.LOWEST else -1
	candidates.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		return sign * _read_stat(a) < sign * _read_stat(b))
	var out: Array[CastSpell] = []
	var k: int = min(take_count, candidates.size())
	for i in k:
		out.append(_propagate_to(candidates[i], state))
	return out


func _read_stat(node: SkillNode) -> float:
	if node == null:
		return 0.0
	var ls := node.get_local_stat(stat_id)
	if ls == null:
		return 0.0
	var v: Variant = ls.value
	return float(v) if v != null else 0.0


func get_description() -> String:
	var dir_word := "highest" if direction == Direction.HIGHEST else "lowest"
	var scope := "enemy" if only_enemy else "any"
	return "Chains to the %s-%s %s neighbour%s, up to %d hop%s." % [
		take_count, dir_word, scope, "" if take_count == 1 else "s",
		max_hops, "" if max_hops == 1 else "s"]
