@tool
class_name HealingBeamOrbVisual
extends Node2D

## #675 body treatment — composes P1-`Soft` ([BoltBody] via `bolt_soft.tscn`)
## with arrival companions (a P2 ring in `IN` mode), the same body+ring shape
## [ComposedProjectileVisual] gives every other spell.
##
## [b]Deliberately does NOT expose a `tint` property[/b] — the coordinator's
## caster-identity stamp (#663 D4) is `if "tint" in v: v.set("tint", ...)`;
## a visual with no such field is documented to be silently skipped, and
## that is exactly the behaviour this spell needs. #675's whole tactical
## point is that Healing Beam's `PropagationConfig` carries **no filter at
## all**, so it heals hostile nodes too — the art must be honest about that
## by making an orb flying into a hostile node look IDENTICAL to one flying
## into a friendly node. Tinting the body by caster colour ("whose spell is
## this") would leak exactly the ownership signal the mechanic itself
## doesn't carry, so the body is pinned to [constant Emissive.NEUTRAL] —
## the Arcane Terminal off-white — always, never gold, never the caster's
## hue.
##
## The arrival ring is the one place #663 D5's crit-heal gold exception
## lives (a caller configures [member ImpactRing.crit_color] on the
## companion scene, same as every other spell's crit colour choice) —
## never here, and never by tinting the orb.

signal finished

const BODY_SCENE: PackedScene = preload("res://ui/vfx/projectile/visual/bolt_soft.tscn")

## Spawned only at [method _on_arrival] — [ImpactRing]'s own `_ready()`
## autoplays unless its direct parent is a [Projectile], so spawning here
## (one level deeper) sidesteps that guard instead of relying on it, exactly
## as [ComposedProjectileVisual] does.
@export var arrival_companions: Array[PackedScene] = []

var _body: BoltBody
var _pending: int = 0
var _arrival_handled: bool = false
var _done_emitted: bool = false
var _context: Variant = null
var _crit_tier: int = 0


func _ready() -> void:
	if VfxEditorScene.is_edited(self):
		return
	_body = BODY_SCENE.instantiate()
	add_child(_body)
	# Keep the body's own authored ALPHA (bolt_soft.tscn's alpha-led 0.55) —
	# only the hue is pinned, so "alpha-soft" survives being forced neutral.
	var neutral: Color = Emissive.NEUTRAL
	_body.tint = Color(neutral.r, neutral.g, neutral.b, _body.tint.a)


func _on_launch() -> void:
	_forward(_body, &"_on_launch", [])


func _on_progress(t: float) -> void:
	_forward(_body, &"_on_progress", [t])


func _on_context(entry: Variant) -> void:
	_context = entry
	_forward(_body, &"_on_context", [entry])


func _on_crit(tier: int) -> void:
	# The body never escalates on a crit — only the arrival ring carries
	# #663 D5's gold exception, and it must do so on arrival, not in flight,
	# so a crit heal's orb still reads identical friend/foe right up to the
	# moment it lands.
	_crit_tier = tier


func _on_arrival() -> void:
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
	# Deferred, matching [ComposedProjectileVisual]: a same-frame completion
	# would otherwise emit before `Projectile._wait_for_visual_done`'s
	# `await finished` has registered.
	call_deferred(&"emit_signal", &"finished")
