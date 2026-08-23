extends GutTest

## #500's last acceptance item, pinned in isolation: **no mode's application
## discovers a target that resolution did not emit.**
##
## `docs/domain/attack-timeline.md` states it as *"the gate is a veto, not a
## re-plan. A landing that fails its gate is dropped. Application never
## discovers new targets."* Re-aiming a wasted shot at some other live target is
## the one shape of the land-time gate that breaks everything downstream: an
## [AttackOutcome] would stop being usable as a preview or as AI scoring input,
## and an [AttackRecord] would stop being replayable, since a peer REPLAYS
## landings rather than re-deriving them.
##
## Until now this rested on implicit coverage — `test_attack_record_replay.gd`
## and `test_outcome_fixture_replay.gd` would both go red if application
## invented a landing, but neither of them says so, so neither would tell you
## WHY. These do.
##
## Two shapes, because "discovers a target" has two distinct failure modes:
##
##   **A. Application APPENDS a landing.** The live seam is on-hit effects:
##      they hold the [AttackOutcome] and append to it (`eff.apply(state,
##      outcome)` in [SpellResolver]), which is legal during RESOLUTION and must
##      never happen from inside [OutcomeApplier]. Checked by re-applying a
##      finished outcome and asserting it did not grow.
##
##   **B. Gating GROWS the target set.** A cast whose early landings kill things
##      must land on a SUBSET of what the identical cast lands on when nothing
##      dies. Killing can only remove candidates. This is the behavioural half,
##      and magic is where it bites — its gate lives in candidate selection, so
##      it is the only mode that could expand a walk rather than merely veto a
##      landing.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## One point over the `node_health` scaffold's default of 10, so a lethal wave
## is lethal by the smallest margin that proves the point. Same constant and
## same reasoning as `test/unit/spell/test_wave_gating.gd`.
const _LETHAL_POWER: float = 11.0


# ── Fixture ──────────────────────────────────────────────────────────────────
#
# Built here rather than borrowed from SpellTestHelper for the reason
# test_wave_gating.gd gives: the gate needs a defender whose owned subgraph a
# shadow can actually snapshot, which means real AllocationSystem ownership
# (the helper writes `owned_by` directly and never mirrors) plus a
# `core_location` for a cascade to island against.

func _make_entity(graph: Graph, nm: String) -> Entity:
	var ent := Entity.new()
	ent.display_name = nm
	# Its own one-member camp: both entities otherwise inherit `npc.tres` and
	# read as ALLIED, which makes every hostile filter admit nothing at all.
	var camp := Faction.new()
	camp.id = StringName("discovers_nothing_%s_%d" % [nm, ent.get_instance_id()])
	ent.faction = camp
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Exact-landing assertions behind a real resolve must zero this, per
	# .claude/rules/testing.md — the default board crits 5% of hits.
	ent.stat_board.get_stat(&"crit_chance").base_value = 0.0
	graph.add_child(ent)
	return ent


