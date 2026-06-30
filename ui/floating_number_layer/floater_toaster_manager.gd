class_name FloaterToasterManager
extends Node2D

## Manages per-target [FloaterToaster]s. Receives [FloaterRequest]s from the
## [FloaterDirector] and routes them to the appropriate toaster, creating one
## lazily when a new target is seen and letting it self-destruct when idle.
##
## This node replaced [FloatingNumberLayer] (#81). It no longer owns a
## [_process] cooldown queue — the [FloaterToaster] handles its own stagger.
##
## Anchor resolution: when creating a toaster, this manager inspects the
## request's target for a [Marker2D] child named [code]FloatAnchor[/code]
## (unique-name lookup). If found, that marker's world position is used and
## stored on the toaster's [member FloaterToaster._anchor] so
## [method FloaterToaster._on_target_moved] can re-read it on movement.
## If the target emits [code]position_changed[/code], the manager connects it
## so the toaster tracks position without a _process loop. The connection
## dissolves automatically if the target is freed before the toaster.

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
		add_child(t)
		_wire_anchor(t, request.target)
		_toasters[key] = t
	return t


## Resolve the anchor node for [param target], set the toaster's initial
## world position, and connect a movement signal if the target exposes one.
func _wire_anchor(toaster: FloaterToaster, target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var anchor: Node2D = target.get_node_or_null(^"%FloatAnchor") as Node2D
	if anchor == null:
		anchor = target
	toaster._anchor = anchor
	toaster.global_position = anchor.global_position
	# Duck-typed position tracking: connect if the target advertises movement.
	# The connection dissolves for free when target is freed before the toaster.
	if target.has_signal(&"position_changed"):
		target.position_changed.connect(toaster._on_target_moved)


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
