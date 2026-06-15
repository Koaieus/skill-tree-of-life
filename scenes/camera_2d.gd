class_name GraphCamera
extends Camera2D


@export_range(0, 1500, 1.0, 'or_greater') var pan_speed: float = 800.0

const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.00


func _unhandled_input(event: InputEvent) -> void:
	# Panning: middle mouse button drag
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			global_position -= event.relative / zoom
	# Zooming: scroll wheel
	if event is InputEventMouseButton:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP):
			zoom = Vector2(MAX_ZOOM, MAX_ZOOM).min(zoom + Vector2.ONE * 0.25)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN):
			zoom = Vector2(MIN_ZOOM, MIN_ZOOM).max(zoom - Vector2.ONE * 0.25)

func _process(delta: float) -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		global_position += input_dir * pan_speed * delta
