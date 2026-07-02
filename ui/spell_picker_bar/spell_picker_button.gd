@tool
class_name SpellPickerButton
extends Button

## A single spell pick in [SpellPickerBar]. Toggle button (radio-managed by
## the bar's ButtonGroup) that renders a spell card:
##   * top inset — one tick per [member SpellDef.min_degree]
##   * icon (or letter glyph fallback)
##   * name + mana cost label
##
## Same shader scaffolding as [AttackModeButton] — the bg shader handles
## rounded-rect rendering, mouse-proximity glow, rim, breathing pulse when
## active, and a desaturated/dimmed disabled state; the text shader gives
## the name + letter labels a soft halo + tint blend. State plumbing routes
## hover / pressed (toggle) / disabled into shader strength uniforms via
## tweens so transitions are smooth.
##
## On hover emits [signal Events.spell_hovered] / [signal Events.spell_unhovered]
## so the floating [SpellTooltip] (mounted in UIRoot) shows a formatted scene
## with dynamic-value highlighting instead of a plain-text Godot tooltip.

const BG_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button.gdshader")
const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const TICK_SCENE := preload("res://ui/spell_picker_bar/spell_picker_button_tick.tscn")

const ANIMATION_TIME: float = 0.2
const _LETTER_FONT_SIZE: int = 28

@export_color_no_alpha var tint: Color = Color(0.55, 0.85, 1.0)
@export_range(0.0, 1.0, 0.01) var glow_radius: float = 0.36

@export var spell: SpellDef = null:
	set(value):
		spell = value
		_apply_spell()

@onready var _bg: ColorRect = $Bg
@onready var _ticks: HBoxContainer = %Ticks
@onready var _icon_rect: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _letter_label: Label = %LetterLabel

var _bg_mat := ShaderMaterial.new()
var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []

## The casting entity whose stats may modify spell values shown in the
## floating tooltip. Set externally by [SpellPickerBar.update_gating_context].
var _caster: Entity = null

var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween


var hovered: float = 0.0:
	set(value):
		hovered = value
		_push(&"glow_strength", value)

var active: float = 0.0:
	set(value):
		active = value
		_push(&"active_strength", value)

var _disabled_strength: float = 0.0:
	set(value):
		_disabled_strength = value
		_push(&"disabled_strength", value)


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(96, 96)
	clip_text = true
	_install_materials()
	_push(&"tint", tint)
	_push(&"glow_radius", glow_radius)
	_push(&"texture_size", Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y))))
	# Snap state — Button's pressed/disabled may have been set in the .tscn
	# before we wired the shader.
	hovered = 0.0
	active = 1.0 if button_pressed else 0.0
	_disabled_strength = 1.0 if disabled else 0.0
	_apply_spell()


func _install_materials() -> void:
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BG_SHADER
	_bg.material = _bg_mat
	_text_mat = ShaderMaterial.new()
	_text_mat.shader = TEXT_SHADER
	_name_label.material = _text_mat
	_letter_label.material = _text_mat
	_materials = [_bg_mat, _text_mat]


func _push(param: StringName, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)


## Toggle castability — flips Button.disabled so engine click-gating + the
## shader's disabled fade both engage.
func set_castable(castable: bool) -> void:
	disabled = not castable
	_tween_disabled(0.0 if castable else 1.0)


func refresh() -> void:
	_apply_spell()


func _apply_spell() -> void:
	if not is_node_ready():
		return
	if spell == null:
		_name_label.text = ""
		_icon_rect.texture = null
		_letter_label.text = ""
		if not Engine.is_editor_hint():
			_clear_ticks()
		return
	_name_label.text = "%s (%d)" % [spell.name, spell.mana_cost]
	if spell.icon != null:
		_icon_rect.texture = spell.icon
		_letter_label.visible = false
	else:
		_icon_rect.texture = null
		_letter_label.visible = true
		_letter_label.text = spell.name.substr(0, 1).to_upper() if spell.name != "" else "?"
	_rebuild_ticks(spell.min_degree)


func _clear_ticks() -> void:
	for c in _ticks.get_children():
		c.queue_free()


func _rebuild_ticks(n: int) -> void:
	_clear_ticks()
	for i in maxi(0, n):
		var tick := TICK_SCENE.instantiate() as ColorRect
		_ticks.add_child(tick)


func _tooltip_for(s: SpellDef) -> String:
	var lines: Array[String] = []
	lines.append("%s — %d mana" % [s.name, s.mana_cost])
	lines.append("Requires node degree ≥ %d" % s.min_degree)
	if s.description != "":
		lines.append(s.description)
	if s.propagation != null:
		var prop := s.propagation.get_description()
		if prop != "":
			lines.append(prop)
	return "\n".join(lines)


# --- Shader plumbing -------------------------------------------------------

func _process(_delta: float) -> void:
	if _bg == null:
		return
	_push(&"mouse_uv", get_local_mouse_position() / size)


func _on_resized() -> void:
	_push(&"texture_size", Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y))))


func _on_mouse_entered() -> void:
	_tween_hover(1.0)
	if spell != null:
		Events.spell_hovered.emit(spell, _caster)


func _on_mouse_exited() -> void:
	_tween_hover(0.0)
	Events.spell_unhovered.emit()


func _on_toggled(toggled_on: bool) -> void:
	_tween_active(1.0 if toggled_on else 0.0)


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
	_disabled_tweener.tween_property(self, "_disabled_strength", to, ANIMATION_TIME)
