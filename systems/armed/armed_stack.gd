@tool
class_name ArmedStack
extends Node

## The seat-local armed-input stack (#1222): the active branch of a statechart,
## root first. The root ([ManageMode]) is unpoppable; every other level is an
## [ArmedMode] pushed on top. Never synced — only the Commands a level submits
## cross the wire.
##
## Every public mutation emits [signal changed] exactly once (or not at all when
## nothing moved), however many levels it pushed or popped. [method ArmedMode.on_popped]
## runs top-down, AFTER the level has left the branch.

signal changed
## The plan of the attack level on the branch moved — armed, swapped, dropped.
## Fires once per move, after the branch settled; the argument is the plan
## itself, or null.
signal attack_plan_changed(plan: AttackPlan)
## The plan moved ([signal attack_plan_changed]) or changed inside (its own
## [signal HighlightProvider.state_changed]) — what a body repaints on.
signal attack_plan_state_changed
## RESET cleared the plan's selection ([method reset_plan]) — the event the
## armed step levels ([BladeMode], [TargetMode]) pop on.
signal plan_reset


## An entity's picked spell moved ([method select_spell]) — a sticky
## preference on its [MagicMemory] that outlives every plan.
signal selected_spell_changed(spell: SpellDef)

## Per-entity [SeatMemory], keyed by `get_instance_id()`. Never synced, never
## saved, and untouched by [method clear_to_root]: it lasts the level, i.e. the run.
var _memory: Dictionary[int, SeatMemory] = {}
var _branch: Array[ArmedMode] = []
var _last_plan: AttackPlan = null


## [param entity]'s [SeatMemory] — every attack mode's last choice. Keyed by
## `get_instance_id()` (the [GateLockSet] pattern) so a hot-seat handover keeps
## each player's. A null entity gets a throwaway default.
func memory_for(entity: Entity) -> SeatMemory:
	if entity == null:
		return SeatMemory.new()
	var id := entity.get_instance_id()
	if not _memory.has(id):
		_memory[id] = SeatMemory.new()
	return _memory[id]


## Pick [param spell] for [param entity]: the next [MagicMode] plan of that
## entity is minted with it, and an armed magic plan of that entity is
## re-equipped ([method MagicAttackPlan.set_spell]) with its infusion swapped
## for the remembered one. Null means "the plan's bundled fallback". A no-op
## (no [signal selected_spell_changed]) when the pick is unchanged.
func select_spell(entity: Entity, spell: SpellDef) -> void:
	var magic_memory := memory_for(entity).magic
	if magic_memory.selected_spell == spell:
		return
	magic_memory.selected_spell = spell
	var magic := attack_plan() as MagicAttackPlan
	if magic != null and entity != null and magic.attacker == entity:
		remember_infusion(magic)
		magic.set_spell(spell)
		restore_infusion(magic)
	selected_spell_changed.emit(spell)


## Install [param mode] as the unpoppable root, dropping any branch silently
## (no [method ArmedMode.on_popped], no [signal changed]) — construction, not play.
func set_root(mode: ArmedMode) -> void:
	_branch = [mode]
	mode.stack = self


## The plan of the attack level ([AttackArmMode]) on the branch, or null. The
## level creates it on push and drops it on pop; this only exposes it.
func attack_plan() -> AttackPlan:
	var level := find(AttackArmMode) as AttackArmMode
	return level.plan() if level != null else null


## Re-reads [method attack_plan] and announces a move. Called after every
## branch mutation and by an [AttackArmMode] whose plan moved under it.
func sync_attack_plan() -> void:
	var p := attack_plan()
	if p == _last_plan:
		return
	if _last_plan is MagicAttackPlan:
		remember_infusion(_last_plan)
	if p is MagicAttackPlan:
		restore_infusion(p)
	if _last_plan != null and _last_plan.state_changed.is_connected(attack_plan_state_changed.emit):
		_last_plan.state_changed.disconnect(attack_plan_state_changed.emit)
	_last_plan = p
	if p != null:
		p.state_changed.connect(attack_plan_state_changed.emit)
	attack_plan_changed.emit(p)
	attack_plan_state_changed.emit()


