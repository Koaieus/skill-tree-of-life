extends GutTest

## Coverage for #378 slice B — [AIController]'s AP×2 attack loop: candidate
## scoring via [AiCombatScorer] wired into `take_turn()`, dent-then-finish
## re-eval, the 1-damage floor, and near-miss-aware frontier growth.
##
## Separate fixture from test_ai_controller.gd because those tests rely on
## "no hostile anywhere in the graph" for the fog short-circuit; this file
## needs a real, visible hostile + a headless [BattleSystem] to exercise the
## attack step.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _SPARK_SPELL := preload("res://attack/spell/defs/spark.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _bs: BattleSystem
var _player: Entity
var _enemy: Entity
var _hostile: Entity
var _ai: AIController
var _nodes: Array[SkillNode] # N0 (AI core) - N1 (AI leaf)      H0 (hostile core)

var _decisions: Array[String] = []
var _launches: Array[BattleSystem.AttackMode] = []


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Zero the board's 5 % baseline crit. Since #507 ranged rolls crits off a
	# freshly randomized per-attack seed, so a test that chips a target to
	# EXACTLY two shots' worth and asserts the first volley leaves it alive
	# would otherwise flake whenever a shot doubles. Same reason
	# `SpellTestHelper.make_entity` does it: damage-math tests shouldn't have
	# to manage a seed just to avoid noise.
	e.stat_board.get_stat(&"crit_chance").base_value = 0.0
	if faction != null:
		e.faction = faction
	return e


func before_each() -> void:
	_decisions = []
	_launches = []

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	# #504: land each attack in one go. These tests are about the AI's
	# DECISIONS — what it targets, how it re-evaluates after a dent, whether it
	# spends both AP — none of which is about presentation timing. On the real
	# beat clock every `await bs.launch_attack()` inside `take_turn` would wait
	# out the full arrival ramp, making an AI turn take seconds of wall time.
	_bs.instant_mutation = true
	add_child(_bs)

	# Since #512 the AI mutates only through the applier — a fixture without
	# one has an AI that decides and never acts.
	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _bs
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	# Idle second entity so the clock parks somewhere after the AI ends its
	# turn (see test_ai_controller.gd's before_each for why).
	_player = _make_entity("Player")
	_graph.entities_container.add_child(_player)
	_player.add_child(PlayerController.new())

	_enemy = _make_entity("Enemy")
	_graph.entities_container.add_child(_enemy)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.command_applier_override = _applier
	_ai.battle_system_override = _bs
	_enemy.add_child(_ai)

	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.entities_container.add_child(_hostile)

	await get_tree().process_frame

	_alloc.force_allocate(_enemy, _nodes[0])
	_enemy.core_location = _nodes[0]
	_alloc.force_allocate(_enemy, _nodes[1])
	_alloc.force_allocate(_hostile, _nodes[2])
	_hostile.core_location = _nodes[2]

	# N0 (0,0) - N1 (100,0) ... H0 (300,0): N1 is within default `range` (400)
	# of H0.
	_nodes[0].global_position = Vector2.ZERO
	_nodes[1].global_position = Vector2(100.0, 0.0)
	_nodes[2].global_position = Vector2(300.0, 0.0)

	# No SP to spend — isolates the attack loop from the frontier-growth step
	# except where a test explicitly grants SP.
	_enemy.stat_board.skill_points.set_current(0)

	Events.ai_decision.connect(_on_ai_decision)
	_bs.attack_launched.connect(_on_attack_launched)


func after_each() -> void:
	if Events.ai_decision.is_connected(_on_ai_decision):
		Events.ai_decision.disconnect(_on_ai_decision)


func _on_ai_decision(_entity: Entity, summary: String) -> void:
	_decisions.append(summary)


