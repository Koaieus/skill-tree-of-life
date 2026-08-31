extends GutTest

## Cyclone (#696, redesigned #699) — the cycle spell. Fans onward but never
## back the way it came; a ring gets punished whatever its parity, by one of
## two crit conditions that between them cover both:
##   ODD  — the arms differ by one, pass on the antipodal EDGE, never merge,
##          and each laps home onto its own trail → [CycleCritCondition].
##   EVEN — the arms are equal, meet head-on at the antipodal NODE and merge
##          → [ConvergenceCritCondition], at hop L/2.
##
## On closing, the trail TRUNCATES to the ring just walked (rotated to end at
## the landing) and the veto clears, so the storm keeps the loop it found and
## grinds it, critting every beat until the visit cap bites. The invariant that
## buys: the trail is always ring + all-distinct tail, so a close is always a
## back-edge onto a SIMPLE walk and every crit certifies a real cycle of
## length ≥ 3. Minimum length 3 falls out — there is no gate.
##
## X = the seed (`spell_damage(cast-from node) × power`, D-32); a landing at
## hop n carries whatever the authored [HopDamageProgression] makes of it, so
## [method _at_hop] asks the progression instead of hardcoding its shape —
## goldens survive a retune of the ramp (#278). Crit is ×2.
##
## The four topologies are the whole thesis, and they are the acceptance:
##   TRIANGLE — the owner's worked example, hop for hop, crits included.
##   SQUARE   — detonates head-on at the far corner (hop 2), then strands.
##   PENTAGON — the fronts pass mid-edge and lap home at hop 5.
##   HEXAGON  — detonates at the antipodal node on hop 3.

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


## What a landing at `hop` carries before any crit — asked of the authored
## progression rather than reimplemented, so a ramp retune moves the goldens
## with it instead of breaking them.
func _at_hop(hop: int) -> float:
	var prog: HopDamageProgression = _CYCLONE.propagation.hop_damage
	var seed_damage := _x()
	var carried := seed_damage
	for i in hop:
		carried = prog.apply(carried, seed_damage, i)
	return carried


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
	var p := s.propagation as PropagationConfig
	assert_true(p.step is CycloneStep, "Cyclone fans with the cycle bookkeeping")
	assert_true(p.reducer is CycloneReducer, "max damage, unioned veto, winner's trail")
	assert_not_null(p.hop_damage, "damage has to move per hop — the grind is the payoff")
	# Tuning knobs (power, mana, ramp, visit cap) are the owner's to move and
	# are deliberately NOT pinned here. This one is not a knob: a pentagon is
	# the smallest odd ring past the triangle, and it can only be punished by
	# lapping the whole way home, so anything under 5 silently deletes half
	# the spell's thesis.
	assert_true(p.max_hops >= 5, "an odd ring has to be able to lap home")
	assert_eq(s.crit_conditions.size(), 2, "one condition per parity")
	var crits: Array = []
	for c in s.crit_conditions:
		crits.append(c.get_script())
	assert_true(crits.has(CycleCritCondition), "odd rings: a lineage laps home")
	assert_true(crits.has(ConvergenceCritCondition), "even rings: the arms meet head-on")


func test_the_filter_composes_hostile_with_no_backtracking_and_no_self_loops() -> void:
	var f := _CYCLONE.propagation.filter as CompositeFilter
	assert_eq(f.mode, CompositeFilter.Mode.AND)
	var kinds: Array = []
	for child in f.children:
		kinds.append(child.get_script())
	assert_true(kinds.has(BacktrackFilter), "the veto")
	assert_true(kinds.has(OwnerFilter), "enemy ground only — never the caster's own perch")
	assert_true(kinds.has(NoSelfLoopFilter),
			"authored, not inherited: #699's bug was assuming the veto covered this")


func test_the_cast_range_is_short_and_euclidean() -> void:
	var finder := _CYCLONE.targeting.range_finder
	assert_true(finder is EuclideanRangeFinder, "straight-line pixels, not hops")
	assert_almost_eq((finder as EuclideanRangeFinder).max_distance, 150.0, 0.01)


