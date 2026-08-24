@tool
extends FloaterToast
# No class_name — consumers reach it through FloaterStyle.scene_override, and
# skipping the global_script_class_cache rebuild keeps this addable without
# disrupting an open editor (same trick as strikethrough_toast.gd).

## Crit toast, MOTION register — the number LANDS instead of fading in.
##
## The other two crit candidates ([method FloaterStyles.crit_heat] /
## [method FloaterStyles.crit_gold]) express intensity through colour and size,
## which a plain [FloaterStyle] can already carry. This one exists because entry
## animation cannot be expressed as a style field, and motion is the channel the
## toast layer was not using at all.
##
## The beat: spawn oversized and ignition-white ([constant Emissive.PEAK] above
## the style's own fill), snap to true size on a TRANS_BACK overshoot, and cool
## back down to the style colour over roughly twice that. So the eye catches the
## movement first and reads the number a moment later — which is the right order,
## because a crit's job is to interrupt.
##
## [b][method animate] still grows [member Control.custom_minimum_size]'s y from
## zero exactly as the base does.[/b] That growth is what pushes the rest of the
## stack upward; a subclass that replaces the entry animation and forgets it
## silently breaks every other toast on the same toaster.

## How much larger than final size the number lands at.
@export_range(1.0, 3.0, 0.05, "suffix:×") var punch_scale: float = 1.7
## How long the overshoot takes to settle.
@export_range(0.02, 0.6, 0.01, "suffix:s") var punch_duration: float = 0.18
## EV stops above the style's fill colour that the ignition frame sits at.
## [constant Emissive.PEAK] is the sanctioned "momentary overshoot, never a
## resting state" tier — which is exactly what this is (see [Emissive]).
@export_range(0.0, 3.0, 0.05) var ignition_stops: float = Emissive.PEAK

## The style's own fill — what the ignition flash cools back down to. Captured in
## [method set_content], since that is where the style is stamped.
var _settled_color: Color = Color.WHITE


## Deliberately hooked here rather than in a `_ready` override: [FloaterToast]
## has no explicit `_ready`, only the implicit one Godot generates to assign its
## `@onready var label` — and a subclass `_ready` that forgot `super()` would
## leave that null. [FloaterToaster] always calls this before [method animate],
## so there is nothing to gain by overriding `_ready` at all.
func set_content(text: String, style: FloaterStyle) -> void:
	super(text, style)
	if label.label_settings != null:
		_settled_color = label.label_settings.font_color
	# The Label is anchored, so its size is only real after layout. Scaling
	# around a stale pivot would make the punch grow down-right instead of
	# outward from the number's centre.
	if not label.resized.is_connected(_recentre_pivot):
		label.resized.connect(_recentre_pivot)
	_recentre_pivot()


func animate() -> void:
	var full_height := custom_minimum_size.y
	modulate.a = 0.0
	custom_minimum_size.y = 0.0
	_recentre_pivot()
	label.scale = Vector2.ONE * punch_scale
	_cool_to(ignition_stops)

	var tween := create_tween().set_parallel(true)
	# Slot growth, unchanged from the base — this is what moves the stack.
	tween.tween_property(self, "custom_minimum_size:y", full_height, fade_in_duration)
	# The fade is much faster than the base's: a crit that eases in has already
	# lost the argument. It is at full opacity before the overshoot settles.
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration * 0.3)
	tween.tween_property(label, "scale", Vector2.ONE, punch_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(_cool_to, ignition_stops, 0.0, punch_duration * 2.0)
	tween.tween_callback(_animate_out).set_delay(fade_in_duration + visible_duration)


func _recentre_pivot() -> void:
	label.pivot_offset = label.size * 0.5


## Drive the label colour from [param stops] EV above [member _settled_color];
## 0 lands exactly back on it. Written through `label_settings` because
## [LabelSettings.font_color] outranks a theme colour override in Godot 4 — the
## same reason [method FloaterToast.set_content] does.
func _cool_to(stops: float) -> void:
	if label.label_settings == null:
		return
	label.label_settings.font_color = Emissive.at(_settled_color, stops)
