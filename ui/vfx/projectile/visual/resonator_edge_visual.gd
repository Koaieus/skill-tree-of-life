@tool
class_name ResonatorEdgeVisual
extends Node2D

## Resonator's EDGE-verb body (#678): a [WavePath]-riding [BoltPacket]
## running CONCURRENTLY with an [EdgeEnergize] overlay lighting the wire
## underneath it — "waves live in wires" is Resonator's core differentiator
## from Reverberator's node-centric, self-loop-only treatment (#663 hub).
##
## [b]Why not [ComposedProjectileVisual].[/b] Its `arrival_companions` spawn
## ONLY at `_on_arrival` — right for a one-shot ring, wrong here: the
## energize front must ride `_on_progress(t)` for the WHOLE flight, exactly
## matching the bolt's own travel. So both children live from `_ready`,
## receive every duck-typed call, and this wrapper's own `finished` waits on
## both.
##
## [b]`edge_origin`/`edge_target` are not stamped by any coordinator in the
## shared kit[/b] — only `tint` is (mirroring `ArrowVolleyCoordinator`). This
## wrapper derives them itself from the [ScheduleEntry] `_on_context` hands
## over: every entry already carries `origin`/`target` [SkillNode] refs
## (#543 D6), so no shared-kit change is needed.
##
## This is composed as the `body_scene` of a STOCK [ComposedProjectileVisual]
## (`resonator_edge_composed_visual.tscn`), which supplies the convergence
## gather ring at arrival — that composition is unmodified kit behaviour,
## since [ImpactRing] already reads `convergence_count` off its own
## `_on_context`.

signal finished

@export var body_scene: PackedScene = preload("res://ui/vfx/projectile/visual/bolt_packet.tscn")
@export var edge_energize_scene: PackedScene = preload("res://ui/vfx/projectile/visual/edge_energize.tscn")

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_tint()

var _body: Node
var _energize: Node2D
var _pending: int = 0
var _done_emitted: bool = false


func _ready() -> void:
	if VfxEditorScene.is_edited(self):
		return
	if body_scene != null:
		_body = body_scene.instantiate()
		add_child(_body)
		_track(_body)
	if edge_energize_scene != null:
		_energize = edge_energize_scene.instantiate() as Node2D
		if _energize != null:
			# EdgeEnergize._place() writes `position`/`rotation` in PARENT
			# space, and this wrapper's parent is the flying, rotating
			# Projectile (`face_velocity = true`) — top_level is what keeps
			# the overlay laid along the edge in WORLD space instead of
			# swimming and spinning with the bolt.
			_energize.top_level = true
			add_child(_energize)
			_track(_energize)
	_push_tint()


# ---------------------------------------------------------------- duck contract


func _on_launch() -> void:
	_forward(&"_on_launch", [])


func _on_progress(t: float) -> void:
	_forward(&"_on_progress", [t])


func _on_context(entry: Variant) -> void:
	_forward(&"_on_context", [entry])
	if _energize == null or not (entry is Object):
		return
	var obj: Object = entry
	var origin_node: Variant = obj.get("origin") if "origin" in obj else null
	var target_node: Variant = obj.get("target") if "target" in obj else null
	if origin_node is Node2D and target_node is Node2D:
		_energize.edge_origin = (origin_node as Node2D).global_position
		_energize.edge_target = (target_node as Node2D).global_position


func _on_crit(tier: int) -> void:
	_forward(&"_on_crit", [tier])


func _on_arrival() -> void:
	_forward(&"_on_arrival", [])


# ------------------------------------------------------------------- internals


func _push_tint() -> void:
	if _body != null and "tint" in _body:
		_body.set("tint", tint)
	if _energize != null and "tint" in _energize:
		_energize.set("tint", tint)


func _forward(method: StringName, args: Array) -> void:
	for node in [_body, _energize]:
		if node != null and node.has_method(method):
			node.callv(method, args)


func _track(node: Node) -> void:
	if node != null and node.has_signal(&"finished"):
		_pending += 1
		node.finished.connect(_on_child_finished)


func _on_child_finished() -> void:
	_pending -= 1
	if _pending <= 0 and not _done_emitted:
		_done_emitted = true
		call_deferred(&"emit_signal", &"finished")
