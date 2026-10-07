extends GutTest

## The AI fills its infusion slots greedily (#1464): by floor(aspect x rate)
## descending, ties by roster order, each bounded by its aspect stat and the
## per-cast pool.

const _VENOM: SpellDef = preload("res://attack/spell/defs/venom.tres")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _caster(intelligence: float, poison: float, blind: float) -> Entity:
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	var b := atk.stat_board
	b.intelligence.base_value = intelligence
	b.poison_aspect.base_value = poison
	b.get_stat(&"blindness_aspect").base_value = blind
	return atk


func test_one_slot_takes_the_higher_ingest() -> void:
	var picked := AiInfusionPicker.pick(_caster(100, 3, 5), _VENOM)
	assert_eq(picked, {&"poison": 3} as Dictionary[StringName, int], "poison 3 x2 = 6 beats blindness 5")


func test_two_slots_take_both() -> void:
	var picked := AiInfusionPicker.pick(_caster(1000, 3, 5), _VENOM)
	assert_eq(picked.get(&"poison", 0), 3)
	assert_eq(picked.get(&"blindness", 0), 5)


func test_pool_bounds_the_total() -> void:
	var picked := AiInfusionPicker.pick(_caster(1000, 20, 20), _VENOM)
	assert_eq(picked.get(&"poison", 0), 20)
	assert_eq(picked.get(&"blindness", 0), 11, "what is left of the 31-point pool")


func test_capacity_bounds_the_cast() -> void:
	var spell: SpellDef = _VENOM.duplicate()
	spell.infusion_capacity = 2.0
	var picked := AiInfusionPicker.pick(_caster(1000, 3, 5), spell)
	assert_eq(picked, {&"poison": 2} as Dictionary[StringName, int])


func test_no_slots_picks_nothing() -> void:
	assert_true(AiInfusionPicker.pick(_caster(0, 3, 5), _VENOM).is_empty())


# ── the launched plan carries the pick ──────────────────────────────────

class _ValidPlan extends MagicAttackPlan:
	func is_valid() -> bool:
		return true


class _CapturingBattle extends BattleSystem:
	var launched: AttackPlan = null

	func new_plan(_mode: AttackMode, attacker: Entity) -> AttackPlan:
		var p := _ValidPlan.new()
		p.attacker = attacker
		return p

	func launch_attack(plan: AttackPlan) -> void:
		launched = plan


func test_launched_ai_plan_carries_the_pick() -> void:
	var atk := _caster(100, 3, 5)
	var battle := _CapturingBattle.new()
	add_child_autofree(battle)
	var ai := AIController.new()
	ai.battle_system = battle
	atk.add_child(ai)
	var c := AiCombatScorer.ScoredCandidate.new()
	c.mode = BattleSystem.AttackMode.MAGIC
	c.spell = _VENOM
	var ok: bool = await ai._execute_candidate(c)
	assert_true(ok, "the stub plan launches")
	var sent := (battle.launched as MagicAttackPlan).to_dict(null)
	assert_eq(sent.get("infusion"), {"poison": 3}, "to_dict carries the picked infusion")
