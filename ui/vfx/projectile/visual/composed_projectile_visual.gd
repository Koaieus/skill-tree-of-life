@tool
class_name ComposedProjectileVisual
extends Node2D

## Composes a flying [member body_scene] with zero or more
## [member arrival_companions] (#671/#672) — the shape a per-spell visual
## needs whenever it wants BOTH a travelling body (a [BoltBody] config) AND
## the crit-grammar ring ([ImpactRing]) or another one-shot arrival effect
## (Bruiser's dust puff), since a [Projectile]'s [member Projectile.visual_scene]
## slot only takes ONE scene per verb.
##
## [b]Why arrival companions are instantiated at [method _on_arrival], not
## authored as static children.[/b] [ImpactRing]'s own `_ready()` autoplays
## unless its DIRECT parent is a [Projectile] — a guard this wrapper would
## silently defeat if the ring sat one level deeper in the tree, firing a
## full flight early. Spawning it only once arrival actually happens sidesteps
## the guard instead of relying on it.
##
## Forwards the full duck-typed visual contract (see [Projectile]) to
## [member body_scene] for the whole flight, and to each arrival companion at
## the moment it is spawned. This wrapper's own [signal finished] fires once
## every child that owns one has fired its own — deferred, so a body whose
## fade is already zero-length (an immediate, same-frame `finished`) does not
## race the caller's `await` that starts listening right after
## `_on_arrival()` returns.

signal finished

## The flight body — a [BoltBody] config (or anything sharing its duck
## contract). Instantiated once, up front, and lives for the whole flight.
@export var body_scene: PackedScene

## Spawned only at [method _on_arrival], in order — [ImpactRing] for the crit
## grammar, plus any one-shot (Bruiser's dust puff). Each receives the latest
## `_on_context` entry and `_on_crit` tier before its own `_on_arrival`.
@export var arrival_companions: Array[PackedScene] = []

## Whether a crit reaches [member body_scene]'s own `_on_crit` (the
## retint-and-swell half [BoltBody] owns). Default true is the shared #670
## behaviour; Bruiser (#672) sets this false because its body "must not read
## as lethal" even on a crit — only its [ImpactRing] companion may escalate.
## Companions always receive the crit tier regardless of this flag.
@export var forward_crit_to_body: bool = true

## The caster's identity colour, stamped by the coordinator right after
## `Projectile.launch` exactly as it is on a bare [BoltBody] — this wrapper sits
## BETWEEN the projectile and the body, so without forwarding it the stamp would
## land here and stop, and every composed spell would render neutral-white while
## an uncomposed one tinted correctly.
##
## Forwarded to [member body_scene] only, never to the arrival companions:
## identity is carried by the flying body (#663 D3/D4), while [ImpactRing] is
## crit-grammar punctuation whose colour is its own tier ladder. Tinting the ring
## with the caster colour would make "where it fired" read as identity instead of
## as placement.
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_push_tint()

## How much of the wave the arc this projectile draws is carrying (#708),
## stamped by the coordinator right after `launch` exactly as [member tint] is —
## and forwarded down for exactly the same reason: this wrapper sits BETWEEN the
## projectile and the body, so a stamp that stopped here would be invisible in
## the composed case every spell uses.
##
## Body only, never the arrival companions: a weak offshoot must still punctuate
## at full strength, and dimming an [ImpactRing] by its arc's share would undo
## the crit grammar #709 just gave this spell.
@export var arc_weight: float = 1.0:
	set(value):
		arc_weight = value
		_push_arc_weight()

var _body: Node
var _pending: int = 0
var _arrival_handled: bool = false
var _done_emitted: bool = false
var _context: Variant = null
var _crit_tier: int = 0


func _ready() -> void:
	# `@tool` is the house convention for every visual in this directory, so it
	# stays — but this is the only one that SPAWNS A CHILD, and an unowned
	# `add_child` from a tool script shows up as a phantom node the moment a
	# per-spell scene is opened in the editor (and can be offered for saving
	# into the `.tscn`). The other primitives only draw themselves, which is why
	# none of them needs this guard.
	#
	# It must be `is_edited`, NOT `Engine.is_editor_hint()`: the latter is
	# process-wide, so it also swallows the throwaway instances a live sandbox
	# tab spawns at runtime — which is how every wrapped spell rendered its
	# impact rings and NO projectile body in the VFX playground (#663).
	if VfxEditorScene.is_edited(self):
		return
	if body_scene == null:
		return
	_body = body_scene.instantiate()
	add_child(_body)
	# The setter may have run before `_ready` (an authored value, or a stamp
	# that beat instantiation), when there was no body to push onto yet.
	_push_tint()
	_push_arc_weight()


func _on_launch() -> void:
	_forward(_body, &"_on_launch", [])


func _on_progress(t: float) -> void:
	_forward(_body, &"_on_progress", [t])


func _on_context(entry: Variant) -> void:
	_context = entry
	_forward(_body, &"_on_context", [entry])


func _on_crit(tier: int) -> void:
	_crit_tier = tier
	if forward_crit_to_body:
		_forward(_body, &"_on_crit", [tier])


func _on_arrival() -> void:
	# `_track` connects `finished` BEFORE any forwarded call that might emit
	# it synchronously (a zero-length fade, a same-frame companion) — connect
	# after invoking and a synchronous emission is missed forever, since a
	# Godot signal has no replay for a listener that showed up late.
	_track(_body)
	_forward(_body, &"_on_arrival", [])
	for scene in arrival_companions:
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		add_child(node)
		_track(node)
		if _context != null:
			_forward(node, &"_on_context", [_context])
		if _crit_tier > 0:
			_forward(node, &"_on_crit", [_crit_tier])
		_forward(node, &"_on_arrival", [])
	_arrival_handled = true
	_check_done()


func _push_tint() -> void:
	if _body != null and "tint" in _body:
		_body.set("tint", tint)


func _push_arc_weight() -> void:
	if _body != null and "arc_weight" in _body:
		_body.set("arc_weight", arc_weight)



func _forward(node: Node, method: StringName, args: Array) -> void:
	if node != null and node.has_method(method):
		node.callv(method, args)


## Only children that actually expose `finished` gate this wrapper's own
## signal — a companion with no such signal is, per the visual contract,
## already done the instant it's spawned.
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
	# Deferred: a same-frame completion (e.g. a body with fade_seconds == 0)
	# would otherwise emit before `Projectile._wait_for_visual_done`'s
	# `await finished` has registered, which hangs the await forever.
	call_deferred(&"emit_signal", &"finished")
