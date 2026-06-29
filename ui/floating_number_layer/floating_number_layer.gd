class_name FloatingNumberLayer
extends Node2D

## Pure renderer: turns a [FloaterRequest] into a drifting, fading world-space
## number. Knows NOTHING about domain events, stats, entities, or fog — the
## [FloaterDirector] translates domain facts into requests and hands them here.
##
## Lives as a child of the FloaterDirector (Node2D under Graph/), sharing the
## graph's world coordinates — NOT on a CanvasLayer (that would detach floaters
## from Camera2D and break the world-anchored toaster). A high [member
## Node2D.z_index] orders floaters above graph content.
##
## Per-target toaster: requests sharing a [method FloaterRequest.stack_key] are
## buffered and released on a stagger cadence so a burst reads as a sequence.
## Ungrouped requests (key == 0, raw-position escape hatch) bypass the buffer.

## The stock floater. A [FloaterStyle] may override it with an inherited scene.
const _FLOATER_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater.tscn")

## Seconds between consecutive releases from the same target's buffer.
@export var stagger_seconds: float = 0.15
## Per-target queue cap — oldest entry is dropped when exceeded.
@export var max_stack_size: int = 8

# stack_key (int) → Array[FloaterRequest]
var _queues: Dictionary = {}
# stack_key (int) → float seconds remaining until next release
var _cooldowns: Dictionary = {}


func _process(delta: float) -> void:
	for key: int in _cooldowns.keys().duplicate():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			var queue: Array = _queues.get(key, [])
			if queue.is_empty():
				_cooldowns.erase(key)
				_queues.erase(key)
			else:
				_fire_next(key)


## Route the request through the per-target buffer. Ungrouped requests (no live
## target) bypass it — they spawn immediately.
func spawn(request: FloaterRequest) -> void:
	if request == null or request.text.is_empty():
		return
	var key := request.stack_key()
	if key == 0:
		_spawn_now(request)
		return
	if not _queues.has(key):
		_queues[key] = []
	_queues[key].append(request)
	if (_queues[key] as Array).size() > max_stack_size:
		(_queues[key] as Array).pop_front()
	# Fire immediately only if not already in cooldown; otherwise wait for _process.
	if not _cooldowns.has(key):
		_fire_next(key)


func _fire_next(key: int) -> void:
	var queue: Array = _queues.get(key, [])
	if queue.is_empty():
		return
	_spawn_now(queue.pop_front())
	_cooldowns[key] = stagger_seconds


func _spawn_now(request: FloaterRequest) -> void:
	var style := request.style
	var scene: PackedScene = _FLOATER_SCENE
	if style != null and style.scene_override != null:
		scene = style.scene_override
	var floater: Floater = scene.instantiate()
	floater.text = request.text
	if style != null:
		style.apply_to(floater)
	add_child(floater)
	floater.global_position = request.anchor_position()
	floater.animate()


## Convenience: spawn a plain number at [param target] with [param color] and
## otherwise-default styling, without composing a [FloaterRequest] by hand.
## Thin wrapper over [method spawn] — the predefined-variant escape hatch.
func spawn_simple(target: Node2D, text: String, color: Color) -> void:
	var style := FloaterStyle.new()
	style.fill_color = color
	var req := FloaterRequest.new()
	req.target = target
	req.text = text
	req.style = style
	spawn(req)
