@tool
class_name FloaterToaster
extends Node2D

## Stacked toast manager for one world-space target. Receives [FloaterRequest]s
## via [method add_toast], drains them one-per-[member FloaterToast.fade_in_duration]
## so rapid bursts read as a sequence rather than simultaneous noise, and
## self-destructs when the queue is empty and the last toast has exited.
##
## Placed at the target's world position by [FloaterToasterManager]. If
## [member target] is set, [method _process] mirrors the target's position
## each frame (low cost — toasters are short-lived).


## Cap on the waiting queue (not counting the currently-displayed toast).
## When exceeded, the oldest queued entry is dropped.
@export var max_queue_size: int = 8

## Optional live target to track. When set, this toaster's [member Node2D.global_position]
## follows [member target]'s global_position each frame.
var target: Node2D = null

@onready var _vbox: VBoxContainer = $VBoxContainer
@onready var _timer: Timer = $Timer

var _queue: Array[FloaterRequest] = []

const _FLOATER_TOAST_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater_toast.tscn")

# Tool button for in-editor smoke-testing.
@export_tool_button("+ Toast!") var _btn: Callable = _add_debug_toasts


func _ready() -> void:
	_vbox.child_exiting_tree.connect(_on_toast_exited)


func _process(_delta: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position


func add_toast(request: FloaterRequest) -> void:
	_queue.append(request)
	if _queue.size() > max_queue_size:
		_queue.pop_front()
	if _timer.is_stopped():
		_pop_toast()


func _pop_toast() -> void:
	if _queue.is_empty():
		return
	var request: FloaterRequest = _queue.pop_front()
	var scene: PackedScene = _FLOATER_TOAST_SCENE
	# scene_override lets the director swap in a concrete toast variant (e.g.
	# the strikethrough scene for removed modifiers — see #82). The override
	# MUST be a scene whose root extends FloaterToast.
	if request.style != null and request.style.scene_override != null:
		scene = request.style.scene_override
	var toast := scene.instantiate() as FloaterToast
	_vbox.add_child(toast)
	var color := request.style.fill_color if request.style != null else Color.WHITE
	toast.set_content(request.text, color)
	toast.animate()
	_timer.start(toast.fade_in_duration)


func _on_toast_exited(_node: Node) -> void:
	if _queue.is_empty() and _vbox.get_child_count() <= 1:
		queue_free()


func _add_debug_toasts() -> void:
	var samples := ["-3", "+5 STR", "+123 XP", "LEVEL UP: +1 SP"]
	for s in samples:
		var req := FloaterRequest.new()
		req.text = s
		add_toast(req)
