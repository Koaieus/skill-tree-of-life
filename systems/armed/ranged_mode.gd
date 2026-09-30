class_name RangedMode
extends AttackArmMode

## Ranged armed, no target yet: a click on a valid target aims the volley and
## pushes [TargetMode]. Reload refills the quiver.


func _init(p_ctl: PlayerInputController) -> void:
	super(p_ctl, BattleSystem.AttackMode.RANGED)


func handle_left_click(node: SkillNode) -> bool:
	if plan() == null:
		return false
	if set_target(node):
		stack.push(TargetMode.new(self))
	return true


func set_target(node: SkillNode) -> bool:
	var p := plan() as RangedAttackPlan
	return p != null and p.set_target(node)


func reload() -> bool:
	ctl.request_reload()
	return true
