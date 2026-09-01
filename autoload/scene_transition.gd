extends CanvasLayer
#class_name SceneTransitionManager

## The curtain: one black rect + one progress bar, above every game layer
## (`layer = 101`; the game's own UI is `layer = 2`).
##
## [b]The curtain STAYS UP between [method fade_out] and [method fade_in].[/b]
## `fade_out` used to `hide()` itself the instant it finished, which uncovered
## the outgoing scene for the whole threaded load and then uncovered the
## incoming one while it was still building — the "HUD with nothing behind it"
## flash. Whoever raised it is responsible for lowering it; see
## [SceneDirector] for who that is on a scene change.

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
	# Hidden until something actually reports progress. A bar sitting at 0%
	# for the length of a fade is the flash this is not.
	progress_bar.hide()


func set_faded(fade_status: bool) -> void:
	show()
	fade_rect.modulate = COLOR_FADED if fade_status else COLOR_UNFADED


## Is the screen currently covered? The guard for "fade in only if someone
## faded out" — a scene launched directly (no [SceneDirector]) never raised the
## curtain, and must not gain a black fade nobody asked for.
func is_curtain_up() -> bool:
	return visible and fade_rect.modulate.a > 0.0


## Mid-animation, either way. Lets a second would-be revealer stand down
## instead of restarting a fade that is already running.
func is_fading() -> bool:
	return anim.is_playing()


func fade_out():
	show()
	progress_bar.hide()
	anim.play("fade_out")
	await anim.animation_finished
	fade_out_finished.emit()


func fade_in():
	show()
	progress_bar.hide()
	anim.play("fade_in")
	await anim.animation_finished
	hide()
	fade_in_finished.emit()


func set_progress(value: float) -> void:
	progress_bar.value = value
	progress_updated.emit(value)
