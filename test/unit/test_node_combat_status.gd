extends GutTest

## NodeCombat's status slice (#872, state only): apply / tick / remove /
## clear / read, plus the shadow clone. The acceptance list on the issue,
## one test each. Turn-start ticking and dealloc clearing are #879's wiring
## and are NOT exercised here — `tick_statuses()` is called by hand.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## A StatusDef that journals every hook call so a test can read the sequence.
class SpyDef:
	extends StatusDef
	var ticks: Array = []        # [before, after] pairs
	var applied: Array = []      # powers
	var removed: int = 0
	## Optional: id of ANOTHER status to remove from inside `_on_tick`.
	var remove_on_tick: StringName = &""

	func _on_applied(_node: NodeCombat, power: float) -> void:
		applied.append(power)

	func _on_tick(node: NodeCombat, before: float, after: float) -> void:
		ticks.append([before, after])
		if remove_on_tick != &"":
			node.remove_status(remove_on_tick)

	func _on_removed(_node: NodeCombat) -> void:
		removed += 1


var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Defender"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	_entity.core_location = _node
	await get_tree().process_frame


func after_each() -> void:
	for s in _shadows:
		s.free_shadow()


func _def(id: StringName, power_max: float, decay: float = 1.0,
		reapply := StatusDef.Reapply.REFRESH) -> SpyDef:
	var d := SpyDef.new()
	d.id = id
	d.display_name = String(id).capitalize()
	d.power_max = power_max
	d.decay_per_tick = decay
	d.reapply = reapply
	return d


func _combat() -> NodeCombat:
	return _node.get_combat()


# ── Apply ────────────────────────────────────────────────────────────────────

func test_accumulate_stacks_and_clamps_at_power_max() -> void:
	var d := _def(&"poison", 3.0, 1.0, StatusDef.Reapply.ACCUMULATE)
	_combat().apply_status(d, 2.0)
	_combat().apply_status(d, 2.0)
	assert_eq(_combat().get_status_power(&"poison"), 3.0, "2 + 2 clamps at power_max 3")


func test_refresh_keeps_the_larger_power_instead_of_stacking() -> void:
	var d := _def(&"blind", 3.0, 1.0, StatusDef.Reapply.REFRESH)
	_combat().apply_status(d, 2.0)
	_combat().apply_status(d, 2.0)
	assert_eq(_combat().get_status_power(&"blind"), 2.0, "REFRESH twin stays at 2")
	_combat().apply_status(d, 1.0)
	assert_eq(_combat().get_status_power(&"blind"), 2.0, "a weaker re-apply never lowers power")


func test_apply_fires_on_applied_with_the_resulting_power() -> void:
	var d := _def(&"poison", 3.0, 1.0, StatusDef.Reapply.ACCUMULATE)
	_combat().apply_status(d, 2.0)
	_combat().apply_status(d, 2.0)
	assert_eq(d.applied, [2.0, 3.0])


func test_apply_on_an_unallocated_node_is_a_no_op() -> void:
	var loose := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(loose)
	var d := _def(&"poison", 3.0)
	loose.get_combat().apply_status(d, 2.0)
	assert_eq(loose.get_combat().get_status_power(&"poison"), 0.0)
	assert_true(loose.get_combat().get_statuses().is_empty(), "a CLEAR def never lands on nothing")
	assert_eq(d.applied.size(), 0, "_on_applied must not fire either")


func test_non_positive_power_or_null_def_is_ignored() -> void:
	_combat().apply_status(null, 2.0)
	_combat().apply_status(_def(&"poison", 3.0), 0.0)
	assert_true(_combat().get_statuses().is_empty())


# ── Tick ─────────────────────────────────────────────────────────────────────

func test_tick_decays_flat_then_removes_at_zero_with_one_on_removed() -> void:
	var d := _def(&"poison", 3.0, 1.0)
	_combat().apply_status(d, 3.0)
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"poison"), 2.0)
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"poison"), 1.0)
	_combat().tick_statuses()
	assert_eq(_combat().get_status_power(&"poison"), 0.0)
	assert_true(_combat().get_statuses().is_empty(), "removed at <= 0")
	assert_eq(d.removed, 1, "_on_removed exactly once")
	assert_eq(d.ticks, [[3.0, 2.0], [2.0, 1.0], [1.0, 0.0]], "_on_tick sees before/after each tick")
	_combat().tick_statuses()
	assert_eq(d.removed, 1, "a tick on an empty slice fires nothing")


