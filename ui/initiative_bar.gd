@tool
class_name InitiativeBar
extends Control

## Player's turn-order clock. Tracks the `initiative` PoolStat: the bar fills as
## the clock climbs toward its cap (the action threshold) between turns and flips
## to the ACTIVE tint + holds full once the entity is ready to act.
##
## On the player's turn the whole panel animates OUT of view (a teensy dip south,
## then north off-screen) — full at the time. When the turn ends it animates back
## IN (roughly empty by then, the cyclic pool having carried the overshoot off).
##
## Readiness drives the "full" visual, NOT the raw `current` value — the cyclic
## pool carries overshoot forward, so `current` snaps back near zero the instant
## the clock crosses the cap. We'd flicker if we followed `current` there, so
## `_on_ready` holds the bar full until the turn ends and it re-enters empty.

const ACTIVE_TINT: Color = Color(1.0, 0.8, 0.4, 1.0)
const INACTIVE_TINT: Color = Color(0.51, 0.301, 0.117, 1.0)
const PROGRESS_ANIMATION_SPEED: float = 0.2
const PANEL_ANIMATION_SPEED: float = 0.35
## Small downward anticipation dip before the panel launches north on exit.
const PANEL_DIP: float = 8.0
## Extra clearance past the panel's own height so it parks fully off-screen.
const PANEL_OUT_MARGIN: float = 40.0


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
@onready var panel: GlassPanel = %GlassPanel

var _tween: Tween
var _panel_tween: Tween
## Resting Y of the panel, captured lazily on the first exit (when it's settled
## at its layout position). The slide animates relative to this.
var _panel_rest_y: float = 0.0
var _panel_rest_captured: bool = false
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


## TurnManager.turn_started for this bar's entity. The bar is full + ACTIVE; slide
## the whole panel out of view (the value stays put — it re-enters empty later).
func _on_owner_turn_started(_current_value: float) -> void:
	_play_exit()


## TurnManager.turn_ended for this bar's entity. The pool has carried its overshoot
## off, so snap the bar to the live (near-empty) value, drop the ACTIVE tint, and
## slide the panel back in — from which it climbs again over the coming ticks.
func _on_owner_turn_ended(current_value: float) -> void:
	active = false
	initiative = current_value  # instant: the panel is off-screen, no climb to show
	_play_enter()


func _tween_initiative(to: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, 'initiative', to, PROGRESS_ANIMATION_SPEED)


# --- Panel slide (out on the player's turn, back in when it ends) ------------

func _capture_panel_rest() -> void:
	if not _panel_rest_captured and panel != null:
		_panel_rest_y = panel.position.y
		_panel_rest_captured = true


## Y that parks the panel fully above the top edge.
func _panel_out_y() -> float:
	return _panel_rest_y - panel.size.y - PANEL_OUT_MARGIN


## Dip south a teensy bit (anticipation), then accelerate north out of view.
func _play_exit() -> void:
	if panel == null:
		return
	_capture_panel_rest()
	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.tween_property(panel, "position:y", _panel_rest_y + PANEL_DIP,
			PANEL_ANIMATION_SPEED * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(panel, "position:y", _panel_out_y(),
			PANEL_ANIMATION_SPEED).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Drop in from above with a soft settle.
func _play_enter() -> void:
	if panel == null:
		return
	_capture_panel_rest()
	if _panel_tween:
		_panel_tween.kill()
	panel.position.y = _panel_out_y()  # ensure we start off-screen
	_panel_tween = create_tween()
	_panel_tween.tween_property(panel, "position:y", _panel_rest_y,
			PANEL_ANIMATION_SPEED).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