## Record [param plan]'s infusion as its spell's entry in its attacker's
## [member MagicMemory.last_infusion]. Taken when a magic plan leaves a spell
## (re-equip, disarm, launch) — never off [signal AttackPlan.state_changed],
## since [method MagicAttackPlan.set_spell] resets the infusion before it
## emits. Spells with an empty [member SpellDef.id] are not remembered.
func remember_infusion(plan: MagicAttackPlan) -> void:
	if plan.spell == null or plan.spell.id.is_empty():
		return
	var magic := memory_for(plan.attacker).magic
	magic.last_infusion[plan.spell.id] = plan.infusion.points.duplicate()
	magic.last_fields[plan.spell.id] = plan.infusion.fields_to_dict()


## Put back the remembered infusion of [param plan]'s spell, clamped by
## [method clamp_infusion] (the aspects) and [method clamp_fields] (the shape
## and the ride). Nothing remembered leaves the plan as it is.
func restore_infusion(plan: MagicAttackPlan) -> void:
	var magic := memory_for(plan.attacker).magic
	if plan.spell == null:
		return
	var remembered := magic.last_infusion
	if remembered.has(plan.spell.id):
		var kept := clamp_infusion(plan.spell, plan.attacker, remembered[plan.spell.id],
				plan.capacity())
		for id in plan.infusion.points.keys():
			if not kept.has(id):
				plan.set_infusion(id, 0)
		for id in kept:
			plan.set_infusion(id, kept[id])
	if magic.last_fields.has(plan.spell.id):
		var fields := clamp_fields(plan.spell, plan.attacker, magic.last_fields[plan.spell.id])
		plan.set_shape(fields.shape_element, fields.shape_points)
		plan.set_ride(fields.ride_element, fields.ride_points)


## The remembered aspects of [param points] (`{concept id: points}`) socketed
## into one cast of [param spell] by [param attacker] today, in entry order (the
## socket order): refused concepts dropped, no more entries than
## `infusion_slots`, and each kept aspect filled to the most it can carry —
## `min(<concept>_aspect held, what [param cap] leaves)`. [param cap] is the
## cap in force — [method MagicAttackPlan.capacity], the best eligible caster's
## before a target is picked; below 0 it is the spell's base cap. Nothing is
## consumed, so the remembered point counts are ignored. Its
## [method MagicAttackPlan.aspect_overrun] is 0.
static func clamp_infusion(spell: SpellDef, attacker: Entity,
		points: Dictionary, cap: int = -1) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	if spell == null:
		return out
	var slots := AspectCurrency.cap_of(attacker, &"infusion_slots")
	var left := cap if cap >= 0 else spell.capacity_at(spell.min_degree)
	var capped := left < SpellDef.UNCAPPED
	for key in points:
		var id := StringName(key)
		if out.size() >= slots or (capped and left <= 0):
			break
		if Infusion.rate_of(spell, id) <= 0.0:
			continue
		var stat := AspectCurrency.stat_of(id)
		if stat.is_empty():
			continue
		var pts := AspectCurrency.cap_of(attacker, stat)
		if capped:
			pts = mini(pts, left)
		if pts <= 0:
			continue
		out[id] = pts
		left -= pts
	return out


