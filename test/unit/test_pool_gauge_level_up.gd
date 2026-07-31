extends GutTest

## PoolGauge level-up animation (#154). On an XP level-up the pool edits its
## current/max three times in one frame (fill to cap → grow cap → reset to the
## overflow), which used to collapse into a single downward jump. play_level_up
## replays it over time as fill → wrap-to-empty → fill, so the bar visibly rises
## to full before starting the new level.

const _MATERIAL := "res://ui/gauges/pool_gauge_material.tres"

var _gauge: PoolGauge


func before_each() -> void:
	_gauge = PoolGauge.new()
	_gauge.custom_minimum_size = Vector2(120, 12)
	_gauge.size = Vector2(120, 12)
	# Fast timings keep the test quick while preserving ordering.
	_gauge.level_up_fill_time = 0.1
	_gauge.level_up_wrap_time = 0.04
	add_child_autofree(_gauge)
	await get_tree().process_frame


func _fraction() -> float:
	return _gauge.current / _gauge.max_value if _gauge.max_value > 0.0 else 0.0


## Level up from 3/5 (0.6) to a new level that started at 2/10 (0.2). The bar
## must rise to ~full first, not jump straight down to 0.2.
func test_level_up_rises_to_full_before_settling_low() -> void:
	_gauge.max_value = 5.0
	_gauge.current = 3.0
	_gauge.play_level_up(3.0, 5.0, 2.0, 10.0)

	# Sample across the whole animation, tracking the peak fill fraction.
	var peak := 0.0
	for i in 24:
		await get_tree().process_frame
		await wait_seconds(0.02)
		peak = max(peak, _fraction())

	assert_gt(peak, 0.95, "the bar must fill to (near) full during the level-up")

	# And it must settle on the new level's state, not the old.
	assert_almost_eq(_gauge.current, 2.0, 0.05, "settles at the new current")
	assert_almost_eq(_gauge.max_value, 10.0, 0.05, "settles at the grown cap")
	assert_almost_eq(_fraction(), 0.2, 0.02, "final fill is the overflow fraction")


# ── animate_to (#317) — the everyday move, formerly a hard cut ────────────────

func test_a_gain_is_tweened_not_snapped() -> void:
	_gauge.max_value = 10.0
	_gauge.current = 2.0
	_gauge.animate_to(8.0, 10.0)
	await get_tree().process_frame
	await wait_seconds(0.03)
	assert_between(_gauge.current, 2.0, 8.0, "caught mid-rise")
	await wait_seconds(0.15)
	assert_almost_eq(_gauge.current, 8.0, 0.05, "and arrives")


## Losses deliberately keep the old behaviour: `current` snaps and the ghost
## (`drain_from`) is what animates, so a wound still reads as a fading trail.
## Tweening the fill down under `_suppress_drain` would silently delete it.
func test_a_loss_snaps_and_leaves_a_drain_trail() -> void:
	_gauge.max_value = 10.0
	_gauge.current = 8.0
	await get_tree().process_frame
	_gauge.animate_to(3.0, 10.0)
	assert_eq(_gauge.current, 3.0, "the fill snaps to the loss immediately")
	assert_gt(_gauge.drain_from, 3.0, "the ghost stays behind to fade")


func test_fill_finished_fires_once_per_call_even_with_nothing_to_do() -> void:
	# NB: an `int` local would be captured BY VALUE by the lambda and never
	# observed here — count into a reference type.
	var fires: Array[int] = []
	_gauge.fill_finished.connect(func(): fires.append(1))
	_gauge.max_value = 10.0
	_gauge.current = 5.0
	_gauge.animate_to(5.0, 10.0)  # already there
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(fires.size(), 1, "a no-op move still reports done, deferred, exactly once")


# ── fill_speed (#320) — constant rate, so the SIZE of a gain is readable ──────
#
# Under a flat duration a 2%-of-bar tick and a 60% gain both take the same third
# of a second, so the big one reads as a snap to full and the animation carries
# no information. Rate mode makes duration proportional to distance.

