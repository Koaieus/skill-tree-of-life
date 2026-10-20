extends GutTest

## Absolution: a load-capped, priced cleanse of corruption and curse. Each
## intake row's [CleanseUse] writes its load as the cap of one shared
## [CleanseEffect]; a landing on a node holding both crits and multiplies the
## caps; [PayWorthTerm] charges the cleared stacks' worth as one TRUE hit after
## the clears. Expectations read the authored `.tres` and the statuses' own
## worth so a retune moves them with it.

const _DEF_PATH := "res://attack/spell/defs/absolution.tres"
const _CORRUPTION: StatusDef = preload("res://effects/status/corruption.tres")
const _CURSE: StatusDef = preload("res://effects/status/curse.tres")
const _POISON: StatusDef = preload("res://effects/status/poison.tres")

var _h: SpellTestHelper
var _def: SpellDef
var _graph: Graph
var _me: Entity
var _them: Entity
var _n: Array[SkillNode] = []
var _saved_crit_when: LandingCondition = null


## 0 my core ─ 1 mine ─ 2 theirs ─ 3 their core
func before_each() -> void:
	_h = SpellTestHelper.new()
	_def = load(_DEF_PATH) as SpellDef if ResourceLoader.exists(_DEF_PATH) else null
	_saved_crit_when = _template().crit_when if _template() != null else null
	_graph = _h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	_me = _h.make_entity(_graph, "A", Color.GREEN)
	_them = _h.make_entity(_graph, "B", Color.RED)
	_h.give_big_hp(_me)
	_h.give_big_hp(_them)
	_h.assign_owner(_graph, _me, [0, 1])
	_h.assign_owner(_graph, _them, [3, 2])
	_me.stat_board.get_stat(&"crit_multiplier").base_value = 2.0
	_n.assign(_graph.get_skill_nodes())


func after_each() -> void:
	if _template() != null:
		_template().crit_when = _saved_crit_when


func _template() -> CleanseEffect:
	if _def == null or _def.intakes.is_empty():
		return null
	var use := _def.intakes[0].use as CleanseUse
	return use.effect if use != null else null


## Resolve on a shadow, then replay the record on the live world.
func _launch(target: SkillNode, infusion: Infusion = null) -> AttackOutcome:
	var outcome := SpellResolver.resolve_against(_def, target, _n[1], _me, _graph,
			CombatWorld.shadow(), null, infusion)
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	OutcomeApplier.apply(AttackRecord.rebuild(wired, _graph), CombatWorld.live())
	return outcome


func _of(outcome: AttackOutcome, type: Variant) -> Array:
	return outcome.hits.filter(func(hit): return is_instance_of(hit, type))


func _price(outcome: AttackOutcome) -> float:
	var total := 0.0
	for p: CleansePriceInstance in _of(outcome, CleansePriceInstance):
		total += p.amount
	return total


func _stacks(node: SkillNode, def: StatusDef) -> float:
	return node.get_combat().get_status_power(def.id)


func _burst(node: SkillNode, count: int) -> float:
	return (_CORRUPTION as CorruptionStatus).burst_amount(node.get_combat(), 1, count)


func test_the_def_is_authored_and_catalogued() -> void:
	assert_not_null(_def, "absolution.tres is authored")
	if _def == null:
		return
	assert_eq(SpellCatalog.by_id(&"absolution"), _def, "registered in SpellCatalog")
	assert_true(_def.on_hit_effects.is_empty(), "no damage of its own")
	assert_eq((_def.intakes[1].use as CleanseUse).effect, _template(), "both rows share one template")


func test_both_statuses_crit_and_double_the_caps() -> void:
	if _def == null:
		fail_test("no def")
		return
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CORRUPTION, 3.0)
	spot.get_combat().adjust_status_power(_CURSE, 30.0)
	var expected := _burst(spot, 3) + 30.0
	var outcome := _launch(spot)
	var cures := _of(outcome, CureInstance)
	assert_eq(cures.size(), 1, "one cure hit per landing")
	if cures.size() == 1:
		assert_eq((cures[0] as CureInstance).crit_tier, 1, "stamped as a crit")
	assert_eq(_stacks(spot, _CORRUPTION), 0.0, "corruption cleared (cap 10)")
	assert_eq(_stacks(spot, _CURSE), 0.0, "curse cleared (cap 40)")
	assert_almost_eq(_price(outcome), expected, 0.0001, "one TRUE hit of the summed worth")
	var idx_cure := outcome.hits.find(cures[0]) if cures.size() == 1 else -1
	var prices := _of(outcome, CleansePriceInstance)
	assert_eq(prices.size(), 1)
	if prices.size() == 1:
		assert_gt(outcome.hits.find(prices[0]), idx_cure, "the price lands after the clears")
		assert_eq((prices[0] as DamageInstance).type, DamageInstance.Type.TRUE)


