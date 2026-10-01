extends GutTest

## [ArmorBreakStatus] (#877, flat since #1308): an additive `armor` modifier of
## `-power` on the node, `power` a stack count (one stack = -1 armor), uncapped
## and free to push armor below zero (Mitigation then raises the hit). `reapply
## = ACCUMULATE` makes repeated hits add stacks and a flat `decay` recovers
## them. Same shape as Blindness (#873) on a different stat — including the
## shadow-isolation rule: a static modifier is SHARED between a live board and
## its clone, so a def must replace, never mutate, the found modifier.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _def: ArmorBreakStatus
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Sundered"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = "N0"
	_graph.skill_nodes_container.add_child(sn)
	_nodes = [sn]
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]
	_entity.stat_board.get_stat(&"armor").base_value = 5.0

	_def = ArmorBreakStatus.new()
	_def.id = &"armor_break"
	_def.power_max = 0.0
	_def.decay = FlatDecay.new(1.0)
	_def.reapply = StatusDef.Reapply.ACCUMULATE


func after_each() -> void:
	for sh in _shadows:
		sh.free_shadow()


func _combat() -> NodeCombat:
	return _nodes[0].get_combat()


func _armor() -> float:
	return float(_nodes[0].get_local_value(&"armor"))


func _armor_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var s: Stat = _nodes[0].node_board.get_stat(&"armor") if _nodes[0].node_board != null else null
	if s == null:
		return out
	for m in s._modifiers:
		if m is ArmorBreakStatus.ArmorBreakModifier:
			out.append(m)
	return out


# ── Numbers ──────────────────────────────────────────────────────────────────

func test_three_stacks_on_armor_five_leave_two() -> void:
	assert_almost_eq(_armor(), 5.0, 0.001, "baseline: no break yet")
	_combat().apply_status(_def, 3.0)
	assert_almost_eq(_armor(), 2.0, 0.001, "-1 armor per stack")
	assert_eq(_armor_modifiers().size(), 1)


func test_accumulate_adds_stacks_uncapped_and_armor_goes_negative() -> void:
	for _i in 10:
		_combat().apply_status(_def, 1.0)
	assert_almost_eq(_armor(), -5.0, 0.001, "10 stacks on armor 5 -> -5, no floor at zero")
	assert_almost_eq(_combat().get_status_power(&"armor_break"), 10.0, 0.001, "uncapped")


func test_recovery_one_stack_per_tick_restores_armor_and_strips_the_modifier() -> void:
	_combat().apply_status(_def, 3.0)
	var expected: Array[float] = [3.0, 4.0, 5.0]
	for step in expected.size():
		_combat().tick_statuses()
		assert_almost_eq(_armor(), expected[step], 0.001, "tick %d" % (step + 1))
	assert_eq(_armor_modifiers().size(), 0, "no armor-break modifier remains once fully recovered")
	assert_almost_eq(_combat().get_status_power(&"armor_break"), 0.0, 0.001,
			"status gone after full recovery")


func test_removing_the_status_restores_armor() -> void:
	_combat().apply_status(_def, 3.0)
	_combat().remove_status(&"armor_break")
	assert_almost_eq(_armor(), 5.0, 0.001)
	assert_eq(_armor_modifiers().size(), 0)


func test_negative_armor_raises_a_raw_one_hit_above_the_floor() -> void:
	_entity.stat_board.get_stat(&"armor").base_value = 0.0
	_entity.stat_board.get_stat(&"min_damage_taken").base_value = 3.0
	var raw := DamageInstance.new()
	raw.amount = 1.0
	raw.type = DamageInstance.Type.PHYSICAL
	assert_almost_eq(Mitigation.apply(raw, _nodes[0]), 3.0, 0.001, "unbroken: floored at min_damage_taken")
	_combat().apply_status(_def, 10.0)
	assert_almost_eq(_armor(), -10.0, 0.001)
	assert_almost_eq(Mitigation.apply(raw, _nodes[0]), 11.0, 0.001, "raw 1 - (-10) = 11")


# ── Shadow isolation (run knowledge from hub #868, same rule as Blindness) ───

func test_shadow_apply_never_writes_the_live_modifier() -> void:
	_combat().apply_status(_def, 1.0)
	var live_mods := _armor_modifiers()
	assert_eq(live_mods.size(), 1)
	if live_mods.is_empty():
		return
	var live_value: float = live_mods[0].value

	var shadow_world := _entity.get_combat().snapshot()
	_shadows.append(shadow_world)
	var shadow := shadow_world.shadow_for(_nodes[0])
	shadow.apply_status(_def, 5.0)

	assert_almost_eq(float(shadow.get_local_value(&"armor")), -1.0, 0.01,
			"the shadow reads its own 6-stack value (1 live + 5)")
	assert_almost_eq(live_mods[0].value, live_value, 0.001,
			"the live modifier instance is untouched by the shadow resolve")
	assert_almost_eq(_armor(), 4.0, 0.01, "live world unchanged (still one stack)")


# ── Authored content loads and is wired (values are the owner's knobs) ──────

func test_authored_armor_break_and_sunder_load_and_are_in_the_debug_book() -> void:
	var a_break := load("res://effects/status/armor_break.tres") as ArmorBreakStatus
	assert_not_null(a_break, "armor_break.tres is an ArmorBreakStatus")
	if a_break == null:
		return
	assert_eq(a_break.id, &"armor_break")
	assert_true(&"debuff" in a_break.tags, "tagged as a debuff")
	assert_eq(a_break.power_max, 0.0, "uncapped (#962)")

	var sunder := load("res://attack/spell/defs/sunder.tres") as SpellDef
	assert_not_null(sunder, "sunder.tres is a SpellDef")
	if sunder == null:
		return
	var applier: ApplyStatusEffect = null
	var has_damage := false
	for fx in sunder.on_hit_effects:
		if fx is ApplyStatusEffect:
			applier = fx
		elif fx is DamageEffect:
			has_damage = true
	assert_true(has_damage, "sunder also deals a little damage")
	assert_not_null(applier, "sunder composes an ApplyStatusEffect")
	if applier != null:
		assert_eq(applier.def, a_break, "…that applies the authored Armor Break def")
		assert_gt(applier.power, 0.0)

	var book := load("res://entity/spellbook_debug.tres") as SpellBook
	assert_true(sunder in book.spells, "sunder is in the debug spellbook")
