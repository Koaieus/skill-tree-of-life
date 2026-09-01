extends GutTest

## Cyclone (#696, redesigned #699, re-thesised #703) — the CURL spell.
##
## The mechanic is no longer parity. At every node the storm ranks the turns it
## could make, clockwise from the edge it arrived on, and splits its power
## across them — hardest into the sharpest turn. Each share is below 1 so no
## thread survives alone; the shares SUM to more than 1 and converging fronts
## ADD, so anything that folds back onto itself feeds itself while offshoots
## bleed out. Closing a loop crits AND boosts the share feeding that loop.
##
## The two readings the whole design rests on, measured as the spectral radius
## of the walk operator:
##     rho(any lone ring)      = c_1        -- length and parity irrelevant
##     rho(dense triangulated) -> sum(c_r)
## so the authoring condition is c_1 < 1 < sum(c_r).
##
## What the tests below pin is that thesis, not a hop-by-hop golden: a tree gets
## nothing whatever you tune, rings grade smoothly by LENGTH with no odd/even
## zigzag anywhere, and joined triangles become an epicentre.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _CYCLONE := preload("res://attack/spell/defs/cyclone.tres")

var _helper: SpellTestHelper
var _graph: Graph
var _attacker: Entity
var _defender: Entity


func _polar(i: int, n: int, r: float = 60.0) -> Vector2:
	var a := TAU * float(i) / float(n)
	return Vector2(cos(a), sin(a)) * r


## Builds `count` defender nodes at `positions`, plus one attacker perch hung
## off `seed_idx` to cast FROM. The perch is a neighbour of the seed and must
## never be walked — OwnerFilter HOSTILE is what keeps the storm off its own
## caster — but it DOES give the seed its arrival direction, which is what makes
## the opening fan one-sided instead of symmetric.
func _build(adjacency: Array, positions: Dictionary, count: int, seed_idx: int) -> void:
	var adj := adjacency.duplicate(true)
	var perch := count
	adj.append([seed_idx, perch])
	var pos := positions.duplicate()
	pos[perch] = positions[seed_idx] * 2.2 + Vector2(7, 3)
	_helper = H.new()
	_graph = _helper.make_graph(adj, self, pos)
	_attacker = _helper.make_entity(_graph, "A")
	_defender = _helper.make_entity(_graph, "D")
	_helper.give_big_hp(_defender)
	_helper.give_big_hp(_attacker)
	var owned: Array = []
	for i in count:
		owned.append(i)
	_helper.assign_owner(_graph, _defender, owned)
	_helper.assign_owner(_graph, _attacker, [perch])


func _cast(count: int, seed_idx: int = 0, spell: SpellDef = null) -> AttackOutcome:
	var nodes := _graph.get_skill_nodes()
	return SpellResolver.resolve(
			spell if spell != null else _CYCLONE,
			nodes[seed_idx], nodes[count], _attacker, _graph)


func _total(outcome: AttackOutcome) -> float:
	var t := 0.0
	for hit in outcome.hits:
		t += hit.amount
	return t


func _crit_count(outcome: AttackOutcome) -> int:
	var n := 0
	for hit in outcome.hits:
		if hit.crit_tier > 0:
			n += 1
	return n


