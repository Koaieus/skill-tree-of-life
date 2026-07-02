extends FloaterToast
# No class_name — avoids global_script_class_cache rebuild on import.

## Shader-driven strikethrough toast for removed-modifier events (#82).
##
## A SubViewportContainer renders the label; its canvas_item ShaderMaterial owns
## every visual: simultaneous greyscale, hot-tip sweep, strike line drawn through
## transparent glyph gaps, and UV-displacement unzip.  This class only drives
## the shader uniforms via tweens — no clip nodes, no coordinate math.
##
## Scene-tunable knobs live on the ShaderMaterial (inspector: Label → Material):
## hot_color, line_color, tip_radius, line_half_thick. Timing knobs are @export on
## this node: strike_duration, plus the inherited visible_duration /
## fade_in_duration / fade_out_duration.
##
## The diagonal cut is NOT scene-authored: [method strike_endpoints] derives the
## split_y_start / split_y_end uniforms from the label's actual font metrics, so
## the line lands cleanly through the x-height of whatever font/size/box is used
## (the old hardcoded 0.7→0.4 lerp looked right but only for one shape). It's
## recomputed whenever the label resizes.

@export var strike_duration: float = 0.2
## Visual tilt of the cut, in degrees (aspect-corrected, so it reads the same
## angle regardless of label width). 0 = a flat strikethrough. Default ≈6.5°
## reproduces the known-good 0.7/0.4 slope at the stock 32px label; tune by eye
## in the toast sandbox for other fonts.
@export_range(0.0, 30.0, 0.5, "suffix:°") var angle_deg: float = 6.5
## Fraction of the ascent above the baseline to place the cut. 0.30 sits in the
## lowercase x-height band; raise toward ~0.45 to ride higher through capitals.
@export_range(0.0, 0.6, 0.01) var strike_height_ratio: float = 0.30

var _mat: ShaderMaterial


func _ready() -> void:
	# Own copy of the material — sub-resources are shared across scene instances
	# by default; parallel toasts must not share uniform state (set via the
	# scene's resource_local_to_scene).
	_mat = label.material as ShaderMaterial
	label.resized.connect(_refresh_geometry)
	_refresh_geometry()


## Push the current label size + recompute the diagonal endpoints. Driven by
## [signal Control.resized] instead of polled every frame — the label only
## changes size when its text/font does.
func _refresh_geometry() -> void:
	if label == null or _mat == null:
		return
	var label_size := label.size
	_mat.set_shader_parameter(&"label_size", label_size)
	if label_size.y <= 0.0:
		return
	var font := _resolve_font()
	var fsize := _resolve_font_size()
	var ascent := font.get_ascent(fsize)
	var total_h := font.get_height(fsize)
	var endpoints := strike_endpoints(ascent, total_h, label_size, angle_deg, strike_height_ratio)
	_mat.set_shader_parameter(&"split_y_start", endpoints.x)
	_mat.set_shader_parameter(&"split_y_end", endpoints.y)


## PURE geometry: the diagonal cut's UV endpoints (y at x=0, y at x=1) for a line
## centred on the x-height band. Text is vertically centred in the label rect, so
## the baseline sits at `(H - total_h)/2 + ascent`; the cut rides [param height_ratio]
## of the ascent above it. [param angle_deg] tilts the line, aspect-corrected by
## `W/H` so the on-screen angle is constant across label widths. Returned as
## `Vector2(start_y, end_y)` with `start_y > end_y` (bottom-left → top-right) for a
## positive angle. No Font/Node deps → unit-testable headless.
static func strike_endpoints(
		ascent: float, total_height: float, label_size: Vector2,
		angle_deg: float, height_ratio: float) -> Vector2:
	var h := label_size.y
	if h <= 0.0:
		return Vector2(0.5, 0.5)
	var baseline_px := (h - total_height) * 0.5 + ascent
	var center_px := baseline_px - ascent * height_ratio
	var center_uv := center_px / h
	# Aspect-corrected half-spread: a constant visual angle regardless of width.
	var half := 0.5 * tan(deg_to_rad(angle_deg)) * (label_size.x / h)
	return Vector2(
		clampf(center_uv + half, 0.0, 1.0),
		clampf(center_uv - half, 0.0, 1.0))


func _resolve_font() -> Font:
	if label.label_settings != null and label.label_settings.font != null:
		return label.label_settings.font
	return label.get_theme_font(&"font")


func _resolve_font_size() -> int:
	if label.label_settings != null:
		return label.label_settings.font_size
	return label.get_theme_font_size(&"font")


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
	tween.tween_property(label, "modulate:a", 0.0, fade_out_duration * 0.4) \
		.set_delay(fade_out_duration * 0.6)
	tween.tween_callback(queue_free).set_delay(fade_out_duration)
