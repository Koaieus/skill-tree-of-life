@tool
extends GutTest

## A spell's innate intake lands through [Infusion] (#1461): one
## [ApplyStatusEffect] rider per concept with affinity > 0, after the spell's
## own [member SpellDef.on_hit_effects], at every landing.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _VENOM := preload("res://attack/spell/defs/venom_burst.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _CURSE := preload("res://effects/status/curse.tres")


func _intake(status: StatusDef, innate: int, gain: int = 1, cost: int = 1) -> AspectIntake:
	var a := AspectIntake.new()
	a.identity = status.identity
	a.innate = innate
	a.affinity_gain = gain
	a.affinity_cost = cost
	return a



## `{concept, innate, affinity gain:cost}` rows on a spell with ingest
## `ingest_gain:ingest_cost`, [param infused] points of [param id] → its load.
func _load(id: StringName, innate: int, a_gain: int, a_cost: int, i_gain: int, i_cost: int,
		infused: int) -> int:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = StatusRoster.shared().by_concept(id).identity
	row.innate = innate
	row.affinity_gain = a_gain
	row.affinity_cost = a_cost
	spell.intakes = [row] as Array[AspectIntake]
	spell.ingest_gain = i_gain
	spell.ingest_cost = i_cost
	return Infusion.for_cast(spell, {id: infused}).load_of(spell).get(id, 0)


## The owner's examples (2026-10-13): rates multiply, int:int, floored.
func test_load_is_innate_plus_floored_infusion_times_ingest_times_affinity() -> void:
	# [concept, innate, affinity gain, cost, ingest gain, cost, infused, load, why]
	var rows := [
		[&"poison", 5, 1, 1, 1, 1, 3, 8, "venom innate 5, affinity 1:1, +3"],
		[&"poison", 5, 2, 1, 1, 1, 3, 11, "affinity 2:1, +3"],
		[&"poison", 0, 1, 2, 1, 1, 1, 0, "cyclone-like 1:2, +1 floors to 0"],
		[&"poison", 0, 1, 2, 1, 1, 2, 1, "1:2, +2"],
		[&"poison", 0, 1, 1, 1, 5, 10, 2, "a listed 1:1 row on a 1:5-ingest many-hit spell, +10"],
		[&"poison", 0, 2, 1, 1, 2, 3, 3, "affinity 2:1 times ingest 1:2, +3"],
		[&"corruption", 0, 0, 1, 1, 1, 5, 0, "affinity 0:1 refuses"],
	]
	for r in rows:
		assert_eq(_load(r[0], r[1], r[2], r[3], r[4], r[5], r[6]), r[7], r[8])


func test_an_unlisted_concept_takes_the_ingest_rate_alone() -> void:
	var spell := SpellDef.new()
	spell.ingest_cost = 5
	assert_eq(Infusion.for_cast(spell, {&"poison": 10}).load_of(spell).get(&"poison", 0), 2,
			"affinity 1:1 unlisted, ingest 1:5")
	spell.ingest_gain = 0
	assert_eq(Infusion.for_cast(spell, {&"poison": 10}).load_of(spell).get(&"poison", 0), 0,
			"ingest 0 refuses")

## Line 0(atk) - 1 - 2, both enemy; fan_all, max_hops 1: two landings.
func _cast(spell_intakes: Array[AspectIntake], max_hops: int = 1) -> AttackOutcome:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = max_hops})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.intakes = spell_intakes
	var n := graph.get_skill_nodes()
	return SpellResolver.resolve(spell, n[1], n[0], atk, graph)


func _statuses(outcome: AttackOutcome) -> Array[StatusInstance]:
	var out: Array[StatusInstance] = []
	for hit in outcome.hits:
		if hit is StatusInstance:
			out.append(hit)
	return out


func test_venom_burst_lands_one_poison_of_its_innate_per_landing_with_no_infusion() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_VENOM, n[1], n[0], atk, graph)
	var statuses := _statuses(outcome)
	assert_eq(statuses.size(), 1, "one poison per landing")
	if statuses.size() == 1:
		assert_eq(statuses[0].def, _POISON, "the rider is poison")
		assert_eq(statuses[0].power, float(_VENOM.intakes[0].innate), "the innate")
		assert_eq(statuses[0].target, n[1], "on the landing's node")


## ADR 0047 rule 4: a spell's status is its affinity, never an authored
## [ApplyStatusEffect] — every def under `attack/spell/defs/`.
func test_no_spell_def_authors_an_apply_status_effect() -> void:
	const DIR := "res://attack/spell/defs/"
	var walked := 0
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".tres"):
			continue
		var spell := load(DIR + file) as SpellDef
		if spell == null:
			continue
		walked += 1
		for effect in spell.on_hit_effects:
			assert_false(effect is ApplyStatusEffect,
					"%s authors an ApplyStatusEffect; its status belongs in an affinity" % file)
	assert_gt(walked, 5, "walked %d spell defs" % walked)
	assert_eq(Infusion.innate(_VENOM).load_of(_VENOM),
			{&"poison": _VENOM.intakes[0].innate} as Dictionary[StringName, int])


func test_two_affinities_land_two_riders_per_landing() -> void:
	var outcome := _cast([_intake(_POISON, 3), _intake(_CURSE, 2)] as Array[AspectIntake])
	var statuses := _statuses(outcome)
	assert_eq(statuses.size(), 4, "two landings × two riders")
	var by_node := {}
	for s in statuses:
		by_node.get_or_add(s.target, []).append([s.def, s.power])
	assert_eq(by_node.size(), 2, "both landings carry riders")
	for node in by_node:
		assert_eq(by_node[node], [[_POISON, 3.0], [_CURSE, 2.0]], "poison 3 then curse 2 on %s" % node)


func test_innate_zero_lands_nothing() -> void:
	var outcome := _cast([_intake(_POISON, 0)] as Array[AspectIntake])
	assert_eq(_statuses(outcome).size(), 0, "innate 0 is no rider")
	assert_true(Infusion.innate(SpellDef.new()).riders(SpellDef.new()).is_empty())


func test_riders_run_after_the_spells_own_effects() -> void:
	var outcome := _cast([_intake(_POISON, 1)] as Array[AspectIntake], 0)
	assert_eq(outcome.hits.size() >= 2, true)
	var damage_at := -1
	var status_at := -1
	for i in outcome.hits.size():
		var hit = outcome.hits[i]
		if hit is StatusInstance and status_at < 0:
			status_at = i
		elif not hit is StatusInstance and not hit is ExertInstance and damage_at < 0:
			damage_at = i
	assert_true(damage_at >= 0 and status_at > damage_at, "damage %d before rider %d" % [damage_at, status_at])


func test_affinity_description_reads_the_stacks_fold_and_the_rate() -> void:
	assert_eq(_intake(_POISON, 5, 2).get_description(), "Applies Poison (5 per hit; +2 per poison infused).")
	assert_eq(_intake(_POISON, 0, 0).get_description(), "Applies Poison (0 per hit; refuses poison infusions).")
	assert_eq(AspectIntake.new().get_description(), "Applies nothing (no status set).")


func test_apply_status_description_is_the_status_applies_line() -> void:
	var board := (preload("res://entity/default_entity_board.tres") as EntityStatBoard).duplicate(true) as EntityStatBoard
	var eff := ApplyStatusEffect.new()
	eff.def = _POISON
	eff.power = 3.0
	var expected := _POISON.applies_line(board, 3.0)
	assert_eq(expected, "Applies Poison (3 per hit).", "the shared line")
	assert_eq(eff.get_description(null, board), expected)
