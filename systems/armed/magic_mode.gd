class_name MagicMode
extends AttackArmMode

## Magic armed, no target yet: one click sets the target and stamps the
## auto-picked caster (#728), pushing [TargetMode]. The badge is the equipped
## spell's own icon when it has one.


func _init(p_ctl: PlayerInputController) -> void:
	super(p_ctl, BattleSystem.AttackMode.MAGIC)


func handle_left_click(node: SkillNode) -> bool:
	if plan() == null:
		return false
	if set_target(node):
		stack.push(TargetMode.new(self))
	return true


func set_target(node: SkillNode) -> bool:
	var p := plan() as MagicAttackPlan
	return p != null and p.set_target(node)


func icon() -> Texture2D:
	var p := plan() as MagicAttackPlan
	if p != null and p.spell != null and p.spell.icon != null:
		return p.spell.icon
	return super()
