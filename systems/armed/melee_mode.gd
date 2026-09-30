class_name MeleeMode
extends AttackArmMode

## Melee armed, no pivot yet: a click on an owned node sets the pivot and
## pushes [BladeMode] — the only constructor of one. Its icon is the hilt
## alone, the blade still to be formed (#683); Blade on top shows the sword.

const _HILT_ICON := preload("res://assets/icons/addons/armed_melee_hilt.png")


func _init(p_ctl: PlayerInputController) -> void:
	super(p_ctl, BattleSystem.AttackMode.MELEE)


func handle_left_click(node: SkillNode) -> bool:
	var p := plan() as MeleeAttackPlan
	if p == null:
		return false
	if p.set_pivot(node):
		open_blade()
	return true


## Push the [BladeMode] over this level — after a pivot click, or after a
## reform rebuilt the pivot outside input. A no-op when one already stands.
func open_blade() -> void:
	if stack != null and stack.find(BladeMode) == null:
		stack.push(BladeMode.new(self))


func reload() -> bool:
	ctl.reform_blade()
	return true


func icon() -> Texture2D:
	return _HILT_ICON
