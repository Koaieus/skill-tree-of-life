extends GutTest

## The reducer's stack fold: N arrivals at one node in one beat fold their
## stack weights into the landing's starting stack scale (MAX by default, SUM /
## MIN / FIRST on the reducer); the fold is per-landing and never compounds;
## `hop_stacks` shapes the weight per hop; the row lands an integer, rounded
## once after crit × scale.

const _POISON := preload("res://effects/status/poison.tres")
const INNATE := 1.0

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## Attacker owns 0; the defender owns the rest; returns [graph, attacker].
func _board(adjacency: Array, node_count: int) -> Array:
	var graph := h.make_graph(adjacency, self)
	var atk := h.make_entity(graph, "A")
	var def := h.make_entity(graph, "D")
	h.give_big_hp(def)
	h.give_big_hp(atk)
	var defender_idx: Array = []
	for i in range(1, node_count):
		defender_idx.append(i)
	h.assign_owner(graph, def, defender_idx)
	h.assign_owner(graph, atk, [0])
	return [graph, atk]


func _poison(power: float = INNATE) -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.def = _POISON
	e.power = power
	return e


func _reducer(fold: IncidentReducer.StackFold) -> IncidentReducer:
	var r := h.sum_reducer()
	r.stack_fold = fold
	return r


func _stacks_on(outcome: AttackOutcome, node: SkillNode) -> float:
	var total := 0.0
	for hit in outcome.hits:
		if hit.target == node and hit is StatusInstance:
			total += (hit as StatusInstance).power
	return total


func _cast(adjacency: Array, node_count: int, reducer: IncidentReducer, hops: int,
		on_hits: Array[OnHitEffect], hop_stacks: HopDamageProgression = null) -> Array:
	var b := _board(adjacency, node_count)
	var graph: Graph = b[0]
	var config := h.make_config(h.fan_all(), h.owner_enemy(), reducer, {max_hops = hops})
	config.hop_stacks = hop_stacks
	var spell := h.make_spell(config, on_hits, 10.0)
	var n := graph.get_skill_nodes()
	return [n, SpellResolver.resolve(spell, n[1], n[0], b[1], graph)]


## 0 → seed 1 → {2, 3} → 4.
const DIAMOND := [[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]]


func _diamond(reducer: IncidentReducer) -> Array:
	var on_hits: Array[OnHitEffect] = [_poison()]
	return _cast(DIAMOND, 5, reducer, 2, on_hits)


func test_a_sum_fold_lands_one_share_per_converging_branch() -> void:
	var r := _diamond(_reducer(IncidentReducer.StackFold.SUM))
	var n: Array = r[0]
	var single := _stacks_on(r[1], n[2])
	assert_gt(single, 0.0, "fixture: a single arrival lands its stacks")
	assert_almost_eq(_stacks_on(r[1], n[4]), single * 2.0, 0.0001, "SUM: two branches land 2×")


func test_a_max_fold_and_a_null_reducer_land_one_share() -> void:
	for reducer in [_reducer(IncidentReducer.StackFold.MAX), null]:
		var r := _diamond(reducer)
		var n: Array = r[0]
		assert_almost_eq(_stacks_on(r[1], n[4]), _stacks_on(r[1], n[2]), 0.0001,
				"MAX / null reducer: the convergence lands 1×")


func test_three_arrivals_of_one_fold_by_the_reducer_rule() -> void:
	# 0 → seed 1 → {2, 3, 4} → 5.
	var adj := [[0, 1], [1, 2], [1, 3], [1, 4], [2, 5], [3, 5], [4, 5]]
	var expected := {
		IncidentReducer.StackFold.SUM: 3.0,
		IncidentReducer.StackFold.MAX: 1.0,
		IncidentReducer.StackFold.MIN: 1.0,
	}
	for fold in expected:
		var on_hits: Array[OnHitEffect] = [_poison()]
		var r := _cast(adj, 6, _reducer(fold), 2, on_hits)
		var n: Array = r[0]
		assert_almost_eq(_stacks_on(r[1], n[5]), _stacks_on(r[1], n[2]) * float(expected[fold]),
				0.0001, "fold %s over three 1s" % IncidentReducer.StackFold.keys()[fold])