func _on_attack_launched(mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
	_launches.append(mode)


## Routes through Graph.add_edge (emits edge_added) rather than a raw child-add
## — the magic candidate tests need graph.navigator (the GLOBAL mirror
## HopRangeFinder traverses) to actually see the edge; a raw
## edges_container.add_child skips that signal entirely. See .claude/rules/graph.md.
func _add_edge(a: SkillNode, b: SkillNode) -> void:
	_graph.add_edge(a, b)


func _true_damage(target: SkillNode, amount: float) -> void:
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.amount = amount
	target.take_damage(amount, dmg)


# ---------------------------------------------------------------------------
# Basic ranged attack, no regression from slice A's fixed-priority behaviour
# ---------------------------------------------------------------------------

func test_ranged_attack_launched_when_hostile_visible_and_reachable() -> void:
	_tm.start_turn(_enemy)

	await get_tree().create_timer(0.3).timeout

	assert_true(_launches.has(BattleSystem.AttackMode.RANGED), "should have fired a ranged attack")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended")


# ---------------------------------------------------------------------------
# Dent-then-finish across the AP×2 loop
# ---------------------------------------------------------------------------

func test_dent_then_finish_on_ap2() -> void:
	# Chip H0 to exactly 2 shots' worth: AP1 dents (survives), AP2 kills.
	var per_shot: float = float(_nodes[1].get_local_value(&"ranged_damage"))
	_true_damage(_nodes[2], _nodes[2].get_current_hp() - per_shot * 2.0)
	assert_almost_eq(_nodes[2].get_current_hp(), per_shot * 2.0, 0.01)

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_eq(_launches.count(BattleSystem.AttackMode.RANGED), 2,
			"both AP should have gone into finishing H0")
	var kill_decisions := _decisions.filter(func(s): return s.find("kill=yes") != -1)
	assert_eq(kill_decisions.size(), 1, "AP2's re-eval should read the dent and score a kill")


# ---------------------------------------------------------------------------
# 1-damage floor
# ---------------------------------------------------------------------------

func test_one_damage_floor_spends_ap_even_without_a_kill_this_turn() -> void:
	# H0 starts at full HP (fixture default) — far more than either AP can
	# remove this turn. The acceptance property is "no minimum-EV gate blocks
	# an attack" — the assertions below are what demonstrate it, not this line.
	var target_hp := _nodes[2].get_current_hp()
	var per_shot: float = float(_nodes[1].get_local_value(&"ranged_damage"))
	assert_gt(target_hp, per_shot * 2.0, "fixture should not be killable in one turn")

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_eq(_launches.count(BattleSystem.AttackMode.RANGED), 2,
			"both AP should be spent chipping H0 even though neither kills")
	assert_lt(_nodes[2].get_current_hp(), target_hp, "H0 should have taken damage")


# ---------------------------------------------------------------------------
# Tactical-leaf-for-near-miss-kill (frontier growth)
# ---------------------------------------------------------------------------

func test_frontier_growth_prioritizes_near_miss_enabling_leaf() -> void:
	# Move H0 out of N1's attack reach but keep it inside vision (boosted so
	# the fog gate doesn't hide the very target the heuristic is meant to
	# react to), chip it to a 1-shot kill, and give the AI two frontier
	# candidates off N1: one that reaches H0, one that doesn't.
	_enemy.stat_board.vision_range.base_value = 700.0
	_nodes[2].global_position = Vector2(600.0, 0.0)
	var per_shot: float = float(_nodes[1].get_local_value(&"ranged_damage"))
	_true_damage(_nodes[2], _nodes[2].get_current_hp() - per_shot)

	var enabling := _SKILL_NODE_SCENE.instantiate() as SkillNode
	enabling.name = "Enabling"
	_graph.add_skill_node(enabling)
	_add_edge(_nodes[1], enabling)
	enabling.global_position = Vector2(250.0, 0.0) # within `range` (400) of H0 (600,0)

	var decoy := _SKILL_NODE_SCENE.instantiate() as SkillNode
	decoy.name = "Decoy"
	_graph.add_skill_node(decoy)
	_add_edge(_nodes[1], decoy)
	decoy.global_position = Vector2(100.0, 50.0) # closer to AI core, useless for the kill

	await get_tree().process_frame

	# Order, not exclusivity, is the acceptance bar — turn-start XP upkeep can
	# mint enough SP to eventually allocate both, but the near-miss enabler
	# must come FIRST.
	var allocation_order: Array[SkillNode] = []
	enabling.owner_changed.connect(func(): allocation_order.append(enabling))
	decoy.owner_changed.connect(func(): allocation_order.append(decoy))

	_enemy.stat_board.skill_points.set_current(1)
	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_eq(enabling.owned_by, _enemy, "growth should prefer the leaf that lands the near-miss kill")
	assert_gt(allocation_order.size(), 0, "at least the enabling leaf should have been allocated")
	assert_eq(allocation_order[0], enabling, "the near-miss enabler must be allocated before the decoy")


# ---------------------------------------------------------------------------
# Magic candidates — the third mode, and the AP-progress guard
# ---------------------------------------------------------------------------

## Push H0 out of ranged's Euclidean `range` (so RangedAttackPlan invalidates
## and never enters the candidate pool at all) but connect it to N1 by a
## direct edge, so Spark's hop-based [HopRangeFinder] (3 hops, position-
## independent) still reaches it. Isolates "can a magic candidate be gathered
## and executed" from "does it currently out-damage ranged" — Spark's
## resolved damage in this default board is INT-formula-driven, not the
## flat 5 its description advertises, so it isn't reliably higher-EV than a
## reaching ranged shot.
func _make_ranged_unreachable_but_magic_reachable() -> void:
	_enemy.stat_board.vision_range.base_value = 6000.0 # keep H0 fog-visible despite the move
	_nodes[2].global_position = Vector2(5000.0, 0.0)
	_add_edge(_nodes[1], _nodes[2])


func test_magic_candidate_is_gathered_and_can_be_executed() -> void:
	# N1 has degree 1 (edge to N0) >= Spark's min_degree (1).
	_make_ranged_unreachable_but_magic_reachable()
	_enemy.get_spellbook().learn(_SPARK_SPELL)

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_true(_launches.has(BattleSystem.AttackMode.MAGIC),
			"the only reachable candidate this turn is magic")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended normally")


func test_magic_insufficient_mana_is_excluded_rather_than_stalling_the_turn() -> void:
	# Ranged is unreachable and mana can't afford the only known spell —
	# _gather_magic_candidates filters unaffordable spells out (mana isn't
	# gated by MagicAttackPlan.validate(), and BattleSystem.launch_attack's
	# mana bail doesn't deduct AP or clear the plan, which would otherwise
	# stall the AP loop with AP left unspent — the 1-damage floor requires
	# ending the turn cleanly, not hanging on an unaffordable pick).
	#
	# Cost set absurdly high rather than draining `mana` to 0: turn-start
	# upkeep ADDS `mana_per_turn` before take_turn runs (same shape as the
	# SP-minting gotcha in .claude/rules/turn-manager.md), so a pre-turn
	# `mana.set_current(0.0)` doesn't stay 0 by the time the AP loop reads it.
	_make_ranged_unreachable_but_magic_reachable()
	var unaffordable_spark := _SPARK_SPELL.duplicate(true) as SpellDef
	unaffordable_spark.mana_cost = 999
	_enemy.get_spellbook().learn(unaffordable_spark)

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_ne(_tm.current_entity, _enemy, "turn must still end, not hang on an unaffordable cast")
	assert_false(_launches.has(BattleSystem.AttackMode.MAGIC),
			"the unaffordable spell must never be launched")
	assert_true(_decisions.has("no reachable attack this turn"),
			"with ranged unreachable and magic unaffordable, nothing was left to do: %s" % str(_decisions))


# ---------------------------------------------------------------------------
# Melee — the fourth candidate source (#378 slice C, AiBladeRollout)
# ---------------------------------------------------------------------------

## H0 sits well beyond ranged's Euclidean `range` (400) from EITHER owned
## node, but exactly on N1's swing circle around N0 (edge length 500) — only
## a melee swing's geometry, not the `range` stat, can reach it.
func test_melee_candidate_is_gathered_and_can_be_executed_through_take_turn() -> void:
	_enemy.stat_board.vision_range.base_value = 1000.0
	_nodes[1].global_position = Vector2(500.0, 0.0)
	_nodes[2].global_position = Vector2(0.0, 500.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.6).timeout

	assert_true(_launches.has(BattleSystem.AttackMode.MELEE),
			"ranged is out of Euclidean range from both owned nodes; melee's swing geometry still connects")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended normally")


# ---------------------------------------------------------------------------
# Dormant Cores: scenery, until they're the wall (#604)
# ---------------------------------------------------------------------------

## Park the real hostile out of sight and put a Dormant Core on N1's only other
## edge, so the ONLY thing the AI can see is the scenery walling it in. The
## fixture is already growth-capped (N0 and N1 are both owned and N0-N1 is the
## only edge between them), which is the point.
func _wall_in_with_a_dormant_core() -> SkillNode:
	_nodes[2].global_position = Vector2(100000.0, 0.0)

	var walled := _SKILL_NODE_SCENE.instantiate() as SkillNode
	walled.name = "Walled"
	_graph.add_skill_node(walled)
	_add_edge(_nodes[1], walled)
	walled.global_position = Vector2(200.0, 0.0)

	var core := _make_entity("DormantCore", preload("res://entity/factions/blocker.tres"))
	_graph.entities_container.add_child(core)
	await get_tree().process_frame
	_alloc.force_allocate(core, walled)
	core.core_location = walled
	return walled


## A chain of free nodes off N1, long enough that no amount of turn-start SP
## minting can consume it — the AI stays uncapped for the whole turn, however
## generous the economy is feeling.
func _open_room_to_grow() -> void:
	var previous: SkillNode = _nodes[1]
	for i in 5:
		var free_node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		free_node.name = "Free%d" % i
		_graph.add_skill_node(free_node)
		_add_edge(previous, free_node)
		free_node.global_position = Vector2(-100.0 * (i + 1), 0.0)
		previous = free_node
	await get_tree().process_frame


func test_growth_capped_ai_attacks_the_dormant_core_walling_it_in() -> void:
	var walled: SkillNode = await _wall_in_with_a_dormant_core()
	var hp_before := walled.get_current_hp()

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_true(_launches.has(BattleSystem.AttackMode.RANGED),
			"boxed in with nowhere to allocate, the AI should shoot its way out")
	assert_lt(walled.get_current_hp(), hp_before, "the core should have taken the damage")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended normally")


func test_uncapped_ai_still_ignores_a_dormant_core() -> void:
	# Same board plus room to grow. Indifference is still the default stance.
	var walled: SkillNode = await _wall_in_with_a_dormant_core()
	await _open_room_to_grow()
	var hp_before := walled.get_current_hp()

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_false(AiRecon.is_growth_capped(_enemy), "fixture guard: room was left to grow")
	assert_eq(walled.get_current_hp(), hp_before, "scenery takes no fire from an AI that can grow")
	assert_eq(_launches.size(), 0, "and there is nothing else visible to shoot")
	assert_false(_enemy.ai_growth_capped, "the stance should not have flipped")


func test_the_stance_does_not_outlive_the_turn_that_earned_it() -> void:
	await _wall_in_with_a_dormant_core()

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout
	assert_true(_enemy.ai_growth_capped, "capped this turn")

	# Open room to grow and take another turn: the stance must be re-decided
	# from scratch, not latched on. Deliberately NOT by freeing `walled` — the
	# AI would allocate that one freed node and be capped again on the same
	# check, which is correct behaviour but tests nothing about latching.
	#
	# Clearing `current_entity` by hand rather than `end_turn()` — that
	# auto-ticks to whoever is ready next, and this test is about the AI's
	# SECOND turn specifically, not the clock.
	await _open_room_to_grow()
	_tm.current_entity = null
	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_false(_enemy.ai_growth_capped,
			"an AI that broke out once must not keep shooting scenery forever")


func test_clearing_the_core_expands_into_the_freed_node_the_same_turn() -> void:
	var walled: SkillNode = await _wall_in_with_a_dormant_core()
	# One shot's worth of HP left: the kill lands inside the AP loop, and the
	# SP the growth pass couldn't spend is still banked for the second pass.
	var per_shot: float = float(_nodes[1].get_local_value(&"ranged_damage"))
	_true_damage(walled, walled.get_current_hp() - per_shot)
	_enemy.stat_board.skill_points.set_current(1)

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.4).timeout

	assert_eq(walled.owned_by, _enemy,
			"kill, then walk through the door it opened — on the same turn")



