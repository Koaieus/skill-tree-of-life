extends GutTest

## Status effects live panel: a one-node bench whose TurnManager is scoped to
## its own Graph and wired into its own Bearer, so ▶ Tick turn serves the
## bench's entity even with every other sandbox tab in the same tree. Drives the
## panel through its public beats and asserts on the real world it hosts.

## Loaded by path, not preloaded: a missing scene is then a failing assert,
## never a parse error GUT would skip while reporting green.
const _PANEL_PATH := "res://addons/status_sandbox/status_sandbox_panel.tscn"
const _POISON := preload("res://effects/status/poison.tres")

const SETUP_NODE := 0
const SETUP_CORE := 1
const SETUP_CORE_DRAINED := 2

var _panel


func before_each() -> void:
	var scene: PackedScene = load(_PANEL_PATH) if ResourceLoader.exists(_PANEL_PATH) else null
	assert_not_null(scene, "the status panel scene exists")
	if scene == null:
		return
	_panel = scene.instantiate()
	add_child_autofree(_panel)
	await get_tree().process_frame


func _node() -> SkillNode:
	return _panel.bench.node


func _bearer() -> Entity:
	return _panel.bench.bearer


func test_tick_serves_the_benchs_own_bearer_and_poison_ticks_the_node() -> void:
	if _panel == null:
		return
	_panel.select_setup(SETUP_NODE)
	_panel.apply_status(_POISON, 3.0)
	var hp_before: float = _node().get_current_hp()
	var turns_before: int = _bearer().turns_taken
	var log_before: String = _panel.get_log_text()

	_panel.tick_turn()

	assert_eq(_bearer().turns_taken, turns_before + 1,
			"one Tick is exactly one turn of THIS bench's Bearer — the TurnManager binding")
	assert_lt(_node().get_current_hp(), hp_before, "poison ticked node HP down")
	var gained: String = _panel.get_log_text().substr(log_before.length())
	assert_string_contains(gained, "damage", "the log gained a damage line")


func test_the_bearers_navigator_mirrors_the_authored_node() -> void:
	if _panel == null:
		return
	for i in [SETUP_NODE, SETUP_CORE, SETUP_CORE_DRAINED]:
		_panel.select_setup(i)
		assert_true(_bearer().navigator.get_mirrored_nodes().has(_node()),
				"setup %d: scene-authored ownership reaches the mirror" % i)
		assert_eq(_node().owned_by, _bearer(), "setup %d: the node is the Bearer's" % i)


func test_drained_core_lands_the_status_on_the_entity() -> void:
	if _panel == null:
		return
	_panel.select_setup(SETUP_CORE_DRAINED)
	assert_eq(_bearer().core_location, _node(), "the node is the core")
	assert_almost_eq(_node().get_current_hp(), 0.0, 0.001, "node HP authored drained")
	assert_almost_eq(_bearer().stat_board.health.current, float(_bearer().stat_board.health.value),
			0.001, "entity HP full")

	_panel.apply_status(_POISON, 2.0)

	assert_almost_eq(_bearer().get_combat().get_status_power(&"poison"), 2.0, 0.001,
			"the hit fell through the cracked core onto the entity")
	assert_almost_eq(_node().get_combat().get_status_power(&"poison"), 0.0, 0.001)


func test_resistance_slider_scales_the_next_apply() -> void:
	if _panel == null:
		return
	_panel.select_setup(SETUP_NODE)
	_panel.set_resistance(&"poison_resistance", 0.5)
	assert_almost_eq(float(_bearer().stat_board.get_value(&"poison_resistance")), 0.5, 0.001)

	_panel.apply_status(_POISON, 4.0)

	assert_almost_eq(_node().get_combat().get_status_power(&"poison"), 2.0, 0.001,
			"landed through the real hit path: power × (1 − resistance)")


func test_reset_rearms_a_fresh_bench_that_still_ticks() -> void:
	if _panel == null:
		return
	_panel.select_setup(SETUP_NODE)
	_panel.apply_status(_POISON, 3.0)
	var old_bench: Node = _panel.bench

	_panel.reset()

	assert_false(is_instance_valid(old_bench), "the old bench is gone, not left ticking")
	assert_almost_eq(_node().get_combat().get_status_power(&"poison"), 0.0, 0.001, "fresh node")
	var turns_before: int = _bearer().turns_taken
	_panel.tick_turn()
	assert_eq(_bearer().turns_taken, turns_before + 1, "the new bench's clock is bound too")
