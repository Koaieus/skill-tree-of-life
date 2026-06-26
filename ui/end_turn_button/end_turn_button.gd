@tool
class_name EndTurnButton
extends Button

## End-phase / end-turn button. The chevron shader visualises the phase:
## 1 chevron = CONTRACT, 2 = EXPAND, 3 = BATTLE. Phase tint flows from
## cool blue → green-neon → fiery orange. Hover speeds the scroll.
##
## Confirmation: an inline speech-bubble lives as a child node. When unspent
## resources would be forfeit, UIRoot calls [method show_confirm] instead of
## advancing; the bubble pops above the button and clicking it commits.
## Ctrl-clicking the button itself skips the bubble entirely (UIRoot decides;
## we just expose the signals).

const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const ANIMATION_TIME: float = 0.25

## Chevron scroll cadence. Integrated per-frame in script (not as TIME * speed
## in the shader) so a hover-driven bump doesn't jump the pattern hard at
## large TIME — small TIME * Δspeed is fine; a 10-min-old TIME * Δspeed snaps
## visibly. See `_process`.
const _SCROLL_IDLE_SPEED: float = 0.55
const _SCROLL_HOVER_SPEED: float = 1.25

## Canonical phase tints — shared with PhaseIndicator. Keep these two in sync.
const PHASE_TINTS := {
	TurnManager.Phase.CONTRACT: Color(0.55, 0.70, 1.00),
	TurnManager.Phase.EXPAND:   Color(0.45, 1.00, 0.55),
	TurnManager.Phase.BATTLE:   Color(1.00, 0.55, 0.20),
}
const PHASE_HOT_TINTS := {
	TurnManager.Phase.CONTRACT: Color(0.85, 0.95, 1.00),
	TurnManager.Phase.EXPAND:   Color(0.75, 1.00, 0.85),
	TurnManager.Phase.BATTLE:   Color(1.00, 0.85, 0.40),
}
const PHASE_CHEVRONS := {
	TurnManager.Phase.CONTRACT: 1,
	TurnManager.Phase.EXPAND:   2,
	TurnManager.Phase.BATTLE:   3,
}

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
@onready var _bubble: PanelContainer = %ConfirmBubble
@onready var _bubble_warning: Label = %ConfirmBubble/Margin/VBox/Warning


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


## Switch chevron count + tint to match [param phase]. UIRoot is the only
## caller; widgets stay dumb. Falls back to CONTRACT values for an unknown int.
func set_phase(phase: int) -> void:
	var tint: Color = PHASE_TINTS.get(phase, PHASE_TINTS[TurnManager.Phase.CONTRACT])
	var hot: Color = PHASE_HOT_TINTS.get(phase, PHASE_HOT_TINTS[TurnManager.Phase.CONTRACT])
	var count: int = PHASE_CHEVRONS.get(phase, 1)
	_push("tint", tint)
	_push("hot_color", hot)
	_push("chevron_count", count)


func _ready() -> void:
	update_label_text()

	_text_mat.shader = TEXT_SHADER
	label.material = _text_mat
	_materials = [_bg_mat, _text_mat]

	_push("texture_size", size)
	# Seed with CONTRACT — UIRoot will overwrite on the first phase_changed.
	set_phase(TurnManager.Phase.CONTRACT)
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


func hide_confirm() -> void:
	_bubble.visible = false


func is_confirm_open() -> bool:
	return _bubble != null and _bubble.visible


func _on_bubble_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			hide_confirm()
			confirmed.emit()
			get_viewport().set_input_as_handled()