func test_capped_ai_prefers_the_door_over_an_equally_reachable_hostile() -> void:
	# Both in range and identical on EV — but only the core borders the AI's
	# territory, so only killing it hands the AI a node. Without the breakout
	# bonus the tie goes to enumeration order and the AI plinks the hostile
	# forever while the wall beside it goes unhit: the same "stuck" complaint
	# in a different costume.
	var walled := _SKILL_NODE_SCENE.instantiate() as SkillNode
	walled.name = "Walled"
	_graph.add_skill_node(walled)
	_add_edge(_nodes[1], walled)
	walled.global_position = Vector2(200.0, 0.0)
	var core := _make_entity("DormantCore", preload("res://entity/factions/blocker.tres"))
	_graph.entities_container.add_child(core)
	await get_tree().process_frame
	_alloc.force_allocate(core, walled)
	core.core_location = walled

	var wall_hp := walled.get_current_hp()
	var hostile_hp := _nodes[2].get_current_hp()

	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout

	assert_lt(walled.get_current_hp(), wall_hp, "the wall is the door — hit it")
	assert_eq(_nodes[2].get_current_hp(), hostile_hp,
			"H0 borders nothing of the AI's, so killing it opens no board")


# ---------------------------------------------------------------------------
# #745 characterization — the union rewire is a COST change, not a behaviour one
# ---------------------------------------------------------------------------

