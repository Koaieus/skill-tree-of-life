class_name PauseMenu
extends Control

## Single source of truth for the paused state. Toggling it shows/hides the menu
## and flips the SceneTree pause flag together. The node runs in
## PROCESS_MODE_ALWAYS (set in the scene) so it still catches the un-pause key
## and drives its buttons while the rest of the tree is frozen.
@export var active: bool:
	set(v):
		if v == active: return
		active = v
		_toggle(active)


func _ready() -> void:
	# Start hidden + unpaused regardless of the editor-saved `visible`.
	visible = false


func _toggle(on: bool) -> void:
	visible = on
	get_tree().paused = on


## Reload the running level from scratch. `paused` is a SceneTree flag that
## survives the reload, so clear it first (via `active`) or the fresh scene boots
## frozen. No confirmation for now — straight restart.
func _restart() -> void:
	active = false
	get_tree().reload_current_scene()


func _on_restart_button_pressed() -> void:
	_restart()


func _on_save_button_pressed() -> void:
	push_warning('ToDo: implement saving')


func _on_load_button_pressed() -> void:
	push_warning('ToDo: implement loading')


func _on_to_main_menu_button_pressed() -> void:
	push_warning('ToDo: implement a main menu / metagame / outer world')


## Quit the application. `get_tree().quit()` requests a clean shutdown — the
## engine finishes the frame, runs NOTIFICATION_WM_CLOSE_REQUEST / _exit_tree,
## then closes. (Editor: stops the play session.)
func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_continue_button_pressed() -> void:
	active = false


## Esc toggles pause from either state. Routed through `active` so the export
## stays truthful. Runs in any process mode because the node is ALWAYS.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		active = not active
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F5:
		get_viewport().set_input_as_handled()
		_restart()
