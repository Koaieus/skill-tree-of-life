extends GutTest

## Venom Burst (#1502): the dose. A big folded poison stack on the target,
## then a 2-hop enemy fan whose per-hop stack weight follows the def's
## `hop_stacks` progression; `max_visits_per_node` 1 keeps it purely outward.

const _DEF_PATH := "res://attack/spell/defs/venom_burst.tres"

var _h: SpellTestHelper
var _def: SpellDef


func before_each() -> void:
	_h = SpellTestHelper.new()
	_def = load(_DEF_PATH) as SpellDef


func _cast(adjacency: Array, enemy: Array, infusion: Infusion = null) -> Array:
	var graph := _h.make_graph(adjacency, self)
	var atk := _h.make_entity(graph, "A", Color.RED)
	var def := _h.make_entity(graph, "D", Color.BLUE)
	_h.give_big_hp(def)
	_h.assign_owner(graph, atk, [0])
	_h.assign_owner(graph, def, enemy)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_def, n[enemy[0]], n[0], atk, graph, null, infusion)
	return [n, outcome]


func _statuses_on(outcome: AttackOutcome, node: SkillNode) -> Array:
	var out: Array = []
	for hit in outcome.hits:
		if hit.target == node and hit is StatusInstance:
			out.append(hit)
	return out


## Seed 1 → A 2 → B 3: each lands `base` × the progression's weight for its hop.
func _assert_path_scales_from(base: float, infusion: Infusion) -> void:
	var prog: HopDamageProgression = _def.propagation.hop_stacks
	assert_not_null(prog, "the dose shapes its stacks per hop")
	if prog == null:
		return
	var r := _cast([[0, 1], [1, 2], [2, 3]], [1, 2, 3], infusion)
	var n: Array = r[0]
	var w := 1.0
	for i in 3:
		var hits := _statuses_on(r[1], n[1 + i])
		assert_eq(hits.size(), 1, "hop %d lands once" % i)
		if hits.size() == 1:
			assert_almost_eq(hits[0].power, StatusDef.round_half_up(base * w), 0.0001,
					"hop %d lands base × its weight" % i)
		w = prog.apply(w, 1.0, i)
	assert_lt(w, 1.0, "the progression tapers")


func test_path_lands_innate_tapered_by_the_progression() -> void:
	assert_not_null(_def)
	_assert_path_scales_from(float(_def.affinities[0].innate), null)


func test_infusion_scales_every_hop_together() -> void:
	var aff: SpellAffinity = _def.affinities[0]
	var points := 3
	var inf := Infusion.for_cast(_def, {&"poison": points})
	_assert_path_scales_from(float(aff.innate) + floorf(points * aff.rate), inf)


func test_diamond_lands_the_far_node_once() -> void:
	assert_eq(_def.propagation.max_visits_per_node, 1, "pure outward")
	# 0 → seed 1 → {2, 3} → 4.
	var r := _cast([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [1, 2, 3, 4])
	var n: Array = r[0]
	assert_eq(_statuses_on(r[1], n[4]).size(), 1, "two branches, one landing")
	assert_eq(_statuses_on(r[1], n[1]).size(), 1, "the seed is never revisited")


func test_the_dose_keeps_its_damage_and_no_reducer() -> void:
	var has_damage := false
	for fx in _def.on_hit_effects:
		has_damage = has_damage or fx is DamageEffect
	assert_true(has_damage, "venom's damage stays on the dose")
	assert_null(_def.propagation.reducer, "default MAX fold")
	assert_eq(_def.propagation.max_hops, 2.0)
	assert_eq(_def.default_rate, 1.0)
