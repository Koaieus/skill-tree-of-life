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
## which strangles the epicentre exactly when it starts mattering. Owner call
## 2026-09-01: uncap it. `max_hops` bounds the walk on its own, so the visit
## counter has nothing left to protect against and is authored out of the way.
func test_revisits_are_effectively_uncapped() -> void:
	var p := _CYCLONE.propagation as PropagationConfig
	assert_gt(p.max_visits_per_node, p.max_hops * 10,
			"max_hops is the only propagation limit this spell wants")


## The merge redirects the flow. Two fronts of unequal strength arriving from
## different sides leave as one front heading between them, biased toward the
## stronger — which is what keeps the curl coherent through a convergence
## instead of snapping to whichever predecessor the reducer happened to keep.
func test_converging_fronts_combine_their_heading_by_strength() -> void:
	_build(_ring(4), _ring_positions(4), 4, 0)
	var node := _graph.get_skill_nodes()[0]
	var strong := CastSpell.new()
	strong.damage = 9.0
	strong.arrival_bearing = Vector2.RIGHT
	var weak := CastSpell.new()
	weak.damage = 1.0
	weak.arrival_bearing = Vector2.UP
	var incidents: Array[CastSpell] = [strong, weak]
	for c in incidents:
		c.visited = [] as Array[SkillNode]
		c.came_from = [] as Array[SkillNode]
	var merged := CycloneReducer.new().reduce(incidents, node, PropagationContext.new())
	assert_gt(merged.arrival_bearing.x, 0.0, "still mostly heading the strong way")
	assert_lt(merged.arrival_bearing.y, 0.0, "but pulled toward the weak front")
	assert_gt(absf(merged.arrival_bearing.x), absf(merged.arrival_bearing.y) * 5.0,
			"9 vs 1 is a strong bias, not an even split")


## Equal and opposite is what colliding arms ARE, so the average heading is
## genuinely zero and the survivor keeps its own rather than stalling.
func test_a_head_on_collision_keeps_the_survivors_heading() -> void:
	_build(_ring(4), _ring_positions(4), 4, 0)
	var node := _graph.get_skill_nodes()[0]
	var east := CastSpell.new()
	east.damage = 5.0
	east.arrival_bearing = Vector2.RIGHT
	var west := CastSpell.new()
	west.damage = 5.0
	west.arrival_bearing = Vector2.LEFT
	var incidents: Array[CastSpell] = [east, west]
	for c in incidents:
		c.visited = [] as Array[SkillNode]
		c.came_from = [] as Array[SkillNode]
	var merged := CycloneReducer.new().reduce(incidents, node, PropagationContext.new())
	assert_ne(merged.arrival_bearing, Vector2.ZERO, "a stalled front has no turn to rank")


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


## The headline of #703. Under the old design a square crit once at hop 2 and
## STRANDED for 26 damage while a pentagon lapped home for six times that:
## parity WAS the mechanic, and its signature was that an even ring detonated
## and died.
##
## What is pinned here is the death of that signature — every ring keeps
## critting past its first close, and none is worth a fraction of another.
## Deliberately NOT monotonicity in ring length: with a finite `max_hops` a
## short ring simply fits more laps in (a triangle laps ~2.7 times in 8 hops, a
## hexagon ~1.3), so totals pair up 3-4 and 5-6 by lap count. That is a hop-
## budget artifact and it is not an odd/even alternation — which is exactly
## what a parity detector would produce and this no longer does.
func test_no_ring_strands_the_way_parity_used_to_make_it() -> void:
	var totals: Array[float] = []
	for n in [3, 4, 5, 6]:
		_build(_ring(n), _ring_positions(n), n, 0)
		var out := _cast(n)
		assert_gt(_crit_count(out), 2,
				"a ring keeps critting once it closes — it never detonates and "
				+ "strands, which is what an even ring used to do (n=%d)" % n)
		totals.append(_total(out))
	var best := 0.0
	for t in totals:
		best = maxf(best, t)
	for i in totals.size():
		assert_gt(totals[i], best * 0.35,
				"no ring collapses to a fraction of another — the old square/"
				+ "pentagon gap was 6x (%s)" % [totals])
	assert_gt(totals[0], totals[totals.size() - 1],
			"the trend across the range is still downward with length (%s)" % [totals])


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


# -- #710: the closed ring crosses the seam ---------------------------------
#
# The closing hop is the payoff of the whole #703 redesign, and until #710 it
# lit at most ONE node. `PropagationEvent.closed_ring` is the ring itself,
# stamped where the crit is stamped: the resolver copies `state.visited` on
# every closing landing, because `CycloneStep.closed_ring()` has already
# truncated that trail to exactly the loop.


