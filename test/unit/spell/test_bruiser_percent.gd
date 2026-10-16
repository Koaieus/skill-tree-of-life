extends GutTest

## Bruiser chips a fraction of the target's CURRENT hp, and that fraction is
## its [member SpellDef.power] flat — the caster's spell_damage does not enter.
## The ADR 0033 clamp (current − 1) keeps it from ever killing on its own.
##
## Asserts the ratio (hit = power × current, never lethal), never the authored
## number: power is a tentative knob.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _BRUISER := preload("res://attack/spell/defs/bruiser.tres")


## Line 0–1: the attacker casts from 0, the defender's node 1 is the seed and
## its only neighbour is the attacker's, so the cast lands exactly one hit.
## Returns the HP that hit took off node 1 at [param current] hp.
func _bruiser_hit_on(current: float, spell_damage: float) -> float:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A", Color.RED)
	var def := helper.make_entity(graph, "D", Color.BLUE)
	helper.assign_owner(graph, atk, [0])
	helper.assign_owner(graph, def, [1])
	var n := graph.get_skill_nodes()
	def.stat_board.get_stat(&"node_health").base_value = current
	n[1].get_max_hp()
	(n[1].node_board.get_stat(&"node_health") as PoolStat).set_current(current)
	helper.set_spell_damage(atk, spell_damage)
	var outcome := SpellResolver.resolve(_BRUISER, n[1], n[0], atk, graph)
	return helper.total_damage_on(outcome, n[1])


func _expected(current: float) -> float:
	return minf(ceilf(_BRUISER.power * current), maxf(0.0, current - 1.0))


func test_bruiser_lands_the_same_fraction_of_current_hp_on_small_and_big_nodes() -> void:
	for current: float in [20.0, 2000.0]:
		var hit := _bruiser_hit_on(current, 1.0)
		assert_almost_eq(hit, _expected(current), 0.001,
				"%s hp: hit = power × current, rounded up" % current)
		assert_lt(hit, current, "%s hp: never lethal on its own" % current)


func test_caster_spell_damage_does_not_move_bruisers_hit() -> void:
	for current: float in [20.0, 2000.0]:
		var weak := _bruiser_hit_on(current, 1.0)
		var strong := _bruiser_hit_on(current, 5.0)
		assert_almost_eq(strong, weak, 0.001, "%s hp: INT does not scale Bruiser" % current)
		assert_almost_eq(weak, _expected(current), 0.001, "%s hp: still power × current" % current)


func test_bruiser_on_a_one_hp_node_lands_nothing() -> void:
	assert_almost_eq(_bruiser_hit_on(1.0, 5.0), 0.0, 0.001, "1 hp node takes 0")


func test_a_default_spell_still_lands_spell_damage_times_power() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A", Color.RED)
	helper.assign_owner(graph, atk, [0])
	helper.set_spell_damage(atk, 4.0)
	var spell := helper.make_spell(helper.make_config(helper.fan_all(), helper.owner_enemy(), null),
			[DamageEffect.new()], 3.0)
	var n := graph.get_skill_nodes()
	assert_almost_eq(SpellResolver.impact_damage(spell, n[0]), 12.0, 0.001,
			"default spell: spell_damage × power")
	assert_almost_eq(SpellResolver.impact_damage(spell, null, atk.stat_board), 12.0, 0.001,
			"default spell, board preview: spell_damage × power")


func test_bruiser_chip_reads_percent_of_current_hp_with_and_without_a_board() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A", Color.RED)
	helper.set_spell_damage(atk, 5.0)
	var want := "%s%% of current HP" % NumFmt.num(_BRUISER.power * 100.0)
	var dmg: OnHitEffect = _BRUISER.on_hit_effects[0]
	assert_string_contains(dmg.get_description(_BRUISER, null), want, "no board")
	assert_string_contains(dmg.get_description(_BRUISER, atk.stat_board), want, "caster board")
