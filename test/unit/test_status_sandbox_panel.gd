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
var _decoy


## A second panel enters the tree FIRST, as another live tab does in the
## sandbox host: its TurnManager is then the group's first (what an unwired
## Bearer would bind to) and its Bearer ticks on the same initiative (what an
## unscoped clock would serve). Every assert below runs in that shared tree.
func before_each() -> void:
	var scene: PackedScene = load(_PANEL_PATH) if ResourceLoader.exists(_PANEL_PATH) else null
	assert_not_null(scene, "the status panel scene exists")
	if scene == null:
		return
	_decoy = scene.instantiate()
	add_child_autofree(_decoy)
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


func test_a_foreign_bearer_nearer_its_turn_is_not_served_by_this_clock() -> void:
	if _panel == null:
		return
	_panel.select_setup(SETUP_NODE)
	var pool: PoolStat = _decoy.bench.bearer.stat_board.initiative
	pool.set_current(float(pool.value) * 0.99)
	var turns_before: int = _bearer().turns_taken

	_panel.tick_turn()

	assert_eq(_panel.bench.turn_manager.current_entity, _bearer(),
			"the clock is scoped to this bench's Graph — the other tab's Bearer crosses first and is ignored")
	assert_eq(_bearer().turns_taken, turns_before + 1)


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

	assert_almost_eq(_node().get_combat().get_status_power(&"poison"), 4.0, 0.001,
			"landed through the real hit path: the row stays raw")
	assert_almost_eq(_node().get_combat().effective_status_power(_POISON, 4.0), 2.0, 0.001,
			"the host filters it at effect time: 4 − ⌈2 − ½⌉")


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


## The bench's pinned fan unit by name (EffectReadout / NodeStats / Core).
func _fan_unit(unit_name: StringName) -> FanUnit:
	for n in _panel.bench.find_child("Fan", true, false).find_children("*", "FanUnit", true, false):
		if n.name == unit_name:
			return n as FanUnit
	return null


func _status_rows(unit: FanUnit) -> int:
	return unit.find_children("*", "StatusRow", true, false).size()


## The drained-core setup is left out: its status falls through to the Bearer
## entity host, and EFFECTS lists only the node's own status state by design —
## the entity's rows belong to the Core panel.
func test_an_applied_status_shows_in_the_pinned_effects_panel() -> void:
	if _panel == null:
		return
	for i in [SETUP_NODE, SETUP_CORE]:
		_panel.select_setup(i)
		var unit := _fan_unit(&"EffectReadout")
		assert_not_null(unit, "setup %d: the bench pins an EffectReadout unit" % i)
		if unit == null:
			continue
		_panel.apply_status(_POISON, 2.0)
		assert_true(unit.participating, "setup %d: a landed status makes EFFECTS participate" % i)
		assert_eq(_status_rows(unit), 1, "setup %d: EFFECTS lists the one landed status" % i)
