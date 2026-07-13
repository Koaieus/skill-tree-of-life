extends GutTest

## #152 follow-up: the Pacifist renders DP/MP with cap 0 + a nonzero surplus
## (all budget bought from unspent AP). Pin down whether the surplus reaches the
## gauge/shader at cap 0 — separating "numbers wrong" from "gauge won't draw it".

const _PANEL := preload("res://ui/hud/turn_resources_panel/turn_resources_panel.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _panel: TurnResourcesPanel
var _board: StatBoard


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	_board = _BOARD.duplicate(true) as StatBoard
	# Emulate the Pacifist state: MP cap SET to 0, current 0, but 3 surplus
	# purchased from restraint.
	var mp := _board.movement_points
	mp.base_value = 0.0
	mp.set_current(0.0)
	mp.set_surplus(3)
	await get_tree().process_frame


func _mp_gauge() -> SurplusPoolGauge:
	return _panel.get_node(^"%MPGauge") as SurplusPoolGauge


func test_surplus_reaches_the_gauge_property() -> void:
	_panel.bind(_board)
	await get_tree().process_frame
	assert_eq(_mp_gauge().surplus, 3.0, "gauge.surplus mirrors the stat's surplus bin at cap 0")


func test_surplus_reaches_the_shader_uniform() -> void:
	_panel.bind(_board)
	await get_tree().process_frame
	var mat := _mp_gauge().material as ShaderMaterial
	assert_eq(mat.get_shader_parameter(&"surplus"), 3.0, "shader `surplus` uniform pushed at cap 0")
	assert_eq(mat.get_shader_parameter(&"cell_count"), 0.0, "cap-0 pool pushes cell_count 0")
