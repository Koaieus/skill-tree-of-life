class_name MagicMode
extends AttackArmMode

## Magic armed, no target yet: one click sets the target and stamps the
## auto-picked caster (#728), pushing [TargetMode]. The badge is the equipped
## spell's own icon when it has one.
##
## An aimed spell ([constant Targeting.TargetingKind.AIM]) is hover-aimed
## instead: while this level is the top, [method update_aim] snaps the shape to
## the eligible caster nearest the cursor and points it at the cursor, and
## [method lock_aim] (a left click) commits it by pushing [TargetMode] exactly
## as a clicked target does. Popping that level unlocks back to hover-aim.


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
	var p := plan() as MagicAttackPlan
	if p == null:
		return false
	if p.is_aimed():
		lock_aim()
		return true
	if set_target(node):
		stack.push(TargetMode.new(self))
	return true


## True while hover-aim is live: an aimed spell is armed and no aim is locked
## (nothing stands above this level).
func is_aiming() -> bool:
	var p := plan() as MagicAttackPlan
	return p != null and p.is_aimed() and stack != null and stack.top() == self


## Snap to the eligible caster nearest [param world] (global canvas position)
## and aim from it at [param world]. The lookup is over the union's casters,
## never the board; no threshold. A cursor inside the snapped caster's own disc
## names no direction — the last aim stands, so a click there commits nothing
## new.
func update_aim(world: Vector2) -> void:
	if not is_aiming():
		return
	var p := plan() as MagicAttackPlan
	var nearest: SkillNode = null
	var best := INF
	for src in p.union().sources:
		if not is_instance_valid(src):
			continue
		var d := world.distance_squared_to(src.global_position)
		if d < best:
			best = d
			nearest = src
	if nearest == null:
		return
	var delta := world - nearest.global_position
	if delta.length() <= maxf(nearest.radius, 1.0):
		return
	p.set_aim(nearest, delta.angle())


## Lock the hover-aim: a plan it left castable commits by pushing
## [TargetMode]. Idempotent — a no-op once locked (this level is no longer the
## top) or while the aim does not validate. True iff it pushed.
func lock_aim() -> bool:
	if not is_aiming():
		return false
	var p := plan() as MagicAttackPlan
	if not p.validate().is_empty():
		return false
	return stack.push(TargetMode.new(self))


## Open the spell picker ([SpellPickMode]) on top, or close the one on the
## branch. True iff the picker is open afterwards. The one entry point the
## magic body's spell button calls. An open aspect chooser closes.
func toggle_picker() -> bool:
	if stack == null:
		return false
	var picker := stack.find(SpellPickMode) as SpellPickMode
	if picker != null and picker.magic == self:
		picker.pop_self()
		return false
	return _open_leaf(SpellPickMode.new(self), stack.find(InfusionPickMode))


## Open the aspect chooser ([InfusionPickMode]) on infusion socket
## [param index], close it when that socket is already open, or move an open
## one to [param index]; an open spell picker closes. True iff a chooser is
## open afterwards. The entry point a socket's left-click calls.
func toggle_socket(index: int) -> bool:
	if stack == null:
		return false
	var open := stack.find(InfusionPickMode) as InfusionPickMode
	if open == null or open.magic != self:
		return _open_leaf(InfusionPickMode.new(self, index), stack.find(SpellPickMode))
	if open.socket == index:
		open.pop_self()
		return false
	return _open_leaf(InfusionPickMode.new(self, index), open)


## Push [param leaf], or swap it in for [param rival] — the other chooser leaf
## open on the branch — in one [signal ArmedStack.changed]: the spell picker
## and an aspect chooser never stand open together.
func _open_leaf(leaf: ArmedMode, rival: ArmedMode) -> bool:
	if rival == null:
		return stack.push(leaf)
	var branch := stack.branch()
	return stack.switch_to(leaf, branch[branch.find(rival) - 1])


## An aimed spell has no target node: a click while locked ([TargetMode]'s
## retarget) changes nothing — right-click unlocks back to hover-aim.
func set_target(node: SkillNode) -> bool:
	var p := plan() as MagicAttackPlan
	if p != null and p.is_aimed():
		return false
	return p != null and p.set_target(node)


func icon() -> Texture2D:
	var p := plan() as MagicAttackPlan
	if p != null and p.spell != null and p.spell.icon != null:
		return p.spell.icon
	return super()