## Every event that carries a ring, in timeline order.
func _rings(outcome: AttackOutcome) -> Array[PropagationEvent]:
	var out: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if not ev.closed_ring.is_empty():
			out.append(ev)
	return out


func _all_distinct(nodes: Array[SkillNode]) -> bool:
	var seen: Array[SkillNode] = []
	for n in nodes:
		if seen.has(n):
			return false
		seen.append(n)
	return true


func test_a_triangle_closure_carries_the_whole_triangle() -> void:
	_build(_ring(3), _ring_positions(3), 3, 0)
	var out := _cast(3)
	var rings := _rings(out)
	assert_gt(rings.size(), 0, "a triangle closes, repeatedly — at least one ring must be stamped")
	var first := rings[0]
	assert_eq(first.closed_ring.size(), 3, "the ring a triangle closes IS the triangle")
	assert_true(_all_distinct(first.closed_ring), "a simple cycle repeats no vertex")
	assert_same(first.closed_ring[first.closed_ring.size() - 1], first.target,
			"the ring ends where the front now stands, so the lap ends on the landing")


func test_the_seed_and_every_open_hop_carry_no_ring() -> void:
	_build(_ring(3), _ring_positions(3), 3, 0)
	var out := _cast(3)
	assert_true(out.timeline[0].closed_ring.is_empty(),
			"a JUMP closes nothing — the seed must not carry a ring")
	# `closed_ring` is stamped exactly where `closed_cycle` is, and
	# CycleCritCondition is the only reader of that flag — so the two counts are
	# the same number seen twice. A ring stamped on a non-closing landing (or
	# missing from a closing one) shows up here as a mismatch.
	var crits: int = 0
	for ev in out.timeline:
		if ev.max_crit_tier() > 0:
			crits += 1
	assert_eq(_rings(out).size(), crits,
			"a ring is stamped on exactly the landings that closed one")


func test_every_stamped_ring_is_a_real_simple_cycle_including_the_wraparound() -> void:
	# The invariant the VFX layer rests on: array order IS the storm's rotation,
	# so consecutive pairs PLUS `ring[-1] -> ring[0]` are the N edges to light.
	# A wraparound that is not an edge would draw a chord across the wheel.
	_build(_hub(6, true), _hub_positions(6), 7, 0)
	var out := _cast(7)
	var rings := _rings(out)
	assert_gt(rings.size(), 3, "a hex wheel closes loops constantly")
	for ev in rings:
		var ring := ev.closed_ring
		assert_gte(ring.size(), 3, "a ring shorter than a triangle is not a cycle: %s" % [ring])
		assert_true(_all_distinct(ring), "a simple cycle repeats no vertex: %s" % [ring])
		assert_same(ring[ring.size() - 1], ev.target, "the ring ends at the landing")
		for k in ring.size():
			var from_node: SkillNode = ring[k]
			var to_node: SkillNode = ring[(k + 1) % ring.size()]
			assert_true(_graph.get_neighbours(from_node).has(to_node),
					"ring[%d] -> ring[%d] must be a real edge (%s)" % [k, (k + 1) % ring.size(), ring])


func test_a_merge_carries_the_closers_ring_not_the_strongest_fronts_trail() -> void:
	# "Closing dominates": the trail has to be a ring some single lineage
	# actually walked, so the closer wins the lineage even when a NON-closer is
	# carrying more damage. Taking the max-damage winner's trail would stamp a
	# `closed_ring` that is not a cycle at all.
	_build(_ring(4), _ring_positions(4), 4, 0)
	var nodes := _graph.get_skill_nodes()
	var loop: Array[SkillNode] = [nodes[0], nodes[1], nodes[2]]
	var trail: Array[SkillNode] = [nodes[3], nodes[2]]
	var closer := CastSpell.new()
	closer.damage = 1.0
	closer.closed_cycle = true
	closer.visited = loop
	closer.came_from = [] as Array[SkillNode]
	var bruiser := CastSpell.new()
	bruiser.damage = 9.0
	bruiser.closed_cycle = false
	bruiser.visited = trail
	bruiser.came_from = [] as Array[SkillNode]
	var incidents: Array[CastSpell] = [bruiser, closer]
	var merged := CycloneReducer.new().reduce(incidents, nodes[2], PropagationContext.new())
	assert_true(merged.closed_cycle, "one closer among the incidents closes the merge")
	assert_eq(merged.visited, loop,
			"the merged landing carries the CLOSER's ring, not the 9-damage front's trail")
