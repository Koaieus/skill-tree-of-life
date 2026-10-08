@tool
class_name InfusionRow
extends HBoxContainer

## The cast's infusion steppers (#1463): one per aspect the caster holds, its
## identity glyph, `points / <concept>_aspect` and −/+ that write
## [method MagicAttackPlan.set_infusion]. The header reads both caps —
## `slots used / infusion_slots · Σ points / min(infusion_points,
## SpellDef.infusion_capacity)`. A "+" greys at the first cap that bites and its
## tooltip names it; a stepper the spell refuses, or that no free slot could
## take, dims whole. Hidden while there is nothing to infuse.
##
## Binds to a bare [MagicAttackPlan] — the caster is [member AttackPlan.attacker]
## — and repaints on the plan's own [signal AttackPlan.state_changed], so any
## host (the tray, a spell playground) only calls [method bind]. Steppers are
## [code]duplicate()[/code]s of the hidden %StepperTemplate, laid out in the
## wrapping %Steppers [HFlowContainer]: a caster may hold every rostered aspect,
## and a row of a dozen steppers must wrap rather than widen its host (#753).

## Points one click adds or takes.
@export_range(1, 10, 1, "or_greater") var step: int = 1
## Points one shift-click adds or takes.
@export_range(1, 100, 1, "or_greater") var big_step: int = 5
## How far a stepper dims when the spell refuses it or no slot could take it.
@export_range(0.0, 1.0, 0.05) var dimmed_alpha: float = 0.4

@onready var _header: Label = %Header
@onready var _steppers_box: HFlowContainer = %Steppers
@onready var _template: HBoxContainer = %StepperTemplate

var _plan: MagicAttackPlan = null
var _steppers: Dictionary[StringName, HBoxContainer] = {}


func _ready() -> void:
	_template.visible = false
	_refresh()


## Show and drive [param plan]'s infusion; null unbinds. Re-binding the bound
## plan is free.
func bind(plan: MagicAttackPlan) -> void:
	if plan == _plan:
		return
	if _plan != null and _plan.state_changed.is_connected(_refresh):
		_plan.state_changed.disconnect(_refresh)
	_plan = plan
	if _plan != null:
		_plan.state_changed.connect(_refresh)
	_refresh()


func stepper_ids() -> Array[StringName]:
	return _steppers.keys()


func value_text(id: StringName) -> String:
	return (_steppers[id].get_node("Value") as Label).text if _steppers.has(id) else ""


func plus_button(id: StringName) -> Button:
	return _steppers[id].get_node("Plus") as Button if _steppers.has(id) else null


func minus_button(id: StringName) -> Button:
	return _steppers[id].get_node("Minus") as Button if _steppers.has(id) else null


func header_text() -> String:
	return _header.text


func _caster() -> Entity:
	return _plan.attacker if _plan != null else null


## Aspects [method _caster] holds above zero, in roster order.
func _held() -> Array[Aspect]:
	var out: Array[Aspect] = []
	if _plan == null or _plan.spell == null:
		return out
	for aspect in AspectRoster.shared().aspects:
		if aspect != null and aspect.stat != null \
				and AspectCurrency.cap_of(_caster(), aspect.stat.id) > 0:
			out.append(aspect)
	return out


## Points this cast may spend in total: `min(infusion_points, infusion_capacity)`.
func _depth() -> int:
	var depth := AspectCurrency.cap_of(_caster(), &"infusion_points")
	if _plan != null and _plan.spell != null and not is_inf(_plan.spell.infusion_capacity):
		depth = mini(depth, maxi(0, floori(_plan.spell.infusion_capacity)))
	return depth


func _refresh() -> void:
	if not is_node_ready():
		return
	var held := _held()
	visible = not held.is_empty()
	var ids: Array[StringName] = []
	for aspect in held:
		ids.append(aspect.id())
	if ids != stepper_ids():
		_rebuild(held)
	if held.is_empty():
		return
	var infusion := _plan.infusion
	var slots := AspectCurrency.cap_of(_caster(), &"infusion_slots")
	_header.text = "slots %d/%d · points %d/%d" % [infusion.slots_used(), slots,
			infusion.total_points(), _depth()]
	for id in _steppers:
		_paint(id, slots)


func _rebuild(held: Array[Aspect]) -> void:
	for stepper in _steppers.values():
		stepper.queue_free()
	_steppers.clear()
	for aspect in held:
		var id := aspect.id()
		var stepper := _template.duplicate() as HBoxContainer
		stepper.name = "Stepper_%s" % id
		stepper.visible = true
		(stepper.get_node("Badge") as IdentityBadge).identity = aspect.identity
		(stepper.get_node("Minus") as Button).pressed.connect(_on_step.bind(id, -1))
		(stepper.get_node("Plus") as Button).pressed.connect(_on_step.bind(id, 1))
		_steppers_box.add_child(stepper)
		_steppers[id] = stepper


func _paint(id: StringName, slots: int) -> void:
	var stepper := _steppers[id]
	var pts: int = _plan.infusion.points.get(id, 0)
	var cap := AspectCurrency.cap_of(_caster(), AspectCurrency.stat_of(id))
	(stepper.get_node("Value") as Label).text = "%d / %d" % [pts, cap]
	var why := _blocked(id, pts, cap, slots)
	var plus := stepper.get_node("Plus") as Button
	plus.disabled = not why.is_empty()
	plus.tooltip_text = why if not why.is_empty() \
			else "+%d %s point (shift: +%d)" % [step, id, big_step]
	var minus := stepper.get_node("Minus") as Button
	minus.disabled = pts <= 0
	minus.tooltip_text = "−%d %s point (shift: −%d)" % [step, id, big_step]
	var refused := Infusion.rate_of(_plan.spell, id) <= 0.0
	var no_slot := pts == 0 and _plan.infusion.slots_used() >= slots
	stepper.modulate.a = dimmed_alpha if refused or no_slot else 1.0


## Why "+" on [param id] is greyed — the first cap that bites — or "".
func _blocked(id: StringName, pts: int, cap: int, slots: int) -> String:
	var spell := _plan.spell
	if Infusion.rate_of(spell, id) <= 0.0:
		return "%s refuses %s infusions" % [spell.name, id]
	if pts >= cap:
		return "At the %s aspect cap (%d)" % [id, cap]
	var depth := _depth()
	if _plan.infusion.total_points() >= depth:
		var pool := AspectCurrency.cap_of(_caster(), &"infusion_points")
		if depth < pool:
			return "At %s's infusion capacity (%d points)" % [spell.name, depth]
		return "At the infusion points cap (%d)" % depth
	if pts == 0 and _plan.infusion.slots_used() >= slots:
		return "No infusion slot free (%d/%d)" % [_plan.infusion.slots_used(), slots]
	return ""


func _on_step(id: StringName, direction: int) -> void:
	if _plan == null:
		return
	var amount := big_step if Input.is_key_pressed(KEY_SHIFT) else step
	var pts: int = _plan.infusion.points.get(id, 0)
	var room := mini(AspectCurrency.cap_of(_caster(), AspectCurrency.stat_of(id)),
			pts + _depth() - _plan.infusion.total_points())
	var next := clampi(pts + amount, 0, maxi(room, 0)) if direction > 0 \
			else maxi(0, pts - amount)
	_plan.set_infusion(id, next)
