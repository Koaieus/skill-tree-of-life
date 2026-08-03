extends GutTest

## D-32 (#274) — the spell damage model: `seed = spell_damage(source) × power`,
## and a [HopDamageProgression] DECLARES whether it scales with the caster.
##
## What each block pins:
##   1. the caster invariant, PER progression class — including the deliberate
##      compression of [FlatAddProgression], which is a spell personality and
##      not a bug (it has been "fixed" away once already);
##   2. `power = 0` still resolves and still animates;
##   3. the defender cannot buff the hit landing on them (source, never
##      current_node);
##   4. INT enters ONCE, at the seed — never compounded per hop;
##   5. the three stock shapes are distinguishable from each other;
##   6. [ExpressionProgression] sees damage / seed_damage / hop_index.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


## Line of 7: attacker owns node 0 and casts from it; the defender owns 1..6,
## so the seed lands on 1 and hop n lands on node 1 + n.
func _setup(helper: SpellTestHelper) -> Array:
	var adjacency: Array = []
	for i in 6:
		adjacency.append([i, i + 1])
	var graph := helper.make_graph(adjacency, self)
	var atk := helper.make_entity(graph, "A", Color.RED)
	var def := helper.make_entity(graph, "D", Color.BLUE)
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3, 4, 5, 6])
	helper.assign_owner(graph, atk, [0])
	return [graph, atk, def]


## Cast one spell down the line and return the damage landed per HOP INDEX
## (index 0 = the seed at node 1).
func _damage_by_hop(
		helper: SpellTestHelper,
		progression: HopDamageProgression,
		power: float,
		spell_damage: float,
		max_hops: int = 5) -> Array[float]:
	var ctx := _setup(helper)
	var graph: Graph = ctx[0]
	var atk: Entity = ctx[1]
	helper.set_spell_damage(atk, spell_damage)
	var config := helper.make_config(
			helper.fan_all(), helper.owner_enemy(), null,
			{max_hops = max_hops, hop_damage = progression})
	var spell := helper.make_spell(config, [DamageEffect.new()], power)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var out: Array[float] = []
	for i in range(max_hops + 1):
		out.append(helper.total_damage_on(outcome, n[1 + i]))
	return out


# ── 1. the caster invariant, per progression class ────────────────────────


func test_doubling_spell_damage_doubles_the_seed_for_every_progression() -> void:
	var h := H.new()
	var progressions: Array = [
		[h.multiply_progression(0.5), "MultiplyProgression"],
		[h.scaled_add_progression(0.5), "ScaledAddProgression"],
		[h.flat_add_progression(2.0), "FlatAddProgression"],
	]
	for entry in progressions:
		var one := _damage_by_hop(H.new(), entry[0], 3.0, 1.0, 1)
		var two := _damage_by_hop(H.new(), entry[0], 3.0, 2.0, 1)
		assert_almost_eq(one[0], 3.0, 0.001, "%s: seed = 1 × power" % entry[1])
		assert_almost_eq(two[0], 6.0, 0.001, "%s: seed doubles with the caster" % entry[1])


func test_relative_progressions_double_every_hop_with_the_caster() -> void:
	var h := H.new()
	var multiply := _damage_by_hop(H.new(), h.multiply_progression(1.5), 2.0, 1.0)
	var multiply_2x := _damage_by_hop(H.new(), h.multiply_progression(1.5), 2.0, 2.0)
	var scaled := _damage_by_hop(H.new(), h.scaled_add_progression(0.5), 2.0, 1.0)
	var scaled_2x := _damage_by_hop(H.new(), h.scaled_add_progression(0.5), 2.0, 2.0)
	for i in multiply.size():
		assert_almost_eq(multiply_2x[i], multiply[i] * 2.0, 0.001,
				"MultiplyProgression hop %d doubles" % i)
		assert_almost_eq(scaled_2x[i], scaled[i] * 2.0, 0.001,
				"ScaledAddProgression hop %d doubles" % i)


