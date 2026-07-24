@tool
class_name TerritorySeeder
extends Resource

## Grows spawn-time territory as a greedy BFS ball (#275, D-19/D-24): assumes
## the core is already claimed (the caller's `spawn_entity` force_allocate),
## then loops [member policy] over the current frontier until [param node_count]
## nodes are owned or the graph runs out of reachable unowned nodes.
##
## Applies via [method AllocationSystem.force_allocate] — the ungated
## primitive. Seeding is one-shot level setup, not gameplay; `allocate` is
## SP/AP-gated and hostile to that.
##
## Injectable per `.claude/rules/scene-composition.md`: `@export`ed so any
## level scene can wire a different policy (the greedy ball today; weighted
## growth is a documented follow-up living on the AI-allocation issue, not
## this class) without touching this script.

## The pick strategy. Its `rng` field is (re)seeded here before every call so
## repeated `seed_territory` calls sharing one on-disk policy resource never
## bleed RNG state between entities or between test runs.
@export var policy: AllocationPolicy

## Neutral, switchable-off tactical intent (D-24). Spawn seeding always wants
## plausible built-out territory, never a directed attack run, so this stays
## null for the seeder; a future tactical AI caller would pass something real
## here instead of routing through TerritorySeeder at all.
@export var objective: Resource = null


## Claims nodes for [param entity] up to [param node_count] total (core
## included). Returns the entity's actual owned-node count once seeding
## stops — equal to `node_count` unless the graph ran out of reachable
## unowned nodes first, in which case it's whatever was claimable.
func seed_territory(
	entity: Entity,
	graph: Graph,
	allocation_system: AllocationSystem,
	node_count: int,
	rng: RandomNumberGenerator,
) -> int:
	if entity == null or graph == null or allocation_system == null \
			or policy == null or entity.navigator == null:
		return _owned_count(entity)
	policy.rng = rng
	var owned_count := _owned_count(entity)
	while owned_count < node_count:
		var frontier := _frontier(entity, graph)
		if frontier.is_empty():
			push_warning("TerritorySeeder: ran out of unowned reachable nodes for '%s' at %d/%d" \
					% [entity.display_name, owned_count, node_count])
			break
		var pick: SkillNode = policy.pick_next(entity, frontier, objective)
		if pick == null:
			break
		allocation_system.force_allocate(entity, pick)
		owned_count += 1
	return owned_count


func _owned_count(entity: Entity) -> int:
	if entity == null or entity.navigator == null:
		return 0
	return entity.navigator.get_mirrored_nodes().size()


## Frontier = every unowned node adjacent to a node `entity` already owns,
## computed over the WHOLE graph — the seeder's candidate set. A future
## sensed-subgraph AI caller would compute its own, narrower one and never
## call this. Uses `graph.get_neighbours()` (cached adjacency) once per owned
## node rather than walking `graph.get_edges()` per candidate — see
## `.claude/rules/graph.md`.
func _frontier(entity: Entity, graph: Graph) -> Array[SkillNode]:
	var frontier: Array[SkillNode] = []
	var seen: Dictionary[SkillNode, bool] = {}
	for owned_node in entity.navigator.get_mirrored_nodes():
		for neighbour in graph.get_neighbours(owned_node):
			if neighbour.owned_by == null and not seen.has(neighbour):
				seen[neighbour] = true
				frontier.append(neighbour)
	return frontier
