@tool
class_name AnnouncerLayer
extends CanvasLayer

## Full-viewport FX layer (#117): fired on [signal BattleSystem.attack_launched].
## A full-width bar grows from the screen's vertical midline while big Cinzel
## text flies in from the left, settles, nudges back toward center, then
## continues off-screen right — mode-tinted (melee red / ranged green /
## magic = spell color, per `.claude/rules/ui-palette.md`).
##
## Distinct visual register from [BannerLayer]/[Banner] (turn/level/kill
## toasts) — see #117: the growing-bar geometry overlaps on paper but the
## close behavior differs (snap-off, not eased) and the trigger/owner is
## combat launches, not turn/game-state events. Kept as a sibling rather
## than folding into Banner's semantic Style enum, which is intentionally
## visual-agnostic ("LEVEL_UP", not "gold-tinted").

const OPEN_TIME: float = 0.25
const SLIDE_IN_TIME: float = 0.35
const HOLD_TIME: float = 1.5
const SLIDE_OUT_TIME: float = 0.35
const SNAP_CLOSE_TIME: float = 0.15
const DRIFT_OFFSET: float = 70.0

@export var bar_height: float = 134.0
@export var font_size: int = 96

@onready var _bg: Panel = %Bg
@onready var _label: Label = %Text

var _tween: Tween
var _battle_system: BattleSystem

## Inspector button: fire a sample announcement for live editor preview.
@export_tool_button("Preview") var _preview_button: Callable = _preview


func _ready() -> void:
	_label.add_theme_font_size_override("font_size", font_size)
	_collapse_bg()
	_bg.visible = false
	_label.visible = false


func bind(battle_system: BattleSystem) -> void:
	if _battle_system != null and _battle_system.attack_launched.is_connected(_on_attack_launched):
		_battle_system.attack_launched.disconnect(_on_attack_launched)
	_battle_system = battle_system
	if _battle_system != null:
		_battle_system.attack_launched.connect(_on_attack_launched)


func _on_attack_launched(mode: BattleSystem.AttackMode, spell: SpellDef) -> void:
	announce(_mode_text(mode, spell), _mode_color(mode))


func _mode_text(mode: BattleSystem.AttackMode, spell: SpellDef) -> String:
	match mode:
		BattleSystem.AttackMode.MELEE: return "MELEE"
		BattleSystem.AttackMode.RANGED: return "RANGED"
		BattleSystem.AttackMode.MAGIC: return spell.name.to_upper() if spell != null else "MAGIC"
		_: return ""


## STR red / DEX green / INT blue — see .claude/rules/ui-palette.md. Magic
## uses the generic spell/INT blue rather than per-spell color; a per-spell
## tint would need a SpellDef.tint_color field, not added here (YAGNI).
func _mode_color(mode: BattleSystem.AttackMode) -> Color:
	match mode:
		BattleSystem.AttackMode.MELEE: return Color(0.9451, 0.2689, 0.2453, 1)
		BattleSystem.AttackMode.RANGED: return Color(0.3187, 0.7773, 0.4484, 1)
		BattleSystem.AttackMode.MAGIC: return Color(0.291, 0.5892, 1.0, 1)
		_: return Color(0.95, 0.85, 1.0)


## Play the growing-bar + flying-text FX once. Not queued — launches are
## already serialized by BattleSystem.launch_attack's VFX await, so overlap
## can't happen; a queue here would be dead weight (see #117 discussion).
func announce(text: String, color: Color) -> void:
	if not is_node_ready():
		await ready
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = text
	_apply_color(color)
	_size_label()

	var w := _bg.size.x
	var entry_x := -_label.size.x
	var hold_x := (w - _label.size.x) * 0.5 + DRIFT_OFFSET
	var drift_x := (w - _label.size.x) * 0.5
	var exit_x := w

	_collapse_bg()
	_bg.visible = true
	_label.position.x = entry_x
	_label.visible = true

	_tween = create_tween()
	_tween.tween_method(_set_bg_open, 0.0, 1.0, OPEN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "position:x", hold_x, SLIDE_IN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "position:x", drift_x, HOLD_TIME).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(_label, "position:x", exit_x, SLIDE_OUT_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: _label.visible = false)
	# "TV-turnoff" snap: hold at full height then collapse fast, unlike
	# Banner's symmetric eased close.
	_tween.tween_method(_set_bg_open, 1.0, 0.0, SNAP_CLOSE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_done)


func _preview() -> void:
	announce("MELEE", Color(0.9451, 0.2689, 0.2453, 1))


func _set_bg_open(t: float) -> void:
	_bg.offset_top = -bar_height * 0.5 * t
	_bg.offset_bottom = bar_height * 0.5 * t


func _collapse_bg() -> void:
	_bg.offset_top = 0.0
	_bg.offset_bottom = 0.0


func _size_label() -> void:
	var font := _label.get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var text_w := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	_label.size = Vector2(text_w + 40.0, bar_height)
	# Label's anchor_top == anchor_bottom (the midline), so its box spans
	# [midline + offset_top, midline + offset_bottom]. Center it the same way
	# _set_bg_open centers Bg — offset_top = -half, offset_bottom = +half —
	# not offset_top = 0, which pins the top edge to the midline and pushes
	# the whole label (and its CENTER-aligned text) into the bottom half.
	_label.position.y = -bar_height * 0.5


func _apply_color(color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.82)
	_bg.add_theme_stylebox_override("panel", sb)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_constant_override("outline_size", 10)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _on_done() -> void:
	_bg.visible = false
