class_name MagicMode
extends AttackArmMode

## Magic armed, no target yet: one click sets the target and stamps the
## auto-picked caster (#728), pushing [TargetMode]. The badge is the equipped
## spell's own icon when it has one.
##
## An aimed spell ([constant Targeting.TargetingKind.AIM]) is dragged instead:
## a press on an eligible caster arms the gesture, [method update_aim] points it
## at the cursor while the button is held, and [method release_aim] commits it
## by pushing [TargetMode] exactly as a clicked target does.


var _on_ownership_3: Callable
var _on_ownership_2: Callable
var _on_turn: Callable
## The caster an aimed drag is anchored on; null when no drag is armed.
var _aim_source: SkillNode = null


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
	_aim_source = null
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
	var p := plan() as MagicAttackPlan
	if p == null:
		return false
	if p.is_aimed():
		_begin_aim(p, node)
		return true
	if set_target(node):
		stack.push(TargetMode.new(self))
	return true


## True while an aimed drag is armed (pressed on a caster, not yet released).
func is_aiming() -> bool:
	return _aim_source != null


## Arms the drag iff [param node] is an eligible caster of the aimed spell;
## any other press arms nothing.
func _begin_aim(p: MagicAttackPlan, node: SkillNode) -> bool:
	_aim_source = node if node != null and p.union().is_source(node) else null
	return _aim_source != null


## Point the armed drag at [param world] (global canvas position). A cursor
## still on the caster's centre names no direction and is ignored.
func update_aim(world: Vector2) -> void:
	var p := plan() as MagicAttackPlan
	if p == null or _aim_source == null or not is_instance_valid(_aim_source):
		return
	var delta := world - _aim_source.global_position
	if delta.is_zero_approx():
		return
	p.set_aim(_aim_source, delta.angle())


## End the drag. A plan the drag left castable commits: [TargetMode] is
## pushed unless this level already has one above it (a re-aim from there).
## A press released without ever aiming commits nothing. True iff a drag was
## armed.
func release_aim() -> bool:
	if _aim_source == null:
		return false
	_aim_source = null
	var p := plan() as MagicAttackPlan
	if p != null and p.validate().is_empty() and stack.top() == self:
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


## For an aimed spell a click names a caster, not a target: it re-arms the
## drag (how [TargetMode] re-aims) rather than committing anything.
func set_target(node: SkillNode) -> bool:
	var p := plan() as MagicAttackPlan
	if p != null and p.is_aimed():
		return _begin_aim(p, node)
	return p != null and p.set_target(node)


func icon() -> Texture2D:
	var p := plan() as MagicAttackPlan
	if p != null and p.spell != null and p.spell.icon != null:
		return p.spell.icon
	return super()
