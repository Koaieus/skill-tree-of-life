extends GutTest

## #489 — PresentationPlayer's view store, and RevealRecorder's pass-through
## mode + cause stack. RevealRecorder is static (its state outlives any one
## test), so every test that touches it must leave it clean.


func _node() -> SkillNode:
	var n := SkillNode.new()
	autofree(n)
	return n


func after_each() -> void:
	RevealRecorder.player = null
	if RevealRecorder.is_recording:
		RevealRecorder.end()


func test_play_instant_leaves_store_at_final_to_value() -> void:
	var player := PresentationPlayer.new()
	add_child_autofree(player)
	var node := _node()
	var tl := RevealTimeline.new()
	tl.append(RevealEvent.node_hp(node, 10.0, 4.0))
	tl.append(RevealEvent.node_hp(node, 4.0, 1.0))
	tl.finalize()

	player.play_instant(tl)

	assert_eq(player.shown_hp(node), 1.0)


func test_play_walks_the_wall_clock() -> void:
	var player := PresentationPlayer.new()
	add_child_autofree(player)
	var node := _node()
	var tl := RevealTimeline.new()
	var e1 := RevealEvent.node_hp(node, 10.0, 6.0)
	e1.t = 0.0
	var e2 := RevealEvent.node_hp(node, 6.0, 2.0)
	e2.t = 0.35
	tl.append(e1)
	tl.append(e2)
	tl.finalize()

	player.play(tl)
	assert_eq(player.shown_hp(node), 6.0, "after t=0 the store holds the first event's to_value")

	await wait_seconds(0.45)
	assert_eq(player.shown_hp(node), 2.0, "after the interval the store holds the second's")


func test_pass_through_applies_immediately() -> void:
	var player := PresentationPlayer.new()
	add_child_autofree(player)
	RevealRecorder.player = player
	var node := _node()

	RevealRecorder.node_hp(node, 10.0, 5.0)

	assert_false(RevealRecorder.is_recording, "no begin() was called")
	assert_eq(player.shown_hp(node), 5.0)


func test_push_cause_stamps_t_on_every_record_in_scope() -> void:
	RevealRecorder.begin(RevealTimeline.new())
	var node := _node()

	RevealRecorder.push_cause(0.8)
	RevealRecorder.node_hp(node, 1.0, 2.0)
	RevealRecorder.node_death(node)
	RevealRecorder.pop_cause()

	var tl := RevealRecorder.end()
	assert_eq(tl.events[0].t, 0.8)
	assert_eq(tl.events[1].t, 0.8, "a plain cause scope does not stagger")


func test_push_strip_scope_staggers_by_cascade_step() -> void:
	RevealRecorder.begin(RevealTimeline.new())
	var n1 := _node()
	var n2 := _node()
	var n3 := _node()

	RevealRecorder.push_strip_scope()
	RevealRecorder.node_owner_lost(n1, null)
	RevealRecorder.node_owner_lost(n2, null)
	RevealRecorder.node_owner_lost(n3, null)
	RevealRecorder.pop_strip_scope()

	var tl := RevealRecorder.end()
	assert_eq(tl.events[0].t, 0.0)
	assert_almost_eq(tl.events[1].t, RevealTimeline.CASCADE_STEP, 0.0001)
	assert_almost_eq(tl.events[2].t, RevealTimeline.CASCADE_STEP * 2.0, 0.0001)


func test_strip_scope_inherits_the_open_cause_base_t() -> void:
	RevealRecorder.begin(RevealTimeline.new())
	var n1 := _node()
	var n2 := _node()

	RevealRecorder.push_cause(1.0)
	RevealRecorder.push_strip_scope()
	RevealRecorder.node_owner_lost(n1, null)
	RevealRecorder.node_owner_lost(n2, null)
	RevealRecorder.pop_strip_scope()
	RevealRecorder.pop_cause()

	var tl := RevealRecorder.end()
	assert_eq(tl.events[0].t, 1.0)
	assert_almost_eq(tl.events[1].t, 1.0 + RevealTimeline.CASCADE_STEP, 0.0001)


func test_freed_subject_mid_timeline_does_not_crash_play() -> void:
	var player := PresentationPlayer.new()
	add_child_autofree(player)
	var node := SkillNode.new()
	var tl := RevealTimeline.new()
	var e1 := RevealEvent.node_hp(node, 10.0, 5.0)
	e1.t = 0.0
	var e2 := RevealEvent.node_hp(node, 5.0, 0.0)
	e2.t = 0.1
	tl.append(e1)
	tl.append(e2)
	tl.finalize()
	node.free()

	player.play(tl)
	await wait_seconds(0.2)

	assert_true(true, "play must not crash when a timeline outlives its subject")
