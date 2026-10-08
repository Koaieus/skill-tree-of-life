class_name MagicMode
extends AttackArmMode

## Magic armed, no target yet: one click sets the target and stamps the
## auto-picked caster (#728), pushing [TargetMode]. The badge is the equipped
## spell's own icon when it has one.


var _on_ownership_3: Callable
var _on_ownership_2: Callable
var _on_turn: Callable


func _init(p_ctl: PlayerInputController) -> void:
	super(p_ctl, BattleSystem.AttackMode.MAGIC)


func on_pushed() -> bool:
	if not super():
		return false
	_on_ownership_3 = _invalidate_union.unbind(3)
	_on_ownership_2 = _invalidate_union.unbind(2)
	_on_turn = _invalidate_union.unbind(1)
	var alloc := ctl.allocation_system
	if alloc != null:
		alloc.allocated.connect(_on_ownership_3)
		alloc.deallocated.connect(_on_ownership_2)
		alloc.force_deallocated.connect(_on_ownership_2)
	if ctl.turn_manager != null:
		ctl.turn_manager.turn_started.connect(_on_turn)
	return true


func on_popped() -> void:
	var alloc := ctl.allocation_system
	if alloc != null and _on_ownership_3.is_valid():
		if alloc.allocated.is_connected(_on_ownership_3):
			alloc.allocated.disconnect(_on_ownership_3)
		if alloc.deallocated.is_connected(_on_ownership_2):
			alloc.deallocated.disconnect(_on_ownership_2)
		if alloc.force_deallocated.is_connected(_on_ownership_2):
			alloc.force_deallocated.disconnect(_on_ownership_2)
	if ctl.turn_manager != null and _on_turn.is_valid() \
			and ctl.turn_manager.turn_started.is_connected(_on_turn):
		ctl.turn_manager.turn_started.disconnect(_on_turn)
	super()


## The pick-spell-first target union (#728) is cached on the plan and depends
## on (spell, ownership, turn) — never on the hovered or committed target, so it
## cannot ride [signal AttackPlan.state_changed]. Ownership and turn move it
## from OUTSIDE the plan; this pushes the invalidation in, then emits the
## PLAN's own `state_changed`, which reaches both the highlight overlays
## (via [signal HighlightController.provider_state_changed]) and the HUD bodies
## (via [signal ArmedStack.attack_plan_state_changed]). Allocating a node that
## newly clears a spell's `min_degree` must make it castable at once.
func _invalidate_union() -> void:
	var p := plan() as MagicAttackPlan
	if p != null:
		p.invalidate_union()
		p.state_changed.emit()


func handle_left_click(node: SkillNode) -> bool:
	if plan() == null:
		return false
	if set_target(node):
		stack.push(TargetMode.new(self))
	return true


## Open the spell picker ([SpellPickMode]) on top, or close the one on the
## branch. True iff the picker is open afterwards. The one entry point the
## magic body's spell button calls.
func toggle_picker() -> bool:
	if stack == null:
		return false
	var picker := stack.find(SpellPickMode) as SpellPickMode
	if picker != null and picker.magic == self:
		picker.pop_self()
		return false
	return stack.push(SpellPickMode.new(self))


func set_target(node: SkillNode) -> bool:
	var p := plan() as MagicAttackPlan
	return p != null and p.set_target(node)


func icon() -> Texture2D:
	var p := plan() as MagicAttackPlan
	if p != null and p.spell != null and p.spell.icon != null:
		return p.spell.icon
	return super()
