@tool
class_name AttackModeButton
extends Button

const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const ANIMATION_TIME: float = 0.2

## Inline glyph edge length, px. Sized to sit beside the 30px label without
## out-shouting it.
const ICON_SIZE := Vector2(24, 24)

## Which attribute's identity colour each attack-mode tab borrows (#465,
## decision 6). Per `.claude/rules/ui-palette.md` [member StatDef.tint_color] is
## the single source of truth for attribute colours — `attack_mode_bar.tscn`
## used to restate all three as inline literals, a duplicate the rule names
## explicitly. Same read [constant AttackPlanArmedMode._MODE_STAT_ID] already
## does, so the tab, the viewport glow and the cursor badge share one value.
##
## The Manage tab is deliberately absent: it has no attribute behind it, so its
## authored `tint` stands.
const _MODE_STAT_ID := {
	BattleSystem.AttackMode.MELEE: &"strength",
	BattleSystem.AttackMode.RANGED: &"dexterity",
	BattleSystem.AttackMode.MAGIC: &"intelligence",
}

@export_color_no_alpha var tint: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var glow_radius: float = 0.3

@export var attack_mode: BattleSystem.AttackMode

## The tab's glyph (#465), shown in TWO registers off ONE authored texture so
## they can never disagree:
##
## - inline at [constant ICON_SIZE] left of the label — the LEGIBLE channel a
##   new player reads. It shares the Label's [member _text_mat], so it is
##   alpha-driven and lights with the text for free (off-white at rest, ramping
##   to [member tint] on hover/active, desaturating when disabled). Its baked
##   cyan RGB is discarded, which is exactly the requested "text coloured".
## - as the background shader's large, faint `watermark` — ATMOSPHERE, and the
##   surface the existing hover ripple washes across. Kept well below the text
##   and rim layers: it must never compete with the label sitting on top of it.
@export var mode_icon: Texture2D:
	set(v):
		mode_icon = v
		_apply_icon()

## Keyboard shortcut chip text shown in the tab's top-left corner (e.g.
## "1", "Q") — purely cosmetic, doesn't drive the actual [member shortcut].
@export var key_hint: String = "":
	set(v):
		key_hint = v
		if _key_label != null:
			_key_label.text = v

var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []


var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = %Label
@onready var _bg_mat: ShaderMaterial = color_rect.material as ShaderMaterial
@onready var _key_chip: PanelContainer = %KeyChip
@onready var _key_label: Label = %KeyChip/KeyLabel
@onready var _icon: TextureRect = %Icon


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

## Sole write-path for the button's enabled state. Mirrors to the engine's
## native `disabled` and runs the visual tween. Use `btn.enabled = X` at call
## sites — direct `disabled = X` writes would bypass the tween (engine writes
## to the native property can't be intercepted from GDScript).
var enabled: bool = true: set = set_enabled

func set_enabled(value: bool) -> void:
	enabled = value
	disabled = not value
	_tween_disabled(float(not value))

func _ready() -> void:
	update_label_text()

	_text_mat.shader = TEXT_SHADER
	label.material = _text_mat
	# The icon rides the SAME material INSTANCE as the label rather than a
	# parallel one: the text shader reads only `glyph.a` and colours the mask
	# itself, and our icons are flat single-colour PNGs with alpha, so sharing
	# it makes the glyph track the label's hover / active / disabled ramp with
	# no second state machine to keep in sync.
	_icon.material = _text_mat
	_icon.custom_minimum_size = ICON_SIZE
	_materials = [_bg_mat, _text_mat]

	_resolve_tint()
	_apply_icon()
	_push("tint", tint)
	_push("glow_radius", glow_radius)
	_push("texture_size", size)
	enabled = not disabled    # snap GDScript var to .tscn-set Button.disabled

	if _key_chip != null:
		var sb: StyleBoxFlat = _key_chip.get_theme_stylebox(&"panel").duplicate()
		sb.border_color = tint
		_key_chip.add_theme_stylebox_override(&"panel", sb)
	if _key_label != null:
		_key_label.modulate = tint
		_key_label.text = key_hint

## Pull the attribute tint for this tab off [StatRegistry] (decision 6). A tab
## with no attack mode behind it — Manage — keeps whatever the scene authored.
func _resolve_tint() -> void:
	var stat_id: StringName = _MODE_STAT_ID.get(attack_mode, &"")
	if stat_id == &"":
		return
	var def := StatRegistry.get_def(stat_id)
	if def != null:
		tint = def.tint_color


func _apply_icon() -> void:
	if _icon != null:
		_icon.texture = mode_icon
		_icon.visible = mode_icon != null
	# A no-op before _ready (`_materials` is empty) — _ready re-runs it.
	_push("watermark", mode_icon)
	_push("has_watermark", 1.0 if mode_icon != null else 0.0)


func _push(param: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)


func override_toggle(is_on: bool) -> void:
	active = is_on
	set_pressed_no_signal(is_on)

func update_label_text() -> void:
	if not label: return
	if label.text != text:
		label.text = text
		
	
func _process(_delta: float) -> void:
	_push("mouse_uv", get_local_mouse_position() / size)

func _tween_disabled(to: float) -> void:
	if _disabled_tweener: _disabled_tweener.kill()
	_disabled_tweener = create_tween()
	_disabled_tweener.tween_property(self, "_disabled", to, ANIMATION_TIME)

func _tween_hover(to: float) -> void:
	if _hover_tweener: _hover_tweener.kill()
	_hover_tweener = create_tween()
	_hover_tweener.tween_property(self, "hovered", to, ANIMATION_TIME)

func _tween_active(to: float) -> void:
	if _active_tweener: _active_tweener.kill()
	_active_tweener = create_tween()
	_active_tweener.tween_property(self, "active", to, ANIMATION_TIME)

func _on_mouse_entered() -> void:
	_tween_hover(1.0)

func _on_mouse_exited() -> void:
	_tween_hover(0.0)

func _on_toggled(toggled_on: bool) -> void:
	_tween_active(float(toggled_on))

func _on_resized() -> void:
	_push("texture_size", size)
