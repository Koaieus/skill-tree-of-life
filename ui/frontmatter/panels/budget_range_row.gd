class_name BudgetRangeRow
extends HBoxContainer

## The modifier-budget min/max row — **the one control in #643 that must work**.
##
## The LAN requirement in the owner's own words (2026-08-27): *"allow users like
## 'hey do the normal stuff but increase budgets, lets go HAM'. so that i don't
## have to recompile + redistribute the game mid-lan if we want to tune runs"*.
## That is why this is raw spinners rather than a named ladder, inverting #597
## D6's presets-first default: there is no meaningful Few/Regular/Lots for "go
## HAM", and a beautiful picker that does not reach
## [member BudgetPolicy.base_min] / [member BudgetPolicy.base_max] delivers
## none of the requirement.
##
## [b]`allow_greater` is load-bearing, not a stray inspector flag.[/b] "Go HAM"
## is precisely the case where the host wants a number past anything worth
## authoring a slider range for, and a [SpinBox] that silently clamped the typed
## value would fail the requirement while looking like it worked.
##
## [b]Both leaves are `int`[/b] ([member BudgetPolicy.base_min] is `@export var
## base_min: int`), and a [SpinBox] hands back a `float`. #642's D14 probe
## measured `set_indexed` SILENTLY TRUNCATING a float into an int leaf, so this
## row rounds at its own boundary and emits ints — belt and braces with
## [method ScenarioOverride._coerce], which rounds explicitly and warns when
## lossy. Emitting a float here would be correct-by-luck.

## A real edit by the host. Never fires for [method set_range]'s seeding write —
## which is the whole of #643 acceptance 5: an untouched control must write NO
## override, so "untouched" has to be observable as "this never emitted".
signal range_changed(base_min: int, base_max: int)

@onready var _label: Label = %Label
@onready var _min_spin: SpinBox = %MinSpin
@onready var _max_spin: SpinBox = %MaxSpin

var _updating := false


func _ready() -> void:
	_min_spin.value_changed.connect(_on_min_changed)
	_max_spin.value_changed.connect(_on_max_changed)


## Seeds both spinners from the preset's AUTHORED values, silently. The seed
## must be the authored number rather than a neutral placeholder: the host is
## tuning relative to "the normal stuff", so the box has to open showing what
## normal currently is.
func set_range(base_min: int, base_max: int) -> void:
	_updating = true
	_min_spin.value = base_min
	_max_spin.value = base_max
	_updating = false


func get_min_value() -> int:
	return roundi(_min_spin.value)


func get_max_value() -> int:
	return roundi(_max_spin.value)


## Raising min past max drags max with it (and vice versa), because
## [BudgetPolicy]'s roll is `lerp(base_min, base_max, randf())` — an inverted
## range does not error, it quietly rolls DOWN from min to max, which is the
## kind of silent wrongness a LAN has no time to diagnose.
func _on_min_changed(v: float) -> void:
	if _updating:
		return
	if v > _max_spin.value:
		_updating = true
		_max_spin.value = v
		_updating = false
	_emit()


func _on_max_changed(v: float) -> void:
	if _updating:
		return
	if v < _min_spin.value:
		_updating = true
		_min_spin.value = v
		_updating = false
	_emit()


func _emit() -> void:
	range_changed.emit(get_min_value(), get_max_value())
