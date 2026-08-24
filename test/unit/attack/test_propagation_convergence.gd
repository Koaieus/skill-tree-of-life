extends GutTest

## #542 — a converging spell landing must record EVERY predecessor that fed
## it, not just [member PropagationEvent.predecessor] (which the
## [IncidentReducer] always picked as `incidents[0]`, silently dropping the
## rest). Covers the resolver's population of [member PropagationEvent.predecessors],
## the ragged [AttackRecord] round-trip (including the MIXED case a flat
## per-event encoding can't express), and D2 — one landing stays one landing.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


## Diamond: 0(atk) - 1(seed) - {2, 3} - 4. Both branches reach node 4 in the
## same BFS wave; a real (non-cancelling) reducer merges them into ONE landing.
## fan_all + owner_enemy + sum_reducer, max_hops 2 so wave 2 reaches node 4.
func _diamond_outcome() -> Array:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3, 4])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(),
			helper.sum_reducer(), {max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	return [SpellResolver.resolve(spell, n[1], n[0], atk, graph), n, graph]


func _event_at(outcome: AttackOutcome, target: SkillNode) -> PropagationEvent:
	for ev in outcome.timeline:
		if ev.target == target:
			return ev
	return null


# ── Acceptance 1: the reconvergence event records every predecessor ─────────

func test_reconvergence_event_records_every_converging_predecessor() -> void:
	var res := _diamond_outcome()
	var outcome: AttackOutcome = res[0]
	var n: Array = res[1]
	var ev := _event_at(outcome, n[4])
	assert_not_null(ev, "node 4 must land")
	assert_eq(ev.predecessors.size(), 2, "both branches converged here")
	var by_node: Dictionary = {}
	for hit in outcome.hits:
		var cs := hit.source as CastSpell
		if cs != null and cs.current_node == n[4]:
			by_node[n[4]] = cs
	var incident_count: int = (by_node[n[4]] as CastSpell).incident_count
	assert_eq(ev.predecessors.size(), incident_count,
			"predecessor count matches the reducer's incident_count")
	assert_true(ev.predecessors.has(n[2]), "branch through node 2 is recorded")
	assert_true(ev.predecessors.has(n[3]), "branch through node 3 is recorded")
	assert_true(ev.predecessor == n[2] or ev.predecessor == n[3],
			"the singular field still names one of the converging branches")

	# Non-convergent landings (a single incoming branch) stay a single-entry
	# set — the ragged shape's boring case, and the one every OLD event was.
	var simple := _event_at(outcome, n[2])
	assert_eq(simple.predecessors.size(), 1, "node 2 has exactly one predecessor: node 1")
	assert_eq(simple.predecessors[0], n[1])


# ── Acceptance 3 (D2): one landing stays one landing ─────────────────────────

func test_convergent_landing_still_applies_damage_exactly_once() -> void:
	var res := _diamond_outcome()
	var outcome: AttackOutcome = res[0]
	var n: Array = res[1]
	var hits_on_4: Array = []
	for hit in outcome.hits:
		if hit.target == n[4]:
			hits_on_4.append(hit)
	assert_eq(hits_on_4.size(), 1,
			"two incidents converged, but the reducer folds them into ONE HitInstance")
	var events_on_4: Array = []
	for ev in outcome.timeline:
		if ev.target == n[4]:
			events_on_4.append(ev)
	assert_eq(events_on_4.size(), 1,
			"one PropagationEvent (one floater) even though it carries 2 predecessors")
	assert_eq(events_on_4[0].hits.size(), 1, "the one event carries the one hit")


# ── Acceptance 2: capture -> rebuild round-trip, MIXED case ──────────────────

func test_capture_rebuild_round_trip_preserves_the_ragged_predecessor_sets() -> void:
	# The diamond outcome IS the mixed case: node 2/3's events carry a single
	# predecessor, node 4's carries two — exactly the shape a flat
	# one-entry-per-event encoding (the old e_pred) cannot express.
	var res := _diamond_outcome()
	var outcome: AttackOutcome = res[0]
	var n: Array = res[1]
	var graph: Graph = res[2]

	var d := AttackRecord.capture(outcome, graph)
	var rebuilt := AttackRecord.rebuild(d, graph)

	assert_eq(rebuilt.timeline.size(), outcome.timeline.size(), "every event survives")
	var by_target_original: Dictionary = {}
	for ev in outcome.timeline:
		by_target_original[ev.target] = ev
	var by_target_rebuilt: Dictionary = {}
	for ev in rebuilt.timeline:
		by_target_rebuilt[ev.target] = ev

	for target_key in [n[2], n[3], n[4]]:
		var orig: PropagationEvent = by_target_original[target_key]
		var back: PropagationEvent = by_target_rebuilt[target_key]
		assert_eq(back.predecessors.size(), orig.predecessors.size(),
				"predecessor COUNT round-trips for target %s" % target_key.name)
		var orig_names: Array = []
		for p in orig.predecessors:
			orig_names.append(p.name if p != null else "null")
		var back_names: Array = []
		for p in back.predecessors:
			back_names.append(p.name if p != null else "null")
		assert_eq(back_names, orig_names,
				"predecessor IDENTITIES round-trip, in order, for target %s" % target_key.name)
		assert_eq(back.predecessor, orig.predecessor,
				"the singular canonical field still round-trips too")

	# The single-predecessor events (node 2, 3) must not have silently grown
	# or shrunk under the same encoding that the 2-predecessor event (node 4)
	# uses — this is the ragged encoding's actual failure mode: a naive
	# flat/count mismatch corrupts EVERY event once one event's count differs
	# from 1, not just the convergent one.
	assert_eq(by_target_rebuilt[n[2]].predecessors.size(), 1)
	assert_eq(by_target_rebuilt[n[3]].predecessors.size(), 1)
	assert_eq(by_target_rebuilt[n[4]].predecessors.size(), 2)


func test_capture_rebuild_round_trip_preserves_a_pure_single_predecessor_timeline() -> void:
	# Guard the boring case in isolation too: a straight line has no
	# convergence anywhere, so every event's predecessors set is size ≤ 1.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)

	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, graph), graph)
	assert_eq(rebuilt.timeline.size(), outcome.timeline.size())
	for i in outcome.timeline.size():
		assert_eq(rebuilt.timeline[i].predecessors.size(),
				outcome.timeline[i].predecessors.size())


# ── The reducer's own comment/field contract stays intact ───────────────────

func test_reducer_still_picks_a_single_canonical_predecessor() -> void:
	# incident_reducer.gd's `_merge_payload_defaults` deliberately keeps
	# picking incidents[0] for the merged CastSpell's singular `predecessor` —
	# #542 only stopped that choice from being the ONLY thing recorded.
	var res := _diamond_outcome()
	var outcome: AttackOutcome = res[0]
	var n: Array = res[1]
	var ev := _event_at(outcome, n[4])
	assert_eq(ev.predecessor, ev.predecessors[0],
			"the canonical predecessor is the first of the converging set")
