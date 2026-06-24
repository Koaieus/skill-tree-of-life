@tool
class_name RandomBudgetBoost
extends GuaranteedPlacement

## Stamps a role tag on N randomly-chosen nodes. The procgen modifier roll
## passes per-node `role_tags` into [BudgetPolicy.compute_budget], which looks
## up matching keys in `role_bonus` and multiplies them into the rolled
## budget. So setting:
##     BudgetPolicy.role_bonus = {&"anomalous": 1.75}
##     RandomBudgetBoost { count: 10, role_tag: &"anomalous" }
## produces 10 nodes with 1.75× the rolled modifier budget — without making
## them a separate archetype.
##
## Selection is random over all nodes (excluding starter positions by default —
## the starter typically wants designed content, not a random boost).

@export var count: int = 0
@export var role_tag: StringName = &"anomalous"
@export var exclude_starters: bool = true


func apply(context: PlacementContext) -> void:
	if context == null or context.rng == null:
		return
	if count <= 0 or role_tag == &"":
		return
	var candidates: Array[int] = []
	var starter_set := {}
	if exclude_starters:
		for s in context.starter_indices:
			starter_set[s] = true
	for i in context.positions.size():
		if not starter_set.has(i):
			candidates.append(i)
	# Fisher-Yates partial shuffle: pick the first `count` from a random permutation.
	var pick := mini(count, candidates.size())
	for i in pick:
		var j := i + context.rng.randi() % (candidates.size() - i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
		context.add_role_tag(candidates[i], role_tag)
