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
## Timing knobs are @export on this node: strike_duration, strike_y_frac,
## plus the inherited visible_duration / fade_in_duration / fade_out_duration.

@export var strike_duration: float = 0.2
@export_range(0.0, 1.0, 0.01) var strike_y_frac: float = 0.47

@onready var _svc:           SubViewportContainer = $SubViewportContainer
@onready var _content_label: Label = $SubViewportContainer/SubViewport/ContentLabel

var _mat: ShaderMaterial


func _ready() -> void:
	label.hide()
	# Own copy of the material — sub-resources are shared across scene instances
	# by default; parallel toasts must not share uniform state.
	_svc.material = _svc.material.duplicate()
	_mat = _svc.material as ShaderMaterial
	_mat.set_shader_parameter("split_y", strike_y_frac)


func set_content(text: String, color: Color) -> void:
	super.set_content(text, color)
	_content_label.text = text
	# Duplicate before writing (same shared-resource reason as the base class).
	if _content_label.label_settings != null:
		_content_label.label_settings            = _content_label.label_settings.duplicate()
		_content_label.label_settings.font_color = color
	else:
		_content_label.add_theme_color_override("font_color", color)


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
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration)
	# UV displacement opens the gap at the cut; fade removes the SVC afterward.
	tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("split_open", v),
		0.0, 1.0, fade_out_duration)
	tween.tween_property(_svc, "modulate:a", 0.0, fade_out_duration * 0.6) \
		.set_delay(fade_out_duration * 0.4)
	tween.tween_callback(queue_free).set_delay(fade_out_duration)
