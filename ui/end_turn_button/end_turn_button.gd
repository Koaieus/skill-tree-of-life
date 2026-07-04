@tool
class_name EndTurnButton
extends Button

## End-turn button. A scrolling chevron shader gives it life; hover speeds the
## scroll. (Phases are gone, so the chevron count + tint are fixed — the button
## just ends the single-phase turn.)
##
## Confirmation: an inline speech-bubble lives as a child node. When the player
## would waste action points, the owning cluster ([ActionCluster] in HudRoot)
## calls [method show_confirm] instead of ending; the bubble pops above the
## button and clicking it commits. Ctrl-clicking the button itself skips the
## bubble entirely (the owning cluster decides; we just expose the signals).

const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const ANIMATION_TIME: float = 0.25

## Chevron scroll cadence. Integrated per-frame in script (not as TIME * speed
## in the shader) so a hover-driven bump doesn't jump the pattern hard at
## large TIME — small TIME * Δspeed is fine; a 10-min-old TIME * Δspeed snaps
## visibly. See `_process`.
const _SCROLL_IDLE_SPEED: float = 0.55
const _SCROLL_HOVER_SPEED: float = 1.25

## Fixed button look (no more per-phase tinting).
const _TINT := Color(1.0, 0.851, 0.4, 1.0)
const _DARK_TINT := Color(0.278, 0.239, 0.114, 1.0) # Color(1.00, 0.55, 0.20)
const _HOT_TINT := Color(1.0, 0.549, 0.2, 1.0) #Color(1.00, 0.85, 0.40)
const _CHEVRON_COUNT := 1

## Emitted when the user clicks the confirmation bubble.
signal confirmed

var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []

var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween

var _scroll_offset: float = 0.0

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var _bg_mat: ShaderMaterial = color_rect.material as ShaderMaterial
@onready var _bubble: GlassPanel = %ConfirmBubble
@onready var _bubble_warning: Label = %ConfirmBubble/Margin/VBox/Warning
## One-shot auto-dismiss for the confirm bubble (#90). Restarted on every
## show_confirm, stopped on hide. Scene-authored (%ConfirmTimer) + its timeout /
## the button's focus_exited both wire to hide_confirm in the .tscn.
@onready var _confirm_timer: Timer = %ConfirmTimer


var hovered: float = 0.0:
	set(value):
		hovered = value
		_push("glow_strength", value)

var active: float = 0.0:
	set(value):
		active = value
		_push("active_strength", value)

var _disabled: float = 0.0:
	set(value):
		_disabled = value
		_push("disabled_strength", value)


var enabled: bool = true: set = set_enabled


func set_enabled(value: bool) -> void:
	enabled = value
	disabled = not value
	_tween_disabled(float(not value))
	_tween_active(1.0 if value else 0.0)
	if not value:
		hide_confirm()


func _ready() -> void:
	update_label_text()

	_text_mat.shader = TEXT_SHADER
	label.material = _text_mat
	_materials = [_bg_mat, _text_mat]

	_push("texture_size", size)
	_push("tint", _TINT)
	_push("dark_tint", _DARK_TINT)
	_push("hot_color", _HOT_TINT)
	_push("chevron_count", _CHEVRON_COUNT)
	enabled = not disabled

	_bubble.visible = false
	_bubble.gui_input.connect(_on_bubble_gui_input)


func _push(param: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)


func update_label_text() -> void:
	if not label: return
	if label.text != text:
		label.text = text


func _process(delta: float) -> void:
	_push("mouse_uv", get_local_mouse_position() / size)
	# Frame-integrated scroll. `active` is the "is anything happening" gate
	# (disabled buttons freeze); `hovered` smoothly mixes in the hover boost.
	var current_speed: float = active * lerp(_SCROLL_IDLE_SPEED, _SCROLL_HOVER_SPEED, hovered)
	_scroll_offset += delta * current_speed
	_push("scroll_offset", _scroll_offset)
	update_label_text()


func _tween_hover(to: float) -> void:
	if _hover_tweener: _hover_tweener.kill()
	_hover_tweener = create_tween()
	_hover_tweener.tween_property(self, "hovered", to, ANIMATION_TIME)


func _tween_active(to: float) -> void:
	if _active_tweener: _active_tweener.kill()
	_active_tweener = create_tween()
	_active_tweener.tween_property(self, "active", to, ANIMATION_TIME)


func _tween_disabled(to: float) -> void:
	if _disabled_tweener: _disabled_tweener.kill()
	_disabled_tweener = create_tween()
	_disabled_tweener.tween_property(self, "_disabled", to, ANIMATION_TIME)


func _on_mouse_entered() -> void:
	_tween_hover(1.0)


func _on_mouse_exited() -> void:
	_tween_hover(0.0)


func _on_resized() -> void:
	_push("texture_size", size)


# ── Confirm bubble ──────────────────────────────────────────────────────────

func show_confirm(warning_text: String) -> void:
	_bubble_warning.text = warning_text
	_bubble.visible = true
	_confirm_timer.start()  # restart the countdown on every (re-)show


func hide_confirm() -> void:
	_bubble.visible = false
	if _confirm_timer:
		_confirm_timer.stop()


func is_confirm_open() -> bool:
	return _bubble != null and _bubble.visible


func _on_bubble_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			hide_confirm()
			confirmed.emit()
			get_viewport().set_input_as_handled()
