extends GutTest

## Cyclone (#696) — the odd-cycle spell. Fans onward but never back the way it
## came; when a front lands on a node its own lineage already struck the cycle
## CLOSES: crit, and the veto + trail reset so the storm laps the loop again.
##
## X = the seed (`spell_damage(cast-from node) × power`, D-32) and the ramp is
## `ScaledAddProgression(0.25)`, so a landing at hop n carries `X(1 + n/4)`.
## Goldens are written as X expressions, never literals, so they pin the SHAPE
## and survive an INT-coefficient retune (#278). Crit is ×2.
##
## The three topologies are the whole thesis, and they are the acceptance:
##   TRIANGLE — the owner's worked example, hop for hop. Crits at 3, 6, 9.
##   SQUARE   — counter-rotating fronts collide head-on at the antipodal NODE,
##              veto each other's shoulders, and the walk dies at hop 2.
##   PENTAGON — they pass on the antipodal EDGE instead and both lap home at 5.
## Even rings extinguish, odd rings spin. Cyclone is a parity detector, and
## nothing in it was authored to be one — it falls out of the veto being a
## union.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _CYCLONE := preload("res://attack/spell/defs/cyclone.tres")

const _CRIT := 2.0

var _helper: SpellTestHelper
var _graph: Graph
var _attacker: Entity
var _defender: Entity


## `ring_size` defender nodes wired into a cycle, plus one attacker node hung
## off node 0 to cast FROM. The attacker's node is a neighbour of the seed and
## must never be walked — [OwnerFilter] HOSTILE is what keeps the storm off its
## own caster, and a ring test that forgot it would read as a bigger ring.
func _ring(ring_size: int) -> void:
	var adjacency: Array = []
	for i in ring_size:
		adjacency.append([i, (i + 1) % ring_size])
	adjacency.append([0, ring_size])  # the attacker's perch
	_helper = H.new()
	_graph = _helper.make_graph(adjacency, self)
	_attacker = _helper.make_entity(_graph, "A")
	_defender = _helper.make_entity(_graph, "D")
	_helper.give_big_hp(_defender)
	_helper.give_big_hp(_attacker)
	var owned: Array = []
	for i in ring_size:
		owned.append(i)
	_helper.assign_owner(_graph, _defender, owned)
	_helper.assign_owner(_graph, _attacker, [ring_size])


func _n(i: int) -> SkillNode:
	return _graph.get_skill_nodes()[i]


func _cast(ring_size: int) -> AttackOutcome:
	return SpellResolver.resolve(_CYCLONE, _n(0), _n(ring_size), _attacker, _graph)


## X — the seed damage for this cast.
func _x() -> float:
	return _helper.seed_multiplier(_n(_graph.get_skill_nodes().size() - 1)) * _CYCLONE.power


## What a landing at `hop` carries before any crit: `X(1 + hop × fraction)`.
func _at_hop(hop: int) -> float:
	var frac := (_CYCLONE.propagation.hop_damage as ScaledAddProgression).seed_fraction_per_hop
	return _x() * (1.0 + float(hop) * frac)


## Every landing as `[beat, node_index, amount]`, in resolution order.
func _landings(outcome: AttackOutcome) -> Array:
	var nodes := _graph.get_skill_nodes()
	var out: Array = []
	for hit in outcome.hits:
		out.append([int(hit.structural_key), nodes.find(hit.target), hit.amount])
	return out


func _beats_that_crit(outcome: AttackOutcome) -> Array:
	var out: Array = []
	for hit in outcome.hits:
		if hit.crit_tier > 0:
			out.append(int(hit.structural_key))
	return out


# ── preset sanity ─────────────────────────────────────────────────────────


func test_cyclone_preset_well_formed() -> void:
	var s: SpellDef = _CYCLONE
	assert_eq(s.id, &"cyclone")
	assert_eq(s.min_degree, 4, "the catalogue's deepest casting requirement")
	assert_eq(s.power, 2.0)
	assert_eq(s.mana_cost, 5)
	var p := s.propagation as PropagationConfig
	assert_true(p.step is CycloneStep, "Cyclone fans with the cycle bookkeeping")
	assert_true(p.reducer is CycloneReducer, "max damage, unioned veto, winner's trail")
	assert_true(p.hop_damage is ScaledAddProgression,
			"linear AND caster-scaling — FlatAdd's caster-independence is Trailblazer's (D-32)")
	assert_eq(p.max_hops, 9, "three triangle laps")
	assert_eq(p.max_visits_per_node, 6, "two entries per shoulder per lap, three laps")
	assert_eq(s.crit_conditions.size(), 1)
	assert_true(s.crit_conditions[0] is CycleCritCondition)


