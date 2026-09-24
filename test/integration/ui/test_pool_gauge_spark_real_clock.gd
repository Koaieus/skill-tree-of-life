extends GutTest

## The ONE real-clock run of the segment sweep (#1065, #882). Every timing
## assert lives in `test/unit/ui/test_pool_gauge_spark.gd`, stepped through
## each gauge's [TweenClock] in manual mode; this script is the single proof
## that GaugeSpark's tweens still settle when the real frame loop drives them
## — production leaves `clock.manual` false, so nothing here flips it.

const _PANEL := preload("res://ui/hud/turn_resources_panel/turn_resources_panel.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _panel: TurnResourcesPanel
var _board: EntityStatBoard


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	_board = _BOARD.duplicate(true) as EntityStatBoard
	await get_tree().process_frame


func _mp_gauge() -> SurplusPoolGauge:
	return _panel.get_node(^"%MPGauge") as SurplusPoolGauge


func _sp_bar() -> CompositeBarGauge:
	return _panel.get_node(^"%SPBar") as CompositeBarGauge


func test_mp_spend_settles_on_the_real_clock() -> void:
	var mp := _board.movement_points
	mp.base_value = 5.0
	mp.set_current(5.0)
	_panel.bind(_board)
	var gauge := _mp_gauge()
	gauge.cell_step_time = 0.05
	await get_tree().process_frame

	mp.set_current(1.0)
	var settled := func() -> bool:
		return gauge.clock.live_count() == 0 and absf(gauge.shown_current - 1.0) < 0.01
	assert_true(await wait_until(settled, 15.0),
			"a spend settles the display at the new value with no tween left running")


func test_sp_spend_settles_on_the_real_clock() -> void:
	var sp := _board.skill_points
	sp.base_value = 10.0
	sp.set_current(6.0)
	_panel.bind(_board)
	var bar := _sp_bar()
	bar.cell_step_time = 0.05
	await get_tree().process_frame

	sp.spend(1)
	var settled := func() -> bool:
		return bar.clock.live_count() == 0 and absf(bar.shown_fractions.x - 0.5) < 0.001
	assert_true(await wait_until(settled, 15.0),
			"an SP spend settles the run at the new fraction with no tween left running")
