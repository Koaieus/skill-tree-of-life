extends GutTest

## [CurseStatus] (#965, hub #952): one node-local `ADD_BASE` on
## `min_damage_taken`, `value == power` — every stack raises the floor a hit
## lands at by 1. Deals nothing itself; halving decay, uncapped; a bunker's
## negative floor is pushed toward (and past) zero, so the heal flip goes
## away under enough stacks. Same shadow-isolation rule as ArmorBreak /
## Blindness: the def is stateless, the handle is FOUND and REPLACED, never
## edited in place — a static modifier is shared between a live board and
## its shadow clone.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _nodes: Array[SkillNode]
var _def: CurseStatus
var _shadows: Array[EntityCombat] = []


func before_each() -> void:
	_shadows = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.display_name = "Hexed"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)

	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = "N0"
	_graph.skill_nodes_container.add_child(sn)
	_nodes = [sn]
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]
	# Fixture, not the authored defaults: armor 100 soaks any small hit, so
	# every PHYSICAL hit below lands exactly at the floor.
	_entity.stat_board.get_stat(&"armor").base_value = 100.0
	_entity.stat_board.get_stat(&"min_damage_taken").base_value = 3.0

	# Hand-built: the owner tunes curse.tres.
	_def = CurseStatus.new()
	_def.id = &"curse"
	_def.tags = [&"debuff"]
	_def.power_max = 0.0  # uncapped
	_def.decay_mode = StatusDef.DecayMode.FRACTION
	_def.decay_per_tick = 0.5
	_def.reapply = StatusDef.Reapply.ACCUMULATE


func after_each() -> void:
	for sh in _shadows:
		sh.free_shadow()


func _combat() -> NodeCombat:
	return _nodes[0].get_combat()


func _floor() -> float:
	return float(_nodes[0].get_local_value(&"min_damage_taken"))


func _hit(amount: float, type: DamageInstance.Type = DamageInstance.Type.PHYSICAL) -> DamageInstance:
	var raw := DamageInstance.new()
	raw.amount = amount
	raw.type = type
	return raw


func _curse_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var s: Stat = _nodes[0].node_board.get_stat(&"min_damage_taken") if _nodes[0].node_board != null else null
	if s == null:
		return out
	# ADD_BASE folds into a scalar bin; the handle only lives in the stat's
	# applied list (same walk the stat-board visualizer does).
	for m in s._modifiers:
		if m is CurseStatus.CurseModifier:
			out.append(m)
	return out


# ── Numbers (acceptance 1) ──────────────────────────────────────────────────

func test_ten_stacks_raise_the_floor_by_ten_then_halve_then_clear() -> void:
	assert_almost_eq(_floor(), 3.0, 0.001, "baseline floor")
	assert_almost_eq(Mitigation.apply(_hit(1.0), _nodes[0]), 3.0, 0.001, "baseline: 1 dmg at armor 100 lands at the floor")
	_combat().apply_status(_def, 10.0)
	assert_almost_eq(_floor(), 13.0, 0.001, "10 stacks: floor 3 + 10")
	assert_almost_eq(Mitigation.apply(_hit(1.0), _nodes[0]), 13.0, 0.001, "1-damage hit takes 13")
	assert_eq(_curse_modifiers().size(), 1, "exactly one curse modifier planted")

	_combat().tick_statuses()
	assert_almost_eq(_combat().get_status_power(&"curse"), 5.0, 0.001, "halving decay: 10 -> 5")
	assert_almost_eq(Mitigation.apply(_hit(1.0), _nodes[0]), 8.0, 0.001, "after one tick (5 stacks) the hit takes 8")
	assert_eq(_curse_modifiers().size(), 1, "re-plant replaces, never stacks a second modifier")

	# 5 -> 2.5 -> 1.25 -> 0 (tail below 1 is cut): three more ticks clear the row.
	for _i in 3:
		_combat().tick_statuses()
	assert_almost_eq(_combat().get_status_power(&"curse"), 0.0, 0.001, "row cleared")
	assert_almost_eq(_floor(), 3.0, 0.001, "floor reads 3 again")
	assert_eq(_curse_modifiers().size(), 0, "modifier gone once the row clears")


func test_stacks_accumulate_across_applications() -> void:
	_combat().apply_status(_def, 4.0)
	_combat().apply_status(_def, 6.0)
	assert_almost_eq(_combat().get_status_power(&"curse"), 10.0, 0.001, "ACCUMULATE, uncapped")
	assert_almost_eq(_floor(), 13.0, 0.001)
	assert_eq(_curse_modifiers().size(), 1)


