extends CanvasLayer
#class_name SceneTransitionManager

signal fade_out_finished
signal fade_in_finished
signal progress_updated(progress: float)

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var fade_rect: ColorRect = $ColorRect

const COLOR_FADED = Color(Color.BLACK, 1)
const COLOR_UNFADED = Color(Color.BLACK, 0)

func _ready():
	hide()
	
func set_faded(fade_status: bool) -> void:
	show()
	fade_rect.modulate = COLOR_FADED if fade_status else COLOR_UNFADED
	

func fade_out():
	progress_bar.value = 0
	show()
	anim.play("fade_out")
	await anim.animation_finished
	progress_bar.show()
	hide()
	emit_signal("fade_out_finished")
	

func fade_in():
	show()
	progress_bar.hide()
	anim.play("fade_in")
	await anim.animation_finished
	hide()
	emit_signal("fade_in_finished")

func set_progress(value: float) -> void:
	progress_bar.value = value
	emit_signal("progress_updated", value)