# ── the owner's triangle, hop for hop ─────────────────────────────────────


## The worked example from #696, extended by the owner in #699 to cover what
## happens AFTER the lap comes home — which is the whole point of truncating
## the trail instead of resetting it:
##   0: A            3: A     (both close the cycle → ONE merged crit)
##   1: B, C         4: B, C  (veto cleared, and both shoulders are still in
##   2: C, B                   the kept ring → CRIT CRIT)
##                   5: A     (CRIT, and the visit cap ends it here)
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
	assert_eq(beats.get(4), [1, 2], "the cleared veto lets A fan freely again")
	assert_eq(beats.get(5), [0], "and home once more, where the visit cap ends it")


## The behaviour the truncation exists for. Under the old reset the storm
## forgot the loop the instant it closed it, so beats 4 and 5 landed cold and
## only every third beat crit. Keeping the RING — and only the ring — means
## every beat of the grind is a hop onto ground the lineage is still standing
## on, and the crit is continuous from the first lap home.
func test_triangle_crits_every_beat_once_the_loop_is_closed() -> void:
	_ring(3)
	assert_eq(_beats_that_crit(_cast(3)), [3, 4, 4, 5],
			"cold until the lap home, then both shoulders, then home again")


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
			"the hop-3 landing, doubled")


func test_triangle_never_walks_the_casters_own_node() -> void:
	_ring(3)
	for entry in _landings(_cast(3)):
		assert_ne(entry[1], 3, "the attacker's perch is hostile-filtered out")


## The grind is unbounded by construction — a closed ring re-closes forever —
## so what ends a cast is the visit cap, not the loop running out. Worth
## pinning: this is the knob that decides how long a crit chain runs, and it
## is the one an over-tuned Cyclone would be over-tuned on.
func test_triangle_grind_is_bounded_by_the_visit_cap() -> void:
	_ring(3)
	var per_node: Dictionary = {}
	for entry in _landings(_cast(3)):
		per_node[entry[1]] = int(per_node.get(entry[1], 0)) + 1
	var cap: int = _CYCLONE.propagation.max_visits_per_node
	for i in 3:
		assert_eq(per_node.get(i), cap,
				"every node of a closed triangle is ground to the cap, none spared")


# ── parity: two crit conditions, one per parity ───────────────────────────


## The even half, and what [ConvergenceCritCondition] bought (#699). The two
## fronts meet at C having arrived from B and D — neither lineage's own trail
## holds C, so the CYCLE condition sees nothing; the merge itself is the
## evidence, and it crits on contact at hop L/2.
##
## The storm still strands there, which is the union veto doing its old job:
## C refuses both shoulders and has nowhere else to go. Detonating and dying
## in the same beat is the even ring's whole story.
func test_square_detonates_head_on_at_the_far_corner() -> void:
	_ring(4)
	var out := _cast(4)
	var landings: Array = _landings(out)
	assert_eq(_beats_that_crit(out), [2], "the head-on meeting crits, at hop L/2")
	assert_eq(landings[-1][0], 2, "and the walk dies there, well short of max_hops")
	assert_eq(landings[-1][1], 2, "at the corner opposite the one you aimed at")
	assert_eq(out.hits.size(), 4, "A, both shoulders, and the far corner once")
	# The load-bearing assertion, and the one a landing count cannot make: the
	# walk has to die because C REFUSED BOTH FRONTS, not merely because it ran
	# out of unvisited ground. A veto that regressed to `incidents[0]` would
	# still terminate here and still land four hits.
	assert_eq(out.timeline[-1].predecessors.size(), 2,
			"both shoulders converged on the far corner, and the merged veto saw both")


