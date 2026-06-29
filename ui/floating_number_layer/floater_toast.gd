class_name FloaterToast
extends Control


@export_range(1.0, 10.0, 0.05, "or_greater", "suffix:s") var visible_duration: float = 5.0
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_in_duration: float = 0.5
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_out_duration: float = 1.0


@onready var label: Label = $Label


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	
func animate() -> void:
	var full_height := custom_minimum_size.y
	modulate.a = 0.0
	custom_minimum_size.y = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "custom_minimum_size:y", full_height, fade_in_duration)
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	tween.tween_property(self, "modulate:a", 0.0, fade_out_duration) \
		.set_delay(fade_in_duration + visible_duration)
	tween.chain()
	tween.tween_property(self, "custom_minimum_size:y", 0.0, fade_out_duration * 0.5)
	tween.tween_callback(queue_free)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
