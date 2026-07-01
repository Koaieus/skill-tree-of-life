extends FloaterToast
# No class_name — avoids global_script_class_cache rebuild on import.

## Shader-driven strikethrough toast for removed-modifier events (#82).
##
## A SubViewportContainer renders the label; its canvas_item ShaderMaterial owns
## every visual: simultaneous greyscale, hot-tip sweep, strike line drawn through
## transparent glyph gaps, and UV-displacement unzip.  This class only drives
## the shader uniforms via tweens — no clip nodes, no coordinate math.
##
## Scene-tunable knobs live on the ShaderMaterial (inspector: SubViewportContainer
## → Material): hot_color, line_color, tip_radius, line_half_thick.
## Timing knobs are @export on this node: strike_duration,
## plus the inherited visible_duration / fade_in_duration / fade_out_duration.
## The diagonal cut position is computed from font metrics in _ready() and is
## not scene-authorable — it tracks the actual x-height of whatever font is used.

@export var strike_duration: float = 0.2

var _mat: ShaderMaterial


func _ready() -> void:
	# Own copy of the material — sub-resources are shared across scene instances
	# by default; parallel toasts must not share uniform state. -- done via scene resource setting
	_mat = label.material as ShaderMaterial
	#_apply_diagonal_from_font()

func _process(delta: float) -> void:
	if not label: return
	# TODO: do this in a `label_size` setter and on ready instead of every frame
	var label_size := label.size
	if label_size != _mat.get_shader_parameter('label_size'): 
		_mat.set_shader_parameter('label_size', label_size)

#func _apply_diagonal_from_font() -> void:
	#var font := label.get_theme_font("font")
	#var fsize := float(
		#label.label_settings.font_size if label.label_settings else 32)
	#var vp_h := float((_svc.get_child(0) as SubViewport).size.y)  # 32 from scene
	#var ascent := font.get_ascent(ceil(fsize))
	#var total_h := font.get_height(ceil(fsize))
	## Baseline y in the SubViewport (text is vertically centred inside it).
	#var baseline_px := (vp_h - total_h) * 0.5 + ascent
	## Typographic strikethrough: ~30 % of ascent above the baseline.
	## This sits in the x-height zone and misses all ascender dots.
	#var center_px := baseline_px - ascent * 0.30
	#var center_uv := clampf(center_px / vp_h, 0.1, 0.9)
	## Slope from the StrikeThroughBox geometry: the box fills the FloaterToast
	## Label which is ~45 px tall and ~275 px wide.  In SubViewport UV space
	## (220×32) that maps to dy/dx ≈ 1.13 — a corner-to-corner slash.
	## Clamp the half-spread so both endpoints stay within [0.01, 0.99].
	#var half := minf(center_uv - 0.01, 0.99 - center_uv)
	#_mat.set_shader_parameter("split_y_start", center_uv + half)
	#_mat.set_shader_parameter("split_y_end",   center_uv - half)


#func set_content(text: String, color: Color) -> void:
	#super.set_content(text, color)
	#_content_label.text = text
	## Duplicate before writing (same shared-resource reason as the base class).
	#if _content_label.label_settings != null:
		#_content_label.label_settings            = _content_label.label_settings.duplicate()
		#_content_label.label_settings.font_color = color
	#else:
		#_content_label.add_theme_color_override("font_color", color)


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
	var t := create_tween().set_parallel(true)
	# gray_amount and strike_x sweep in lockstep so the tip leads the grey wave.
	t.tween_method(func(v: float) -> void: _mat.set_shader_parameter("gray_amount", v),
		0.0, 1.0, strike_duration)
	t.tween_method(func(v: float) -> void: _mat.set_shader_parameter("strike_x", v),
		0.0, 1.0, strike_duration)


func _animate_out() -> void:
	var tween := create_tween().set_parallel(true)
	# Collapse the VBox slot so remaining toasts rearrange.
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration * 0.4).set_delay(0.6)
	# UV displacement opens the gap at the cut; fade removes the SVC afterward.
	tween.tween_method(func(v: float): _mat.set_shader_parameter("split_open", v),
		0.0, 1.0, fade_out_duration)
	tween.tween_property(label, "modulate:a", 0.0, fade_out_duration * 0.6) \
		.set_delay(fade_out_duration * 0.4)
	tween.tween_callback(queue_free).set_delay(fade_out_duration)
