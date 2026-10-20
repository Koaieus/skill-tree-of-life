extends GutTest

## Rend: one [DefenderStatShare] of armor read twice — as extra Sunder stacks by
## the intake's rider and as extra damage by [AddStackTermDamageEffect] — up a
## climb toward higher armor, critting on the summit. Ratios and relations only:
## every number is read off the def or the arranged board, never a literal knob.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _REND_PATH := "res://attack/spell/defs/rend.tres"
const _SUNDER := preload("res://effects/status/sunder.tres")

var _h: SpellTestHelper
var _graph: Graph
var _n: Array[SkillNode]
var _blue: Entity
var _rend: SpellDef

## Arranged armor per Red node: 1 → 2 → 3 rises; 4 is a lower branch off 1.
const _ARMOR := {1: 4.0, 2: 8.0, 3: 12.0, 4: 2.0}


## 0 and 5 Blue (the caster, two nodes so the source clears min_degree);
## the line 1-2-3 and the branch 1-4 Red.
func before_each() -> void:
	_rend = load(_REND_PATH) as SpellDef
	_h = H.new()
	_graph = _h.make_graph([[0, 1], [1, 2], [2, 3], [1, 4], [0, 5]], self)
	_blue = _h.make_entity(_graph, "Blue", Color.BLUE)
	var red := _h.make_entity(_graph, "Red", Color.RED)
	_h.give_big_hp(red)
	_h.assign_owner(_graph, red, [1, 2, 3, 4])
	_h.assign_owner(_graph, _blue, [0, 5])
	_blue.stat_board.get_stat(&"crit_multiplier").base_value = 1.0
	_n = _graph.get_skill_nodes()
	for i in _ARMOR:
		var m := StatModifier.new()
		m.stat_id = &"armor"
		m.operation = StatModifier.Operation.ADD_BASE
		m.value = _ARMOR[i] - float(_n[i].get_local_value(&"armor"))
		_n[i].add_local_modifier(m)


func _term_effect() -> AddStackTermDamageEffect:
	for fx in _rend.on_hit_effects:
		if fx is AddStackTermDamageEffect:
			return fx
	return null


func _ratio() -> float:
	return (_term_effect().stack_terms[0] as DefenderStatShare).ratio


## Each landed node's damage hit (not its Sunder status), by node.
func _damage_hits(spell: SpellDef = _rend) -> Dictionary:
	var outcome := SpellResolver.resolve(spell, _n[1], _n[0], _blue, _graph)
	var out := {}
	for h in outcome.hits:
		if h is StatusInstance or h is ExertInstance:
			continue
		if h.kind == HitInstance.Kind.DAMAGE:
			out[h.target] = h
	return out


# ── the def's shape ─────────────────────────────────────────────────────────


func test_the_intake_and_the_damage_effect_share_one_armor_term() -> void:
	var fx := _term_effect()
	assert_not_null(fx, "rend carries an AddStackTermDamageEffect")
	var row: AspectIntake = _rend.intakes[0]
	assert_eq(row.identity, _SUNDER.identity, "the intake is Sunder")
	assert_eq(row.stack_terms.size(), 1, "the intake carries one term")
	assert_eq(fx.stack_terms.size(), 1, "the effect carries one term")
	assert_same(row.stack_terms[0], fx.stack_terms[0], "one SubResource, two readers")
	var share := row.stack_terms[0] as DefenderStatShare
	assert_not_null(share, "the term is a DefenderStatShare")
	assert_eq(share.stat_id, &"armor", "the share is of armor")


func test_the_damage_term_is_authored_before_the_damage_effect() -> void:
	var term_at := _rend.on_hit_effects.find(_term_effect())
	var dmg_at := -1
	for i in _rend.on_hit_effects.size():
		if _rend.on_hit_effects[i] is DamageEffect:
			dmg_at = i
	assert_gt(dmg_at, term_at, "DamageEffect emits the boosted number")
	assert_gt(term_at, -1)


func test_rend_climbs_rather_than_landing_node_only() -> void:
	assert_gt(_rend.propagation.max_hops, 0.0, "rend walks")
	var crit := _rend.crit_conditions[0] as LocalExtremumCondition if not _rend.crit_conditions.is_empty() else null
	assert_not_null(crit, "rend crits on a local extremum")
	if crit != null:
		assert_eq(crit.mode, LocalExtremumCondition.Mode.MAX, "a summit, not a weak point")
		assert_eq((crit.ranker as StatRanker).stat_id, &"armor", "of armor")


# ── the climb ───────────────────────────────────────────────────────────────


func test_rend_climbs_to_the_highest_armor_and_skips_the_low_branch() -> void:
	var hits := _damage_hits()
	for i in [1, 2, 3]:
		assert_true(hits.has(_n[i]), "N%d is struck" % i)
	assert_false(hits.has(_n[4]), "the lower-armor branch is never entered")


func test_the_seed_damage_is_power_plus_the_armor_share() -> void:
	var plain := _rend.duplicate() as SpellDef
	plain.on_hit_effects = _rend.on_hit_effects.filter(func(fx): return fx is DamageEffect)
	var base: float = _damage_hits(plain)[_n[1]].amount
	assert_almost_eq(_damage_hits()[_n[1]].amount - base, _ratio() * _ARMOR[1], 0.01,
			"the seed landing adds ratio × its armor to what the power alone deals")


func test_each_climb_step_carries_the_damage_and_adds_its_own_share() -> void:
	var hits := _damage_hits()
	assert_almost_eq(hits[_n[2]].amount - hits[_n[1]].amount, _ratio() * _ARMOR[2], 0.01,
			"the minted child carries the boosted damage, then adds ratio × its armor")
	assert_almost_eq(hits[_n[3]].amount - hits[_n[2]].amount, _ratio() * _ARMOR[3], 0.01,
			"it snowballs up the climb")


# ── the summit crit ─────────────────────────────────────────────────────────


func test_rend_crits_on_the_summit_and_not_on_the_slope() -> void:
	var hits := _damage_hits()
	assert_true(hits[_n[3]].is_crit, "the top of the climb is a summit")
	assert_false(hits[_n[1]].is_crit, "the seed sits on a slope")
	assert_false(hits[_n[2]].is_crit, "the middle sits on a slope")