## The bigger even ring, to prove the crit tracks L/2 rather than a constant.
func test_hexagon_detonates_at_the_antipodal_node_on_hop_three() -> void:
	_ring(6)
	var out := _cast(6)
	assert_eq(_beats_that_crit(out), [3], "L/2 for a hexagon, not L/2 for a square")
	var last: Array = _landings(out)[-1]
	assert_eq(last[1], 3, "the node directly opposite the seed")


## The odd half. The arms differ by one, so they pass mid-edge at beat 3
## instead of merging — no convergence crit anywhere — and each lineage has to
## run the whole way home to earn it.
func test_pentagon_laps_home_because_the_fronts_pass_on_an_edge() -> void:
	_ring(5)
	var out := _cast(5)
	assert_eq(_beats_that_crit(out), [5, 6, 6],
			"odd ring: they cross mid-edge at beat 3, reach A at 5, then grind")
	var closing: Array = []
	for hit in out.hits:
		if hit.crit_tier > 0:
			closing.append(_graph.get_skill_nodes().find(hit.target))
			break
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
## re-seed. Closing dominates instead — and the merged trail is the CLOSER's
## truncated ring, never the strongest incident's, because the trail has to be
## a loop some single lineage actually walked.
func test_closing_dominates_the_union_on_a_mixed_convergence() -> void:
	_ring(3)
	var ring: Array[SkillNode] = [_n(1), _n(2), _n(0)]
	var closer := _incident(_n(0), 4.0, ring, [] as Array[SkillNode], true)
	var passer := _incident(_n(0), 10.0, [_n(2), _n(0)] as Array[SkillNode],
			[_n(2)] as Array[SkillNode], false)
	var merged := CycloneReducer.new().reduce([closer, passer], _n(0), PropagationContext.new())
	assert_true(merged.closed_cycle, "one front closed, so the landing closed")
	assert_eq(merged.came_from, [], "the re-seed wins — the storm is free to go anywhere")
	assert_eq(merged.visited, ring, "and it carries the ring the closer kept")
	assert_almost_eq(merged.damage, 10.0, 0.01,
			"damage is still the strongest incident's, even when that one didn't close")


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


## The #699 bug, pinned as the shape it actually had. Cyclone claimed to be
## "self-loop-blind by construction" because a self-loop hop has
## `to == from == current_node` — but `came_from` holds the PREDECESSOR, and
## never the current node, so the veto never once covered the case. The first
## assertion below is the proof, and the reason the fix had to be a filter of
## its own rather than a tweak to this one: an unrelated rule that happens to
## cover your case is a rule that can stop covering it silently.
func test_the_self_loop_veto_is_structural_and_not_a_backtrack_side_effect() -> void:
	_ring(3)
	var ctx := PropagationContext.new()
	# Exactly what CycloneStep mints for a front that walked A → B.
	var minted := _incident(_n(1), 1.0, [_n(0), _n(1)] as Array[SkillNode],
			[_n(0)] as Array[SkillNode], false)
	assert_true(BacktrackFilter.new().allows(_n(1), _n(1), minted, ctx),
			"the veto holds the predecessor, so it never covered self-loops")
	assert_false(NoSelfLoopFilter.new().allows(_n(1), _n(1), minted, ctx),
			"going nowhere is not a cycle — and a length-1 loop is Reverberator's")


# ── the step's ring bookkeeping ───────────────────────────────────────────


## Rotated to END at the landing, because that is where the front now stands
## and where the next hop measures its own trail from.
func test_a_closed_ring_is_the_trail_suffix_rotated_onto_the_landing() -> void:
	_ring(3)
	var trail: Array[SkillNode] = [_n(0), _n(1), _n(2)]
	assert_eq(CycloneStep.closed_ring(trail, 0), [_n(1), _n(2), _n(0)],
			"A→B→C closing on A keeps the whole triangle, ending on A")


## A tail ahead of the ring is not part of the loop and is dropped.
func test_a_closed_ring_discards_the_walk_that_led_up_to_it() -> void:
	_ring(4)
	var trail: Array[SkillNode] = [_n(3), _n(0), _n(1), _n(2)]
	assert_eq(CycloneStep.closed_ring(trail, 1), [_n(1), _n(2), _n(0)],
			"the hop home to A closes A-B-C; D was only how the storm got there")


