@tool
class_name CycloneRingFlash
extends Node2D

## Cyclone's closing gesture (#710): the ring the storm just closed, lit AS a
## ring. One front runs the whole loop in the walk's own rotation over a fixed
## [member lap_seconds], and each edge lingers and fades from its own completion.
##
## [b]A composition of kit primitives, not a new primitive.[/b] N [EdgeEnergize]
## children laid on the N ring edges, all on [constant
## EdgeEnergize.SHARED_MATERIAL] — so this is one batch, and paint-on-top /
## width-tracks-zoom / fog-oblivious are inherited rather than re-decided. There
## is no new shader and no per-instance uniform anywhere in this file.
## [ResonatorEdgeVisual] is the precedent for a spell-specific composition that
## is deliberately NOT catalogued (`docs/domain/spell-vfx-kit.md`): the API here
## is a plain polyline of node positions with nothing Cyclone-specific in it, so
## promoting it when a second spell has a ring to light is a rename plus a
## gallery entry.
##
## [b]One lap, whatever the ring's length[/b] (owner, 2026-09-03). A 3-ring and a
## 20-ring both take [member lap_seconds]; per-edge speed would give a 20-ring a
## ~7-beat gesture that stacks with the next closure. Simultaneous flash of all N
## was rejected — it loses the "it circulates" read, and #663 D3's Cyclone
## identity is motion.
##
## [b]Stateless, once per event.[/b] Uncapped revisits (b98a2ca) mean a triangle
## can close every beat; each closing landing simply re-runs the lap, which reads
## as a continuously spinning ring. Nothing here remembers a ring across events —
## that would be the parallel view store `.claude/rules/presentation-clock.md`
## forbids, and escalation-on-repeat would have to be resolver-stamped instead.
## Simultaneous closures stack on purpose: several rings closing in one beat each
## get their own lap, and a shared edge simply adds up.
##
## [b]The concurrency bound is linger[/b], the [EdgeEnergize] precedent:
## `ring_size * EdgeEnergize.max_live_overlays(lap_seconds + linger, beat)`.
##
## Visual contract (see [Projectile]):
##   inbound  — `_on_context(entry)`, `_on_launch()`, `_on_progress(t)`,
##              `_on_crit(tier)`, `_on_arrival()`
##   outbound — [signal finished]

signal finished

## Shortest polyline that is a ring at all. Matches [constant
## CycloneStep.MIN_RING] in spirit, but stated as the geometric floor this
## visual needs: two nodes have one edge and a wraparound onto the same edge.
const MIN_RING_NODES: int = 3

@export var edge_energize_scene: PackedScene = preload("res://ui/vfx/projectile/visual/edge_energize.tscn")

## How long ONE lap of the whole ring takes, regardless of how many edges it
## has. Roughly a beat at the shipped tempo; the owner tunes it live.
@export_range(0.05, 4.0, 0.05) var lap_seconds: float = 0.4

## Caster identity colour, stamped by the coordinator after `launch()` exactly
## as every bolt's is, and forwarded to every child (they all carry it).
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_tint()

var _edges: Array[Node2D] = []
var _lap: float = 0.0
var _arrived: bool = false
var _crit_tier: int = 0
var _pending: int = 0
var _done_emitted: bool = false


# ---------------------------------------------------------------- duck contract


## Builds the ring. Read duck-typed off the entry rather than through a typed
## parameter, the whole-kit convention — a visual handed a shape it does not
## read must keep working.
##
## The children are built HERE and not at `_ready` because the ring only exists
## on the entry; `_on_context` runs at visual instantiation, before `_on_launch`,
## so they are in place for the first frame either way.
func _on_context(entry: Variant) -> void:
	if not _edges.is_empty() or edge_energize_scene == null:
		return
	var ring: Array = _read_ring(entry)
	if ring.size() < MIN_RING_NODES:
		return
	for k in ring.size():
		# `ring[-1] → ring[0]` is the edge the closer just crossed, i.e. the Nth
		# edge of the loop and not a seam to skip — which is exactly what the
		# modulo says.
		var from_node: Node2D = ring[k]
		var to_node: Node2D = ring[(k + 1) % ring.size()]
		_add_edge(from_node.global_position, to_node.global_position)
	_push_tint()


