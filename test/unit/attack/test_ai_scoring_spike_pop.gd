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
##
## [b]Which arm carries the spike is no longer forced, and this note replaces
## one that said it was.[/b] #785 gave edges swept-capsule collision, which
## makes an arm's reach the whole DISC out to its radius rather than a ring at
## it — so the long arm's edge sweeps over everything the short arm can touch,
## and containment is one-way. That mattered while an edge could drain and
## sever against a spike: the spiked target had to sit on the LONG arm or no
## swing could be the "landed, popped nothing" control.
##
## [b]ADR 0005 retired that constraint.[/b] Edges never interact with spikes, so
## the long arm's edge crossing the short arm's target is inert — no drain, no
## severance, no damage — and either placement now works. The radii are left
## where #785 put them because swapping them back would churn a
## characterization fixture for no behavioural difference, NOT because the swap
## would break anything. The geometry note above survives on its own merits: it
## is why an inert edge contact still shows up in the event list below.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/spike_ring_addon.tscn")

const _SHORT := 150.0
const _LONG := 400.0

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _long_arm: SkillNode
var _short_arm: SkillNode
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

	# Pivot ── LongArm  (r=400, coincident with Spiked)
	#       └─ ShortArm (r=150, coincident with Plain)
	# Two radii so the SHORT arm's TAU sweep cannot reach the long arm's target;
	# see the #785 note in the class docstring for why the spike goes on the
	# long arm rather than the short one.
	_pivot = _spawn("Pivot", Vector2.ZERO)
	_long_arm = _spawn("LongArm", Vector2(_LONG, 0.0))
	_short_arm = _spawn("ShortArm", Vector2(_SHORT, 0.0))
	_graph.add_edge(_pivot, _long_arm)
	_graph.add_edge(_pivot, _short_arm)

	_spiked = _spawn("Spiked", Vector2(_LONG, 0.0))
	_plain = _spawn("Plain", Vector2(_SHORT, 0.0))

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _long_arm)
	_alloc.force_allocate(_attacker, _short_arm)
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
	var outcome := _swing(_long_arm)

	assert_gt(outcome.hits.size(), 0,
			"the swing must produce a contact or this proves nothing")
	assert_eq(outcome.popped_nodes, 1, "the spike popped exactly one vertex")
	for hit in outcome.hits:
		assert_eq(hit.effective_amount, 0.0,
				"the gate refused every contact, so nothing was ever applied")

	assert_eq(AiCombatScorer.expected_damage(outcome, _attacker), 0.0,
			"a swing whose only vertex popped deals no damage, so it banks no EV")


func test_an_unpopped_swing_still_banks_its_real_damage() -> void:
	var outcome := _swing(_short_arm)

	assert_eq(outcome.popped_nodes, 0, "an un-spiked target pops nothing")
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
	# Same silent no-op as _heavy_blade carried (#779): without
	# add_local_modifier this armor never applied, so "on a node with nonzero
	# armor" was vacuous and the assertion below compared 0 against 0.
	_plain.add_local_modifier(mod)
	await get_tree().process_frame

	var outcome := _swing(_short_arm)

	assert_gt(outcome.hits.size(), 0, "the far arm must connect")
	for hit in outcome.hits:
		assert_almost_eq(hit.effective_amount, Mitigation.apply(hit, hit.target), 0.001,
				"shadow-resolved mitigation matches the live node's formula")


# ---------------------------------------------------------------------------
# The behavioural statement
# ---------------------------------------------------------------------------

func test_the_ai_prefers_a_swing_that_lands_over_one_that_pops() -> void:
	var popped := AiCombatScorer.score(BattleSystem.AttackMode.MELEE,
			_swing(_long_arm), _spiked, _attacker, 0)
	var landed := AiCombatScorer.score(BattleSystem.AttackMode.MELEE,
			_swing(_short_arm), _plain, _attacker, 0)

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
## LongArm carries the HEAVIER raw `blade_damage` on purpose. [method
## AiBladeRollout._primary_target] ranks by the largest single hit, and the
## whole point of #692 is that a popped hit's raw `amount` is a lie — so the
## fixture is built to make the lie win if anyone reads it.
func _heavy_blade(node: SkillNode, bonus: float) -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = bonus
	# add_local_modifier, NOT node_board.add_modifier (#779). The bare board
	# call binds the modifier but never mints the node-local Stat that
	# get_local_value() reads, so the bonus silently did nothing: both arms
	# measured blade_damage 2.0 and `raw_best` below was decided by a
	# coincidental tie-break, not by this fixture's stated margin.
	node.add_local_modifier(mod)


func _mixed_swing() -> AttackOutcome:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_long_arm, _short_arm]
	assert_true(plan.is_valid(), "fixture plan should validate: %s" % str(plan.validate()))
	return plan.resolve()


func test_a_mixed_swing_banks_only_the_arm_that_landed() -> void:
	_heavy_blade(_long_arm, 20.0)
	await get_tree().process_frame

	var far_only := AiCombatScorer.expected_damage(_swing(_short_arm), _attacker)
	assert_gt(far_only, 0.0, "the far arm alone must land something to compare against")

	var outcome := _mixed_swing()
	assert_eq(outcome.popped_nodes, 1,
			"the long arm popped; the short arm hangs off the pivot and survives it")
	assert_almost_eq(AiCombatScorer.expected_damage(outcome, _attacker), far_only, 0.001,
			"the popped arm contributes nothing and the landed arm contributes all of it")