func test_curse_deals_no_damage_itself() -> void:
	_combat().apply_status(_def, 10.0)
	var hp_before := _combat().get_current_hp()
	_combat().tick_statuses()
	assert_almost_eq(_combat().get_current_hp(), hp_before, 0.001, "a tick costs no hp")
	assert_almost_eq(_def.projected_damage(_combat(), 10.0), 0.0, 0.001, "projects 0 damage")


# ── Bunker (acceptance 2) ───────────────────────────────────────────────────

func test_bunker_floor_minus_five_takes_five_at_ten_stacks_and_still_heals_at_four() -> void:
	_entity.stat_board.get_stat(&"min_damage_taken").base_value = -5.0
	assert_almost_eq(Mitigation.apply(_hit(1.0), _nodes[0]), -5.0, 0.001, "bunker baseline: the hit heals 5")
	_combat().apply_status(_def, 10.0)
	assert_almost_eq(Mitigation.apply(_hit(1.0), _nodes[0]), 5.0, 0.001, "10 stacks on a -5 floor: takes 5, no heal flip")
	_combat().remove_status(&"curse")
	_combat().apply_status(_def, 4.0)
	assert_almost_eq(Mitigation.apply(_hit(1.0), _nodes[0]), -1.0, 0.001, "4 stacks on a -5 floor: still heals 1")


# ── TRUE damage (acceptance 3) ──────────────────────────────────────────────

func test_true_damage_ignores_the_curse() -> void:
	_combat().apply_status(_def, 10.0)
	assert_almost_eq(Mitigation.apply(_hit(1.0, DamageInstance.Type.TRUE), _nodes[0]), 1.0, 0.001,
			"TRUE bypasses armor and floor, cursed or not")


# ── Shadow isolation (acceptance 4) ─────────────────────────────────────────

func test_shadow_apply_never_writes_the_live_modifier() -> void:
	_combat().apply_status(_def, 2.0)
	var live_mods := _curse_modifiers()
	assert_eq(live_mods.size(), 1)
	if live_mods.is_empty():
		return
	var live_value: float = live_mods[0].value

	var shadow_world := _entity.get_combat().snapshot()
	_shadows.append(shadow_world)
	var shadow := shadow_world.shadow_for(_nodes[0])
	shadow.apply_status(_def, 10.0)

	assert_almost_eq(float(shadow.get_local_value(&"min_damage_taken")), 15.0, 0.01,
			"the shadow reads its own 12 stacks on the base floor")
	assert_almost_eq(live_mods[0].value, live_value, 0.001,
			"the live modifier instance is untouched by the shadow resolve")
	assert_almost_eq(_floor(), 5.0, 0.01, "live world unchanged (still 2 stacks)")


# ── Authored content loads and is wired (values are the owner's knobs) ──────

func test_authored_curse_and_hex_load_and_are_in_the_debug_book() -> void:
	var curse := load("res://effects/status/curse.tres") as CurseStatus
	assert_not_null(curse, "curse.tres is a CurseStatus")
	if curse == null:
		return
	assert_eq(curse.id, &"curse")
	assert_true(&"debuff" in curse.tags, "tagged as a debuff")
	assert_eq(curse.potency_stat_id, &"curse_potency")
	assert_eq(curse.resistance_stat_id, &"curse_resistance")
	# FLAT since #1091 (a legible "cursed for N turns" window); the shape law
	# lives in test_status_decay_shapes. The hand-built fixture above keeps
	# FRACTION 0.5 — it tests the floor formula, not the authored fade.
	assert_almost_eq(curse.power_max, 0.0, 0.001, "uncapped")
	assert_eq(curse.reapply, StatusDef.Reapply.ACCUMULATE, "stacks add")

	var hex := load("res://attack/spell/defs/hex.tres") as SpellDef
	assert_not_null(hex, "hex.tres is a SpellDef")
	if hex == null:
		return
	var applier: ApplyStatusEffect = null
	for fx in hex.on_hit_effects:
		if fx is ApplyStatusEffect:
			applier = fx
	assert_not_null(applier, "hex composes an ApplyStatusEffect")
	if applier != null:
		assert_eq(applier.def, curse, "…that applies the authored Curse def")
		assert_gt(applier.power, 0.0)

	var book := load("res://entity/spellbook_debug.tres") as SpellBook
	assert_true(hex in book.spells, "hex is in the debug spellbook")
