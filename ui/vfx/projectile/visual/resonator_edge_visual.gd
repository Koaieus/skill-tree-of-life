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
var _drain := VisualDrain.new(finished)


func _ready() -> void:
	if VfxEditorScene.is_edited(self):
		return
	if body_scene != null:
		_body = body_scene.instantiate()
		add_child(_body)
		_drain.track(_body)
	if edge_energize_scene != null:
		_energize = edge_energize_scene.instantiate() as Node2D
		if _energize != null:
			add_child(_energize)
			_drain.track(_energize)
	# Both children live from here on; no arrival gate.
	_drain.seal()
	_push_tint()


# ---------------------------------------------------------------- duck contract


func _on_launch() -> void:
	VisualDrain.forward(_body, &"_on_launch", [])
	VisualDrain.forward(_energize, &"_on_launch", [])


func _on_progress(t: float) -> void:
	VisualDrain.forward(_body, &"_on_progress", [t])
	VisualDrain.forward(_energize, &"_on_progress", [t])


func _on_context(entry: Variant) -> void:
	VisualDrain.forward(_body, &"_on_context", [entry])
	VisualDrain.forward(_energize, &"_on_context", [entry])


func _on_crit(tier: int) -> void:
	VisualDrain.forward(_body, &"_on_crit", [tier])
	VisualDrain.forward(_energize, &"_on_crit", [tier])


func _on_arrival() -> void:
	VisualDrain.forward(_body, &"_on_arrival", [])
	VisualDrain.forward(_energize, &"_on_arrival", [])


# ------------------------------------------------------------------- internals


func _push_tint() -> void:
	if _body != null and "tint" in _body:
		_body.set("tint", tint)
	if _energize != null and "tint" in _energize:
		_energize.set("tint", tint)
