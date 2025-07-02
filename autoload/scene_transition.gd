extends CanvasLayer
#class_name SceneTransitionManager

signal fade_out_finished
signal fade_in_finished
signal progress_updated(progress: float)

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var fade_rect: ColorRect = $ColorRect

func _ready():
	hide()

func fade_out():
	show()
	progress_bar.value = 0
	anim.play("fade_out")
	await anim.animation_finished
	emit_signal("fade_out_finished")

func fade_in():
	anim.play("fade_in")
	await anim.animation_finished
	hide()
	emit_signal("fade_in_finished")

func set_progress(value: float) -> void:
	progress_bar.value = value
	emit_signal("progress_updated", value)
