class_name BladeMode
extends AttackStepMode

## The blade being formed on a pivot. A click on the pivot pops this level
## (the pivot is never a member — the self-click fallthrough, consumed so the
## [MeleeMode] below does not re-arm it); any other click toggles a member.
## Popping clears the pivot. A temp upgrade arms only on top of this level.

const _MELEE_ICON := preload("res://assets/icons/addons/armed_melee.png")

var melee: MeleeMode:
	get: return parent as MeleeMode


func _init(p_melee: MeleeMode) -> void:
	super(p_melee)


func handle_left_click(node: SkillNode) -> bool:
	var p := parent.plan() as MeleeAttackPlan
	if p == null:
		return false
	if node == p.source:
		pop_self()
	else:
		p.toggle_member(node)
	return true


## Arm [param scene] on this blade, replacing any other armed card.
func arm_temp_upgrade(scene: PackedScene) -> bool:
	return stack.switch_to(TempUpgradeMode.new(ctl, scene), self)


func _undo(p: AttackPlan) -> void:
	(p as MeleeAttackPlan).clear_pivot()


func icon() -> Texture2D:
	return _MELEE_ICON

