@tool
class_name CalloutBand
extends AnnouncementBand

## Top-anchored, narrower single-line CALLOUT variant (#117, reworked): big
## Cinzel text flies in from the left, settles, nudges back toward center,
## then continues off-screen right — mode-tinted (melee red / ranged green /
## magic blue, per `.claude/rules/ui-palette.md`). Deliberately kept off the
## screen's vertical midline (unlike [TitleBand]) so it no longer covers the
## action it's announcing.
##
## Close behavior stays a fast "TV-turnoff" snap, distinct from TitleBand's
## symmetric eased close — a styling choice of this variant, not a
## structural difference AnnouncementLayer needs to know about.

const OPEN_TIME: float = 0.25
const SLIDE_IN_TIME: float = 0.35
const HOLD_TIME: float = 1.5
const SLIDE_OUT_TIME: float = 0.35
const SNAP_CLOSE_TIME: float = 0.15
const DRIFT_OFFSET: float = 40.0

@export var bar_height: float = 64.0
@export var font_size: int = 44

@onready var _bg: Panel = %Bg
@onready var _label: Label = %Text

var _tween: Tween

## Inspector button: fire a sample announcement for live editor preview.
@export_tool_button("Preview") var _preview_button: Callable = _preview


func _ready() -> void:
	_label.add_theme_font_size_override("font_size", font_size)
	_collapse_bg()
	_bg.visible = false
	_label.visible = false


func play(request: AnnouncementRequest) -> void:
	if not is_node_ready():
		await ready
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = request.main_text
	_apply_style(request.style)
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
	# TitleBand's symmetric eased close.
	_tween.tween_method(_set_bg_open, 1.0, 0.0, SNAP_CLOSE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_done)


func _preview() -> void:
	play(AnnouncementRequest.make(
			"MELEE", "", AnnouncementRequest.Style.MELEE, AnnouncementRequest.Kind.CALLOUT))


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


## STR red / DEX green / INT blue, read live off StatDef.tint_color via
## StatRegistry — see .claude/rules/ui-palette.md. Magic uses the generic
## spell/INT blue rather than per-spell color; a per-spell tint would need a
## SpellDef.tint_color field, not added here (YAGNI).
func _apply_style(style: AnnouncementRequest.Style) -> void:
	var color: Color
	match style:
		AnnouncementRequest.Style.MELEE: color = StatRegistry.get_def(&"strength").tint_color
		AnnouncementRequest.Style.RANGED: color = StatRegistry.get_def(&"dexterity").tint_color
		AnnouncementRequest.Style.MAGIC: color = StatRegistry.get_def(&"intelligence").tint_color
		_: color = Color(0.95, 0.85, 1.0)

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
	finished.emit()
