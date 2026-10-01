@tool
class_name FloaterToast
extends Control

## A single item in a [FloaterToaster] stack. Grows its slot from zero to push
## existing toasts upward, fades in, waits, then calls [method _animate_out].
##
## Subclass and override [method _animate_out] for custom exit animations
## (e.g. the top_level escape + unzip used by the strikethrough toast in #82).
## The base implementation fades the content in-place and collapses the slot so
## remaining toasts rearrange gently.
##
## The [member label] accessor and [method _animate_out] are the two public seams
## that concrete toast scenes wire into. The [FloaterToaster] calls
## [method set_content] before [method animate] — both are always called before
## the node's first process frame.
##
## [method set_content] takes the whole [FloaterStyle] and stamps every field the
## toast can express (colour, font size, glow, on-screen hold). This is the toast
## growing up from the #81 PoC into the renderer's single style-application site —
## the old per-field carrier on the legacy [Floater] is gone. Fields left at their
## inherit sentinel (`font_size`/`float_time` == 0) keep the scene-authored value.


@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:s") var visible_duration: float = 1.75
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_in_duration: float = 0.3
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_out_duration: float = 1.5


## Size of the [member suffix] span relative to the main text — "small", so a
## merged toast reads as one number with a footnote, not two numbers.
@export_range(0.2, 1.0, 0.05) var suffix_scale: float = 0.6
@export_range(0.0, 32.0, 1.0, "suffix:px") var suffix_gap: float = 6.0


@onready var label: Label = $Label
## Optional trailing span after the main text (the merged cascade toast's
## `+N W`), set by [method set_suffix]. Null on a variant scene that doesn't
## author one — the suffix is then dropped, never misplaced.
@onready var suffix: Label = get_node_or_null(^"Label/Suffix") as Label


## Set the toast text and apply [param style]. [param style] may be null (raw
## debug toasts) → white, everything inherited.
func set_content(text: String, style: FloaterStyle) -> void:
	label.text = text
	var color: Color = style.fill_color if style != null else Color.WHITE
	# LabelSettings.font_color takes priority over add_theme_color_override in
	# Godot 4, so we must write into the settings resource. Duplicate first —
	# sub-resources are SHARED across scene instances by default, so mutating
	# without duplicating would corrupt every other live toast.
	if label.label_settings != null:
		var settings: LabelSettings = label.label_settings.duplicate()
		settings.font_color = color
		if style != null:
			_apply_style(settings, style)
		label.label_settings = settings
	else:
		label.add_theme_color_override("font_color", color)
	if style != null and style.float_time > 0.0:
		visible_duration = style.float_time


## Show [param text] as a small span right after the main text, in
## [param style]'s colour, and recentre the pair. Call AFTER [method
## set_content] — it measures the main text at its final size. Empty text hides
## the span.
func set_suffix(text: String, style: FloaterStyle) -> void:
	if suffix == null:
		return
	suffix.visible = not text.is_empty()
	if not suffix.visible:
		return
	suffix.text = text
	var main_settings := label.label_settings
	var font: Font = main_settings.font if main_settings != null else null
	if font == null:
		font = label.get_theme_font(&"font")
	var main_size: int = main_settings.font_size if main_settings != null \
		else label.get_theme_font_size(&"font_size")
	var settings := LabelSettings.new() if main_settings == null \
		else main_settings.duplicate() as LabelSettings
	settings.font_color = style.fill_color if style != null else Color.WHITE
	settings.font_size = maxi(1, roundi(float(main_size) * suffix_scale))
	suffix.label_settings = settings
	var main_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, main_size).x
	var suffix_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, settings.font_size).x
	# The span hangs off the centred main run (its anchors sit at the label's
	# horizontal centre); shifting the label by half the span keeps the pair centred.
	suffix.offset_left = main_w * 0.5 + suffix_gap
	suffix.offset_right = suffix.offset_left + suffix_w
	var shift := (suffix_gap + suffix_w) * 0.5
	label.offset_left -= shift
	label.offset_right -= shift


## Stamp the non-colour style fields the stacked toast can express onto its
## (already-duplicated) [param settings]. Font size and glow only. Grows the
## slot to fit an enlarged font so it doesn't clip.
func _apply_style(settings: LabelSettings, style: FloaterStyle) -> void:
	if style.font_size > 0:
		settings.font_size = style.font_size
		custom_minimum_size.y = maxf(custom_minimum_size.y, float(style.font_size))
	if style.glow:
		# A soft halo: an offset-less shadow in the glow colour reads as a glow.
		settings.shadow_color = style.glow_color
		settings.shadow_size = 10
		settings.shadow_offset = Vector2.ZERO


func animate() -> void:
	var full_height := custom_minimum_size.y
	modulate.a = 0.0
	custom_minimum_size.y = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "custom_minimum_size:y", full_height, fade_in_duration)
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	tween.tween_callback(_animate_out).set_delay(fade_in_duration + visible_duration)


## Override for custom exit animation. Base: fade in-place, then collapse slot.
## If using the top_level escape trick, promote [member label] to top_level,
## snapshot [code]label.global_position[/code], run the escape tween on the label,
## then collapse the slot here so remaining toasts rearrange. Call [method queue_free]
## on both the label and self when done.
func _animate_out() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration) \
		.set_delay(fade_out_duration * 0.5)
	tween.tween_callback(queue_free).set_delay(fade_out_duration)
