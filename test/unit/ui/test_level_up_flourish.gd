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
##
## `min_dwell` is post-cascade presentation pacing (`LevelUpFlourish.release()`
## reads it only when the cascade drains) — not part of what these assertions
## check (ordering, counts, resets). Overriding it here, before any stamp has
## a chance to call `release()`, is the same test-only-override pattern
## sanctioned for `AIController.turn_delay` in 8917a81: it collapses an
## artificial ~2s wait per call without touching what's asserted. Scoped to
## `_settle()` alone, restored after — `test_a_single_level_still_dwells` and
## `test_rebinding_cuts_a_live_flourish` check `_open` against the SHIPPED
## `min_dwell` at a fixed wait and would break if this leaked into `before_each`.
func _settle() -> void:
	var _shipped_dwell := _flourish.min_dwell
	_flourish.min_dwell = 0.05
	for i in 60:
		await get_tree().process_frame
		await wait_seconds(0.01)
	await wait_seconds(_flourish.min_dwell + 0.2)
	_flourish.min_dwell = _shipped_dwell


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


## [b]A level's loop costs the same however many are queued behind it.[/b]
## Owner call, #320, 2026-08-24 — reversing an earlier fixed-total budget that
## made four levels take the same wall-clock as one:
##
## [i]"ideally the XP bar goes at a speed independent of how many levelups ...
## XP gain is important to witness, so we don't want to rush it. and if gaining
## 4 levels at once takes more or less twice as long as gaining 2 levels,
## that's all fine — revel in your gains a bit longer."[/i]
##
## So the property is a RATIO, not a ceiling: measure the per-level pace of a
## two-level cascade and a four-level one at the shipped gauge settings, and
## they must match. A budget that divides by the queue depth fails this.
func test_the_per_level_pace_does_not_depend_on_how_many_levels_land() -> void:
	_use_shipped_timings()
	var two := await _time_cascade(20.0, 2)   # 20 XP off a fresh board = 2 levels
	after_each()
	await before_each()
	_use_shipped_timings()
	var four := await _time_cascade(60.0, 4)  # 60 XP = 4 levels

	# Measured spread between the two is ~2% (1.300s vs 1.327s), so 15% is
	# loose enough not to flake and far tighter than any depth-scaling scheme
	# could sneak through: dividing a fixed total by the queue would put these
	# 40%+ apart.
	assert_almost_eq(four, two, two * 0.15,
			"a level costs a level, whether it is one of two or one of four")
	# The same fact stated the way the owner asked for it: four levels is twice
	# the watch time of two, not the same.
	assert_almost_eq(four * 4.0, (two * 2.0) * 2.0, two * 2.0 * 0.3,
			"four levels take about twice as long to watch as two")


## Restores the gauge to what the HUD actually ships, undoing before_each's
## fast fixture — a pacing test that ran on the fixture would measure nothing.
func _use_shipped_timings() -> void:
	_gauge.fill_speed = 0.9
	_gauge.level_up_fill_time = 0.35
	_gauge.level_up_wrap_time = 0.10
	_gauge.level_up_hold_time = 0.15


## Grant `amount`, wait for exactly `expected` beats, and return the average
## seconds per level. Fails the test if the grant did not cross that many caps.
func _time_cascade(amount: float, expected: int) -> float:
	var beats: Array[float] = []
	_track.level_reached.connect(func(_l: int): beats.append(float(Time.get_ticks_msec())))
	var started := float(Time.get_ticks_msec())
	_entity.stat_board.xp.replenish(amount)
	while beats.size() < expected and (float(Time.get_ticks_msec()) - started) < 12000.0:
		await get_tree().process_frame
	assert_eq(beats.size(), expected,
			"%s XP is exactly %d levels off a fresh board" % [amount, expected])
	if beats.size() < expected:
		return 0.0
	return ((beats[expected - 1] - started) / 1000.0) / float(expected)