func test_the_filter_composes_hostile_with_no_backtracking() -> void:
	var f := _CYCLONE.propagation.filter as CompositeFilter
	assert_eq(f.mode, CompositeFilter.Mode.AND)
	var kinds: Array = []
	for child in f.children:
		kinds.append(child.get_script())
	assert_true(kinds.has(BacktrackFilter), "the veto")
	assert_true(kinds.has(OwnerFilter), "enemy ground only — never the caster's own perch")


func test_the_cast_range_is_short_and_euclidean() -> void:
	var finder := _CYCLONE.targeting.range_finder
	assert_true(finder is EuclideanRangeFinder, "straight-line pixels, not hops")
	assert_almost_eq((finder as EuclideanRangeFinder).max_distance, 150.0, 0.01)


# ── the owner's triangle, hop for hop ─────────────────────────────────────


## The worked example from #696, and the acceptance for the whole mechanic:
##   0: A            2: C, B  (crossed over — neither went back to A)
##   1: B, C         3: A     (both close the cycle → ONE merged crit)
## then the reset lets A fan freely again and the whole thing laps twice more.
func test_triangle_lands_the_owners_worked_example() -> void:
	_ring(3)
	var beats: Dictionary = {}
	for entry in _landings(_cast(3)):
		var bucket: Array = beats.get(entry[0], [])
		bucket.append(entry[1])
		bucket.sort()
		beats[entry[0]] = bucket
	assert_eq(beats.get(0), [0], "seed lands on A alone")
	assert_eq(beats.get(1), [1, 2], "A fans to both shoulders")
	assert_eq(beats.get(2), [1, 2], "they cross over — B→C and C→B, neither back to A")
	assert_eq(beats.get(3), [0], "both come home to A, merged into one landing")
	assert_eq(beats.get(4), [1, 2], "the reset lets A fan freely again")


func test_triangle_crits_once_per_lap_and_only_on_closing() -> void:
	_ring(3)
	assert_eq(_beats_that_crit(_cast(3)), [3, 6, 9],
			"one crit per lap home, and never on the crossover beats")


func test_triangle_crit_damage_is_the_ramped_hop_doubled() -> void:
	_ring(3)
	var out := _cast(3)
	var first_crit: HitInstance = null
	for hit in out.hits:
		if hit.crit_tier > 0:
			first_crit = hit
			break
	assert_not_null(first_crit, "the lap home crits")
	assert_almost_eq(first_crit.amount, _at_hop(3) * _CRIT, 0.01,
			"X(1 + 3/4) doubled")


func test_triangle_never_walks_the_casters_own_node() -> void:
	_ring(3)
	for entry in _landings(_cast(3)):
		assert_ne(entry[1], 3, "the attacker's perch is hostile-filtered out")


func test_triangle_grind_is_bounded_by_the_visit_cap() -> void:
	_ring(3)
	var per_node: Dictionary = {}
	for entry in _landings(_cast(3)):
		per_node[entry[1]] = int(per_node.get(entry[1], 0)) + 1
	assert_eq(per_node.get(1), 6, "a shoulder takes exactly its visit cap over three laps")
	assert_eq(per_node.get(2), 6)
	assert_eq(per_node.get(0), 4, "the seed takes the initial hit plus three laps home")


# ── parity: even rings extinguish, odd rings spin ─────────────────────────


## The emergent half of the design, and the reason the veto has to be a UNION.
## The two fronts meet at C having arrived from B and D; the merged payload
## refuses both, C has no other neighbour, and the storm strands with the loop
## still open.
func test_square_extinguishes_head_on_at_the_far_corner() -> void:
	_ring(4)
	var out := _cast(4)
	assert_eq(_beats_that_crit(out), [], "an even ring never closes — no crit")
	var beats: Array = []
	for entry in _landings(out):
		if not beats.has(entry[0]):
			beats.append(entry[0])
	assert_eq(beats, [0, 1, 2], "the walk dies at the collision, well short of max_hops")
	assert_eq(out.hits.size(), 4, "A, both shoulders, and the far corner once")


func test_pentagon_laps_home_because_the_fronts_pass_on_an_edge() -> void:
	_ring(5)
	var out := _cast(5)
	assert_eq(_beats_that_crit(out), [5],
			"odd ring: they cross mid-edge at beat 3 and both reach A at beat 5")
	var closing: Array = []
	for hit in out.hits:
		if hit.crit_tier > 0:
			closing.append(_graph.get_skill_nodes().find(hit.target))
	assert_eq(closing, [0], "the lap comes home to the node you aimed at")


# ── the merge decisions, in isolation ─────────────────────────────────────