func test_without_crit_when_the_caps_stand() -> void:
	if _def == null:
		fail_test("no def")
		return
	_template().crit_when = null
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CORRUPTION, 3.0)
	spot.get_combat().adjust_status_power(_CURSE, 30.0)
	var expected := _burst(spot, 3) + 20.0
	var outcome := _launch(spot)
	assert_eq(_stacks(spot, _CORRUPTION), 0.0)
	assert_eq(_stacks(spot, _CURSE), 10.0, "curse capped at its innate 20")
	assert_almost_eq(_price(outcome), expected, 0.0001)


func test_curse_alone_does_not_crit() -> void:
	if _def == null:
		fail_test("no def")
		return
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CURSE, 30.0)
	var outcome := _launch(spot)
	assert_eq(_stacks(spot, _CURSE), 10.0, "clears 20")
	assert_almost_eq(_price(outcome), 20.0, 0.0001)
	for c: CureInstance in _of(outcome, CureInstance):
		assert_eq(c.crit_tier, 0)


func test_infused_curse_raises_the_cap_three_to_one() -> void:
	if _def == null:
		fail_test("no def")
		return
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CURSE, 30.0)
	_launch(spot, Infusion.for_cast(_def, {&"curse": 2}))
	assert_eq(_stacks(spot, _CURSE), 4.0, "clears 26")


func test_curse_stacks_per_hit_folds_into_the_cap() -> void:
	if _def == null:
		fail_test("no def")
		return
	var stat_id := _CURSE.stacks_stat_id()
	assert_not_null(_me.stat_board.get_stat(stat_id), "the board carries %s" % stat_id)
	var mod := StatModifier.new()
	mod.stat_id = stat_id
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 3.0
	_me.stat_board.get_stat(stat_id).add_modifier(mod)
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CURSE, 30.0)
	var outcome := _launch(spot)
	assert_eq(_stacks(spot, _CURSE), 7.0, "clears 23: the plant's fold")
	assert_almost_eq(_price(outcome), 23.0, 0.0001)


func test_a_clean_node_emits_nothing() -> void:
	if _def == null:
		fail_test("no def")
		return
	var outcome := _launch(_n[2])
	assert_eq(_of(outcome, CureInstance).size(), 0)
	assert_eq(_of(outcome, DamageInstance).size(), 0)


func test_on_a_core_the_core_rows_clear_first_and_pay() -> void:
	if _def == null:
		fail_test("no def")
		return
	var core := _n[3]
	var entity := _them.get_combat()
	entity.adjust_status_power(_CORRUPTION, 2.0)
	core.get_combat().adjust_status_power(_CURSE, 10.0)
	var expected := _CORRUPTION.cleanse_worth(entity, 2.0) + 10.0
	assert_gt(expected, 10.0, "the core's corruption is worth something")
	var hp_before := core.get_combat().get_current_hp()
	var outcome := _launch(core)
	var cures := _of(outcome, CureInstance)
	assert_eq(cures.size(), 1)
	if cures.size() == 1:
		var c := cures[0] as CureInstance
		assert_eq(c.defs[0], _CORRUPTION, "the core row first")
		assert_eq(c.on_core[0], 1)
		assert_eq(c.crit_tier, 1, "the spot holds both, across its two holders")
	assert_eq(entity.get_status_power(_CORRUPTION.id), 0.0, "core corruption cleared")
	assert_eq(_stacks(core, _CURSE), 0.0)
	assert_almost_eq(_price(outcome), expected, 0.0001, "worth read off the entity row")
	assert_almost_eq(hp_before - core.get_combat().get_current_hp(), expected, 0.0001,
			"the price lands through the core's damage path")


func test_the_price_never_crits() -> void:
	if _def == null:
		fail_test("no def")
		return
	_me.stat_board.get_stat(&"crit_chance").base_value = 1.0
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CURSE, 30.0)
	var outcome := _launch(spot)
	var prices := _of(outcome, CleansePriceInstance)
	assert_eq(prices.size(), 1)
	if prices.size() == 1:
		assert_false((prices[0] as HitInstance).is_crit)
	assert_almost_eq(_price(outcome), 20.0, 0.0001, "exactly the summed worth")


func test_an_unlisted_infusion_still_plants() -> void:
	if _def == null:
		fail_test("no def")
		return
	var spot := _n[2]
	spot.get_combat().adjust_status_power(_CURSE, 5.0)
	_launch(spot, Infusion.for_cast(_def, {&"poison": 2}))
	assert_gt(_stacks(spot, _POISON), 0.0, "poison planted by its default use")


func test_tooltip_line_reads_the_cap() -> void:
	if _def == null:
		fail_test("no def")
		return
	var line := _def.intakes[1].get_description()
	assert_string_contains(line, "Cleanses up to 20 Curse per hit")
