extends GutTest

## #489 — RevealTimeline.finalize() must be a STABLE sort by `t`. This is the
## death-ordering fix: equal-`t` events are causally ordered by record order
## (a node's HP change, then its death, then its owner loss), and an unstable
## sort silently reintroduces the bug.


func _node() -> SkillNode:
	var n := SkillNode.new()
	autofree(n)
	return n


func test_finalize_sorts_by_t() -> void:
	var node := _node()
	var tl := RevealTimeline.new()
	var e_mid := RevealEvent.node_hp(node, 0.0, 1.0)
	e_mid.t = 0.5
	var e_first := RevealEvent.node_hp(node, 1.0, 2.0)
	e_first.t = 0.0
	var e_last := RevealEvent.node_hp(node, 2.0, 3.0)
	e_last.t = 0.7

	tl.append(e_mid)
	tl.append(e_first)
	tl.append(e_last)
	tl.finalize()

	assert_eq(tl.events, [e_first, e_mid, e_last])


func test_finalize_keeps_record_order_for_equal_t() -> void:
	var node := _node()
	var tl := RevealTimeline.new()
	var recorded: Array[RevealEvent] = []
	for i in 5:
		var e := RevealEvent.node_hp(node, float(i), float(i) + 1.0)
		e.t = 0.8
		recorded.append(e)
		tl.append(e)

	tl.finalize()

	assert_eq(tl.events, recorded, "equal-t events must keep record (insertion) order")


func test_duration_is_the_max_t() -> void:
	var node := _node()
	var tl := RevealTimeline.new()
	tl.append(RevealEvent.node_hp(node, 0.0, 1.0))
	var late := RevealEvent.node_hp(node, 1.0, 2.0)
	late.t = 1.2
	tl.append(late)

	assert_eq(tl.duration(), 1.2)
