class_name RangedAttackPlan
extends AttackPlan

## Single-target ranged attack: the player left-clicks an enemy-occupied
## node to mark it as the target. Firing positions are derived (every leaf
## of the attacker's owned territory) — those within [member FIRING_RANGE]
## of the target light up as ORIGIN. Right-click the current target to
## clear it.

const FIRING_RANGE: float = 280.0

var target: SkillNode = null


func _init() -> void:
	mode = BattleSystem.AttackMode.RANGED


func _on_node_left_clicked(node: SkillNode) -> void:
	if not _is_valid_target(node):
		return
	if target == node:
		return
	target = node
	state_changed.emit()


func _on_node_right_clicked(node: SkillNode) -> void:
	if target == null or node != target:
		return
	target = null
	state_changed.emit()


func get_firing_positions() -> Array[SkillNode]:
	if attacker == null or attacker.navigator == null:
		return []
	return attacker.navigator.get_leaf_nodes()


## Subset of [method get_firing_positions] within [const FIRING_RANGE] of
## the current target. Empty if no target.
func get_reaching_firing_positions() -> Array[SkillNode]:
	var result: Array[SkillNode] = []
	if target == null:
		return result
	for leaf in get_firing_positions():
		if leaf.global_position.distance_to(target.global_position) <= FIRING_RANGE:
			result.append(leaf)
	return result


func get_highlight_role(node: SkillNode) -> HighlightRole:
	if node == null or attacker == null:
		return HighlightRole.NONE
	if target != null and node == target:
		return HighlightRole.HOSTILE_TARGET
	if node.owned_by == attacker:
		if get_firing_positions().has(node) and target != null:
			var d := node.global_position.distance_to(target.global_position)
			return HighlightRole.ORIGIN if d <= FIRING_RANGE else HighlightRole.NONE
		return HighlightRole.NONE
	if node.owned_by != null and node.owned_by != attacker:
		return HighlightRole.IN_RANGE
	return HighlightRole.NONE


func get_node_range(node: SkillNode) -> float:
	if attacker == null or attacker.navigator == null:
		return 0.0
	if get_firing_positions().has(node):
		return FIRING_RANGE
	return 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if target == null:
		errors.append(&'No target')
		return errors
	if target.owned_by == attacker:
		errors.append(&'Target node is not owned by an enemy')
	if get_reaching_firing_positions().is_empty():
		errors.append(&'No firing position can reach target')
	return errors


func _is_valid_target(node: SkillNode) -> bool:
	if node == null or attacker == null:
		return false
	if node.owned_by == null or node.owned_by == attacker:
		return false
	return true


func resolve() -> AttackOutcome:
	# One DamageInstance per reaching firing position — flat-armour-friendly,
	# stagger-VFX-friendly. Caller (BattleSystem.launch_attack) consumes these
	# in order; arrival is staggered by the VFX layer, not here.
	var outcome := AttackOutcome.new()
	if not is_valid():
		return outcome
	for firing in get_reaching_firing_positions():
		var hit := RangedDamageFormula.compute(attacker, firing, target)
		hit.source = self
		outcome.hits.append(hit)
	return outcome
