extends GutTest

## #707 — the outcome→VFX seam for Cyclone's curl.
##
## #704 asked whether rank could be DERIVED at the VFX layer. It cannot, and the
## code is what settles it: [CycloneStep] holds the turn-rank coefficient as a
## local, multiplies `damage` by it and drops it on the floor; [CycloneReducer]
## then SUMS every incident, and the crit multiplies again at landing. A landed
## amount is not invertible back to the rank that produced it — so rank, which
## is the entire mechanic, has to be stamped, exactly as `verb` already is.
##
## Two things ride across: the per-arc SHARE (a float, aligned with
## `predecessors`, with `closing_gain` folded in) and the TURN SIGN. Neither is
## drawn here — that is #708. This file pins that they arrive, and arrive
## aligned.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _CYCLONE := preload("res://attack/spell/defs/cyclone.tres")
const _LIGHTNING := preload("res://attack/spell/defs/lightning_bolt.tres")

var _helper: SpellTestHelper
var _graph: Graph
var _attacker: Entity
var _defender: Entity


func _polar(i: int, n: int, r: float = 60.0) -> Vector2:
	var a := TAU * float(i) / float(n)
	return Vector2(cos(a), sin(a)) * r


## Mirrors test_cyclone.gd's fixture: `count` defender nodes plus one attacker
## perch hung off the seed, which is never walked but does give the seed its
## arrival direction — without it the opening fan is symmetric.
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


## A deep copy with the handedness flipped, so a test never mutates the shipped
## resource the rest of this file preloads.
func _mirrored() -> SpellDef:
	var spell: SpellDef = _CYCLONE.duplicate(true)
	(spell.propagation.step as CycloneStep).clockwise = false
	return spell


func _step() -> CycloneStep:
	return (_CYCLONE.propagation as PropagationConfig).step as CycloneStep


func _events_at(outcome: AttackOutcome, beat: int) -> Array[PropagationEvent]:
	var out: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if ev.beat == beat:
			out.append(ev)
	return out


# -- alignment: the invariant that makes the array readable at all ----------


func test_every_event_carries_one_share_per_predecessor() -> void:
	# The whole point of a parallel array is that entry `i` belongs to
	# predecessor `i`. If the sizes can drift the array is unreadable, so this
	# is pinned before anything about the values.
	_build(_hub(6, true), _hub_positions(6), 7, 0)
	var out := _cast(7)
	assert_gt(out.timeline.size(), 6, "the wheel should produce a real timeline")
	for ev in out.timeline:
		assert_eq(ev.incident_shares.size(), ev.predecessors.size(),
			"one share per converging arc, on beat %d into %s" % [ev.beat, ev.target])


func test_the_alignment_holds_for_every_spell_in_the_catalogue() -> void:
	# The field lives on the shared PropagationEvent, not on a Cyclone-only one,
	# so the invariant must not be Cyclone-only either. A spell that never
	# splits its damage reports a full share of 1.0 per arc.
	var dir := "res://attack/spell/defs/"
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var spell: SpellDef = load(dir + file)
		_build(_hub(6, true), _hub_positions(6), 7, 0)
		var out := _cast(7, 0, spell)
		for ev in out.timeline:
			assert_eq(ev.incident_shares.size(), ev.predecessors.size(),
				"%s emitted a landing whose shares and predecessors disagree" % file)


# -- the values: rank, made visible ----------------------------------------


func test_the_opening_fan_carries_the_authored_coefficients() -> void:
	# A star hub: six distinct rim nodes, so nothing merges and each arc is
	# exactly one minted front. The first three ranks are travelled; anything
	# past the coefficient array is not travelled at all.
	_build(_hub(6, false), _hub_positions(6), 7, 0)
	var out := _cast(7)
	var fan := _events_at(out, 1)
	var coefficients := _step().rank_coefficients
	assert_eq(fan.size(), coefficients.size(),
		"the coefficient array's length doubles as the fan width")
	var seen: Array[float] = []
	for ev in fan:
		assert_eq(ev.incident_shares.size(), 1, "no merging on a star's rim")
		seen.append(ev.incident_shares[0])
	seen.sort()
	var expected: Array[float] = []
	for c in coefficients:
		expected.append(c)
	expected.sort()
	for i in expected.size():
		assert_almost_eq(seen[i], expected[i], 0.0001,
			"the fan's shares must BE the authored coefficients (got %s)" % [seen])


func test_a_rank_one_arc_is_distinguishable_from_a_rank_three_arc() -> void:
	# The #704 complaint, restated as an assertion: a 0.70 arc and a 0.20 arc
	# are the same picture today. They must at least be different DATA.
	_build(_hub(6, false), _hub_positions(6), 7, 0)
	var fan := _events_at(_cast(7), 1)
	var lowest := INF
	var highest := 0.0
	for ev in fan:
		lowest = minf(lowest, ev.incident_shares[0])
		highest = maxf(highest, ev.incident_shares[0])
	assert_gt(highest, lowest * 2.0,
		"the spine must carry more than double the weakest offshoot (%.2f vs %.2f)"
		% [highest, lowest])


