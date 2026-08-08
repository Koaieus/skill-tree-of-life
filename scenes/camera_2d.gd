class_name GraphCamera
extends Camera2D


@export_range(0, 1500, 1.0, 'or_greater') var pan_speed: float = 800.0

## How long one scroll step takes to settle. Short enough to stay responsive,
## long enough that anything tracking a canvas position (the tooltip fan, the
## floater toaster) glides instead of teleporting.
@export_range(0.0, 1.0, 0.01) var zoom_duration: float = 0.15
@export var zoom_step: float = 0.25

const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.00

## The authoritative zoom the wheel accumulates into. `zoom` itself is only the
## tween's output and is fractional mid-flight — accumulating on it would read a
## half-applied value and silently drop steps during fast scrolling.
var _target_zoom: float = 1.0
var _zoom_tween: Tween = null

## Last-known zoom TARGET, mirrored via [signal Events.camera_zoom_changed]
## (#399). Static so a consumer with no live camera in its scene (bloom
## sandbox SubViewport, headless GUT fixtures) still reads a sane default
## instead of needing a tree lookup, and so an Edge spawned between zoom
## steps (procgen/`Graph.add_edge` at level load) sees the current value
## immediately rather than waiting for the next scroll tick.
static var current_zoom: float = 1.0


func _ready() -> void:
	_target_zoom = zoom.x
	current_zoom = _target_zoom
	Events.camera_zoom_changed.emit(current_zoom)


func _unhandled_input(event: InputEvent) -> void:
	# Panning: middle mouse button drag
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			global_position -= event.relative / zoom
	# Zooming: scroll wheel
	if event is InputEventMouseButton:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP):
			_zoom_by(zoom_step)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_by(-zoom_step)

func _process(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		global_position += input_dir * pan_speed * delta


## Advances the zoom target by one step and retargets the tween. Killing the
## previous tween first is what makes rapid scrolling accumulate instead of
## having two tweens fight over `zoom`; because the new tween starts from
## wherever the old one got to, the steps chain into one continuous glide.
##
## Takes a STEP, not an absolute target, so the caller never has to read
## `_target_zoom` before the resync below has had a chance to run.
func _zoom_by(step: float) -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	else:
		# Nothing in flight, so `zoom` is authoritative — honour any external
		# write since the last step. A level scene assigns `zoom` directly from
		# `_setup_level()`, which runs AFTER this node's `_ready`; without this
		# resync `_target_zoom` would still hold the stale value and the first
		# scroll tick would teleport.
		_target_zoom = zoom.x
	_target_zoom = clampf(_target_zoom + step, MIN_ZOOM, MAX_ZOOM)
	current_zoom = _target_zoom
	Events.camera_zoom_changed.emit(current_zoom)
	if zoom_duration <= 0.0:
		zoom = Vector2(_target_zoom, _target_zoom)
		return
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, ^"zoom", Vector2(_target_zoom, _target_zoom), zoom_duration)
