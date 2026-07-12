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
