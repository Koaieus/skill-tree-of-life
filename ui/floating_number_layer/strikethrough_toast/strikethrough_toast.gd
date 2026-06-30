extends FloaterToast
# No class_name — avoids global_script_class_cache rebuild on import
# (see .claude/rules/godot-workflow.md). FloaterToaster casts as FloaterToast;
# FloaterDirector preloads by path. No external reference by name is needed.

## [FloaterToast] variant for removed-modifier events (#82).
##
## Lifecycle on top of the base:
##   1. Fade in at original tint (base handles this).
##   2. Strike: a thin horizontal laser line grows left→right at strike_y_frac
##      height.  Hot-tip leads the sweep; grey text is revealed behind it.
##   3. Unzip (_animate_out): letters cleave along the cut line — top half slides
##      up, bottom half slides down — while the VBox slot collapses normally.
##
## Visual tunables are authored on the scene nodes:
##   $HotTip.color       — leading-tip hot colour
##   $StrikeLine.color   — trail / cool colour
##   $HotTip.size        — tip square size
##   $StrikeLine.size.y  — laser line thickness

@export var strike_duration: float = 0.5
@export_range(0.0, 1.0, 0.01) var strike_y_frac: float = 0.46

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
		_label_grey.label_settings = _label_grey.label_settings.duplicate()
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
	var w: float     = label.size.x
	var h: float     = label.size.y
	var cut_y: float = h * strike_y_frac

	# Read colours and sizes from scene-authored node properties.
	var hot_color:  Color = _hot_tip.color
	var cool_color: Color = _strike_line.color
	var line_h: float     = _strike_line.size.y
	var tip_h: float      = _hot_tip.size.y

	_grey_clip.size  = Vector2(0.0, h)
	_label_grey.size = Vector2(w,   h)

	_strike_line.position = Vector2(0.0, cut_y - line_h * 0.5)
	_strike_line.size.x   = 0.0
	_strike_line.visible  = true

	_hot_tip.position = Vector2(0.0, cut_y - tip_h * 0.5)
	_hot_tip.visible  = true

	var t := create_tween().set_parallel(true)
	t.tween_property(_grey_clip,   "size:x",     w, strike_duration)
	t.tween_property(_strike_line, "size:x",     w, strike_duration)
	t.tween_property(_hot_tip,     "position:x", w, strike_duration)
	t.tween_method(
		func(v: float) -> void: _hot_tip.color = hot_color.lerp(cool_color, v),
		0.0, 1.0, strike_duration)
	t.tween_callback(_hot_tip.hide).set_delay(strike_duration)


func _animate_out() -> void:
	var snap_pos := label.global_position
	var w: float     = label.size.x
	var h: float     = label.size.y
	var cut_y: float = h * strike_y_frac

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
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration * 0.4)
	tween.tween_property(top_clip, "position:y", top_clip.position.y - cut_y - 10.0,       fade_out_duration)
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
