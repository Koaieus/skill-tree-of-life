extends GutTest

## Hell Gnaw (#1720): Sunder's rat swarm. It lands on every allocated node it
## reaches — hostile, allied and the caster's own, never neutral ground —
## biting several times per landing, and crits where the node is gnawed
## through (armor at or below its [StatCondition]'s threshold). Every number is
## read off the def: ratios and relations, never the literal knobs.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const HELL_GNAW: SpellDef = preload("res://attack/spell/defs/hell_gnaw.tres")
const SUNDER_ASPECT := preload("res://aspects/defs/sunder.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _blue: Entity


## 0 and 5 Blue (the caster); 1 Red (hostile); 2 Mate (Blue's ally); 3 and 4
## unallocated. 1 is the seed: 0, 2, 3 hang off it, 5 off 0, 4 off 2.
func before_each() -> void:
	_h = H.new()
	_graph = _h.make_graph([[0, 1], [1, 2], [1, 3], [0, 5], [2, 4]], self)
	var coop := Faction.new()
	coop.id = &"gnaw_coop"
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE, coop)
	var mate := _h.make_entity(_graph, "Mate", Color.GREEN, coop)
	var red := _h.make_entity(_graph, "Red", Color.RED)
	for e in [_blue, mate, red]:
		_h.give_big_hp(e)
	_h.assign_owner(_graph, red, [1])
	_h.assign_owner(_graph, mate, [2])
	_h.assign_owner(_graph, _blue, [0, 5])
	_blue.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_n = _graph.get_skill_nodes()


func _crit() -> StatCondition:
	return HELL_GNAW.crit_conditions[0] as StatCondition if not HELL_GNAW.crit_conditions.is_empty() else null


func _armor(i: int) -> float:
	return float(CombatWorld.live().combat_for(_n[i]).get_local_value(&"armor"))


func _set_armor(i: int, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value - _armor(i)
	_n[i].add_local_modifier(m)


func _gnawed_through(i: int) -> bool:
	var p := CastSpell.new()
	p.graph = _graph
	p.source = _n[0]
	var cast := PropagationContext.new()
	cast.graph = _graph
	cast.caster = _blue
	cast.world = CombatWorld.live()
	return _crit().evaluate(LandingContext.for_test(p, _n[i], cast))


func _damage_by_node(outcome: AttackOutcome) -> Dictionary:
	var out := {}
	for hit in outcome.hits:
		if hit is DamageInstance:
			if not out.has(hit.target):
				out[hit.target] = []
			out[hit.target].append(hit)
	return out


# ── the def ─────────────────────────────────────────────────────────────────


func test_hell_gnaw_is_catalogued_and_listed_on_sunder() -> void:
	assert_eq(SpellCatalog.by_id(&"hell_gnaw"), HELL_GNAW)
	assert_true(SUNDER_ASPECT.spells.has(HELL_GNAW), "Sunder's spells list Hell Gnaw")


func test_each_bite_carries_sunder_and_wither() -> void:
	var ids := HELL_GNAW.intakes.map(func(r: AspectIntake): return r.aspect_id())
	assert_true(ids.has(&"sunder") and ids.has(&"wither"), "gnawed, withered: both rows ride each bite")
	for row in HELL_GNAW.intakes:
		assert_gt(row.innate, 0, "%s lands with no infusion spent" % row.aspect_id())
	assert_lt(float(HELL_GNAW.ingest_gain) / HELL_GNAW.ingest_cost, 1.0,
			"many hits buy a poor intake ratio")
	assert_false(HELL_GNAW.propagation.repeat_landings_by.is_empty(), "a landing bites more than once")


# ── targets ─────────────────────────────────────────────────────────────────


func test_it_gnaws_hostile_allied_and_own_nodes_and_skips_neutral() -> void:
	var dmg := _damage_by_node(SpellResolver.resolve(HELL_GNAW, _n[1], _n[0], _blue, _graph))
	assert_true(dmg.has(_n[1]), "the hostile seed is bitten")
	assert_true(dmg.has(_n[2]), "the ally's node is bitten")
	assert_true(dmg.has(_n[0]), "the caster's own node is bitten")
	assert_true(dmg.has(_n[5]), "the swarm walks on through the caster's land")
	assert_false(dmg.has(_n[3]), "unallocated ground is never bitten")
	assert_false(dmg.has(_n[4]), "nor walked through")


func test_bites_thin_out_as_the_swarm_spreads() -> void:
	var dmg := _damage_by_node(SpellResolver.resolve(HELL_GNAW, _n[1], _n[0], _blue, _graph))
	if not (dmg.has(_n[1]) and dmg.has(_n[0]) and dmg.has(_n[5])):
		fail_test("arranged: seed, hop 1 and hop 2 are all bitten")
		return
	assert_gt(dmg[_n[1]].size(), dmg[_n[0]].size(), "the seed takes more bites than a hop-1 node")
	assert_gt(dmg[_n[0]].size(), dmg[_n[5]].size(), "and hop 1 more than hop 2")


# ── the gnawed-through crit ─────────────────────────────────────────────────


func test_gnawed_through_is_armor_at_or_below_the_threshold() -> void:
	var c := _crit()
	assert_not_null(c, "hell gnaw crits on a stat condition")
	if c == null:
		return
	assert_eq((c.ranker as StatRanker).stat_id, &"armor", "of armor")
	_set_armor(1, c.threshold - 1.0)
	_set_armor(2, c.threshold)
	_set_armor(5, c.threshold + 1.0)
	assert_true(_gnawed_through(1), "below the threshold: gnawed through")
	assert_true(_gnawed_through(2), "at it: gnawed through")
	assert_false(_gnawed_through(5), "above it: still plated")


func test_hits_crit_on_a_gnawed_through_node_and_not_on_a_plated_one() -> void:
	var c := _crit()
	if c == null:
		fail_test("no crit condition")
		return
	_set_armor(1, c.threshold - 1.0)
	_set_armor(2, c.threshold + 1000.0)
	var dmg := _damage_by_node(SpellResolver.resolve(HELL_GNAW, _n[1], _n[0], _blue, _graph))
	assert_true(dmg.has(_n[1]) and dmg.has(_n[2]), "arranged: both bitten")
	if not (dmg.has(_n[1]) and dmg.has(_n[2])):
		return
	assert_true(dmg[_n[1]].all(func(x): return x.is_crit), "every bite on bare flesh crits")
	assert_false(dmg[_n[2]].any(func(x): return x.is_crit), "no bite on thick plate crits")
