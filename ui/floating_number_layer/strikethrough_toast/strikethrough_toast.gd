extends FloaterToast
# No class_name — avoids global_script_class_cache rebuild on import
# (see .claude/rules/godot-workflow.md). FloaterToaster casts as FloaterToast;
# FloaterDirector preloads by path. No external reference by name is needed.

## [FloaterToast] variant for removed-modifier events (#82).
##
## Lifecycle on top of the base:
##   1. Fade in at original tint (base handles this).
##   2. Strike: a thin horizontal laser line grows left→right at _STRIKE_Y_FRAC
##      height.  Hot-tip leads the sweep; grey text is revealed behind it.
##   3. Unzip (_animate_out): letters cleave along the cut line — top half slides
##      up, bottom half slides down — while the VBox slot collapses normally.

const _STRIKE_DURATION := 0.5
const _HOT_COLOR  := Color(1.0, 0.65, 0.1, 1.0)
const _COOL_COLOR := Color(0.55, 0.55, 0.55, 1.0)
## Fractional Y of the laser cut within the label rect (≈ text strikethrough pos).
const _STRIKE_Y_FRAC := 0.46

@onready var _grey_clip:   Control   = $GreyClip
@onready var _label_grey:  Label     = $GreyClip/LabelGrey
@onready var _strike_line: ColorRect = $StrikeLine
@onready var _hot_tip:     ColorRect = $HotTip

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
	var w: float   = label.size.x
	var h: float   = label.size.y
	var cut_y: float = h * _STRIKE_Y_FRAC

	# Grey-text reveal clip: full height, grows left → right behind the laser.
	_grey_clip.size  = Vector2(0.0, h)
	_label_grey.size = Vector2(w,   h)

	# Laser line: 2px horizontal stripe at the cut height.
	_strike_line.position = Vector2(0.0, cut_y - 1.0)
	_strike_line.size     = Vector2(0.0, 2.0)
	_strike_line.color    = _COOL_COLOR
	_strike_line.visible  = true

	# Hot tip: small square leading the sweep.
	_hot_tip.position = Vector2(0.0, cut_y - 2.5)
	_hot_tip.size     = Vector2(5.0, 5.0)
	_hot_tip.color    = _HOT_COLOR
	_hot_tip.visible  = true

	var t := create_tween().set_parallel(true)
	t.tween_property(_grey_clip,   "size:x",      w, _STRIKE_DURATION)
	t.tween_property(_strike_line, "size:x",      w, _STRIKE_DURATION)
	t.tween_property(_hot_tip,     "position:x",  w, _STRIKE_DURATION)
	t.tween_method(
		func(v: float) -> void: _hot_tip.color = _HOT_COLOR.lerp(_COOL_COLOR, v),
		0.0, 1.0, _STRIKE_DURATION)
	t.tween_callback(_hot_tip.hide).set_delay(_STRIKE_DURATION)


func _animate_out() -> void:
	var snap_pos := label.global_position
	var w: float   = label.size.x
	var h: float   = label.size.y
	# Split exactly where the laser was so letters cleave along the cut.
	var cut_y: float = h * _STRIKE_Y_FRAC

	# Build two clipping halves that together mirror the struck label.
	# Added to the Toaster (Node2D grandparent) with top_level=true so they
	# render in world space, unaffected by VBox layout and Toaster tracking.
	var toaster: Node  = get_parent().get_parent()
	var top_clip := _make_half_clip(w, h, 0.0,   cut_y)
	var bot_clip := _make_half_clip(w, h, cut_y, h - cut_y)
	top_clip.top_level = true
	bot_clip.top_level = true
	toaster.add_child(top_clip)
	toaster.add_child(bot_clip)
	top_clip.global_position = snap_pos
	bot_clip.global_position = Vector2(snap_pos.x, snap_pos.y + cut_y)

	modulate.a = 0.0  # hand visibility over to the clips

	var tween := create_tween().set_parallel(true)
	# Collapse the VBox slot so remaining toasts rearrange.
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration * 0.4)
	# Ninja cut: top slides up, bottom slides down.
	tween.tween_property(top_clip, "position:y", top_clip.position.y - cut_y - 10.0, fade_out_duration)
	tween.tween_property(bot_clip, "position:y", bot_clip.position.y + (h - cut_y) + 10.0, fade_out_duration)
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
	lbl.text                 = _label_text
	lbl.position             = Vector2(0.0, -y_into_label)
	lbl.size                 = Vector2(label_w, label_h)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Duplicate label_settings before writing font_color so the original Label
	# is unaffected (they would otherwise share the same resource object).
	if label.label_settings != null:
		lbl.label_settings            = label.label_settings.duplicate()
		lbl.label_settings.font_color = _label_grey_color
	else:
		lbl.add_theme_color_override("font_color", _label_grey_color)
	clip.add_child(lbl)
	return clip