func test_a_closing_hop_carries_more_than_any_bare_coefficient() -> void:
	# closing_gain is folded into the share deliberately: a closing rank-1 arc
	# really IS carrying more than an ordinary one, and stamping the bare rank
	# ordinal instead would have made the two indistinguishable.
	var step := _step()
	var strongest := 0.0
	for c in step.rank_coefficients:
		strongest = maxf(strongest, c)
	_build(_ring(3), _ring_positions(3), 3, 0)
	var out := _cast(3)
	# Skipping the seed, which reports an undivided 1.0 — it was not minted by
	# a turn at all, so it is louder than any coefficient and means something
	# different. Only hops carry ranks.
	var best := 0.0
	for ev in out.timeline:
		if ev.beat == 0:
			continue
		for share in ev.incident_shares:
			best = maxf(best, share)
	assert_almost_eq(best, strongest * step.closing_gain, 0.0001,
		"a ring's strongest arc is a closing rank-1: %.3f x %.3f"
		% [strongest, step.closing_gain])
	assert_gt(best, strongest,
		"which is strictly more than any rank could carry without closing")


func test_a_merge_keeps_both_arcs_weights_rather_than_flattening_them() -> void:
	# This is the reinforcement read, and the reason a per-landing scalar was
	# rejected: a convergence is exactly where a strong arc meets a weak one.
	_build(_hub(6, true), _hub_positions(6), 7, 0)
	var out := _cast(7)
	var merges: int = 0
	for ev in out.timeline:
		if ev.predecessors.size() < 2:
			continue
		merges += 1
		assert_eq(ev.incident_shares.size(), ev.predecessors.size(),
			"a merged landing keeps one share per arc")
		for share in ev.incident_shares:
			assert_gt(share, 0.0, "every converging arc carried real weight")
	assert_gt(merges, 0, "a hex wheel must actually converge somewhere")


func test_a_spell_that_does_not_split_reports_full_strength() -> void:
	# Default 1.0 = "undivided", which is what every non-fan spell means. A
	# reader can therefore treat the share as a weight unconditionally.
	_build(_hub(6, false), _hub_positions(6), 7, 0)
	var out := _cast(7, 0, _LIGHTNING)
	assert_gt(out.timeline.size(), 1, "lightning should propagate on a star")
	for ev in out.timeline:
		for share in ev.incident_shares:
			assert_almost_eq(share, 1.0, 0.0001,
				"a spell with no ranked fan carries an undivided share")


# -- handedness ------------------------------------------------------------


func test_the_turn_sign_follows_the_authored_handedness() -> void:
	_build(_ring(4), _ring_positions(4), 4, 0)
	var clockwise := _cast(4)
	var turned: int = 0
	for ev in clockwise.timeline:
		if ev.beat == 0:
			continue
		assert_almost_eq(ev.turn_sign, 1.0, 0.0001, "a clockwise cast turns +1 at every hop")
		turned += 1
	assert_gt(turned, 0, "the cast must have made some turns to pin the sign on")

	_build(_ring(4), _ring_positions(4), 4, 0)
	var mirrored := _cast(4, 0, _mirrored())
	for ev in mirrored.timeline:
		if ev.beat == 0:
			continue
		assert_almost_eq(ev.turn_sign, -1.0, 0.0001,
			"flipping CycloneStep.clockwise must flip the sign the picture reads")


func test_the_seed_has_no_handedness_and_neither_does_a_non_curl_spell() -> void:
	# The seed is a JUMP, not a turn — there is no incoming edge to measure a
	# turn against, so 0.0 is the honest answer rather than a defaulted +1.
	_build(_ring(4), _ring_positions(4), 4, 0)
	for ev in _events_at(_cast(4), 0):
		assert_almost_eq(ev.turn_sign, 0.0, 0.0001, "the seed does not turn")

	_build(_hub(6, false), _hub_positions(6), 7, 0)
	for ev in _cast(7, 0, _LIGHTNING).timeline:
		assert_almost_eq(ev.turn_sign, 0.0, 0.0001,
			"a rotation-blind spell has no handedness to report")


func test_handedness_survives_a_merge() -> void:
	# It is constant for a cast, so a merged front must not lose it — a wheel's
	# hub converges constantly and would otherwise report 0 exactly where the
	# storm is strongest.
	_build(_hub(6, true), _hub_positions(6), 7, 0)
	var out := _cast(7)
	var merged_events: int = 0
	for ev in out.timeline:
		if ev.predecessors.size() < 2 or ev.beat == 0:
			continue
		merged_events += 1
		assert_almost_eq(ev.turn_sign, 1.0, 0.0001,
			"a merged front still knows which way the storm turns")
	assert_gt(merged_events, 0, "the wheel must converge for this to mean anything")