## The remembered shape and ride [param fields] (
## [method Infusion.fields_to_dict]'s form) cut to what [param attacker] holds
## today, as an [Infusion] carrying only the two fields. Each keeps its
## remembered points and is only cut, never refilled: the shape to its
## element's count, then the ride to what that count leaves (on one element
## the ride gives way first), and to 0 on an element [param spell] refuses.
## The capacity never cuts either. Its [method MagicAttackPlan.aspect_overrun]
## field terms are 0.
static func clamp_fields(spell: SpellDef, attacker: Entity, fields: Dictionary) -> Infusion:
	var wanted := Infusion.new()
	wanted.read_fields(fields)
	var out := Infusion.new()
	if wanted.shape_points > 0:
		var shape_count := AspectCurrency.cap_of(attacker, AspectCurrency.stat_of(wanted.shape_element))
		out.set_shape(wanted.shape_element, mini(wanted.shape_points, shape_count))
	if wanted.ride_points > 0 and Infusion.rate_of(spell, wanted.ride_element) > 0.0:
		var left := AspectCurrency.cap_of(attacker, AspectCurrency.stat_of(wanted.ride_element)) \
				- out.spent_on(wanted.ride_element)
		out.set_ride(wanted.ride_element, mini(wanted.ride_points, left))
	return out


## The armed plan's mode, or NONE when no attack level holds one.
func attack_mode() -> BattleSystem.AttackMode:
	var p := attack_plan()
	return p.mode if p != null else BattleSystem.AttackMode.NONE


## Clear the armed plan's selection and announce [signal plan_reset]. A no-op
## with nothing armed or mid-swing.
func reset_plan() -> void:
	var level := find(AttackArmMode) as AttackArmMode
	if level != null:
		level.reset_plan()


## Disarm: pop the attack level, which drops its plan.
func cancel_attack() -> void:
	var level := find(AttackArmMode)
	if level != null:
		pop(level)


func root() -> ArmedMode:
	return _branch[0] if not _branch.is_empty() else null


func top() -> ArmedMode:
	return _branch.back() if not _branch.is_empty() else null


## Root first. A copy — mutate through the stack's own operations.
func branch() -> Array[ArmedMode]:
	return _branch.duplicate()


func has(mode: ArmedMode) -> bool:
	return mode in _branch


## The top-most level that is an instance of [param type] (a level class), or null.
func find(type: Variant) -> ArmedMode:
	for i in range(_branch.size() - 1, 0, -1):
		if is_instance_of(_branch[i], type):
			return _branch[i]
	return null


## Push [param mode] on top. False when the level refused ([method ArmedMode.on_pushed]).
func push(mode: ArmedMode) -> bool:
	if _branch.is_empty() or not _enter(mode):
		return false
	sync_attack_plan()
	changed.emit()
	return true


## Pop the top level. False at the root.
func pop_top() -> bool:
	if _branch.size() <= 1:
		return false
	_pop_above(_branch.size() - 2)
	sync_attack_plan()
	changed.emit()
	return true


## "Pop me": remove [param mode] and everything above it. False when it is
## not on the branch, or is the root.
func pop(mode: ArmedMode) -> bool:
	var i := _branch.find(mode)
	if i <= 0:
		return false
	_pop_above(i - 1)
	sync_attack_plan()
	changed.emit()
	return true


## Pop back to [param anchor] (the root by default), then push [param mode] —
## one operation, one [signal changed]. Returns whether [param mode] landed; the
## pops stand either way.
func switch_to(mode: ArmedMode, anchor: ArmedMode = null) -> bool:
	var i := _branch.find(anchor if anchor != null else root())
	if i < 0:
		return false
	var popped := _pop_above(i)
	var pushed := _enter(mode)
	sync_attack_plan()
	if popped or pushed:
		changed.emit()
	return pushed


func clear_to_root() -> void:
	if _pop_above(0):
		sync_attack_plan()
		changed.emit()


func _enter(mode: ArmedMode) -> bool:
	mode.stack = self
	if not mode.on_pushed():
		return false
	_branch.append(mode)
	return true


## Cut the branch first, THEN run the hooks top-down: an [method ArmedMode.on_popped]
## that re-arms something (a cancel whose plan-changed listener pushes a fresh
## level) lands on the new branch instead of being popped by this loop forever.
func _pop_above(index: int) -> bool:
	if _branch.size() - 1 <= index:
		return false
	var popped := _branch.slice(index + 1)
	_branch.resize(index + 1)
	for i in range(popped.size() - 1, -1, -1):
		(popped[i] as ArmedMode).on_popped()
	return true
