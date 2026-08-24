extends GutTest

## #320 — the level-up announcement moved onto the XP bar.
##
## The bug it replaces: the center banner ran a fixed 1.8s timeline while a
## level segment takes ~1.1-1.35s, so a four-level cascade stamped "×2", slid
## out while levels 3 and 4 were still landing, and opened a SECOND banner
## behind it — "×2, twice" instead of "×4", in the most valuable real estate on
## screen. The fix is structural, not a longer hold: only the thing holding the
## replay queue can know a cascade is still going, and that is [XpTrack].
##
## So the two properties worth pinning are (a) one flourish spans the whole
## cascade and counts up, released exactly once at the end, and (b) the whole
## replay fits in the couple of seconds a player will actually watch.

const _TRACK_SCENE := preload("res://ui/hud/xp_track/xp_track.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _track: XpTrack
var _entity: Entity
var _gauge: PoolGauge
var _flourish: LevelUpFlourish
## One entry per beat: what the flourish read at that moment.
var _stamps: Array[String] = []


func before_each() -> void:
	_track = _TRACK_SCENE.instantiate() as XpTrack
	_track.custom_minimum_size = Vector2(800, 52)
	add_child_autofree(_track)
	await get_tree().process_frame

	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Leveller"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(_entity)
	await get_tree().process_frame

	_gauge = _track.get_node("%XPGauge") as PoolGauge
	_flourish = _track.get_node("%LevelUpFlourish") as LevelUpFlourish
	# Fixed, fast timings — the ORDER and the counting are what's under test
	# here, not the wall clock. The budget is measured separately, against the
	# shipped rate-based gauge.
	_gauge.fill_speed = 0.0
	_gauge.level_up_fill_time = 0.05
	_gauge.level_up_wrap_time = 0.02
	_gauge.level_up_hold_time = 0.02

	_stamps = []
	_track.bind(_entity)
	# `level_reached` fires immediately after the stamp, so it is the beat's
	# own moment to read the flourish at.
	_track.level_reached.connect(func(_l: int): _stamps.append(_flourish_title()))


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.get_parent().remove_child(_entity)


func _flourish_title() -> String:
	return (_flourish.get_node("%Title") as Label).text


## Runs the replay to completion AND past the flourish's dwell — the count
## resets when the flourish has actually left, not when the queue drained, so
## `min_dwell` is real wall-clock time this has to cover.
func _settle() -> void:
	for i in 60:
		await get_tree().process_frame
		await wait_seconds(0.01)
	await wait_seconds(_flourish.min_dwell + 0.2)


## The headline fix. Four levels in one grant produce ONE element counting to
## ×4 — never a second announcement opening behind the first.
func test_a_four_level_cascade_counts_up_on_one_flourish() -> void:
	_entity.stat_board.xp.replenish(200.0)
	await _settle()
	assert_gte(_stamps.size(), 4, "four levels were narrated")
	assert_eq(_stamps[0], "L E V E L   U P", "the first beat carries no count")
	assert_eq(_stamps[1], "L E V E L   U P  ×2")
	assert_eq(_stamps[3], "L E V E L   U P  ×4", "the fourth beat re-stamps in place")


## The SP line reads the level being NARRATED, not the entity's level — which is
## already at the end of the cascade — so the every-5th-level milestone lands on
## the beat that earned it.
func test_the_sp_total_accumulates_the_levels_actually_narrated() -> void:
	_entity.stat_board.xp.replenish(200.0)
	await _settle()
	# The cascade starts at level 1, so the levels narrated are 2..(1 + beats).
	var final_level := 1 + _stamps.size()
	var expected := 0
	var milestones := 0
	for lvl in range(2, final_level + 1):
		expected += _entity.sp_minted_for_level(lvl)
		if lvl % Entity.MILESTONE_LEVEL_INTERVAL == 0:
			milestones += 1
	assert_gt(milestones, 0, "sanity: the cascade crossed at least one milestone")
	var detail := (_flourish.get_node("%Detail") as Label).text
	assert_eq(detail, "+%d SP — LEVEL %d" % [expected, final_level],
			"each milestone is counted for ITS level, not for the final one")
	# The whole point: a flat per-level rate would MISS the milestone bonuses.
	var flat := _entity.sp_minted_for_level(2) * _stamps.size()
	assert_eq(expected, flat + milestones, "and that is a real difference")


## Released once, at the drain — not per beat, and not while levels are still
## queued. This is the property the center banner could not have.
func test_the_flourish_is_held_until_the_queue_drains() -> void:
	_entity.stat_board.xp.replenish(200.0)
	# Mid-cascade: at least one beat played and more are still queued.
	await wait_seconds(0.12)
	assert_true(_flourish._open, "still on screen while the cascade runs")
	await _settle()
	assert_false(_flourish.is_open(), "and it left once the queue drained")
	assert_eq(_track._cascade_stack, 0, "the count resets when it actually leaves")


## A level landing while the flourish is still on screen CONTINUES the count.
## This is the user-visible half of resetting on close rather than on release:
## reset at release and a late level makes "×4" drop back to a bare "L E V E L
## U P", which is a smaller version of the very bug this replaces.
func test_a_level_landing_during_the_dwell_keeps_counting() -> void:
	_entity.stat_board.xp.replenish(60.0)  # four levels
	# Wait for the queue to drain, then act INSIDE the dwell — polling on the
	# beats rather than sleeping a guessed interval, which would race the dwell.
	while _stamps.size() < 4:
		await get_tree().process_frame
	assert_true(_flourish.is_open(), "sanity: drained, but still on screen")
	var before := _stamps.size()

	_entity.stat_board.xp.replenish(200.0)
	while _stamps.size() == before:
		await get_tree().process_frame
	assert_eq(_flourish_title(), "L E V E L   U P  ×%d" % (before + 1),
			"the late level continued the count instead of re-opening at ×1")


## A single level still gets a readable dwell — the failure mode of a bar-local
## flourish is flashing and vanishing inside the wrap.
func test_a_single_level_still_dwells() -> void:
	_entity.stat_board.xp.replenish(7.0)
	await wait_seconds(0.25)
	assert_true(_flourish._open, "one level is not a flash")


## Rebinding to another hero cuts the flourish rather than letting it finish
## narrating the previous hero's levels over the new one's bar (#459 hot-seat).
func test_rebinding_cuts_a_live_flourish() -> void:
	_entity.stat_board.xp.replenish(200.0)
	await wait_seconds(0.12)
	assert_true(_flourish._open, "sanity: a cascade is on screen")
	var other := Entity.new()
	autofree(other)
	other.display_name = "Other"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(other)
	await get_tree().process_frame
	_track.bind(other)
	assert_false(_flourish._open, "the previous hero's flourish is gone")
	assert_eq(_track._cascade_stack, 0, "and its count with it")
	other.get_parent().remove_child(other)


## [b]The ≤2s requirement, measured end to end against the SHIPPED gauge.[/b]
## Every other test here fixes the timings fast so it can assert on ordering,
## which means none of them ever executes the compression path — and the first
## implementation of the budget shipped a cascade that ran 3.3s and
## DECELERATED (0.45 → 0.60 → 0.90 → 1.35), because it divided the budget by
## the shrinking count of remaining levels without ever spending it down. This
## is the test that fails on that.
func test_a_four_level_cascade_fits_the_budget_at_shipped_timings() -> void:
	# Undo before_each's fast fixture: this one is about the wall clock.
	_gauge.fill_speed = 0.9
	_gauge.level_up_fill_time = 0.35
	_gauge.level_up_wrap_time = 0.10
	_gauge.level_up_hold_time = 0.15

	var beats: Array[float] = []
	_track.level_reached.connect(func(_l: int): beats.append(float(Time.get_ticks_msec())))
	var started := float(Time.get_ticks_msec())
	_entity.stat_board.xp.replenish(60.0)  # four levels in one grant
	# Wait on the WALL CLOCK, not on a frame count: a headless frame is not a
	# real one, and an over-budget cascade must be given room to finish so the
	# failure reads as "too slow" rather than "never happened".
	while beats.size() < 4 and (float(Time.get_ticks_msec()) - started) < 6000.0:
		await get_tree().process_frame
	assert_gte(beats.size(), 4, "four levels were narrated")
	var elapsed: float = (beats[3] - started) / 1000.0
	assert_lt(elapsed, 2.0, "the whole cascade fits the budget a player will watch")
	# ...and it does NOT decelerate: the last gap must not dwarf the first.
	var first_gap: float = beats[1] - beats[0]
	var last_gap: float = beats[3] - beats[2]
	assert_lt(last_gap, first_gap * 2.0,
			"the replay stays even instead of dragging out on the final level")


## The pacing half: a segment handed a budget fits inside it, while a segment
## with no budget keeps the rate-derived duration that makes a gain's SIZE
## legible (#320's constant-rate fills). One level is under budget anyway, so
## the common case is untouched by construction.
func test_a_budget_compresses_a_segment_but_never_below_the_floor() -> void:
	var g := PoolGauge.new()
	autofree(g)
	add_child(g)
	g.fill_speed = 0.9
	g.min_value = 0.0
	g.max_value = 10.0
	g.current = 0.0
	await get_tree().process_frame

	var held: Array[float] = [0.0]
	g.fill_finished.connect(func(): held[0] = float(Time.get_ticks_msec()))
	var started := float(Time.get_ticks_msec())
	g.play_level_segment(10.0, 20.0, 0.45)
	for i in 200:
		await get_tree().process_frame
		if held[0] > 0.0:
			break
	assert_gt(held[0], 0.0, "the segment finished")
	var elapsed: float = (held[0] - started) / 1000.0
	assert_lt(elapsed, 0.75, "a full-bar sweep compressed into its budget")
	assert_gte(elapsed, PoolGauge.MIN_SEGMENT_TIME - 0.05,
			"but never below the floor that keeps the beat visible")