## The pre-#745 enumeration, verbatim, as an oracle: probe one owned node at a
## time and filter the visible enemies through [method AttackPlan.get_node_role].
## This is the implementation [method AiController._gather_magic_candidates]
## replaced with a [SpellTargetUnion] lookup, kept here (and ONLY here) so the
## claim "same candidates, same scores, same order" is checked rather than
## asserted in a comment.
##
## Deterministic on both sides: [member AttackPlan.resolve_seed] is 0 on a
## fresh probe and nothing in the scoring path randomizes it, so the totals
## compare exactly rather than within a tolerance.
func _legacy_magic_candidates(entity: Entity,
		visible_enemies: Array[SkillNode]) -> Array[AiCombatScorer.ScoredCandidate]:
	var out: Array[AiCombatScorer.ScoredCandidate] = []
	var mana: PoolStat = entity.stat_board.mana
	for spell in entity.spellbook.spells:
		if mana != null and mana.current < float(spell.mana_cost):
			continue
		for source in entity.navigator.get_mirrored_nodes():
			var probe := MagicAttackPlan.new()
			probe.attacker = entity
			probe.spell = spell
			probe.source = source
			for target in visible_enemies:
				if probe.get_node_role(target) != HighlightProvider.HighlightRole.IN_RANGE:
					continue
				probe.target = target
				if not probe.is_valid():
					probe.target = null
					continue
				var outcome := probe.resolve()
				var c := AiCombatScorer.score(BattleSystem.AttackMode.MAGIC, outcome,
						target, entity, _ai.ai_tier)
				c.source_node = source
				c.spell = spell
				out.append(c)
				probe.target = null
	return out


