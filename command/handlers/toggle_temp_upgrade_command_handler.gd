class_name ToggleTempUpgradeCommandHandler
extends NodeCommandHandler

## [ToggleTempUpgradeCommand] -> [method BattleSystem.toggle_temp_upgrade_on].


func _validate_node(command: NodeCommand, node: SkillNode, _actor: Entity,
		ctx: CommandContext) -> bool:
	if ctx.battle_system == null:
		return false
	var upgrade := MeleeAttackPlan.upgrade_by_id(
			(command as ToggleTempUpgradeCommand).upgrade_id)
	# Announces its own refusal, where the reason (slot full vs. budget) is
	# knowable — the applier never emits gameplay denials itself. This is why
	# the gate is a method on [BattleSystem] and not an expression here.
	return ctx.battle_system.can_toggle_temp_upgrade_on(node, upgrade)


func _apply_node(command: NodeCommand, node: SkillNode, _actor: Entity,
		ctx: CommandContext) -> bool:
	if ctx.battle_system == null:
		return false
	var upgrade := MeleeAttackPlan.upgrade_by_id(
			(command as ToggleTempUpgradeCommand).upgrade_id)
	return ctx.battle_system.toggle_temp_upgrade_on(node, upgrade)