func _ring(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append([i, (i + 1) % n])
	return a


func _ring_positions(n: int) -> Dictionary:
	var d: Dictionary = {}
	for i in n:
		d[i] = _polar(i, n)
	return d


## Hub 0 plus `spokes` rim nodes. `rim` wires the rim into a cycle, turning the
## star into a fully triangulated wheel — the same vertices, one dimension more.
func _hub(spokes: int, rim: bool) -> Array:
	var a: Array = []
	for i in spokes:
		a.append([0, i + 1])
	if rim:
		for i in spokes:
			a.append([i + 1, (i + 1) % spokes + 1])
	return a


func _hub_positions(spokes: int) -> Dictionary:
	var d: Dictionary = {0: Vector2.ZERO}
	for i in spokes:
		d[i + 1] = _polar(i, spokes)
	return d


## A deep copy with one knob moved, so a tuning test never mutates the shipped
## resource other tests in this file preload.
func _retuned(closing_gain: float) -> SpellDef:
	var spell: SpellDef = _CYCLONE.duplicate(true)
	(spell.propagation.step as CycloneStep).closing_gain = closing_gain
	return spell


# -- the authored preset ---------------------------------------------------


func test_cyclone_preset_well_formed() -> void:
	var s: SpellDef = _CYCLONE
	assert_eq(s.id, &"cyclone")
	var p := s.propagation as PropagationConfig
	assert_true(p.step is CycloneStep, "the curl")
	assert_true(p.reducer is CycloneReducer, "converging fronts ADD — that is the payoff")
	assert_eq(s.crit_conditions.size(), 1, "one condition: the loop closed")
	assert_true(s.crit_conditions[0] is CycleCritCondition)


## The one genuine invariant in the tuning, and the reason the numbers are not
## free: below 1 individually so a lone thread dies, above 1 in sum so
## convergence pays. Break either and the spell stops typing terrain.
func test_the_coefficients_satisfy_c1_below_one_below_their_sum() -> void:
	var step := _CYCLONE.propagation.step as CycloneStep
	assert_gt(step.rank_coefficients.size(), 1, "a single rank cannot fan")
	var total := 0.0
	var previous := INF
	for c in step.rank_coefficients:
		assert_gt(c, 0.0)
		assert_lt(c, previous, "a wider turn must never carry more than a sharper one")
		previous = c
		total += c
	assert_lt(step.rank_coefficients[0], 1.0, "c_1 < 1: a lone ring must not sustain itself")
	assert_gt(total, 1.0, "sum(c_r) > 1: triangulated ground must")
	assert_gte(step.closing_gain, 1.0, "closing a loop never weakens the storm")


## Revisits are the whole point, and the resolver's cap does not merely skip a
## landing — it removes the candidate and KILLS the front (spell_resolver.gd),
## which strangles the epicentre exactly when it starts mattering. `max_hops` is
## the real balance knob here, and it is exponential.
func test_the_visit_cap_leaves_room_to_lap() -> void:
	var p := _CYCLONE.propagation as PropagationConfig
	assert_gt(p.max_visits_per_node, p.max_hops / 2,
			"the storm has to be allowed to come back around")


func test_the_filter_is_hostile_ground_and_no_self_loops_and_nothing_else() -> void:
	var f := _CYCLONE.propagation.filter as CompositeFilter
	assert_eq(f.mode, CompositeFilter.Mode.AND)
	var kinds: Array = []
	for child in f.children:
		kinds.append(child.get_script())
	assert_true(kinds.has(OwnerFilter), "enemy ground only — never the caster's own perch")
	assert_true(kinds.has(NoSelfLoopFilter), "going nowhere is not a turn")
	assert_false(kinds.has(BacktrackFilter),
			"dropped at #703 — Curl.rank measures FROM the arrival edge and "
			+ "so can never offer it back, which a filter cannot promise a merged front")


func test_the_cast_range_is_short_and_euclidean() -> void:
	var finder := _CYCLONE.targeting.range_finder
	assert_true(finder is EuclideanRangeFinder, "straight-line pixels, not hops")
	assert_almost_eq((finder as EuclideanRangeFinder).max_distance, 150.0, 0.01)


# -- the thesis ------------------------------------------------------------


## A tree has no circulation, so every thread decays and dies at the leaves.
## This is the property that must hold whatever the coefficients are tuned to.
func test_a_tree_gets_nothing() -> void:
	_build(_hub(6, false), _hub_positions(6), 7, 0)
	var out := _cast(7)
	assert_eq(_crit_count(out), 0, "nothing ever closes on a tree")
	var beats: Array = []
	for hit in out.hits:
		beats.append(int(hit.structural_key))
	beats.sort()
	assert_lte(beats[beats.size() - 1], 1, "the fan reaches the leaves and stops there")
	# The real claim, and the one that has to survive a retune: a tree is worth
	# the seed plus ONE fan and not a drop more. Asserting only "it stopped
	# early" would still pass if a leaf learned to reverse, or if the arrival
	# edge stopped being dropped — both of which give a tree circulation it must
	# never have.
	var step := _CYCLONE.propagation.step as CycloneStep
	var fan := 0.0
	for c in step.rank_coefficients:
		fan += c
	var seed_damage := SpellResolver.impact_damage(_CYCLONE, _graph.get_skill_nodes()[7])
	assert_almost_eq(_total(out), seed_damage * (1.0 + fan), 0.01,
			"seed + exactly one fan: a tree has no circulation to feed on")


## The headline of #703. Under the old design a square crit at hop 2 and
## STRANDED for 26 damage while a pentagon laped home for far more — parity was
## the mechanic. Now ring length grades smoothly and monotonically, because a
## longer lap simply takes longer to feed itself.
func test_rings_grade_by_length_with_no_parity_zigzag() -> void:
	var totals: Array[float] = []
	for n in [3, 4, 5, 6]:
		_build(_ring(n), _ring_positions(n), n, 0)
		var out := _cast(n)
		assert_gt(_crit_count(out), 0, "every ring closes, whatever its parity (n=%d)" % n)
		totals.append(_total(out))
	for i in range(1, totals.size()):
		assert_lt(totals[i], totals[i - 1],
				"a longer ring feeds itself more slowly — strictly monotone, "
				+ "so no odd/even alternation can be hiding in here (%s)" % [totals])


## The vibe, stated as a test: one triangle is worth killing over, a field of
## joined triangles is an epicentre. Same seven vertices in both casts — the
## wheel differs from the star only by having a rim, i.e. by being
## two-dimensional.
func test_joined_triangles_become_an_epicentre() -> void:
	_build(_hub(6, false), _hub_positions(6), 7, 0)
	var tree := _total(_cast(7))
	_build(_ring(3), _ring_positions(3), 3, 0)
	var triangle := _total(_cast(3))
	_build(_hub(6, true), _hub_positions(6), 7, 0)
	var wheel := _total(_cast(7))
	assert_gt(triangle, tree * 2.0, "a lone triangle already dwarfs a tree")
	assert_gt(wheel, triangle * 3.0,
			"and joined triangles dwarf the lone one (tree %.1f, triangle %.1f, wheel %.1f)"
			% [tree, triangle, wheel])


## The sustain term. `closing_gain` feeds FORWARD — it is not the crit, which
## only multiplies the landing — so raising it makes the ring keep paying.
func test_closing_gain_is_what_sustains_a_ring() -> void:
	_build(_ring(3), _ring_positions(3), 3, 0)
	var flat := _total(_cast(3, 0, _retuned(1.0)))
	_build(_ring(3), _ring_positions(3), 3, 0)
	var boosted := _total(_cast(3, 0, _retuned(1.6)))
	assert_gt(boosted, flat * 1.5,
			"a boosted close compounds every lap (flat %.1f, boosted %.1f)" % [flat, boosted])


## The other half of "no thread survives alone": the reducer has to ADD, or the
## split is pure loss and nothing ever concentrates.
func test_converging_fronts_add_rather_than_take_the_strongest() -> void:
	var incidents: Array[CastSpell] = []
	for amount in [3.0, 5.0]:
		var c := CastSpell.new()
		c.damage = amount
		c.visited = [] as Array[SkillNode]
		c.came_from = [] as Array[SkillNode]
		incidents.append(c)
	var merged := CycloneReducer.new().reduce(incidents, null, PropagationContext.new())
	assert_almost_eq(merged.damage, 8.0, 0.001, "summed, not max'd")
