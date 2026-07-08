@tool
class_name Banner
extends Control

## A single animated banner band — full-viewport-width Control with two
## independent moving parts:
##   * a backdrop ([code]$Bg[/code]) that spans the full screen width and
##     animates vertically (expands from the band's horizontal midline up +
##     down on intro, collapses back the same way on outro — old-TV-turn-on
##     feel);
##   * a text label ([code]$Label[/code]) that slides horizontally on top
##     (main: L → drift → R; sub mirrors).
##
## The widget is purely view: it doesn't know about events, queues, or
## styles beyond translating a request into a tween. The owner ([TitleBand])
## feeds it [AnnouncementRequest]s and listens for [signal finished].
##
## [b]@tool[/b] — the [Banner] scene runs in the editor so designers can
## tweak layout / styling with live visual feedback. Hit the
## [code]Preview[/code] inspector button to play a one-shot animation
## against the current scene.

signal finished

const BG_OPEN_TIME: float = 0.22
const BG_CLOSE_TIME: float = 0.22
const SLIDE_IN_TIME: float = 0.30
const HOLD_TIME: float = 1.20
const SLIDE_OUT_TIME: float = 0.30
const DRIFT_OFFSET: float = 60.0  # px past center on entry side, drifts back to 0
const BADGE_STAMP_TIME: float = 0.18

## Mirrors animation direction (R → L instead of L → R) and selects the
## sub-band font/height. Set on the scene instance, not at runtime.
@export var is_sub: bool = false
@export var main_font_size: int = 96
@export var sub_font_size: int = 48
@export var main_height: int = 140
@export var sub_height: int = 80

## Inspector button: plays a one-shot preview animation in the editor.
@export_tool_button("Preview") var _preview_button: Callable = _preview

@onready var _bg: Panel = $Bg
@onready var _label: Label = $Label
@onready var _count_badge: Label = $Label/CountBadge

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, _band_height())
	_apply_font_size()
	_collapse_bg()
	_bg.visible = false
	_label.visible = false
	_count_badge.visible = false