func test_on_tick_removing_a_sibling_mid_tick_neither_crashes_nor_skips() -> void:
	# Insertion order: a, b, c. `a` yanks `c` from inside its tick; `b` yanks
	# `a` (already visited) — both a not-yet-visited and an already-visited
	# vanishing must be tolerated, and `b` must still be ticked.
	var a := _def(&"a", 3.0)
	var b := _def(&"b", 3.0)
	var c := _def(&"c", 3.0)
	a.remove_on_tick = &"c"
	b.remove_on_tick = &"a"
	_combat().apply_status(a, 3.0)
	_combat().apply_status(b, 3.0)
	_combat().apply_status(c, 3.0)
	_combat().tick_statuses()
	assert_eq(a.ticks.size(), 1, "a ticked")
	assert_eq(b.ticks.size(), 1, "b ticked despite a sibling vanishing")
	assert_eq(c.ticks.size(), 0, "c vanished before its tick and was not ticked")
	assert_eq(c.removed, 1)
	assert_eq(a.removed, 1)
	assert_eq(_combat().get_status_power(&"a"), 0.0, "a was removed mid-tick, not decayed back in")
	assert_eq(_combat().get_status_power(&"b"), 2.0)
	assert_eq(_combat().get_statuses().size(), 1)


func test_on_tick_clearing_everything_mid_tick_is_tolerated() -> void:
	var a := _def(&"a", 3.0)
	var b := _def(&"b", 3.0)
	_combat().apply_status(a, 3.0)
	_combat().apply_status(b, 3.0)
	# Simulate the kill cascade: the node's slice is wiped from inside a tick.
	a.remove_on_tick = &"a"
	_combat().tick_statuses()
	assert_eq(a.removed, 1, "self-removal from inside _on_tick is honoured once")
	assert_eq(_combat().get_status_power(&"a"), 0.0)
	assert_eq(b.ticks.size(), 1)


# ── Remove / clear / read ────────────────────────────────────────────────────

func test_remove_status_fires_on_removed_once_and_ignores_unknown_ids() -> void:
	var d := _def(&"poison", 3.0)
	_combat().apply_status(d, 1.0)
	_combat().remove_status(&"poison")
	_combat().remove_status(&"poison")
	_combat().remove_status(&"nope")
	assert_eq(d.removed, 1)


func test_clear_statuses_removes_all_with_hooks() -> void:
	var a := _def(&"a", 3.0)
	var b := _def(&"b", 3.0)
	_combat().apply_status(a, 1.0)
	_combat().apply_status(b, 1.0)
	_combat().clear_statuses()
	assert_true(_combat().get_statuses().is_empty())
	assert_eq(a.removed, 1)
	assert_eq(b.removed, 1)


func test_get_statuses_rows_carry_display_identity_and_normalised_power() -> void:
	var d := _def(&"poison", 4.0)
	d.tint = Color.GREEN
	_combat().apply_status(d, 1.0)
	var rows := _combat().get_statuses()
	assert_eq(rows.size(), 1)
	var row := rows[0]
	assert_eq(row.def, d)
	assert_eq(row.def.display_name, "Poison")
	assert_eq(row.def.tint, Color.GREEN)
	assert_null(row.def.icon)
	assert_eq(row.power, 1.0)
	assert_almost_eq(row.normalised(), 0.25, 0.0001)


# ── Shadow ───────────────────────────────────────────────────────────────────

func _shadow_node() -> NodeCombat:
	var shadow := _entity.get_combat().snapshot()
	_shadows.append(shadow)
	return shadow.shadow_for(_node)


func test_snapshot_carries_the_slice_and_stays_detached() -> void:
	var d := _def(&"poison", 3.0)
	_combat().apply_status(d, 3.0)
	var shadow := _shadow_node()
	assert_eq(shadow.get_status_power(&"poison"), 3.0, "the clone carries the slice")
	shadow.tick_statuses()
	shadow.apply_status(_def(&"blind", 2.0), 2.0)
	assert_eq(shadow.get_status_power(&"poison"), 2.0)
	assert_eq(_combat().get_status_power(&"poison"), 3.0, "host untouched by a shadow tick")
	assert_eq(_combat().get_status_power(&"blind"), 0.0, "host untouched by a shadow apply")
	assert_eq(_combat().get_statuses().size(), 1)
	shadow.clear_statuses()
	assert_eq(_combat().get_statuses().size(), 1, "host untouched by a shadow clear")
