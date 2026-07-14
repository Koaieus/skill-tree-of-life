@tool
class_name TopologicalBudgetBump
extends GuaranteedPlacement

## Graph-aware sibling of the euclidean [ScalarField] budget bumps: BFS-floods
## `max_hops` from `seed_count` random nodes and stamps `role_tag` on everyone
## caught in the flood. Unlike a positional field, this never jumps a gap —
## the buff only ever reaches nodes actually connected to the seed, which is
## the property [BudgetPolicy.role_bonus] can't get from `budget_field` alone.
##
## Designer-time example:
##   TopologicalBudgetBump { role_tag: &"anomalous", seed_count: 2, max_hops: 2 }
## paired with `BudgetPolicy.role_bonus = {&"anomalous": 1.75}` buffs two
## random pockets of the graph instead of scattering individual nodes
## ([RandomBudgetBoost]) or fixing the bump to a starter ([MinNearStartingPoints]).

@export var role_tag: StringName = &""
@export var seed_count: int = 1
@export var max_hops: int = 2
## Exclude starter positions from seed selection — a topological bump around a
## starter is [MinNearStartingPoints]'s job, not this one's.
@export var exclude_starters: bool = true


func apply(context: PlacementContext) -> void:
	if context == null or context.rng == null or role_tag == &"":
		return
	if seed_count <= 0:
		return
	var candidates: Array[int] = []
	var starter_set := {}
	if exclude_starters:
		for s in context.starter_indices:
			starter_set[s] = true
	for i in context.positions.size():
		if not starter_set.has(i):
			candidates.append(i)
	var pick := mini(seed_count, candidates.size())
	for i in pick:
		var j := i + context.rng.randi() % (candidates.size() - i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
		var seed_index := candidates[i]
		for n in context.nodes_within_hops(seed_index, max_hops):
			context.add_role_tag(n, role_tag)