func play(request: AnnouncementRequest) -> void:
	if not is_node_ready():
		await ready
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = request.main_text if not is_sub else request.sub_text
	_apply_style(request.style)
	_size_label()
	_prepare_count_badge(request.stack_count)

	var w := size.x
	var entry_x := -_label.size.x if not is_sub else w
	var exit_x := w if not is_sub else -_label.size.x
	var hold_x := (w - _label.size.x) * 0.5 + (DRIFT_OFFSET if not is_sub else -DRIFT_OFFSET)
	var drift_x := (w - _label.size.x) * 0.5

	_collapse_bg()
	_bg.visible = true
	_label.position.x = entry_x
	_label.visible = true

	_tween = create_tween()
	# Phase 1: bg opens from 0 to full height (no text yet — clean reveal).
	_tween.tween_method(_set_bg_open, 0.0, 1.0, BG_OPEN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Phase 2-4: text slides in, drifts, slides out (bg stays open).
	_tween.tween_property(_label, "position:x", hold_x, SLIDE_IN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Stamp the ×N badge in right as the slide-in settles into the hold.
	_tween.tween_callback(_stamp_badge)
	_tween.tween_property(_label, "position:x", drift_x, HOLD_TIME).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(_label, "position:x", exit_x, SLIDE_OUT_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	# Phase 5: text is gone — bg collapses back to a line, then hides.
	_tween.tween_callback(func() -> void: _label.visible = false)
	_tween.tween_method(_set_bg_open, 1.0, 0.0, BG_CLOSE_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_done)


## Editor preview entry point — wired to the inspector tool button. Plays a
## representative banner so designers see live changes (font, color, timing).
func _preview() -> void:
	var sample := AnnouncementRequest.make(
			"MAIN SAMPLE", "SUB SAMPLE", AnnouncementRequest.Style.DEFAULT)
	sample.stack_count = 3
	play(sample)


func _band_height() -> int:
	return sub_height if is_sub else main_height


func _apply_font_size() -> void:
	_label.add_theme_font_size_override(
			"font_size", sub_font_size if is_sub else main_font_size)


## Size the label to fit its text within the band height. The label is
## positioned manually (slide animation), so this is just its bounding box.
func _size_label() -> void:
	var font := _label.get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var fs := sub_font_size if is_sub else main_font_size
	var text_w := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var h := _band_height()
	# Pad horizontally so the slide-in/out distance reads as the text moving
	# past, rather than getting clipped at the band edge.
	_label.size = Vector2(text_w + 40.0, h)
	_label.position.y = 0.0


## Only the main band stamps a count badge — the sub line already carries
## the merged data (e.g. "+3 Skill Points — Level 8") via
## AnnouncementRequest.absorb(), so a second badge there would be redundant.
func _prepare_count_badge(stack_count: int) -> void:
	if is_sub or stack_count <= 1:
		_count_badge.visible = false
		return
	_count_badge.text = "×%d" % stack_count
	_count_badge.visible = true
	_count_badge.scale = Vector2.ZERO
	_count_badge.rotation_degrees = 0.0
	_count_badge.pivot_offset = _count_badge.size * 0.5
	# Anchor near the trailing (right) edge of the label's text box, at the
	# vertical midline — "stamped on" near the end of the main text.
	_count_badge.position = Vector2(_label.size.x, _label.size.y * 0.5) - _count_badge.size * 0.5


## One-shot "stamped on" flourish: scale-overshoot + a tiny rotation snap.
## Not a live-updating counter — the badge text is already final by the time
## this plays (see AnnouncementLayer's deferred-pump coalescing).
func _stamp_badge() -> void:
	if not _count_badge.visible:
		return
	_count_badge.scale = Vector2(1.6, 1.6)
	_count_badge.rotation_degrees = -6.0
	var badge_tween := create_tween()
	badge_tween.set_parallel(true)
	badge_tween.tween_property(_count_badge, "scale", Vector2.ONE, BADGE_STAMP_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	badge_tween.tween_property(_count_badge, "rotation_degrees", 0.0, BADGE_STAMP_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Drive both offset_top and offset_bottom symmetrically from t∈[0,1].
## At t=0 the bg is a zero-height line on the midline; at t=1 it fills
## the band vertically.
func _set_bg_open(t: float) -> void:
	var h := float(_band_height())
	_bg.offset_top = -h * 0.5 * t
	_bg.offset_bottom = h * 0.5 * t


func _collapse_bg() -> void:
	_bg.offset_top = 0.0
	_bg.offset_bottom = 0.0


func _apply_style(style: AnnouncementRequest.Style) -> void:
	var bg_color: Color
	var text_color: Color
	match style:
		AnnouncementRequest.Style.PHASE:
			bg_color = Color(0.06, 0.10, 0.18, 0.78)
			text_color = Color(0.55, 0.95, 1.0)
		AnnouncementRequest.Style.LEVEL_UP:
			bg_color = Color(0.20, 0.14, 0.04, 0.82)
			text_color = Color(1.0, 0.85, 0.30)
		AnnouncementRequest.Style.KILL:
			bg_color = Color(0.18, 0.04, 0.04, 0.82)
			text_color = Color(1.0, 0.45, 0.35)
		AnnouncementRequest.Style.DEATH:
			bg_color = Color(0.04, 0.02, 0.02, 0.92)
			text_color = Color(0.75, 0.20, 0.20)
		_:
			bg_color = Color(0.05, 0.05, 0.08, 0.78)
			text_color = Color(0.95, 0.85, 1.0) if is_sub else Color(1.0, 0.95, 0.85)

	# Full-bleed bar: no rounded corners (they'd hit the viewport edges and
	# look weird); no content margins (the Label is a sibling, not a child).
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	_bg.add_theme_stylebox_override("panel", sb)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _on_done() -> void:
	_bg.visible = false
	finished.emit()


func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()
