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


@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:s") var visible_duration: float = 1.75
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_in_duration: float = 0.3
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_out_duration: float = 1.5


@onready var label: Label = $Label


func set_content(text: String, color: Color) -> void:
	label.text = text
	# LabelSettings.font_color takes priority over add_theme_color_override in
	# Godot 4, so we must write the color directly into the settings resource.
	# Sub-resources are duplicated per scene instantiation, so this is safe.
	if label.label_settings != null:
		label.label_settings.font_color = color
	else:
		label.add_theme_color_override("font_color", color)


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
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration * 0.5) \
		.set_delay(fade_out_duration * 0.5)
	tween.tween_callback(queue_free).set_delay(fade_out_duration)
