class_name FloaterToasterManager
extends Node2D

## Manages per-target [FloaterToaster]s. Receives [FloaterRequest]s from the
## [FloaterDirector] and routes them to the appropriate toaster, creating one
## lazily when a new target is seen and letting it self-destruct when idle.
##
## This node replaced [FloatingNumberLayer] (#81). It no longer owns a
## [_process] cooldown queue — the [FloaterToaster] handles its own stagger.

const _TOASTER_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater_toaster.tscn")

## Cap on queued (not-yet-shown) toasts per target. Passed to new toasters.
@export var max_queue_size: int = 8

# stack_key (int) → FloaterToaster; entry may be invalid after self-destruct.
var _toasters: Dictionary = {}


## Route [param request] to the right toaster, creating one if needed.
## Ungrouped requests (key == 0, no live target) each get a one-shot toaster.
func spawn(request: FloaterRequest) -> void:
	if request == null or request.text.is_empty():
		return
	var key := request.stack_key()
	if key == 0:
		var t: FloaterToaster = _TOASTER_SCENE.instantiate()
		add_child(t)
		t.global_position = request.anchor_position()
		t.add_toast(request)
		return
	var toaster := _get_or_create_toaster(key, request)
	toaster.add_toast(request)


func _get_or_create_toaster(key: int, request: FloaterRequest) -> FloaterToaster:
	# Read untyped first — assigning a freed instance to a typed var crashes
	# before is_instance_valid gets a chance to run.
	var stored = _toasters.get(key)
	var t: FloaterToaster = stored if is_instance_valid(stored) else null
	if t == null:
		t = _TOASTER_SCENE.instantiate()
		t.max_queue_size = max_queue_size
		t.target = request.target
		add_child(t)
		t.global_position = request.anchor_position()
		_toasters[key] = t
	return t


## Convenience: spawn a plain number at [param target] without composing a
## [FloaterRequest] by hand.
func spawn_simple(target: Node2D, text: String, color: Color) -> void:
	var style := FloaterStyle.new()
	style.fill_color = color
	var req := FloaterRequest.new()
	req.target = target
	req.text = text
	req.style = style
	spawn(req)
