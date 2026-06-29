@tool
class_name FloaterToasts
extends Node2D
## VBoxContainer to hold the sequence of active toasts until they expire, new ones should push up existing ones,
## existing ones fade out after a while then are freed.


@export var toast_queue: Array = []
@export_tool_button('+ Toast!') var add_toast_button: Callable = _add_debug_toast

@onready var vbox: VBoxContainer = $VBoxContainer
@onready var timer: Timer = $Timer


const FLOATER_TOAST = preload("res://ui/floating_number_layer/floater_toast.tscn")


func add_toast(toast: Variant) -> void: # TODO: Make into a real toast API
	toast_queue.append(toast)
	if timer.is_stopped():
		pop_toast()

func pop_toast() -> void:
	if toast_queue.is_empty():
		return
	var toast_data = toast_queue.pop_front()
	var toast := FLOATER_TOAST.instantiate() as FloaterToast
	vbox.add_child(toast)
	toast.animate()
	timer.start(toast.fade_in_duration)


func _add_debug_toast() -> void:
	add_toast('test')
	add_toast('test')
	add_toast('test')

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_add_debug_toast()
