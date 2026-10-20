extends GutTest

## Gloomflux (#1561): Curse's second spell. One damage, then on the target in
## order: add a few curse stacks, double the row, and copy a share of it out
## through Curse's own spill rule as if the node had died — the target keeps
## its row. Every number is landed on the authority's shadow and replayed on
## the live world from the record.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const GLOOMFLUX: SpellDef = preload("res://attack/spell/defs/gloomflux.tres")
const CURSE := preload("res://effects/status/curse.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _blue: Entity


## 0 is the caster's; 1 the target; 2 and 3 the target owner's own nodes (the
## spill's Mine survivors); 4 hangs off 2 and must never be touched.
func before_each() -> void:
	_h = H.new()
	_graph = _h.make_graph([[0, 1], [1, 2], [1, 3], [2, 4]], self)
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE)
	var red := _h.make_entity(_graph, "Red", Color.RED)
	_h.give_big_hp(red)
	_h.assign_owner(_graph, red, [1, 2, 3, 4])
	_h.assign_owner(_graph, _blue, [0])
	_n = _graph.get_skill_nodes()


func _effect(script: Script) -> OnHitEffect:
	for e in GLOOMFLUX.on_hit_effects:
		if e.get_script() == script:
			return e
	return null


func _added() -> float:
	return float(GLOOMFLUX.intakes[0].innate)


func _factor() -> float:
	return (_effect(MultiplyRowEffect) as MultiplyRowEffect).factor


func _share() -> float:
	return (_effect(FluxEffect) as FluxEffect).share


func _curse(i: int) -> float:
	return _n[i].get_combat().get_status_power(&"curse")


## Resolve on a kept shadow, then replay the record on the live world the
## way the authority does. Returns [outcome, shadow].
func _cast() -> Array:
	var shadow := CombatWorld.shadow()
	var outcome := SpellResolver.resolve_against(GLOOMFLUX, _n[1], _n[0], _blue, _graph, shadow)
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	OutcomeApplier.apply(AttackRecord.rebuild(wired, _graph), CombatWorld.live())
	return [outcome, shadow]


## What Curse's spill hands [param i] for [member FluxEffect.share] of node
## 1's row as it stands on the live world now.
func _spill_quote(i: int) -> float:
	var field := StackField.over_world(CURSE, CURSE.spread.ownership_mask, CombatWorld.live(),
			[_n[1]] as Array[SkillNode], _graph)
	var total := 0.0
	for t in CURSE.spread.copy_out(field, _n[1].get_combat(), _share()):
		if t.to != null and t.to.real() == _n[i]:
			total += t.amount
	return total


func test_an_uncursed_target_holds_added_times_factor_and_takes_1_damage() -> void:
	var r := _cast()
	assert_eq(_curse(1), _added() * _factor(), "add, then double")
	var dealt := 0.0
	for h in (r[0] as AttackOutcome).hits:
		if h is DamageInstance and h.target == _n[1]:
			dealt += h.amount
	assert_eq(dealt, 1.0, "a simple 1 damage")
	(r[1] as CombatWorld).free_shadow()


func test_a_cursed_target_is_row_plus_added_times_factor_and_never_drops() -> void:
	_n[1].get_combat().apply_status(CURSE, 3.0)
	var r := _cast()
	assert_eq(_curse(1), (3.0 + _added()) * _factor(), "(row + added) × factor")
	(r[1] as CombatWorld).free_shadow()


func test_neighbours_gain_the_spill_quote_and_the_target_keeps_its_row() -> void:
	_n[1].get_combat().apply_status(CURSE, 3.0)
	var r := _cast()
	assert_eq(_curse(1), (3.0 + _added()) * _factor(), "the copy never debits the target")
	for i in [2, 3]:
		var quote := _spill_quote(i)
		assert_gt(quote, 0.0, "precondition: the spill hands %d something" % i)
		assert_eq(_curse(i), quote, "neighbour %d gains Curse's spill for that share" % i)
	assert_eq(_curse(0), 0.0, "the caster's node is no Mine survivor of the target")
	assert_eq(_curse(4), 0.0, "the copy reaches direct neighbours only")
	(r[1] as CombatWorld).free_shadow()


func test_the_live_replay_lands_the_shadow_rows() -> void:
	_n[1].get_combat().apply_status(CURSE, 1.0)
	var r := _cast()
	var shadow: CombatWorld = r[1]
	for i in _n.size():
		assert_eq(_curse(i), shadow.combat_for(_n[i]).get_status_power(&"curse"),
				"node %d: the replay lands what the shadow resolved" % i)
	shadow.free_shadow()


func test_gloomflux_is_catalogued_and_listed_on_curse() -> void:
	assert_eq(SpellCatalog.by_id(&"gloomflux"), GLOOMFLUX)
	var curse_aspect: Aspect = load("res://aspects/defs/curse.tres")
	assert_true(curse_aspect.spells.has(GLOOMFLUX), "Curse's spells list Gloomflux")
