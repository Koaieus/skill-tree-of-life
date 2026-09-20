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
## cascade and counts up, released exactly once at the end, and (b) a level
## costs a level to watch, however many are queued behind it.
##
## [b]No clock in here (#981).[/b] The flourish's dwell is a schedule stepped
## with [method LevelUpFlourish.advance]; a beat is the gauge's own
## [signal PoolGauge.level_segment_held], emitted from the test rather than
## awaited off its tween; the pace is read off [method PoolGauge.fill_duration_for].
## The one real-clock run of this feature is
## `test/integration/ui/test_xp_track_real_clock.gd`. Never `await` between a
## `release()` and the `advance()` that closes it — the flourish is in the tree
## and `_process` would feed real delta into the dwell being stepped.

const _TRACK_SCENE := preload("res://ui/hud/xp_track/xp_track.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
## An input, never the shipped `@export` default.
const _DWELL := 1.0

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
	_flourish.min_dwell = _DWELL

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


## One beat at the full bar, driven at the gauge's own seam. The cap it hands
## over is what the track would have been told by the tween.
func _beat(new_max: float) -> void:
	_gauge.level_segment_held.emit(new_max)


## Grant `amount` and play every level it crossed as a beat, synchronously.
## Returns the number of levels narrated. No frame passes, so the deferred
## replay never starts a tween behind these beats.
func _cascade(amount: float) -> int:
	var seq := PoolLevelSequencer.new(float(_entity.stat_board.xp.value))
	var xp: PoolStat = _entity.stat_board.xp
	var observe := func(): seq.observe(float(xp.current), float(xp.value))
	xp.value_changed.connect(observe)
	xp.replenish(amount)
	xp.value_changed.disconnect(observe)
	var segments := seq.pending()
	for segment in segments:
		_beat(segment.new_max)
	return segments.size()


## #981 — the dwell is a schedule the test steps by hand, not a SceneTreeTimer
## only the wall clock can move.
func test_release_closes_after_min_dwell_of_stepped_delta() -> void:
	_flourish.stamp(2, 3, 1)
	_flourish.release()
	_flourish.advance(0.5 * _DWELL)
	assert_true(_flourish.is_open(), "half the dwell served: still on screen")
	_flourish.advance(0.5 * _DWELL)
	assert_false(_flourish.is_open(), "the dwell is served on delta alone: closed")


## The headline fix. Four levels in one grant produce ONE element counting to
## ×4 — never a second announcement opening behind the first.
func test_a_four_level_cascade_counts_up_on_one_flourish() -> void:
	var narrated := _cascade(200.0)
	assert_gte(narrated, 4, "four levels were narrated")
	assert_eq(_stamps.size(), narrated, "one beat per level, on one flourish")
	assert_eq(_stamps[0], "L E V E L   U P", "the first beat carries no count")
	assert_eq(_stamps[1], "L E V E L   U P  ×2")
	assert_eq(_stamps[3], "L E V E L   U P  ×4", "the fourth beat re-stamps in place")


## The SP line reads the level being NARRATED, not the entity's level — which is
## already at the end of the cascade — so the every-5th-level milestone lands on
## the beat that earned it.
func test_the_sp_total_accumulates_the_levels_actually_narrated() -> void:
	_cascade(200.0)
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
## queued. This is the property the center banner could not have: a beat never
## closes it, only the release the track sends when its queue is empty does.
func test_the_flourish_is_held_until_the_queue_drains() -> void:
	watch_signals(_flourish)
	_cascade(20.0)  # two levels
	assert_true(_flourish.is_open(), "still on screen while the cascade runs")
	_flourish.advance(_DWELL * 2.0)
	assert_true(_flourish.is_open(), "no release yet, so no amount of time closes it")
	_flourish.release()
	_flourish.advance(_DWELL)
	assert_false(_flourish.is_open(), "and it left once the queue drained")
	assert_signal_emit_count(_flourish, "closed", 1, "released exactly once")
	assert_eq(_track._cascade_stack, 0, "the count resets when it actually leaves")


## A level landing while the flourish is still on screen CONTINUES the count.
## This is the user-visible half of resetting on close rather than on release:
## reset at release and a late level makes "×4" drop back to a bare "L E V E L
## U P", which is a smaller version of the very bug this replaces.
func test_a_level_landing_during_the_dwell_keeps_counting() -> void:
	var before := _cascade(60.0)  # four levels
	_flourish.release()
	_flourish.advance(0.5 * _DWELL)
	assert_true(_flourish.is_open(), "sanity: drained, but still on screen")

	var late := _cascade(200.0)
	assert_eq(_stamps[before], "L E V E L   U P  ×%d" % (before + 1),
			"the late level continued the count instead of re-opening at ×1")
	assert_eq(_flourish_title(), "L E V E L   U P  ×%d" % (before + late),
			"and the cascade kept counting from there")
	_flourish.advance(_DWELL)
	assert_true(_flourish.is_open(), "the stamp disarmed the pending release")


## A single level still gets a readable dwell — the failure mode of a bar-local
## flourish is flashing and vanishing inside the wrap.
func test_a_single_level_still_dwells() -> void:
	_cascade(7.0)
	_flourish.release()
	_flourish.advance(_DWELL - 0.01)
	assert_true(_flourish.is_open(), "one level is not a flash")
	_flourish.advance(0.02)
	assert_false(_flourish.is_open(), "and it leaves once the dwell is served")


## Rebinding to another hero cuts the flourish rather than letting it finish
## narrating the previous hero's levels over the new one's bar (#459 hot-seat).
func test_rebinding_cuts_a_live_flourish() -> void:
	watch_signals(_flourish)
	_cascade(20.0)
	_flourish.advance(0.1)
	assert_true(_flourish.is_open(), "sanity: a cascade is on screen")
	var other := Entity.new()
	autofree(other)
	other.display_name = "Other"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(other)
	await get_tree().process_frame
	_track.bind(other)
	assert_false(_flourish.is_open(), "the previous hero's flourish is gone")
	assert_signal_emit_count(_flourish, "closed", 1, "closed once, on the cut")
	assert_eq(_track._cascade_stack, 0, "and its count with it")
	_flourish.advance(_DWELL * 2.0)
	assert_signal_emit_count(_flourish, "closed", 1, "no dwell survives the cut")
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
## So the property is a RATIO, not a ceiling: the per-level fill a two-level
## cascade and a four-level one schedule at the shipped gauge settings must
## match. The gauge is the pace owner, so the pace is read off it directly —
## no stopwatch. A budget that divides by the queue depth fails this.
func test_the_per_level_pace_does_not_depend_on_how_many_levels_land() -> void:
	var gauge := PoolGauge.new()
	autofree(gauge)
	_use_shipped_timings(gauge)
	var two := _schedule(gauge, 20.0)   # 20 XP off a fresh board = 2 levels
	var four := _schedule(gauge, 60.0)  # 60 XP = 4 levels
	assert_eq(two.size(), 2, "20 XP is exactly 2 levels off a fresh board")
	assert_eq(four.size(), 4, "60 XP is exactly 4 levels off a fresh board")
	for k in two.size():
		assert_almost_eq(four[k], two[k], 0.001,
				"level %d costs a level, whether it is one of two or one of four" % (k + 2))
	for k in four.size():
		assert_almost_eq(four[k], four[0], 0.001, "and every level in the cascade costs the same")
	# The same fact stated the way the owner asked for it: four levels is twice
	# the watch time of two, not the same.
	assert_almost_eq(_sum(four), 2.0 * _sum(two), 0.001,
			"four levels take twice as long to watch as two")


## What the HUD actually ships — a pacing read on a fixture rate would measure
## nothing.
func _use_shipped_timings(gauge: PoolGauge) -> void:
	gauge.fill_speed = 0.9
	gauge.level_up_fill_time = 0.35
	gauge.level_up_wrap_time = 0.10
	gauge.level_up_hold_time = 0.15


## The per-level fill durations `gauge` schedules for a grant of `amount` off a
## fresh board: each segment fills from empty to the cap it crossed, against
## that cap.
func _schedule(gauge: PoolGauge, amount: float) -> Array[float]:
	var board := _BOARD.duplicate(true) as EntityStatBoard
	var xp: PoolStat = board.xp
	var seq := PoolLevelSequencer.new(float(xp.value))
	xp.value_changed.connect(func(): seq.observe(float(xp.current), float(xp.value)))
	xp.replenish(amount)
	var out: Array[float] = []
	for segment in seq.pending():
		out.append(gauge.fill_duration_for(gauge.min_value, segment.fill_to, segment.fill_to))
	return out


func _sum(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total