func test_fold_stacks_over_mixed_weights() -> void:
	var incidents: Array[CastSpell] = []
	for w in [1.0, 1.0, 2.0]:
		var c := CastSpell.new()
		c.stack_weight = w
		incidents.append(c)
	var expected := {
		IncidentReducer.StackFold.SUM: 4.0,
		IncidentReducer.StackFold.MAX: 2.0,
		IncidentReducer.StackFold.MIN: 1.0,
		IncidentReducer.StackFold.FIRST: 1.0,
	}
	for fold in expected:
		assert_almost_eq(_reducer(fold).fold_stacks(incidents), float(expected[fold]), 0.0001,
				"1 + 1 + 2 under %s" % IncidentReducer.StackFold.keys()[fold])
	var merged := IncidentReducer._merge_payload_defaults(incidents)
	assert_almost_eq(merged.stack_weight, 2.0, 0.0001, "the merged payload carries MAX, never the fold")


func test_a_sum_fold_does_not_compound_across_two_convergences() -> void:
	# 0 → seed 1 → {2, 3} → 4 → {5, 6} → 7.
	var adj := [[0, 1], [1, 2], [1, 3], [2, 4], [3, 4], [4, 5], [4, 6], [5, 7], [6, 7]]
	var on_hits: Array[OnHitEffect] = [_poison()]
	var r := _cast(adj, 8, _reducer(IncidentReducer.StackFold.SUM), 4, on_hits)
	var n: Array = r[0]
	var single := _stacks_on(r[1], n[2])
	assert_almost_eq(_stacks_on(r[1], n[4]), single * 2.0, 0.0001, "first convergence: 2×")
	assert_almost_eq(_stacks_on(r[1], n[7]), single * 2.0, 0.0001, "second convergence: 2×, never 4×")


func test_hop_stacks_shapes_the_weight_per_hop() -> void:
	# A line 0 → seed 1 → 2 → 3, innate 15.
	var prog := h.scaled_add_progression(-1.0 / 3.0)
	var on_hits: Array[OnHitEffect] = [_poison(15.0)]
	var r := _cast([[0, 1], [1, 2], [2, 3]], 4, null, 2, on_hits, prog)
	var n: Array = r[0]
	var w := 1.0
	for i in 3:
		assert_almost_eq(_stacks_on(r[1], n[1 + i]), StatusDef.round_half_up(15.0 * w), 0.0001,
				"hop %d lands innate × its weight" % i)
		w = prog.apply(w, 1.0, i)


func test_a_fold_composes_with_a_content_scale() -> void:
	var b := _board(DIAMOND, 5)
	var graph: Graph = b[0]
	var n := graph.get_skill_nodes()
	var mods: Array[StatModifier] = []
	for i in 2:
		var m := StatModifier.new()
		m.stat_id = &"armor"
		m.value = 1.0
		mods.append(m)
	n[4].modifiers = mods
	var scale := ScaleStacksEffect.new()
	scale.ranker = ContentRanker.new()
	var score: float = scale.ranker.score(n[4], null)
	assert_almost_eq(score, 2.0, 0.0001, "fixture: node 4 scores 2")
	var config := h.make_config(h.fan_all(), h.owner_enemy(), _reducer(IncidentReducer.StackFold.SUM),
			{max_hops = 2})
	var on_hits: Array[OnHitEffect] = [scale, _poison()]
	var outcome := SpellResolver.resolve(h.make_spell(config, on_hits, 10.0), n[1], n[0], b[1], graph)
	assert_almost_eq(_stacks_on(outcome, n[4]), INNATE * 2.0 * score, 0.0001,
			"SUM fold 2 × content 2")


func test_a_crit_on_folded_stacks_lands_a_whole_row() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1])
	var n := graph.get_skill_nodes()
	var s := StatusInstance.new()
	s.def = _POISON
	s.power = 5.0
	s.crit_multiplier = 1.5
	s.target = n[1]
	OutcomeApplier.land_one(s, CombatWorld.live())
	assert_eq(s.power, 8.0, "5 × 1.5 rounds half-up to 8, never 7.5")
	assert_eq(n[1].get_combat().get_status_power(&"poison"), 8.0, "the row holds an integer")