func _spawn(graph: Graph, nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _connect(graph: Graph, a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	graph.edges_container.add_child(e)


## Attacker on a hub, defender on a line of [param defender_nodes] hanging off
## it. [param target_health] bottomless by default so nothing dies; pass
## something small to make the first landing lethal and the rest gated duds.
func _world(defender_nodes: int, target_health: float = 9999.0) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate() as Graph
	add_child_autofree(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)

	var attacker := _make_entity(graph, "Attacker")
	var defender := _make_entity(graph, "Defender")
	defender.stat_board.get_stat(&"node_health").base_value = target_health
	# Non-zero offense, or every hit is amount 0, CritRoll skips it and a
	# "nothing landed" result would pass vacuously.
	attacker.stat_board.get_stat(&"dexterity").base_value = 100.0
	await get_tree().process_frame

	var hub := _spawn(graph, "Hub", Vector2.ZERO)
	alloc.force_allocate(attacker, hub)
	attacker.core_location = hub

	var owned: Array[SkillNode] = []
	var prev := hub
	for i in defender_nodes:
		var sn := _spawn(graph, "D%d" % i, Vector2(120.0 * (i + 1), 0.0))
		_connect(graph, prev, sn)
		alloc.force_allocate(defender, sn)
		owned.append(sn)
		prev = sn
	# The core sits at the far end, so every node before it is an ordinary one
	# a cascade is allowed to strip.
	defender.core_location = owned[owned.size() - 1]
	await get_tree().process_frame

	return {
		graph = graph, alloc = alloc, attacker = attacker,
		defender = defender, hub = hub, owned = owned,
	}


## Landing targets by NAME, in application order. Names rather than references
## so two runs built on two separate graphs stay comparable, and so a failure
## message reads as node names instead of instance ids.
func _targets_of(outcome: AttackOutcome) -> Array[String]:
	var out: Array[String] = []
	for hit in OutcomeApplier.in_arrival_order(outcome.hits):
		out.append(hit.target.name if hit.target != null else "<null>")
	return out


## Shape A, shared by all three modes: hand a FINISHED outcome back to the
## applier against a fresh world and assert it neither grew nor re-aimed.
##
## Un-awaited on purpose, exactly as `RangedAttackPlan.resolve_against` calls
## it: the default clock is `BeatClock.instant_clock()`, which never parks, so
## `apply` runs to completion synchronously.
func _assert_reapply_discovers_nothing(outcome: AttackOutcome, label: String) -> void:
	var count_before := outcome.hits.size()
	assert_gt(count_before, 0,
			"%s: the fixture must produce landings or this proves nothing" % label)
	var targets_before := _targets_of(outcome)

	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	world.free_shadow()

	assert_eq(outcome.hits.size(), count_before,
			("%s: application APPENDED a landing — resolution is no longer the "
			+ "authority on what this attack hits") % label)
	assert_eq(_targets_of(outcome), targets_before,
			("%s: application RE-AIMED a landing — the gate is a veto, never a "
			+ "re-plan") % label)


# ── Shape A: application appends nothing, re-aims nothing ────────────────────

func test_ranged_application_appends_no_landing_and_re_aims_none() -> void:
	var w: Dictionary = await _world(1)
	# Ranged fires from LEAVES of the attacker's own subgraph
	# (`get_firing_positions` -> `navigator.get_leaf_nodes`), so the lone hub is
	# not a firing position — it needs an arm. Target coincident with it so the
	# shot is unambiguously in range and this test stays about the applier
	# rather than about range-finding (the trick `test_attack_determinism.gd`'s
	# ranged fixture uses).
	var leaf := _spawn(w.graph, "Leaf", Vector2.ZERO)
	_connect(w.graph, w.hub, leaf)
	(w.alloc as AllocationSystem).force_allocate(w.attacker, leaf)
	w.owned[0].global_position = Vector2.ZERO
	await get_tree().process_frame
	var plan := RangedAttackPlan.new()
	plan.attacker = w.attacker
	plan.target = w.owned[0]
	var shadow := CombatWorld.shadow()
	var outcome := plan.resolve_against(shadow)
	shadow.free_shadow()
	_assert_reapply_discovers_nothing(outcome, "ranged")


func test_melee_application_appends_no_landing_and_re_aims_none() -> void:
	var w: Dictionary = await _world(1)
	var graph: Graph = w.graph
	var alloc: AllocationSystem = w.alloc
	var attacker: Entity = w.attacker
	attacker.stat_board.blade_size.base_value = 2.0
	# An arm for the blade to be forged from, and a target sitting on top of it
	# so the swing scans a hit without depending on physics-server sync timing
	# (the same trick as test_melee_swing_characterization.gd).
	var arm := _spawn(graph, "Arm", Vector2(150, 0))
	_connect(graph, w.hub, arm)
	alloc.force_allocate(attacker, arm)
	w.owned[0].global_position = Vector2(150, 0)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan._on_node_left_clicked(w.hub)
	plan._on_node_left_clicked(arm)
	var shadow := CombatWorld.shadow()
	var outcome := plan.resolve_against(shadow)
	shadow.free_shadow()
	_assert_reapply_discovers_nothing(outcome, "melee")


func test_magic_application_appends_no_landing_and_re_aims_none() -> void:
	# Magic is the mode this half is really about: its on-hit effects hold the
	# outcome and append to it, which is legal during resolution and must never
	# happen while the applier is walking.
	var w: Dictionary = await _world(2)
	var outcome := SpellResolver.resolve(
			_spell(_LETHAL_POWER), w.owned[0], w.hub, w.attacker, w.graph)
	_assert_reapply_discovers_nothing(outcome, "magic")


# ── Shape B: gating removes candidates, it never adds any ────────────────────

## A two-hop hostile fan that may revisit a node — the same shape as
## test_wave_gating.gd's, which is what lets a later wave come back to a node
## an earlier one hit.
func _spell(power: float) -> SpellDef:
	var config := PropagationConfig.new()
	config.step = FanAllStep.new()
	var f := OwnerFilter.new()
	f.ownership_filter = SkillNode.Ownership.HOSTILE
	config.filter = f
	config.max_hops = 2
	config.max_visits_per_node = 2
	var spell := SpellDef.new()
	spell.propagation = config
	spell.on_hit_effects = [DamageEffect.new()]
	spell.power = power
	return spell


## THE statement of the acceptance item, behaviourally: the identical cast, with
## the identical filter over the identical topology, differing ONLY in whether
## its landings kill — must land on a subset. A gate that removes candidates
## produces a subset; a gate that re-plans produces something else.
##
## Magic carries this test because it is the only mode whose gate lives in
## candidate SELECTION rather than in landing consumption, so it is the only one
## that could grow a walk rather than merely veto a landing.
func test_a_lethal_cast_lands_on_a_subset_of_what_a_harmless_one_lands_on() -> void:
	var control: Dictionary = await _world(2)
	var harmless := SpellResolver.resolve(
			_spell(1.0), control.owned[0], control.hub, control.attacker, control.graph)
	var admitted := _targets_of(harmless)
	assert_gt(admitted.size(), 1,
			"the control must actually propagate, or a subset assertion is free")

	var lethal_world: Dictionary = await _world(2, 10.0)
	var lethal := SpellResolver.resolve(
			_spell(_LETHAL_POWER), lethal_world.owned[0], lethal_world.hub,
			lethal_world.attacker, lethal_world.graph)
	var landed := _targets_of(lethal)
	assert_gt(landed.size(), 0, "the lethal cast must land something")

	# Multiset containment, not set containment: a walk that legitimately hits
	# one node twice must not be able to hide a THIRD invented landing on it.
	var budget: Dictionary = {}
	for nm in admitted:
		budget[nm] = int(budget.get(nm, 0)) + 1
	for nm in landed:
		var left := int(budget.get(nm, 0))
		assert_gt(left, 0,
				("the lethal cast landed on %s more often than the harmless one "
				+ "could — killing a node cannot ADMIT a candidate, only refuse "
				+ "one (control: %s, lethal: %s)") % [nm, admitted, landed])
		budget[nm] = left - 1

	assert_lt(landed.size(), admitted.size(),
			("precondition, not the claim: the lethal cast must actually lose "
			+ "landings to its own kills, or this test would pass on a build "
			+ "with no gate at all (control: %s, lethal: %s)") % [admitted, landed])
