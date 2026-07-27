@tool
class_name FloaterToaster
extends Node2D

## Stacked toast manager for one world-space target. Receives [FloaterRequest]s
## via [method add_toast], drains them one-per-[member FloaterToast.fade_in_duration]
## so rapid bursts read as a sequence rather than simultaneous noise, and
## self-destructs when the queue is empty and the last toast has exited.
##
## Position is set once by [FloaterToasterManager] at creation time (via
## [method bind_anchor]). If the target emits [code]position_changed[/code], the
## manager connects it to [method _on_target_moved] so the toaster tracks
## without a _process loop.


## Cap on the waiting queue (not counting the currently-displayed toast).
## When exceeded, the oldest queued entry is dropped.
@export var max_queue_size: int = 8

@onready var _vbox: VBoxContainer = $VBoxContainer
@onready var _timer: Timer = $Timer

var _queue: Array[FloaterRequest] = []
# The resolved anchor node (FloatAnchor marker, or the target itself).
# Kept so _on_target_moved can re-read its position without storing the target.
var _anchor: Node2D = null

const _FLOATER_TOAST_SCENE: PackedScene = preload("res://ui/floating_number_layer/floater_toast.tscn")

# Tool button for in-editor smoke-testing.
@export_tool_button("+ Toast!") var _btn: Callable = _add_debug_toasts


func _ready() -> void:
	_vbox.child_exiting_tree.connect(_on_toast_exited)
	# Anything queued before _ready wired _vbox/_timer (see add_toast) drains now.
	if not _queue.is_empty() and _timer.is_stopped():
		_pop_toast()


## Adopt [param anchor] as the position source and snap to it. Called by
## [FloaterToasterManager] right after this toaster enters the tree.
func bind_anchor(anchor: Node2D) -> void:
	_anchor = anchor
	_on_target_moved()


## Called by [FloaterToasterManager] when the target signals that it moved.
## Re-reads the anchor's current position rather than receiving it as an
## argument, so any signal signature (or a no-arg signal) can be adapted by the
## manager with [method Callable.bind].
##
## The anchor may live in a DIFFERENT canvas than this toaster: the Hero Sigil
## Card's FloatAnchor sits under the HUD's CanvasLayer, while the toaster hangs
## off the world-space FloaterDirector under Graph. Copying `global_position`
## straight across put the toast at a *world* point whose coordinates happened
## to equal a screen pixel — visibly wrong the moment the camera left the origin
## (i.e. always, `GameRoot._focus_camera_on_player` sees to that). Round-trip
## through the shared viewport space instead: exactly identity for a world-space
## anchor (SkillNode / core), correct for a HUD one.
func _on_target_moved() -> void:
	if not is_instance_valid(_anchor):
		return
	# `get_canvas_transform()` is exactly the prefix `get_global_transform_with_canvas()`
	# applies, so the two compose into a clean round-trip. (`get_viewport_transform()`
	# is NOT interchangeable — it folds in the viewport's stretch transform, which
	# the other side doesn't, and the mismatch shows up as a scaled offset.)
	var canvas_pos: Vector2 = _anchor.get_global_transform_with_canvas().origin
	global_position = get_canvas_transform().affine_inverse() * canvas_pos


func add_toast(request: FloaterRequest) -> void:
	_queue.append(request)
	if _queue.size() > max_queue_size:
		_queue.pop_front()
	# Only pop once _ready has wired _timer/_vbox. If the owning manager is
	# outside the SceneTree (e.g. an editor 2D-canvas preview copy of the
	# scene), add_child never fires this node's _ready, so _timer is still
	# null here — _ready drains the queue if/when we do enter the tree.
	if is_node_ready() and _timer.is_stopped():
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
	toast.set_content(request.text, request.style)
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