## Widens the fixture into a board where the enumeration has something to say:
## two eligible casters, two visible hostile targets in hop range of both, and
## one owned node that fails the spell's `min_degree` — the case the pre-#745
## loop probed and then discarded via `is_valid()`, and the union drops before
## the loop. Returns that ineligible node.
func _widen_for_magic_characterization() -> SkillNode:
	_enemy.stat_board.vision_range.base_value = 6000.0
	_add_edge(_nodes[1], _nodes[2])

	# Owned but isolated: degree 0 < Spark's min_degree (1, the SpellDef
	# default), so it is never an eligible caster.
	var orphan := _SKILL_NODE_SCENE.instantiate() as SkillNode
	orphan.name = "N3_orphan"
	_graph.add_skill_node(orphan)
	orphan.global_position = Vector2(150.0, 400.0)
	_alloc.force_allocate(_enemy, orphan)

	# A second hostile node, one hop past the hostile core.
	var far_hostile := _SKILL_NODE_SCENE.instantiate() as SkillNode
	far_hostile.name = "N4_hostile"
	_graph.add_skill_node(far_hostile)
	far_hostile.global_position = Vector2(400.0, 0.0)
	_add_edge(_nodes[2], far_hostile)
	_alloc.force_allocate(_hostile, far_hostile)

	_enemy.get_spellbook().learn(_SPARK_SPELL)
	return orphan


