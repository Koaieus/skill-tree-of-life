extends GutTest

## The ONE real-clock run of the XP track (#981 keeper). Everything the track,
## gauge and flourish do is asserted at their seams in
## `test/unit/ui/test_xp_track_level_sequence.gd` and
## `test/unit/ui/test_level_up_flourish.gd` with no clock at all; this script
## is the single proof that the chain actually plays end to end when the
## tweens and `_process` drive it — a two-level cascade with a passive grant
## landing mid-replay opens the flourish, dwells, closes with the final SP
## total, and the bar settles on the pool's live value.
##
## Generous budget, no pacing assert: the pace is `PoolGauge.fill_duration_for`,
## read in the unit tier.

const _TRACK_SCENE := preload("res://ui/hud/xp_track/xp_track.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _track: XpTrack
var _entity: Entity
var _gauge: PoolGauge
var _flourish: LevelUpFlourish
var _levels: Array[int] = []
var _opened: bool = false


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
	# Inputs, not the shipped defaults: fast enough to fit the budget with room.
	_gauge.fill_speed = 0.0
	_gauge.level_up_fill_time = 0.05
	_gauge.level_up_wrap_time = 0.02
	_gauge.level_up_hold_time = 0.02
	_flourish.min_dwell = 0.3

	_levels = []
	_opened = false
	_track.bind(_entity)
	_track.level_reached.connect(func(l: int):
		_levels.append(l)
		_opened = _opened or _flourish.is_open())


func after_each() -> void:
	if is_instance_valid(_entity):
		_entity.get_parent().remove_child(_entity)


func test_a_two_level_cascade_plays_out_on_the_real_clock() -> void:
	watch_signals(_flourish)
	_entity.stat_board.xp.replenish(20.0)  # 2 levels off a fresh board: 5 → 10 → 15
	await wait_until(func(): return _levels.size() >= 1, 10.0)
	assert_eq(_levels, [2] as Array[int], "the first beat landed")
	# Passive income lands mid-replay; it must be in the settle, not swallowed.
	_entity.stat_board.xp.replenish(2.0)
	await wait_until(func(): return not _flourish.is_open() and _levels.size() >= 2, 10.0)

	assert_eq(_levels, [2, 3] as Array[int], "one beat per level, in order")
	assert_true(_opened, "the flourish was on screen at the beats")
	assert_false(_flourish.is_open(), "and left once the dwell was served")
	assert_signal_emit_count(_flourish, "closed", 1, "closed exactly once")
	var expected_sp := _entity.sp_minted_for_level(2) + _entity.sp_minted_for_level(3)
	assert_eq((_flourish.get_node("%Detail") as Label).text,
			"+%d SP — LEVEL 3" % expected_sp, "the final SP total, on the last level")
	assert_eq((_track.get_node("%LevelLabel") as Label).text, "LEVEL 3", "the readout caught up")

	await wait_until(func(): return is_equal_approx(_gauge.current, float(_entity.stat_board.xp.current)), 10.0)
	assert_almost_eq(_gauge.max_value, 15.0, 0.01, "settled on the final cap")
	assert_almost_eq(_gauge.current, float(_entity.stat_board.xp.current), 0.05,
			"the bar settles on the pool's LIVE value, including the interrupt")
	assert_almost_eq(_gauge.current, 7.0, 0.05, "20 + 2 XP over caps 5 and 10 carries 7 (sanity)")
