extends GutTest

## #692 — the AI must not bank EV for a blade vertex a defensive spike pops.
##
## [method BladePopResolver.LiveGate.admit] refuses a popped vertex's contact,
## so [method BladeDamageInstance.land_on] never reaches
## [method NodeCombat.take_damage] and the hit's
## [member HitInstance.effective_amount] stays 0.0. But the hit is still IN
## [member AttackOutcome.hits] with its pre-mitigation `amount` intact (#502:
## melee pre-filters nothing at resolve), so any scorer that re-derives damage
## from `amount` credits a swing that dealt none — the owner's #537 report,
## verbatim: [i]"AI can do melee attacks whose blade nodes get neutralized by
## spikes immediately, i bet it still ranks it as if it would deal damage"[/i].
##
## The fixture is the one from `test_melee_swing_characterization.gd` (positions
## coincident at t=0, so the outcome does not depend on physics-server sync),
## widened to a second arm at a second radius: a full swing sweeps a complete
## TAU circle, so the only way to give one arm a target the OTHER arm cannot
## also reach is to put the two targets on different-radius circles.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _NEAR := 150.0
const _FAR := 320.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _near_arm: SkillNode
var _far_arm: SkillNode
var _spiked: SkillNode
var _plain: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 2.0
	_graph.add_child(_attacker)

	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Explicit hostile camp — Entity's default `npc.tres` reads ALLIED, and the
	# blade passes through allied territory without touching it.
	var enemy_camp := Faction.new()
	enemy_camp.id = &"spike_pop_scoring_enemy"
	_defender.faction = enemy_camp
	_graph.add_child(_defender)

	# Pivot ── NearArm (r=150, coincident with Spiked)
	#       └─ FarArm  (r=320, coincident with Plain)
	# Two radii so neither arm's TAU sweep can reach the other's target.
	_pivot = _spawn("Pivot", Vector2.ZERO)
	_near_arm = _spawn("NearArm", Vector2(_NEAR, 0.0))
	_far_arm = _spawn("FarArm", Vector2(_FAR, 0.0))
	_graph.add_edge(_pivot, _near_arm)
	_graph.add_edge(_pivot, _far_arm)

	_spiked = _spawn("Spiked", Vector2(_NEAR, 0.0))
	_plain = _spawn("Plain", Vector2(_FAR, 0.0))

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _near_arm)
	_alloc.force_allocate(_attacker, _far_arm)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _spiked)
	_alloc.force_allocate(_defender, _plain)
	_defender.core_location = _plain

	_arm_spike(_spiked, 5.0)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _arm_spike(node: SkillNode, power: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = power
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	spike.local_modifiers = [mod]
	node.add_child(spike)


func _swing(arm: SkillNode) -> AttackOutcome:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [arm]
	assert_true(plan.is_valid(), "fixture plan should validate: %s" % str(plan.validate()))
	return plan.resolve()


# ---------------------------------------------------------------------------
# The arithmetic statement
# ---------------------------------------------------------------------------

func test_a_popped_vertex_banks_no_expected_damage() -> void:
	var outcome := _swing(_near_arm)

	assert_gt(outcome.hits.size(), 0,
			"the swing must produce a contact or this proves nothing")
	assert_eq(outcome.thinned_nodes, 1, "the spike popped exactly one vertex")
	for hit in outcome.hits:
		assert_eq(hit.effective_amount, 0.0,
				"the gate refused every contact, so nothing was ever applied")

	assert_eq(AiCombatScorer.expected_damage(outcome, _attacker), 0.0,
			"a swing whose only vertex popped deals no damage, so it banks no EV")


func test_an_unpopped_swing_still_banks_its_real_damage() -> void:
	var outcome := _swing(_far_arm)

	assert_eq(outcome.thinned_nodes, 0, "an un-spiked target pops nothing")
	assert_gt(AiCombatScorer.expected_damage(outcome, _attacker), 0.0,
			"a real hit must still score — the fix must not zero everything")


## The advisor-flagged sanity check on the seam the fix crosses:
## `effective_amount` is computed against the SHADOW slice's armor
## ([method NodeCombat.take_damage]'s `host == null` branch), while the old
## scorer read the LIVE node through [method Mitigation.apply]. On a node with
## nonzero armor the two must still agree, or the shadow's board clone is lossy.
func test_shadow_effective_amount_agrees_with_live_mitigation() -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"armor"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 2.0
	_plain.node_board.add_modifier(mod)
	await get_tree().process_frame

	var outcome := _swing(_far_arm)

	assert_gt(outcome.hits.size(), 0, "the far arm must connect")
	for hit in outcome.hits:
		assert_almost_eq(hit.effective_amount, Mitigation.apply(hit, hit.target), 0.001,
				"shadow-resolved mitigation matches the live node's formula")


# ---------------------------------------------------------------------------
# The behavioural statement
# ---------------------------------------------------------------------------

func test_the_ai_prefers_a_swing_that_lands_over_one_that_pops() -> void:
	var popped := AiCombatScorer.score(BattleSystem.AttackMode.MELEE,
			_swing(_near_arm), _spiked, _attacker, 0)
	var landed := AiCombatScorer.score(BattleSystem.AttackMode.MELEE,
			_swing(_far_arm), _plain, _attacker, 0)

	var candidates: Array[AiCombatScorer.ScoredCandidate] = [popped, landed]
	assert_eq(AiCombatScorer.pick_best(candidates), landed,
			"the swing that actually deals damage has to win")


# ---------------------------------------------------------------------------
# The mixed swing — one arm pops, the other lands
# ---------------------------------------------------------------------------

## Everything above swings ONE arm, so nothing there distinguishes "sums each
## hit's landed damage" from "returns 0 whenever anything popped". A two-arm
## blade does: NearArm pops on the spiked node while FarArm connects on the
## plain one, and only the second contributes.
##
## NearArm carries the HEAVIER raw `blade_damage` on purpose. [method
## AiBladeRollout._primary_target] ranks by the largest single hit, and the
## whole point of #692 is that a popped hit's raw `amount` is a lie — so the
## fixture is built to make the lie win if anyone reads it.
func _heavy_blade(node: SkillNode, bonus: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = bonus
	node.node_board.add_modifier(mod)


func _mixed_swing() -> AttackOutcome:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_near_arm, _far_arm]
	assert_true(plan.is_valid(), "fixture plan should validate: %s" % str(plan.validate()))
	return plan.resolve()


func test_a_mixed_swing_banks_only_the_arm_that_landed() -> void:
	_heavy_blade(_near_arm, 20.0)
	await get_tree().process_frame

	var far_only := AiCombatScorer.expected_damage(_swing(_far_arm), _attacker)
	assert_gt(far_only, 0.0, "the far arm alone must land something to compare against")

	var outcome := _mixed_swing()
	assert_eq(outcome.thinned_nodes, 1,
			"the near arm popped; the far arm hangs off the pivot and survives it")
	assert_almost_eq(AiCombatScorer.expected_damage(outcome, _attacker), far_only, 0.001,
			"the popped arm contributes nothing and the landed arm contributes all of it")


## The popped contact's RAW amount is the biggest number in the outcome, so a
## `hit.amount` ranking names the spiked node — and [method AiCombatScorer.score]
## would then compare the whole swing's EV against the HP of a node that took
## none of it, handing out `_KILL_BONUS` for a kill that cannot happen.
func test_the_primary_target_is_the_node_that_actually_took_damage() -> void:
	_heavy_blade(_near_arm, 20.0)
	await get_tree().process_frame

	var outcome := _mixed_swing()
	var visible: Array[SkillNode] = [_spiked, _plain]

	var raw_best: SkillNode = null
	var raw_amount := -1.0
	for hit in outcome.damage_hits():
		if hit.amount > raw_amount:
			raw_amount = hit.amount
			raw_best = hit.target
	assert_eq(raw_best, _spiked,
			"fixture check: ranking on raw amount really does name the popped node")

	assert_eq(AiBladeRollout._primary_target(outcome, visible), _plain,
			"the candidate's anchor is the node the swing actually damaged")


## A swing where EVERY vertex popped anchors on nothing — `_primary_target`
## returns null and [method AiBladeRollout._resolve_and_score] drops the
## candidate rather than emitting a 0-EV one. Pinned deliberately: reading
## `effective_amount` against a `-1.0` seed would instead have returned the
## first gated hit and kept a candidate that can only ever lose.
func test_a_fully_popped_swing_anchors_on_nothing() -> void:
	var outcome := _swing(_near_arm)
	var visible: Array[SkillNode] = [_spiked, _plain]

	assert_gt(outcome.hits.size(), 0, "there were contacts — they just all popped")
	assert_null(AiBladeRollout._primary_target(outcome, visible),
			"no damaged node means no candidate")
