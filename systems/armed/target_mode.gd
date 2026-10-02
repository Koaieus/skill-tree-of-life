class_name TargetMode
extends AttackStepMode

## A ranged or magic target is set. Another click retargets at the same depth
## (a refused retarget is still consumed); popping clears the target.
##
## Beyond [AttackStepMode]'s events, a spell swap
## ([signal ArmedStack.selected_spell_changed]) pops this level when the new
## spell can no longer reach the target. Reading `plan.target` there is the
## plan's own fact read on the plan's own event — never a
## `state_changed` listener, never a poll.


func _init(p_parent: AttackArmMode) -> void:
	super(p_parent)


func on_pushed() -> bool:
	super()
	ctl.armed_stack.selected_spell_changed.connect(_on_spell_changed)
	return true


func on_popped() -> void:
	var seat := ctl.armed_stack
	if seat != null and seat.selected_spell_changed.is_connected(_on_spell_changed):
		seat.selected_spell_changed.disconnect(_on_spell_changed)
	super()


func handle_left_click(node: SkillNode) -> bool:
	if parent.plan() == null:
		return false
	parent.set_target(node)
	return true


func _undo(p: AttackPlan) -> void:
	p.reset()


func _on_spell_changed(_spell: SpellDef) -> void:
	var p := parent.plan() as MagicAttackPlan
	if p != null and p.target == null:
		pop_self()