## THE GUARD. FlatAddProgression's absolute increment is the point: it makes a
## spell strong for a novice and marginal for an archmage (D-32 amendment).
## Deleting this assertion — or "fixing" the progression to be relative —
## deletes the design space D-33 asks for. It has been proposed once already.
func test_flat_add_deliberately_does_not_scale_and_compresses() -> void:
	var h := H.new()
	var novice := _damage_by_hop(H.new(), h.flat_add_progression(2.0), 1.0, 1.0)
	var archmage := _damage_by_hop(H.new(), h.flat_add_progression(2.0), 1.0, 100.0)

	# Absolute damage still climbs with the caster…
	assert_gt(archmage[5], novice[5], "the archmage still hits harder in absolute terms")
	# …but the increment is the SAME absolute number at both ends: hop 5 is
	# seed + 5×2 either way — NOT the doubled/×100 hop a relative ramp gives.
	assert_almost_eq(novice[5], novice[0] + 10.0, 0.001, "novice hop 5 = seed + 5A")
	assert_almost_eq(archmage[5], archmage[0] + 10.0, 0.001, "archmage hop 5 = seed + 5A")

	# The compression: the spell's edge OVER ITS OWN SEED collapses as the
	# caster grows. 11× at spell_damage 1; ~1.1× at 100.
	assert_almost_eq(novice[5] / novice[0], 11.0, 0.001, "novice: 11× its own seed")
	assert_almost_eq(archmage[5] / archmage[0], 1.1, 0.001, "archmage: only 1.1× its own seed")


# ── 2. power = 0 still resolves and still animates ────────────────────────


func test_zero_power_deals_no_damage_but_still_emits_the_timeline() -> void:
	var h := H.new()
	var ctx := _setup(h)
	var graph: Graph = ctx[0]
	var atk: Entity = ctx[1]
	var config := h.make_config(h.fan_all(), h.owner_enemy(), null, {max_hops = 2})
	var spell := h.make_spell(config, [DamageEffect.new()], 0.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 0, "zero power lands no damage")
	assert_eq(outcome.timeline.size(), 3, "seed + 2 hops still emit events (utility path)")


# ── 3. the defender cannot buff the incoming hit ──────────────────────────


func test_defender_node_local_spell_damage_does_not_buff_the_incoming_hit() -> void:
	var h := H.new()
	var ctx := _setup(h)
	var graph: Graph = ctx[0]
	var atk: Entity = ctx[1]
	var n := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), h.owner_enemy(), null, {max_hops = 1})
	var spell := h.make_spell(config, [DamageEffect.new()], 4.0)

	var before := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# A fat node-local spell_damage on the TARGET, owned by the defender. If the
	# resolver ever reads state.current_node instead of state.source, this
	# multiplies the hit landing on them by 50.
	var mod := StatModifier.new()
	mod.stat_id = &"spell_damage"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 50.0
	n[1].add_local_modifier(mod)
	var after := SpellResolver.resolve(spell, n[1], n[0], atk, graph)

	assert_almost_eq(h.total_damage_on(after, n[1]), h.total_damage_on(before, n[1]), 0.001,
			"the defender's own spell_damage must not touch the incoming hit")


func test_casters_node_local_spell_damage_does_buff_the_outgoing_hit() -> void:
	# The mirror of the test above — a "mana font" addon on the cast-from node
	# is exactly what an absolute spell_damage stat is FOR (D-32 SETTLED 1).
	var h := H.new()
	var ctx := _setup(h)
	var graph: Graph = ctx[0]
	var atk: Entity = ctx[1]
	var n := graph.get_skill_nodes()
	var config := h.make_config(h.fan_all(), h.owner_enemy(), null, {max_hops = 0})
	var spell := h.make_spell(config, [DamageEffect.new()], 4.0)

	var before := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var mod := StatModifier.new()
	mod.stat_id = &"spell_damage"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 2.0
	n[0].add_local_modifier(mod)
	var after := SpellResolver.resolve(spell, n[1], n[0], atk, graph)

	assert_almost_eq(
			h.total_damage_on(after, n[1]),
			h.total_damage_on(before, n[1]) + 2.0 * spell.power, 0.001,
			"+2 spell damage on the cast-from node adds 2 × power to the seed")


# ── 4. INT enters once, at the seed ───────────────────────────────────────


func test_hop_two_is_the_seed_progressed_twice_never_int_squared() -> void:
	var h := H.new()
	# A raised spell_damage makes a compounded INT visible: 4 vs 4² = 16.
	var multiply := _damage_by_hop(H.new(), h.multiply_progression(3.0), 1.0, 4.0, 2)
	var scaled := _damage_by_hop(H.new(), h.scaled_add_progression(0.5), 1.0, 4.0, 2)
	var flat := _damage_by_hop(H.new(), h.flat_add_progression(2.0), 1.0, 4.0, 2)

	assert_almost_eq(multiply[2], 4.0 * 9.0, 0.001, "MultiplyProgression: seed × m²")
	assert_almost_eq(scaled[2], 4.0 * 2.0, 0.001, "ScaledAddProgression: seed × (1 + 2k)")
	assert_almost_eq(flat[2], 4.0 + 4.0, 0.001, "FlatAddProgression: seed + 2A")


# ── 5. the three shapes are distinguishable ───────────────────────────────


