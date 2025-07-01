extends CanvasLayer
class_name FadeLayer

signal fade_completed

@onready var fade_rect: ColorRect = $ColorRect
@onready var progress_bar: TextureProgressBar = $ProgressBar

const DEFAULT_FADE_DURATION: float = 0.5

func _ready():
	fade_rect.color.a = 0.0
	progress_bar.visible = false

## Update progress bar progress (input: [0, 1.])
func set_progress(percent: float):
	progress_bar.value = percent * 100.


func animate_alpha(target_alpha: float, duration: float) -> Tween:
	var tween := create_tween()
	tween.tween_property(fade_rect, "color:a", target_alpha, duration)
	return tween

func fade_out(duration := DEFAULT_FADE_DURATION) -> Tween:
	var tween = animate_alpha(0.0, duration)
	tween.finished.connect(_on_fade_out_complete)
	return tween

func fade_in(duration := DEFAULT_FADE_DURATION) -> Tween:
	progress_bar.visible = false
	var tween = animate_alpha(0.0, duration)
	tween.finished.connect(_on_fade_in_complete)
	return tween
	

func _on_fade_in_complete():
	pass
	
func _on_fade_out_complete():
	progress_bar.visible = true
