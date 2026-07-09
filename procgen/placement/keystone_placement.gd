@tool
class_name KeystonePlacement
extends GuaranteedPlacement

## Places a [Keystone] on the node nearest a designer-specified position.
## The placement stores the keystone reference on the [PlacementContext]; the
## per-node loop hands the resulting [SkillNode] to [method Keystone.stamp],
## which bakes the keystone's presentation onto it and leaves its effects as a
## live reference for [AllocationSystem] to grant on allocate.
##
## Future placement-rule subclasses might target highest-degree nodes,
## random within a region, exact node index, etc. For now: one rule.

@export var keystone: Keystone
## Place on the node whose position is nearest to this point.
@export var target_position: Vector2 = Vector2.ZERO
## Optional role tag stamped alongside the keystone reference — useful for
## debug overlays and for [BudgetPolicy.role_bonus] hooks.
@export var role_tag: StringName = &"keystone"
## When true, skip starter positions (a starter usually gets designed
## content, not a placed keystone).
@export var exclude_starters: bool = true


func apply(context: PlacementContext) -> void:
	if context == null or keystone == null:
		return
	var n := context.positions.size()
	if n == 0:
		return
	var excluded := {}
	if exclude_starters:
		for s in context.starter_indices:
			excluded[s] = true
	var best := -1
	var best_sq := INF
	for i in n:
		if excluded.has(i):
			continue
		var d := context.positions[i].distance_squared_to(target_position)
		if d < best_sq:
			best_sq = d
			best = i
	if best == -1:
		push_warning("KeystonePlacement: no eligible node found near %s" % target_position)
		return
	context.keystones[best] = keystone
	if role_tag != &"":
		context.add_role_tag(best, role_tag)