func test_a_bigger_gain_takes_proportionally_longer() -> void:
	_gauge.fill_speed = 1.0  # a full sweep per second
	_gauge.min_fill_time = 0.0
	_gauge.max_fill_time = 4.0
	_gauge.min_value = 0.0
	assert_almost_eq(_gauge._fill_duration(0.0, 10.0, 10.0), 1.0, 0.001, "full sweep")
	assert_almost_eq(_gauge._fill_duration(0.0, 1.0, 10.0), 0.1, 0.001, "a tenth of the bar, a tenth of the time")
	assert_almost_eq(_gauge._fill_duration(4.0, 6.0, 10.0), 0.2, 0.001, "measured on the distance, not the target")


func test_the_clamps_keep_a_sliver_visible_and_a_sweep_finite() -> void:
	_gauge.fill_speed = 1.0
	_gauge.min_fill_time = 0.12
	_gauge.max_fill_time = 0.5
	assert_eq(_gauge._fill_duration(0.0, 0.01, 10.0), 0.12, "a sliver still reads as motion")
	assert_eq(_gauge._fill_duration(0.0, 10.0, 10.0), 0.5, "and a full sweep still ends")


## Feedback bars (health, mana) deliberately stay on the flat duration.
func test_fill_speed_zero_keeps_the_flat_duration() -> void:
	_gauge.fill_speed = 0.0
	_gauge.level_up_fill_time = 0.35
	assert_eq(_gauge._fill_duration(0.0, 10.0, 10.0), 0.35)
	assert_eq(_gauge._fill_duration(0.0, 0.1, 10.0), 0.35, "flat means flat, distance ignored")


## The reported case: 2/5 + 5 XP crosses the cap, so it runs through
## `play_level_segment` — the path a flat duration made "shoot to full". Sampling
## mid-fill is the only honest check that the climb is gradual.
func test_a_levelling_fill_climbs_gradually_rather_than_snapping() -> void:
	_gauge.fill_speed = 0.9
	_gauge.min_fill_time = 0.12
	_gauge.max_fill_time = 1.1
	_gauge.max_value = 5.0
	_gauge.current = 2.0
	await get_tree().process_frame
	_gauge.play_level_segment(5.0, 10.0)
	# 3/5 of the bar at 0.9 bar/s ≈ 0.67s, so a tenth of a second in we should be
	# nowhere near the top — under the old flat 0.35s cubic we'd be past 80%.
	await wait_seconds(0.1)
	var early := _gauge.current
	assert_lt(early, 4.0, "a tenth of a second in, still climbing (not snapped to full)")
	assert_gt(early, 2.0, "but moving")
	for i in 40:
		await get_tree().process_frame
		await wait_seconds(0.02)
	assert_eq(_gauge.max_value, 10.0, "and the segment still completes")


func test_a_level_segment_beats_at_full_then_wraps() -> void:
	_gauge.max_value = 5.0
	_gauge.current = 3.0
	var held_at: Array[float] = []
	_gauge.level_segment_held.connect(func(new_max: float):
		# The bar must be FULL at the old cap when the beat lands — that is the
		# instant the badge bumps and the LEVEL UP banner fires.
		held_at.append(_gauge.current / _gauge.max_value)
		held_at.append(new_max))
	_gauge.play_level_segment(5.0, 10.0)
	for i in 30:
		await get_tree().process_frame
		await wait_seconds(0.01)
	assert_almost_eq(held_at[0], 1.0, 0.02, "beat lands on a full bar")
	assert_eq(held_at[1], 10.0, "carrying the cap the next level opens with")
	assert_eq(_gauge.max_value, 10.0, "cap grew")
	assert_almost_eq(_gauge.current, 0.0, 0.05, "and the bar wrapped to empty")