## The flight is the wind-up: nothing moves before the beat, so the ring ignites
## at the same instant as the closing bolt's [ImpactRing].
func _on_launch() -> void:
	for edge in _edges:
		edge.call(&"_on_launch")


func _on_progress(_t: float) -> void:
	pass


func _on_crit(tier: int) -> void:
	# Held as well as forwarded: `_on_context` may not have built the children
	# yet when a crit arrives, and the closing hop always IS a crit.
	_crit_tier = maxi(_crit_tier, tier)
	for edge in _edges:
		edge.call(&"_on_crit", tier)


## Starts the lap. One tween drives a single scalar, and every edge reads its own
## front off it — a per-edge tween would be N tweens racing one clock.
func _on_arrival() -> void:
	if _arrived:
		return
	_arrived = true
	if _edges.is_empty():
		_emit_finished()
		return
	var tween := create_tween()
	tween.tween_method(_set_lap, 0.0, 1.0, maxf(0.001, lap_seconds))
	tween.tween_callback(_set_lap.bind(1.0))


# ------------------------------------------------------------------- internals


## The lap position of edge `k`, given the whole-ring progress `p`. Edge 0 runs
## over the first 1/N of the lap, edge 1 over the next, and so on — which is
## what makes the front travel in walk order rather than all N igniting at once.
static func edge_front(p: float, k: int, count: int) -> float:
	if count <= 0:
		return 0.0
	return clampf(p * float(count) - float(k), 0.0, 1.0)


func _set_lap(p: float) -> void:
	_lap = p
	var count: int = _edges.size()
	for k in count:
		var edge: Node2D = _edges[k]
		var front: float = edge_front(p, k, count)
		edge.call(&"set_front", front)
		# The moment its front completes, the child runs its OWN arrival — so
		# each edge lingers and fades from where it finished, not from where the
		# lap did. `_on_arrival` is idempotent on EdgeEnergize (`_done_emitted`),
		# which is what lets this be called from every tween step.
		if front >= 1.0:
			edge.call(&"_on_arrival")


func _add_edge(from_pos: Vector2, to_pos: Vector2) -> void:
	var edge: Node2D = edge_energize_scene.instantiate() as Node2D
	if edge == null:
		return
	# `_place()` writes `position`/`rotation` in PARENT space, and this node's
	# parent is the (zero-length, but still transformed) Projectile — top_level
	# is what keeps every overlay laid on its real edge in WORLD space. Same
	# reason ResonatorEdgeVisual sets it.
	edge.top_level = true
	add_child(edge)
	# AFTER add_child: `edge_origin`/`edge_target` are world positions, and a
	# `global_position` read on a node not yet in the tree is the silent
	# writes-`position` trap (`.claude/rules/gdscript-pitfalls.md`).
	edge.set(&"edge_origin", from_pos)
	edge.set(&"edge_target", to_pos)
	if _crit_tier > 0:
		edge.call(&"_on_crit", _crit_tier)
	_edges.append(edge)
	if edge.has_signal(&"finished"):
		_pending += 1
		edge.connect(&"finished", _on_child_finished)


## The ring off a [ScheduleEntry]-shaped context, guarded at every step: the
## entry may be null, may not carry an event, and the event may predate the
## field. Returns an untyped [Array] so a test can stand in with a literal.
func _read_ring(entry: Variant) -> Array:
	var ring: Variant = null
	if entry is Dictionary:
		ring = (entry as Dictionary).get(&"closed_ring")
	elif entry is Object:
		var obj: Object = entry
		# A ScheduleEntry wraps the event; a bare event (or a test's stand-in)
		# carries the field itself.
		var holder: Object = obj
		if &"event" in obj:
			var wrapped: Variant = obj.get(&"event")
			if not (wrapped is Object):
				return []
			holder = wrapped
		if &"closed_ring" in holder:
			ring = holder.get(&"closed_ring")
	if not (ring is Array):
		return []
	var out: Array = []
	for n in (ring as Array):
		if n is Node2D:
			out.append(n)
	return out


func _push_tint() -> void:
	for edge in _edges:
		if "tint" in edge:
			edge.set(&"tint", tint)


func _on_child_finished() -> void:
	_pending -= 1
	if _pending <= 0:
		_emit_finished()


func _emit_finished() -> void:
	if _done_emitted:
		return
	_done_emitted = true
	call_deferred(&"emit_signal", &"finished")
