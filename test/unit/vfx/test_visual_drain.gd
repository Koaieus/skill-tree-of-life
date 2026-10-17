extends GutTest

## [VisualDrain]: the one "count tracked children, emit the owner's
## `finished` deferred, exactly once, after `seal()`" helper every composed
## projectile visual holds.


class OwnerVisual extends Node:
	signal finished


class Child extends Node:
	signal finished

	func finish() -> void:
		finished.emit()


var _owner: OwnerVisual
var _drain: VisualDrain
var _emits: Array = [0]


func before_each() -> void:
	_owner = OwnerVisual.new()
	add_child_autofree(_owner)
	_emits = [0]
	var emits := _emits
	_owner.finished.connect(func() -> void: emits[0] += 1)
	_drain = VisualDrain.new(_owner.finished)


func _child() -> Child:
	var c := Child.new()
	_owner.add_child(c)
	return c


func test_no_emit_before_seal() -> void:
	var c := _child()
	_drain.track(c)
	c.finish()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_emits[0], 0, "a drained count must not emit before seal()")
	_drain.seal()
	await get_tree().process_frame
	assert_eq(_emits[0], 1, "seal() on a drained count emits")


func test_no_emit_while_a_tracked_child_is_pending() -> void:
	var a := _child()
	var b := _child()
	_drain.track(a)
	_drain.track(b)
	_drain.seal()
	a.finish()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_emits[0], 0, "one child still pending gates the emit")
	b.finish()
	await get_tree().process_frame
	assert_eq(_emits[0], 1, "the last child finishing emits")


func test_a_child_without_finished_does_not_gate() -> void:
	var bare := Node.new()
	_owner.add_child(bare)
	_drain.track(bare)
	_drain.track(null)
	_drain.seal()
	await get_tree().process_frame
	assert_eq(_emits[0], 1, "a signal-less (or null) child is done the instant it is tracked")


func test_a_child_finishing_synchronously_during_tracking_is_counted() -> void:
	var a := _child()
	_drain.track(a)
	VisualDrain.forward(a, &"finish", [])
	var b := _child()
	_drain.track(b)
	_drain.seal()
	await get_tree().process_frame
	assert_eq(_emits[0], 0, "b is still pending after a's synchronous finish")
	b.finish()
	await get_tree().process_frame
	assert_eq(_emits[0], 1, "a's synchronous finish was counted, so b's completes the drain")


func test_exactly_one_emit_one_frame_later() -> void:
	var c := _child()
	_drain.track(c)
	c.finish()
	_drain.seal()
	assert_eq(_emits[0], 0, "never in the same frame as the completion")
	await get_tree().process_frame
	assert_eq(_emits[0], 1, "emitted one frame later")
	_drain.seal()
	c.finish()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_emits[0], 1, "exactly once, however often it is re-sealed or re-finished")


func test_forward_calls_only_methods_the_node_has() -> void:
	var c := _child()
	var seen := [0]
	c.finished.connect(func() -> void: seen[0] += 1)
	VisualDrain.forward(c, &"finish", [])
	VisualDrain.forward(c, &"_no_such_method", [1])
	VisualDrain.forward(null, &"finish", [])
	assert_eq(seen[0], 1, "forward calls a method the node has and skips the rest")
