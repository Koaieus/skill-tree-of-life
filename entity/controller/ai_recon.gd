class_name AiRecon
extends RefCounted

## Fog-aware enemy recon for AI v1 (#378). Per-entity vision, not the shared
## player-only [VisionSystem] instance (game_root's `%VisionSystem`, whose
## `viewers` is `[player]` and drives the player's fog rendering only) —
## settled 2026-08-07: "each enemy acts only on what it personally sees", no
## faction-shared reveal in v1. This module reuses VisionSystem's circle-test
## geometry (owned node position + local `vision_range`) but evaluates it
## fresh per AI turn, scoped to one entity, so it never touches the shared
## singleton's cached state.
##
## Recon depth for the cut-vertex/island walk is bounded separately from
## vision range: `recon_bound()` is attack reach + 1 allocation, deliberately
## decoupled from SP bank size so a large-SP entity doesn't scan the whole
## board (tier-2 knob: full SP+DP reach, not v1).


## True if [param entity] currently sees at least one hostile-owned node.
static func has_visible_hostile(entity: Entity) -> bool:
	return not visible_enemy_nodes(entity).is_empty()


## Every enemy-owned [SkillNode] within vision range of any of [param entity]'s
## owned nodes.
static func visible_enemy_nodes(entity: Entity) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if entity == null or entity.navigator == null or entity.navigator.graph == null:
		return out
	var graph := entity.navigator.graph
	var owned := entity.navigator.get_mirrored_nodes()
	if owned.is_empty():
		return out
	for node in graph.get_skill_nodes():
		if node == null or node.owned_by == null:
			continue
		if entity.attitude_to(node.owned_by) != Entity.Attitude.HOSTILE:
			continue
		if _within_vision(node, owned):
			out.append(node)
	return out


static func _within_vision(node: SkillNode, owned: Array[SkillNode]) -> bool:
	for src in owned:
		var r: float = float(src.get_local_value(&"vision_range"))
		if src.global_position.distance_squared_to(node.global_position) <= r * r:
			return true
	return false


## Attack-reach + 1-allocation bound. [param max_reach] is the largest
## per-mode attack reach available to [param entity] this turn — callers
## supply it since mode reach math (ranged/magic/melee) lives outside this
## module.
static func recon_bound(max_reach: float, allocation_cost: float = 1.0) -> float:
	return max_reach + allocation_cost


## Cut vertices in [param entity]'s own territory within [param bound] scene-
## pixels of its core — nodes that would island other owned nodes if
## depleted. Used both defensively (own weak points) and offensively (a
## hostile entity's cut vertices are high-value strike targets).
static func cut_vertices_within(entity: Entity, bound: float) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if entity == null or entity.navigator == null or entity.core_location == null:
		return out
	var core: SkillNode = entity.core_location
	for n in entity.navigator.get_mirrored_nodes():
		if n == core:
			continue
		if core.global_position.distance_to(n.global_position) > bound:
			continue
		if entity.navigator.would_disconnect_from(n, core):
			out.append(n)
	return out