func _step_children(payload: CastSpell, candidates: Array[SkillNode]) -> Array[CastSpell]:
	return CycloneStep.new().step(payload.current_node, payload, candidates,
			PropagationConfig.new(), PropagationContext.new())


## The reversal, and the degenerate loop a naive truncation would leave behind.
## Standing on A with the kept ring [B,C,A], the hop back to C finds C one step
## back — so the forward arc is the single edge A-C. Truncating to that would
## have the lineage forget the triangle and ping-pong A↔C, closing a length-2
## "cycle" every beat forever. The hop really did close the triangle, the other
## way round, so the ring it keeps is the whole ring, rotated.
func test_a_reversal_after_a_close_keeps_the_ring_the_long_way_round() -> void:
	_ring(3)
	var payload := _incident(_n(0), 1.0, [_n(1), _n(2), _n(0)] as Array[SkillNode],
			[] as Array[SkillNode], true)
	var child := _step_children(payload, [_n(2)] as Array[SkillNode])[0]
	assert_true(child.closed_cycle, "the hop closes — and crits — either way")
	assert_eq(child.visited, [_n(0), _n(1), _n(2)],
			"the same triangle, rotated to end where the front now stands")


## The invariant everything else rests on, and the one an earlier cut broke by
## appending the landed node on the short branch: a trail with a node in it
## twice makes `find` return the first occurrence, the next slice runs long,
## and the guard waves through a ring like [C,A,C,B] — a vertex-repeating
## closed walk, which is exactly what #699 exists to refuse.
func test_a_closing_trail_is_always_all_distinct() -> void:
	_ring(3)
	var payload := _incident(_n(0), 1.0, [_n(1), _n(2), _n(0)] as Array[SkillNode],
			[] as Array[SkillNode], true)
	for hops in 6:
		var candidates: Array[SkillNode] = []
		for nb in _graph.get_neighbours(payload.current_node):
			if not payload.came_from.has(nb) and nb != payload.current_node:
				candidates.append(nb)
		payload = _step_children(payload, candidates)[0]
		var seen: Array[SkillNode] = []
		for node in payload.visited:
			assert_false(seen.has(node),
					"hop %d left a node in the trail twice" % hops)
			seen.append(node)
		assert_true(payload.visited.size() >= CycloneStep.MIN_RING)


## The ordinary case: a hop onto the far side of the kept ring truncates to
## exactly the ring, which is what makes the next beat crit too.
func test_a_closing_hop_keeps_the_ring_and_clears_the_veto() -> void:
	_ring(3)
	var payload := _incident(_n(0), 1.0, [_n(1), _n(2), _n(0)] as Array[SkillNode],
			[] as Array[SkillNode], true)
	var child := _step_children(payload, [_n(1)] as Array[SkillNode])[0]
	assert_true(child.closed_cycle)
	assert_eq(child.visited, [_n(2), _n(0), _n(1)], "the same triangle, rotated onto B")
	assert_eq(child.came_from, [], "and the storm re-seeds, free to fan both ways")


## The non-closing case, unchanged: the trail grows and the veto is the one
## node it just left. Vetoing the whole trail instead would make a cycle
## unclosable, which is the one hop the spell exists to reward.
func test_an_open_hop_grows_the_trail_and_vetoes_only_the_predecessor() -> void:
	_ring(3)
	var payload := _incident(_n(1), 1.0, [_n(0), _n(1)] as Array[SkillNode],
			[_n(0)] as Array[SkillNode], false)
	var child := _step_children(payload, [_n(2)] as Array[SkillNode])[0]
	assert_false(child.closed_cycle)
	assert_eq(child.visited, [_n(0), _n(1), _n(2)])
	assert_eq(child.came_from, [_n(1)])