func test_stock_progressions_have_distinguishable_shapes() -> void:
	var h := H.new()
	var seed_dmg := 2.0  # spell_damage 2 × power 1
	var multiply := _damage_by_hop(H.new(), h.multiply_progression(2.0), 1.0, 2.0)
	var scaled := _damage_by_hop(H.new(), h.scaled_add_progression(1.0), 1.0, 2.0)
	var flat := _damage_by_hop(H.new(), h.flat_add_progression(3.0), 1.0, 2.0)

	for i in [1, 3, 5]:
		assert_almost_eq(multiply[i], seed_dmg * pow(2.0, float(i)), 0.001,
				"geometric: seed × factor^%d" % i)
		assert_almost_eq(scaled[i], seed_dmg * (1.0 + float(i)), 0.001,
				"linear in seed-multiples: seed × (1 + %d×k)" % i)
		assert_almost_eq(flat[i], seed_dmg + 3.0 * float(i), 0.001,
				"linear in absolute terms: seed + %d×A" % i)

	# …and they really are three different curves, not one in disguise.
	assert_ne(multiply[5], scaled[5], "geometric ≠ seed-relative linear")
	assert_ne(scaled[5], flat[5], "seed-relative linear ≠ absolute linear")


## A reducer mints a FRESH CastSpell (`_merge_payload_defaults`), so anything
## with the seed's lifecycle has to be copied there or it silently reads 0 —
## the #352 failure mode, one field later. Only ScaledAddProgression reads the
## seed, and it ships without a production user, so this is the only test that
## can catch it.
func test_seed_survives_a_reducer_merge() -> void:
	var h := H.new()
	# Diamond 1-{2,3}-4 with a tail 4-5, so the MERGED payload takes one more
	# hop after the reducer minted it.
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4], [4, 5]], self)
	var atk := h.make_entity(graph, "A", Color.RED)
	var def := h.make_entity(graph, "D", Color.BLUE)
	h.give_big_hp(def)
	h.assign_owner(graph, def, [1, 2, 3, 4, 5])
	h.assign_owner(graph, atk, [0])
	h.set_spell_damage(atk, 2.0)
	var config := h.make_config(h.fan_all(), h.owner_enemy(), h.sum_reducer(),
			{max_hops = 3, hop_damage = h.scaled_add_progression(1.0)})
	var spell := h.make_spell(config, [DamageEffect.new()], 1.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)

	# seed 2 → shoulders 2+2=4 → each arrives at 4 carrying 4+2=6 → summed 12.
	assert_almost_eq(h.total_damage_on(outcome, n[4]), 12.0, 0.001,
			"convergence sums two seed-relative branches")
	# The tail hop runs on the reducer's FRESH payload: 12 + seed(2) = 14.
	# A merge that dropped seed_damage would add 0 and leave it at 12.
	assert_almost_eq(h.total_damage_on(outcome, n[5]), 14.0, 0.001,
			"post-merge hop still adds a full seed — seed_damage survived the merge")


# ── 6. the expression escape hatch ────────────────────────────────────────


func test_expression_progression_sees_damage_seed_and_hop_index() -> void:
	var p := ExpressionProgression.new()
	# `seed_damage`, not `seed`: Godot's Expression parser reads a bare
	# `seed` as the built-in PRNG function (same collision as CastSpell.seed_node).
	p.expression = "damage + seed_damage * 10 + hop_index"
	assert_almost_eq(p.apply(5.0, 2.0, 3), 5.0 + 20.0 + 3.0, 0.001,
			"all three identifiers are in scope")


func test_expression_progression_reproduces_the_deleted_affine_class() -> void:
	# The deleted stock affine class computed (damage + a) × m. With the seed in
	# scope the escape hatch covers that AND the seed-relative variant — which is
	# why #274 (SETTLED 5) deleted it rather than renaming it.
	var affine := ExpressionProgression.new()
	affine.expression = "(damage + 2.0) * 1.5"
	var out := _damage_by_hop(H.new(), affine, 1.0, 2.0, 2)
	assert_almost_eq(out[1], (2.0 + 2.0) * 1.5, 0.001, "hop 1 = (seed + a) × m")
	assert_almost_eq(out[2], ((2.0 + 2.0) * 1.5 + 2.0) * 1.5, 0.001, "hop 2 applies it again")

	var seed_relative := ExpressionProgression.new()
	seed_relative.expression = "damage * 1.5 + seed_damage * 2"
	var rel := _damage_by_hop(H.new(), seed_relative, 1.0, 2.0, 1)
	assert_almost_eq(rel[1], 2.0 * 1.5 + 2.0 * 2.0, 0.001,
			"the seed-relative affine the deleted class could NOT express")
