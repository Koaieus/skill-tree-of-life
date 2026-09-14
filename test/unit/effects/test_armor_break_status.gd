extends GutTest

## [ArmorBreakStatus] (#877, hub #868): a MULTIPLY on node-local `armor`,
## value `1.0 - power`, `power` itself the fraction removed. `reapply =
## ACCUMULATE` makes repeated hits additive on that fraction so five 20% hits
## reach exactly ×0 armor (never a compounding `(1-0.2)^5`), and
## `decay_per_tick` recovers it linearly. Same shape as Blindness (#873) on a
## different stat — including the shadow-isolation rule: a static modifier is
## SHARED between a live board and its clone, so a def must replace, never
## mutate, the found modifier (run knowledge on hub #868, 2026-09-14).

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
	_entity.stat_board.get_stat(&"armor").base_value = 200.0

	_def = ArmorBreakStatus.new()
	_def.id = &"armor_break"
	_def.power_max = 1.0
	_def.decay_per_tick = 0.25
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
	for m in s.bins.multipliers:
		if m is ArmorBreakStatus.ArmorBreakModifier:
			out.append(m)
	return out


# ── Numbers ──────────────────────────────────────────────────────────────────

func test_five_hits_of_0_2_break_armor_to_zero_then_caps() -> void:
	assert_almost_eq(_armor(), 200.0, 0.001, "baseline: no break yet")
	for _i in 5:
		_combat().apply_status(_def, 0.2)
	assert_almost_eq(_armor(), 0.0, 0.001, "5 x 20% removes all armor")
	_combat().apply_status(_def, 0.2)  # a 6th hit
	assert_almost_eq(_armor(), 0.0, 0.001, "capped at power_max, armor stays 0")
	assert_almost_eq(_combat().get_status_power(&"armor_break"), 1.0, 0.001,
			"power capped at power_max, never overshoots")


func test_accumulate_is_additive_on_the_fraction_not_compounding() -> void:
	# The issue's own arithmetic: two 20% hits leave 60% armor (200*0.6=120),
	# never (1-0.2)^2 = 64% (128) — ACCUMULATE adds fractions, it never
	# multiplies remaining multipliers together.
	_combat().apply_status(_def, 0.2)
	_combat().apply_status(_def, 0.2)
	assert_almost_eq(_armor(), 120.0, 0.001, "additive 40% removed, not compounded")


func test_recovery_over_four_ticks_restores_armor_and_strips_the_modifier() -> void:
	for _i in 5:
		_combat().apply_status(_def, 0.2)
	assert_almost_eq(_armor(), 0.0, 0.001)
	var expected: Array[float] = [50.0, 100.0, 150.0, 200.0]
	for step in expected.size():
		_combat().tick_statuses()
		assert_almost_eq(_armor(), expected[step], 0.001, "tick %d" % (step + 1))
	assert_eq(_armor_modifiers().size(), 0, "no armor-break modifier remains once fully recovered")
	assert_almost_eq(_combat().get_status_power(&"armor_break"), 0.0, 0.001,
			"status gone after full recovery")


func test_physical_damage_mitigates_less_as_armor_breaks() -> void:
	var raw := DamageInstance.new()
	raw.amount = 50.0
	raw.type = DamageInstance.Type.PHYSICAL
	assert_almost_eq(Mitigation.apply(raw, _nodes[0]), 3.0, 0.001,
			"full armor floors the hit at min_damage_taken (3)")
	for _i in 5:
		_combat().apply_status(_def, 0.2)
	assert_almost_eq(_armor(), 0.0, 0.001)
	assert_almost_eq(Mitigation.apply(raw, _nodes[0]), 50.0, 0.001,
			"no armor left: the full raw hit lands")


func test_power_max_above_one_is_rejected() -> void:
	_def.power_max = 1.5
	_combat().apply_status(_def, 0.2)
	assert_push_error("ArmorBreakStatus: power_max must be <= 1.0")
	assert_almost_eq(_armor(), 200.0, 0.001, "rejected def: no armor multiplier is planted")
	assert_eq(_armor_modifiers().size(), 0)


# ── Shadow isolation (run knowledge from hub #868, same rule as Blindness) ───

func test_shadow_apply_never_writes_the_live_modifier() -> void:
	_combat().apply_status(_def, 0.2)
	var live_mods := _armor_modifiers()
	assert_eq(live_mods.size(), 1)
	if live_mods.is_empty():
		return
	var live_value: float = live_mods[0].value

	var shadow_world := _entity.get_combat().snapshot()
	_shadows.append(shadow_world)
	var shadow := shadow_world.shadow_for(_nodes[0])
	shadow.apply_status(_def, 1.0)

	assert_almost_eq(float(shadow.get_local_value(&"armor")), 0.0, 0.01,
			"the shadow reads the fully-broken value")
	assert_almost_eq(live_mods[0].value, live_value, 0.001,
			"the live modifier instance is untouched by the shadow resolve")
	assert_almost_eq(_armor(), 160.0, 0.01, "live world unchanged (still one 20% hit)")


# ── Authored content loads and is wired (values are the owner's knobs) ──────

func test_authored_armor_break_and_sunder_load_and_are_in_the_debug_book() -> void:
	var a_break := load("res://effects/status/armor_break.tres") as ArmorBreakStatus
	assert_not_null(a_break, "armor_break.tres is an ArmorBreakStatus")
	if a_break == null:
		return
	assert_eq(a_break.id, &"armor_break")
	assert_true(&"debuff" in a_break.tags, "tagged as a debuff")
	assert_lte(a_break.power_max, 1.0, "power_max stays a legal fraction (<=1.0)")

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
