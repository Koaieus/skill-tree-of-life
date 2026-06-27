@tool
class_name InitiativeBar
extends Control

## Player's turn-order clock. Tracks the `initiative` PoolStat: the bar fills as
## the clock climbs toward its cap (the action threshold) between turns, flips to
## the ACTIVE tint + holds full once the entity is ready to act, and drains when
## the turn starts.
##
## Readiness drives the "full" visual, NOT the raw `current` value — the cyclic
## pool carries overshoot forward, so `current` snaps back near zero the instant
## the clock crosses the cap. We'd flicker if we followed `current` there, so
## `_on_ready` holds the bar full until `_on_owner_turn_started` drains it.

const ACTIVE_TINT: Color = Color(1.0, 0.8, 0.4, 1.0)
const INACTIVE_TINT: Color = Color(0.51, 0.301, 0.117, 1.0)
const ANIMATION_SPEED: float = 0.2

@export_range(0., 100., 1., 'or_greater') var max_initiative: float = 100.0:
	set(v):
		max_initiative = v
		_update_progress()

@export_range(0., 100., 1., 'or_greater', 'prefer_slider') var initiative: float = 0.0:
	set(v):
		initiative = v
		_update_progress()

## True from the moment the clock crosses its cap until the turn starts. Drives
## the fill tint and makes the bar hold full (ignoring `current` carry-reset).
@export var active: bool = false:
	set(v):
		if active == v:
			return
		active = v
		_update_fill_color()

@onready var progress_bar: ProgressBar = %ProgressBar

var _tween: Tween
## Live fill stylebox override — mutated to retint the fill (the `fill` theme
## entry is a StyleBox, so there's no `theme_override_styles/fill/bg_color`
## property path to poke directly).
var _fill_style: StyleBoxFlat


func _ready() -> void:
	_init_fill_style()
	_update_progress()
	_update_fill_color()


func _init_fill_style() -> void:
	if progress_bar == null:
		return
	var existing := progress_bar.get_theme_stylebox("fill")
	_fill_style = existing.duplicate() if existing is StyleBoxFlat else StyleBoxFlat.new()
	progress_bar.add_theme_stylebox_override("fill", _fill_style)


func _update_fill_color() -> void:
	if _fill_style != null:
		_fill_style.bg_color = ACTIVE_TINT if active else INACTIVE_TINT


func _update_progress() -> void:
	if progress_bar:
		progress_bar.max_value = max_initiative
		progress_bar.value = initiative


# --- Bound by UIRoot.compose -------------------------------------------------

## initiative pool's `current_changed`. Animate the climb — but while the entity
## is ready/acting we hold the bar full (the carry-reset would otherwise yank it
## back to ~0).
func _on_initiative_changed(new_value: float) -> void:
	if active:
		return
	_tween_initiative(new_value)


## initiative pool's `replenished` (clock crossed its cap). Latch ready and hold
## the bar full regardless of the carry-reset that follows in the same frame.
func _on_ready() -> void:
	active = true
	_tween_initiative(max_initiative)


## TurnManager.turn_started for this bar's entity. Spend the readiness: clear the
## ACTIVE tint and drain to the live (carried) value, from which it climbs again.
func _on_owner_turn_started(current_value: float) -> void:
	active = false
	_tween_initiative(current_value)


func _tween_initiative(to: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, 'initiative', to, ANIMATION_SPEED)
