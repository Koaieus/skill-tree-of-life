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
## [b][EdgeEnergize]'s own world-space anchoring is its own to derive[/b]
## (#687) — its `_on_context` reads `origin`/`target` off the
## [ScheduleEntry] this wrapper already forwards, so this file just forwards
## and does not re-derive any of it.
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
