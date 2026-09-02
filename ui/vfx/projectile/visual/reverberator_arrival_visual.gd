@tool
class_name ReverberatorArrivalVisual
extends Node2D

## Reverberator's shared per-verb visual (#677): a flying [member body_scene]
## (a bare [BoltPacket] for JUMP/EDGE, [GhostLoopBody] for
## SELF_LOOP) plus an arrival [ImpactRing] in `IN` mode, sized and heated by
## the landing's `visit_index` — "the 1st strike whispers, the 4th blazes"
## (#677 acceptance), drawn literally as an escalating ring per repeat visit.
##
## [b]Why not the stock [ComposedProjectileVisual].[/b] Its arrival
## companions receive whatever `_on_context` it stashed, UNCONDITIONALLY —
## exactly right for Resonator's convergence gather (`ImpactRing` already
## reads `convergence_count` off that), but wrong here: this spell's read is
## `visit_index`, which `ImpactRing` has no hook for. So this composes the
## same "body + one ring companion" shape by hand, applying the visit_index
## ramp to the ring's `expand_radius`/`emissive_tier` directly and never
## forwarding `_on_context` to the ring at all — forwarding it would let the
## ring's own convergence-widening compete for the same two properties this
## ramp already owns.

signal finished

## Visit count (0-based) at which the ring reads fully escalated.
## reverberator.tres caps `max_visits_per_node` at 6, so a node revisited past
## this many times still reads at the loudest authored ring rather than
## growing without bound.
const RAMP_VISITS: float = 3.0

## Flying body — [code]bolt_packet.tscn[/code] for JUMP/EDGE,
## [GhostLoopBody] for SELF_LOOP (set per coordinator slot).
@export var body_scene: PackedScene = preload("res://ui/vfx/projectile/visual/bolt_packet.tscn")

## Arrival ring — `IN` (absorb/gather): "every landing spawns P2 in IN mode"
## (#677 acceptance), whichever verb it arrived by.
@export var ring_scene: PackedScene = preload("res://ui/vfx/projectile/visual/impact_ring_absorb.tscn")

## Ring `expand_radius` at visit_index 0 / RAMP_VISITS+, world pixels — hand-
## picked pixel geometry, not an emissive value, so `docs/domain/hdr-color.md`
## does not apply (the same precedent `SparkImpactRing`/`DustPuff` set).
@export var ring_radius_start: float = 20.0
@export var ring_radius_end: float = 48.0

@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_tint()

var _body: Node
var _pending: int = 0
var _arrival_handled: bool = false
var _done_emitted: bool = false
var _visit_index: int = 0
var _crit_tier: int = 0


func _ready() -> void:
	if VfxEditorScene.is_edited(self):
		return
	if body_scene == null:
		return
	_body = body_scene.instantiate()
	add_child(_body)
	_push_tint()


# ---------------------------------------------------------------- duck contract


func _on_launch() -> void:
	_forward(_body, &"_on_launch", [])


func _on_progress(t: float) -> void:
	_forward(_body, &"_on_progress", [t])


func _on_context(entry: Variant) -> void:
	_forward(_body, &"_on_context", [entry])
	_visit_index = int(VfxContext.read_float(entry, &"visit_index", 0.0))


func _on_crit(tier: int) -> void:
	_crit_tier = tier
	_forward(_body, &"_on_crit", [tier])


func _on_arrival() -> void:
	_track(_body)
	_forward(_body, &"_on_arrival", [])
	if ring_scene != null:
		var ring: ImpactRing = ring_scene.instantiate()
		add_child(ring)
		_track(ring)
		var f: float = clampf(float(_visit_index) / RAMP_VISITS, 0.0, 1.0)
		ring.tint = tint
		ring.expand_radius = lerpf(ring_radius_start, ring_radius_end, f)
		ring.emissive_tier = lerpf(Emissive.LABEL, Emissive.ALERT, f)
		if _crit_tier > 0:
			ring._on_crit(_crit_tier)
		ring._on_arrival()
	_arrival_handled = true
	_check_done()


# ------------------------------------------------------------------- internals


func _push_tint() -> void:
	if _body != null and "tint" in _body:
		_body.set("tint", tint)


func _forward(node: Node, method: StringName, args: Array) -> void:
	if node != null and node.has_method(method):
		node.callv(method, args)


func _track(node: Node) -> void:
	if node != null and node.has_signal(&"finished"):
		_pending += 1
		node.finished.connect(_on_child_finished)


func _on_child_finished() -> void:
	_pending -= 1
	_check_done()


func _check_done() -> void:
	if not _arrival_handled or _done_emitted or _pending > 0:
		return
	_done_emitted = true
	call_deferred(&"emit_signal", &"finished")
