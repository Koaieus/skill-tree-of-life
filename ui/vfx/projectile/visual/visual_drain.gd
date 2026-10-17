class_name VisualDrain
extends RefCounted

## The one "count tracked children, then emit the owner's `finished` one frame
## later once the count is zero" bookkeeping every composed projectile visual
## holds. Each visual keeps its own `signal finished` (the duck-typed contract
## [Projectile] awaits) and builds this with it: `VisualDrain.new(finished)`.
##
## [method track] every child that may still be playing, BEFORE any forwarded
## call that might make it emit synchronously (a zero-length fade, a
## same-frame companion) — connect after invoking and a synchronous emission
## is missed forever, since a Godot signal has no replay for a listener that
## showed up late. [method seal] once no more children are coming. The held
## signal is emitted exactly once, deferred, when sealed with nothing pending.

var _done: Signal
var _pending: int = 0
var _sealed: bool = false
var _emitted: bool = false


func _init(done: Signal) -> void:
	_done = done


## Only a child that actually exposes `finished` gates the emit — one with no
## such signal is, per the visual contract, already done the instant it's
## spawned.
func track(node: Node) -> void:
	if node == null or not node.has_signal(&"finished"):
		return
	_pending += 1
	node.connect(&"finished", _on_child_finished)


## No more children are coming: emits now if nothing is pending.
func seal() -> void:
	_sealed = true
	_check()


## Calls [param method] on [param node] only if it has one — the duck-typed
## forward every drain user also needs.
static func forward(node: Node, method: StringName, args: Array) -> void:
	if node != null and node.has_method(method):
		node.callv(method, args)


func _on_child_finished() -> void:
	_pending -= 1
	_check()


func _check() -> void:
	if not _sealed or _emitted or _pending > 0:
		return
	_emitted = true
	var owner: Object = _done.get_object()
	if not is_instance_valid(owner):
		return
	# Deferred: a same-frame completion (e.g. a body with fade_seconds == 0)
	# would otherwise emit before `Projectile._wait_for_visual_done`'s
	# `await finished` has registered, which hangs the await forever.
	owner.call_deferred(&"emit_signal", _done.get_name())