## The popped contact's RAW amount is the biggest number in the outcome, so a
## `hit.amount` ranking names the spiked node — and [method AiCombatScorer.score]
## would then compare the whole swing's EV against the HP of a node that took
## none of it, handing out `_KILL_BONUS` for a kill that cannot happen.
func test_the_primary_target_is_the_node_that_actually_took_damage() -> void:
	_heavy_blade(_long_arm, 20.0)
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
	var outcome := _swing(_long_arm)
	var visible: Array[SkillNode] = [_spiked, _plain]

	assert_gt(outcome.hits.size(), 0, "there were contacts — they just all popped")
	assert_null(AiBladeRollout._primary_target(outcome, visible),
			"no damaged node means no candidate")


# ---------------------------------------------------------------------------
# #799 — an ORPHAN is not a loss, however many of them one pop makes
# ---------------------------------------------------------------------------

## A chain blade, Pivot ── LongArm ── Outboard ── Tip, swung so LongArm pops on
## the spiked node. Everything past LongArm loses its path to the pivot, so the
## gate's `dead_at` holds all THREE vertices — but only one of them was
## destroyed. Since #186 the other two coast on as a free fragment, still armed
## and still landing their own hits, which is why counting them as losses made
## the AI's shape-risk term over-avoid spiked defenders.
##
## [b]Two orphans, not one, and that is the whole point of the fixture.[/b] A
## single orphan cannot tell the acceptance apart from an off-by-one: `dead_at`
## would read 2, and "counts pops" and "counts pops + 1" both produce it. With
## two, the wrong answers are 3 (`dead_at.size()`, what this issue replaces) and
## 2, while the right one stays at 1 however long the severed tail gets.
var _chain_plan: MeleeAttackPlan


func _chain_swing() -> AttackOutcome:
	# Three-node blade, so blade_size has to clear it — before_each authors 2.
	_attacker.stat_board.blade_size.base_value = 3.0
	var outboard := _spawn("Outboard", Vector2(_LONG * 2.0, 0.0))
	var tip := _spawn("Tip", Vector2(_LONG * 3.0, 0.0))
	await get_tree().process_frame
	_alloc.force_allocate(_attacker, outboard)
	_alloc.force_allocate(_attacker, tip)
	_graph.add_edge(_long_arm, outboard)
	_graph.add_edge(outboard, tip)
	await get_tree().process_frame
	await get_tree().physics_frame

	_chain_plan = MeleeAttackPlan.new()
	_chain_plan.attacker = _attacker
	_chain_plan.source = _pivot
	_chain_plan.blade_nodes = [_long_arm, outboard, tip]
	assert_true(_chain_plan.is_valid(),
			"fixture plan should validate: %s" % str(_chain_plan.validate()))
	return _chain_plan.resolve()


func test_an_orphaned_vertex_is_not_counted_as_a_loss() -> void:
	var outcome := await _chain_swing()
	var result := _chain_plan.last_live_gate.result

	assert_eq(result.pops.size(), 1, "fixture check: exactly one vertex was destroyed")
	assert_eq(result.dead_at.size(), 3,
			"fixture check: that pop orphaned TWO more, so `dead_at` is the wider set")
	assert_eq(outcome.popped_nodes, 1,
			"one pop is one loss no matter how many vertices it orphaned")


## The same rule on a vertex that is no longer steered. Under the owner's model
## a severed vertex is not a different KIND of thing — it is the same sim
## element with one constraint fewer — so a spike that destroys it destroys it
## on exactly the terms a driven vertex is destroyed on, and it counts.
##
## [b]Deliberately mechanism-free.[/b] It names no free-flight symbol and reads
## no per-round gate: the statement is "put a spike on the severed vertex's
## path and the loss count goes up by one", which is true of #186's separate
## coasting pass and stays true under #801, where severance becomes a constraint
## removal inside one sim and there is no second pass to name.
##
## Geometry: the coincident spike is deallocated so the blade actually ROTATES
## before it pops (the fixture's targets sit on the arms at t=0, which would pop
## at t≈0.008 with no separation speed and leave the remainder sitting still).
## SpikedFar sits a quarter turn round at the long arm's radius; the outboard
## vertex separates there at t≈0.383 and coasts out through the third quadrant.
## `_ON_PATH` is a sampled point of that coast, well outside the driven blade's
## own reach — which by then is the pivot alone, the long arm having died.
const _ON_PATH := Vector2(-246.7, 408.4)


func _severed_swing(spike_on_path: bool) -> AttackOutcome:
	_alloc.force_deallocate(_spiked)
	var far := _spawn("SpikedFar", Vector2(0.0, _LONG))
	var outboard := _spawn("Outboard", Vector2(_LONG * 2.0, 0.0))
	var on_path: SkillNode = _spawn("SpikedOnPath", _ON_PATH) if spike_on_path else null
	await get_tree().process_frame
	_alloc.force_allocate(_defender, far)
	_arm_spike(far, 5.0)
	_alloc.force_allocate(_attacker, outboard)
	_graph.add_edge(_long_arm, outboard)
	if on_path != null:
		_alloc.force_allocate(_defender, on_path)
		_arm_spike(on_path, 5.0)
	await get_tree().process_frame
	await get_tree().physics_frame

	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_long_arm, outboard]
	assert_true(plan.is_valid(), "fixture plan should validate: %s" % str(plan.validate()))
	return plan.resolve()


func test_a_severed_vertex_that_meets_nothing_costs_only_the_struck_arm() -> void:
	assert_eq((await _severed_swing(false)).popped_nodes, 1,
			"control: the severance itself is not a loss, so only the struck arm counts")


func test_a_spike_that_destroys_an_unsteered_vertex_still_costs_it() -> void:
	assert_eq((await _severed_swing(true)).popped_nodes, 2,
			"the severed vertex met a spike of its own — one constraint fewer, still a loss")
