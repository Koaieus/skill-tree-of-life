extends FloaterToast
# No class_name — avoids global_script_class_cache rebuild on import
# (see .claude/rules/godot-workflow.md). FloaterToaster casts as FloaterToast;
# FloaterDirector preloads by path. No external reference by name is needed.

## [FloaterToast] variant for removed-modifier events (#82).
##
## Lifecycle on top of the base:
##   1. Fade in at original tint (base handles this).
##   2. Strike phase: a hot-coloured tip sweeps left → right, revealing a grey
##      duplicate of the label, so text progressively desaturates from left.
##   3. Unzip (_animate_out override): text cleves at the strike line; top half
##      slides up, bottom half slides down while the VBox slot collapses normally.

const _STRIKE_DURATION := 0.5
const _HOT_COLOR  := Color(1.0, 0.65, 0.1, 1.0)
const _COOL_COLOR := Color(0.55, 0.55, 0.55, 1.0)

@onready var _grey_clip:  Control = $GreyClip
@onready var _label_grey: Label   = $GreyClip/LabelGrey
@onready var _hot_tip:    ColorRect = $HotTip

var _label_text:       String = ""
var _label_grey_color: Color  = Color.GRAY


func set_content(text: String, color: Color) -> void:
	super.set_content(text, color)
	_label_text = text
	_label_grey.text = text
	# Luminance-correct greyscale of the original tint.
	var lum: float = color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	_label_grey_color = Color(lum, lum, lum, 1.0)
	if _label_grey.label_settings != null:
		_label_grey.label_settings.font_color = _label_grey_color
	else:
		_label_grey.add_theme_color_override("font_color", _label_grey_color)


func animate() -> void:
	super.animate()
	_schedule_strike()


func _schedule_strike() -> void:
	var t := create_tween()
	t.tween_interval(fade_in_duration)
	t.tween_callback(_run_strike)


func _run_strike() -> void:
	if not is_inside_tree():
		return
	var w: float = label.size.x
	var h: float = label.size.y
	_grey_clip.size    = Vector2(0.0, h)
	_label_grey.size   = Vector2(w,   h)
	_hot_tip.size      = Vector2(5.0, h)
	_hot_tip.color     = _HOT_COLOR
	_hot_tip.position  = Vector2.ZERO
	_hot_tip.visible   = true

	var t := create_tween().set_parallel(true)
	t.tween_property(_grey_clip, "size:x",    w, _STRIKE_DURATION)
	t.tween_property(_hot_tip,   "position:x", w, _STRIKE_DURATION)
	t.tween_method(
		func(v: float) -> void: _hot_tip.color = _HOT_COLOR.lerp(_COOL_COLOR, v),
		0.0, 1.0, _STRIKE_DURATION)
	t.tween_callback(_hot_tip.hide).set_delay(_STRIKE_DURATION)


func _animate_out() -> void:
	var snap_pos := label.global_position
	var w: float  = label.size.x
	var h: float  = label.size.y
	var half: float = h * 0.5

	# Build two clipping halves that together mirror the struck label.
	# Added to the Toaster (Node2D grandparent) with top_level=true so they
	# render in world space, unaffected by the VBox layout and by the Toaster's
	# per-frame position tracking.
	var toaster: Node = get_parent().get_parent()
	var top_clip := _make_half_clip(w, h, 0.0,  half)
	var bot_clip := _make_half_clip(w, h, half, half)
	top_clip.top_level = true
	bot_clip.top_level = true
	toaster.add_child(top_clip)
	toaster.add_child(bot_clip)
	top_clip.global_position = snap_pos
	bot_clip.global_position = Vector2(snap_pos.x, snap_pos.y + half)

	modulate.a = 0.0  # hand visibility over to the clips

	var tween := create_tween().set_parallel(true)
	# Collapse the VBox slot so remaining toasts rearrange.
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration * 0.4)
	# Ninja cut: top slides up, bottom slides down.
	var slide: float = half + 10.0
	tween.tween_property(top_clip, "position:y", top_clip.position.y - slide, fade_out_duration)
	tween.tween_property(bot_clip, "position:y", bot_clip.position.y + slide, fade_out_duration)
	tween.tween_property(top_clip, "modulate:a", 0.0, fade_out_duration * 0.6)
	tween.tween_property(bot_clip, "modulate:a", 0.0, fade_out_duration * 0.6)
	tween.tween_callback(func() -> void:
		top_clip.queue_free()
		bot_clip.queue_free()
		queue_free()
	).set_delay(fade_out_duration)


## Returns a Control that clips its label child to a horizontal band of the
## struck text.  [param y_into_label] is the top of the band in the original
## label's local Y space; [param clip_h] is the band height.
func _make_half_clip(label_w: float, label_h: float,
		y_into_label: float, clip_h: float) -> Control:
	var clip := Control.new()
	clip.size = Vector2(label_w, clip_h)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text                   = _label_text
	lbl.position               = Vector2(0.0, -y_into_label)
	lbl.size                   = Vector2(label_w, label_h)
	lbl.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	# Share the label_settings resource (read-only use — font_size, outline).
	if label.label_settings != null:
		lbl.label_settings = label.label_settings
	# Use the grey colour computed at set_content time.
	if lbl.label_settings != null:
		lbl.label_settings = lbl.label_settings.duplicate()
		lbl.label_settings.font_color = _label_grey_color
	else:
		lbl.add_theme_color_override("font_color", _label_grey_color)
	clip.add_child(lbl)
	return clip