func _incident(node: SkillNode, damage: float, trail: Array[SkillNode],
		came_from: Array[SkillNode], closed: bool) -> CastSpell:
	var s := CastSpell.new()
	s.current_node = node
	s.damage = damage
	s.visited = trail
	s.came_from = came_from
	s.closed_cycle = closed
	return s


## The hole worth naming: a plain union would hand the merged storm the
## NON-closer's veto, so an unrelated front silently weakens someone else's
## reset. Reset dominates instead.
func test_reset_dominates_the_union_on_a_mixed_convergence() -> void:
	_ring(3)
	var closer := _incident(_n(0), 10.0, [_n(0)] as Array[SkillNode], [] as Array[SkillNode], true)
	var passer := _incident(_n(0), 4.0, [_n(2), _n(0)] as Array[SkillNode], [_n(2)] as Array[SkillNode], false)
	var merged := CycloneReducer.new().reduce([closer, passer], _n(0), PropagationContext.new())
	assert_true(merged.closed_cycle, "one front closed, so the landing closed")
	assert_eq(merged.came_from, [], "the reset wins — the storm is free to go anywhere")
	assert_eq(merged.visited, [_n(0)], "and its trail restarts here")


## Travel is physical: the fronts really did arrive from all those directions,
## so the merged payload refuses all of them — not just the one the stock merge
## keeps as `predecessor`.
func test_a_non_closing_convergence_unions_every_way_it_came() -> void:
	_ring(3)
	var from_b := _incident(_n(0), 10.0, [_n(1), _n(0)] as Array[SkillNode], [_n(1)] as Array[SkillNode], false)
	var from_c := _incident(_n(0), 4.0, [_n(2), _n(0)] as Array[SkillNode], [_n(2)] as Array[SkillNode], false)
	var merged := CycloneReducer.new().reduce([from_b, from_c], _n(0), PropagationContext.new())
	assert_false(merged.closed_cycle)
	assert_eq(merged.came_from.size(), 2, "both shoulders vetoed, not just the first")
	assert_true(merged.came_from.has(_n(1)) and merged.came_from.has(_n(2)))


## The stock merge unions `visited`, which would crit on nodes the surviving
## lineage never walked — and only when it happened to converge with someone
## who did. The strongest incident's lineage survives whole instead.
func test_a_non_closing_convergence_keeps_the_winners_trail_not_the_union() -> void:
	_ring(3)
	var strong := _incident(_n(0), 10.0, [_n(1), _n(0)] as Array[SkillNode], [_n(1)] as Array[SkillNode], false)
	var weak := _incident(_n(0), 4.0, [_n(2), _n(0)] as Array[SkillNode], [_n(2)] as Array[SkillNode], false)
	var merged := CycloneReducer.new().reduce([strong, weak], _n(0), PropagationContext.new())
	assert_almost_eq(merged.damage, 10.0, 0.01, "strongest incident's damage")
	assert_false(merged.visited.has(_n(2)),
			"the loser's node is NOT in the trail — no crit on ground this lineage never walked")


# ── the filter ────────────────────────────────────────────────────────────


func test_backtrack_filter_vetoes_only_the_set_it_was_given() -> void:
	_ring(3)
	var f := BacktrackFilter.new()
	var payload := _incident(_n(0), 1.0, [] as Array[SkillNode], [_n(1)] as Array[SkillNode], false)
	assert_false(f.allows(_n(0), _n(1), payload, PropagationContext.new()), "where it came from")
	assert_true(f.allows(_n(0), _n(2), payload, PropagationContext.new()), "anywhere else")


## An empty set allowing everything is what makes the reset branchless — the
## filter never learns that a cycle closed, it just finds nothing to refuse.
func test_an_empty_veto_allows_everything() -> void:
	_ring(3)
	var f := BacktrackFilter.new()
	var payload := _incident(_n(0), 1.0, [] as Array[SkillNode], [] as Array[SkillNode], true)
	assert_true(f.allows(_n(0), _n(1), payload, PropagationContext.new()))
	assert_true(f.allows(_n(0), _n(2), payload, PropagationContext.new()))


## Free, and it is what keeps Cyclone off Reverberator's turf: a self-loop hop
## has `to == from == current_node`, which a non-closing payload always carries
## in its veto set.
func test_a_self_loop_hop_is_vetoed_by_construction() -> void:
	_ring(3)
	var f := BacktrackFilter.new()
	var payload := _incident(_n(1), 1.0, [] as Array[SkillNode], [_n(0)] as Array[SkillNode], false)
	payload.came_from = [_n(1)] as Array[SkillNode]
	assert_false(f.allows(_n(1), _n(1), payload, PropagationContext.new()),
			"going nowhere is not a cycle")
