extends GutTest

## #152 UI: the ActionCluster conversion line reframes unspent AP as the surplus
## it buys next turn — `roundi(unspent_ap × ap_transfer_rate)` bonus move + dealloc,
## each tinted with its stat's colour. Shown whenever the conversion is nonzero,
## independent of the warning's enemy-visible gate.

const _CLUSTER := preload("res://ui/hud/action_cluster/action_cluster.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _cluster: ActionCluster
var _entity: Entity


func before_each() -> void:
	_cluster = _CLUSTER.instantiate()
	add_child_autofree(_cluster)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child_autofree(_entity)
	await get_tree().process_frame
	_cluster.set(&"_player", _entity)


func _label() -> RichTextLabel:
	return _cluster.get_node(^"%ConversionLabel") as RichTextLabel


func test_shows_boost_at_default_rate() -> void:
	# Default rate 2, 2 unspent AP → +4 move / +4 dealloc.
	_entity.stat_board.action_points.set_current(2.0)
	_cluster.call(&"_refresh_conversion")
	var txt := _label().text
	assert_string_contains(txt, "+4 move")
	assert_string_contains(txt, "+4 dealloc")
	assert_almost_eq(_label().modulate.a, 1.0, 0.01, "shown when boost > 0")


func test_uses_stat_tint_colors() -> void:
	_entity.stat_board.action_points.set_current(1.0)
	_cluster.call(&"_refresh_conversion")
	var mp_hex := _entity.stat_board.movement_points.definition.tint_color.to_html(false)
	var dp_hex := _entity.stat_board.deallocation_points.definition.tint_color.to_html(false)
	assert_string_contains(_label().text, mp_hex)
	assert_string_contains(_label().text, dp_hex)


func test_hidden_when_no_unspent_ap() -> void:
	_entity.stat_board.action_points.set_current(0.0)
	_cluster.call(&"_refresh_conversion")
	assert_almost_eq(_label().modulate.a, 0.0, 0.01, "no unspent AP → hidden")


func test_hidden_at_zero_rate() -> void:
	# The Berserker pole: converts nothing, so no conversion line even with AP.
	_entity.stat_board.ap_transfer_rate.base_value = 0.0
	_entity.stat_board.action_points.set_current(2.0)
	_cluster.call(&"_refresh_conversion")
	assert_almost_eq(_label().modulate.a, 0.0, 0.01, "rate 0 → nothing to show")