func test_magic_candidates_match_the_pre_union_enumeration_exactly() -> void:
	_widen_for_magic_characterization()
	var visible := AiRecon.visible_enemy_nodes(_enemy)
	assert_gt(visible.size(), 1, "fixture must offer more than one visible hostile target")

	var expected := _legacy_magic_candidates(_enemy, visible)
	var actual := _ai._gather_magic_candidates(visible)

	assert_gt(expected.size(), 1,
			"the oracle must produce a real candidate list, or this test is vacuous")
	assert_eq(actual.size(), expected.size(), "same number of candidates")
	for i in mini(actual.size(), expected.size()):
		var a := actual[i]
		var e := expected[i]
		assert_eq(a.source_node, e.source_node, "candidate %d: same casting source" % i)
		assert_eq(a.target, e.target, "candidate %d: same target" % i)
		assert_eq(a.spell, e.spell, "candidate %d: same spell" % i)
		assert_eq(a.total, e.total, "candidate %d: same score" % i)


## The oracle comparison above only pins ordering if the fixture's gather order
## happens to differ from the fog list's. This pins the contract directly:
## within one casting source, candidates come out in AiRecon.visible_enemy_nodes
## order, never in RangeFinder.gather_multi's. AiCombatScorer.pick_best breaks a
## score tie by first-appended, so this IS the tie-break rule.
func test_candidates_for_one_source_follow_the_fog_list_order() -> void:
	_widen_for_magic_characterization()
	var visible := AiRecon.visible_enemy_nodes(_enemy)
	var candidates := _ai._gather_magic_candidates(visible)
	assert_gt(candidates.size(), 1, "need more than one candidate to have an order at all")

	# Guard against the check going vacuous: comparing two targets for the same
	# source is the whole point, so at least one source must emit two.
	var per_source_count: Dictionary[SkillNode, int] = {}
	for c in candidates:
		per_source_count[c.source_node] = per_source_count.get(c.source_node, 0) + 1
	var widest := 0
	for n: SkillNode in per_source_count:
		widest = maxi(widest, per_source_count[n])
	assert_gt(widest, 1, "no source emits two targets — nothing to order")

	var last_index: Dictionary[SkillNode, int] = {}
	for c in candidates:
		var at := visible.find(c.target)
		assert_gt(at, -1, "every candidate target must be a fog-visible enemy")
		var previous: int = last_index.get(c.source_node, -1)
		assert_gt(at, previous,
				"source %s emitted targets out of fog order (%d after %d)"
						% [c.source_node.name, at, previous])
		last_index[c.source_node] = at


func test_a_source_below_min_degree_is_never_a_magic_candidate() -> void:
	var orphan := _widen_for_magic_characterization()

	assert_eq(_enemy.navigator.get_degree(orphan), 0, "the orphan must stay isolated")
	assert_true(_enemy.navigator.get_mirrored_nodes().has(orphan),
			"it is still owned — the pre-#745 loop probed it and threw the result away")

	for c in _ai._gather_magic_candidates(AiRecon.visible_enemy_nodes(_enemy)):
		assert_ne(c.source_node, orphan,
				"an ineligible caster must not reach the scoring loop at all")
