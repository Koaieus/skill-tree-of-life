@tool
class_name MinNearStartingPoints
extends GuaranteedPlacement

## "Natural-expansion" guarantee: for every starter, ensure at least `count`
## nodes within `max_hops` carry the given role tag. If fewer than `count`
## are already tagged after upstream placements ran, this placement tags
## random eligible nodes near the starter to fill the gap.
##
## v2.7 implementation tags by role_tag — a future content hook (forced pool
## entry, or a soft-bias weight profile) can react to that tag. We don't
## force-inject a modifier in the roll pass yet — that interleaves badly with
## the budget-only invariant.
##
## Designer-time example:
##   MinNearStartingPoints {
##     role_tag: &"xp_growth",
##     count: 1,
##     max_hops: 3,
##   }

@export var role_tag: StringName = &""
@export var count: int = 1
@export var max_hops: int = 3
## When true, prefer nodes that don't already carry other role tags. False =
## pick any.
@export var prefer_untagged: bool = true


func apply(context: PlacementContext) -> void:
	if context == null or context.rng == null or role_tag == &"":
		return
	for s in context.starter_indices:
		var reachable := context.nodes_within_hops(s, max_hops)
		# Skip the starter itself; tag content lives on neighbours.
		var eligible: Array[int] = []
		var already_tagged := 0
		for n in reachable:
			if n == s:
				continue
			var tags: Array = context.role_tags[n]
			if role_tag in tags:
				already_tagged += 1
				continue
			if prefer_untagged and not tags.is_empty():
				continue
			eligible.append(n)
		var need := count - already_tagged
		if need <= 0:
			continue
		if eligible.is_empty() and prefer_untagged:
			# Fall back to any untagged-for-this-tag node.
			for n in reachable:
				if n == s:
					continue
				var tags: Array = context.role_tags[n]
				if role_tag not in tags:
					eligible.append(n)
		if eligible.is_empty():
			push_warning("MinNearStartingPoints: starter %d has no eligible neighbour for tag %s within %d hops" % [s, String(role_tag), max_hops])
			continue
		# Random sample without replacement.
		var pick := mini(need, eligible.size())
		for i in pick:
			var j := i + context.rng.randi() % (eligible.size() - i)
			var tmp := eligible[i]
			eligible[i] = eligible[j]
			eligible[j] = tmp
			context.add_role_tag(eligible[i], role_tag)
