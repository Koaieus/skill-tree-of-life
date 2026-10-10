class_name ChannelLassoDirector
extends Node2D

## One [ChannelLasso] per channelling node, core → node, for as long as the
## channel is open. Pure presentation: every lasso reads its node and the
## [AllocationSystem] live; this only keeps the set in step with the channels.
##
## A channel that ends without landing (cancel, leash, ownership) plays the
## existing [GateRope] snap from the previous owner's core to the node.
## Mounted under `Graph/` beside [AllocationVFX] so world coordinates match;
## the rim cue is AllocationVFX's, never duplicated here.
##
## Deps are wired in [method initialize], never `_ready` (scene authoring).
## [method rebuild] is the reconcile pass for state adopted without signals
## (a resync) — GameRoot connects it to [signal WorldSyncChannel.resync_applied].

@export var allocation_system: AllocationSystem
@export var lasso_scene: PackedScene = preload("res://ui/vfx/channel_lasso/channel_lasso.tscn")
@export var snap_scene: PackedScene = preload("res://graph/gate_rope.tscn")

## Keyed by the node's `get_instance_id()` — a freed node's ref reads `== null`.
var _lassos: Dictionary[int, ChannelLasso] = {}


func initialize() -> void:
	if allocation_system == null:
		return
	var hooks: Array = [
		[allocation_system.channel_changed, _on_channel_changed],
		[allocation_system.channel_stepped, _on_channel_stepped],
		[allocation_system.channel_ended, _on_channel_ended],
		[allocation_system.core_moved, _on_core_moved],
	]
	for hook: Array in hooks:
		var sig: Signal = hook[0]
		if not sig.is_connected(hook[1]):
			sig.connect(hook[1])
	rebuild()


## Reconcile the lasso set against the graph: free every lasso whose node is
## gone or idle, create one for every channelling node that lacks it.
## [param _reason] absorbs [signal WorldSyncChannel.resync_applied]'s argument.
func rebuild(_reason: String = "") -> void:
	for id: int in _lassos.keys():
		var node := instance_from_id(id) as SkillNode
		if node == null or not node.is_channelling():
			_free_lasso(id)
	if allocation_system == null or allocation_system.graph == null:
		return
	for node in allocation_system.graph.get_skill_nodes():
		if node.is_channelling():
			_ensure_lasso(node)


func lasso_count() -> int:
	return _lassos.size()


func has_lasso(node: SkillNode) -> bool:
	return node != null and _lassos.has(node.get_instance_id())


func _ensure_lasso(node: SkillNode) -> void:
	var id := node.get_instance_id()
	if _lassos.has(id) or lasso_scene == null:
		return
	var lasso := lasso_scene.instantiate() as ChannelLasso
	add_child(lasso)
	lasso.bind(node, allocation_system)
	_lassos[id] = lasso


func _free_lasso(id: int) -> void:
	var lasso: ChannelLasso = _lassos.get(id)
	_lassos.erase(id)
	if lasso != null and is_instance_valid(lasso):
		lasso.queue_free()


func _on_channel_changed(node: SkillNode) -> void:
	if node != null and node.is_channelling():
		_ensure_lasso(node)


func _on_channel_stepped(node: SkillNode, _direction: int) -> void:
	if node == null:
		return
	var lasso: ChannelLasso = _lassos.get(node.get_instance_id())
	if lasso != null:
		lasso.on_stepped()


func _on_channel_ended(node: SkillNode, previous_owner: Entity, reason: StringName) -> void:
	if node == null:
		return
	_free_lasso(node.get_instance_id())
	if reason != &"landed":
		_play_snap(node, previous_owner)


func _play_snap(node: SkillNode, previous_owner: Entity) -> void:
	if snap_scene == null or previous_owner == null or not is_instance_valid(previous_owner) \
			or previous_owner.core_location == null:
		return
	var rope := snap_scene.instantiate() as GateRope
	add_child(rope)
	rope.play(GateRope.Mode.SNAP, previous_owner.core_location.global_position,
			node.global_position, previous_owner.color, previous_owner.color)


func _on_core_moved(entity: Entity, _from_node: SkillNode, _to_node: SkillNode) -> void:
	for id: int in _lassos:
		var node := instance_from_id(id) as SkillNode
		if node != null and node.owned_by == entity:
			_lassos[id].on_core_moved()
