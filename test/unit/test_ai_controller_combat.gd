extends GutTest

## A `var`, not a `const`: the parser constant-folds `CONST.kinds[i]`.
var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

## Coverage for #378 slice B — [AIController]'s AP×2 attack loop: candidate
## scoring via [AiCombatScorer] wired into `take_turn()`, dent-then-finish
## re-eval, the 1-damage floor, and near-miss-aware frontier growth.
##
## Separate fixture from test_ai_controller.gd because those tests rely on
## "no hostile anywhere in the graph" for the fog short-circuit; this file
## needs a real, visible hostile + a headless [BattleSystem] to exercise the
## attack step.

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
	# Flat board: kill-sized-volley fixtures arrange node_health themselves, tuned CON must not ride in.
	e.stat_board = TestBoards.flat_entity_board()
	# #957: a volley needs arrows; the default board's quiver starts empty.
	e.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
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
	_bs.temp_upgrade_catalog = _catalog
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


## The idle PlayerController entity parks the clock on itself after the AI
## (before_each), so "current entity is no longer the enemy" is the fact that
## the AI's take_turn -> command -> end_turn chain landed — the fact a
## budgeted 0.3s/0.4s/0.6s sleep stood in for (#987).
func _await_enemy_turn_end() -> void:
	await wait_until(func() -> bool: return _tm.current_entity != _enemy, 2.0)


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

	await _await_enemy_turn_end()

	assert_true(_launches.has(BattleSystem.AttackMode.RANGED), "should have fired a ranged attack")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended")


# ---------------------------------------------------------------------------
# Dent-then-finish across the AP×2 loop
# ---------------------------------------------------------------------------

func test_dent_then_finish_is_one_kill_sized_volley() -> void:
	# Pre-#958 this was two 1-arrow volleys, one per AP: dent, re-eval, finish.
	# A volley costs 0 AP and carries N arrows now, so the AI reads
	# arrows-to-kill off the resolve and fires the kill in ONE volley — the
	# re-eval no longer has a dent to read, it has a corpse to skip.
	_true_damage(_nodes[2], 8.0)
	assert_almost_eq(_nodes[2].get_current_hp(), 2.0, 0.01)

	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()

	assert_eq(_launches.count(BattleSystem.AttackMode.RANGED), 1,
			"one kill-sized volley, never a dent volley plus a finish volley")
	var kill_decisions := _decisions.filter(func(s): return s.find("kill=yes") != -1)
	assert_eq(kill_decisions.size(), 1, "the one volley was scored as the kill")
	assert_lte(_nodes[2].get_current_hp(), 0.0, "and H0 is at 0 (a core overflows into entity health)")
	assert_eq(_enemy.stat_board.action_points.current, 2.0, "a volley costs no AP")


# ---------------------------------------------------------------------------
# 1-damage floor
# ---------------------------------------------------------------------------

func test_one_damage_floor_fires_a_full_chip_volley_even_without_a_kill_this_turn() -> void:
	# One shot per leaf: two leaves, two arrows, far short of H0's full HP. The
	# acceptance property is "no minimum-EV gate blocks an attack" — the chip
	# still goes out, at the largest N the leaves carry, and costs no AP.
	_enemy.stat_board.max_shots_per_leaf.base_value = 1.0
	var target_hp := _nodes[2].get_current_hp()
	var stock_before: int = roundi(_enemy.stat_board.arrows.current)

	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()

	assert_eq(_launches.count(BattleSystem.AttackMode.RANGED), 1,
			"one chip volley even though it cannot kill")
	assert_eq(stock_before - roundi(_enemy.stat_board.arrows.current), 2,
			"and it carried every shot the leaves had — never a single arrow")
	assert_lt(_nodes[2].get_current_hp(), target_hp, "H0 should have taken damage")
	assert_gt(_nodes[2].get_current_hp(), 0.0, "fixture: not a kill")
	assert_eq(_enemy.stat_board.action_points.current, 2.0, "the chip cost no AP")


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
	await _await_enemy_turn_end()

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
	await _await_enemy_turn_end()

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
	await _await_enemy_turn_end()

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
	await _await_enemy_turn_end()

	assert_true(_launches.has(BattleSystem.AttackMode.MELEE),
			"ranged is out of Euclidean range from both owned nodes; melee's swing geometry still connects")
	assert_ne(_tm.current_entity, _enemy, "turn should have ended normally")


## #823 requirement 9: a scored candidate's clamp_nodes must land on the
## LAUNCHED plan as real temp-upgrade addons, beside blade_nodes/swing_cw —
## execution has to match scoring, not just reach/direction. Drives
## `_execute_candidate` directly with a synthetic candidate rather than
## through the full rollout, so this is a claim about the execution wiring
## specifically, independent of what the generator would have proposed here.
func test_execute_candidate_arms_the_scored_clamp_as_a_real_addon() -> void:
	_enemy.stat_board.blade_size.base_value = 3.0 # member (1) + clamp (1), with headroom
	# Plain state, not `_tm.start_turn(_enemy)` — that would also fire the
	# AI's own turn_started listener and race the manual _execute_candidate
	# call below with a real independent take_turn(). request_attack_mode's
	# fresh plan only needs `turn_manager.current_entity` to stamp `attacker`.
	_tm.start_turn(_enemy)
	var candidate := AiCombatScorer.ScoredCandidate.new()
	candidate.mode = BattleSystem.AttackMode.MELEE
	candidate.source_node = _nodes[0]
	var members: Array[SkillNode] = [_nodes[1]]
	candidate.blade_nodes = members
	candidate.swing_cw = true
	candidate.clamp_nodes = [_nodes[1]]

	assert_false(_nodes[1].has_addon(ClampAddon), "sanity: no clamp before execution")
	# A temp upgrade is PER-SWING (`.claude/rules/blade-budget-and-clamps.md`)
	# — `apply_temp_upgrade`'s "refunded when the plan resets" is the same
	# lifecycle a player's own clamp click gets, and `launch_attack`'s normal
	# post-swing plan reset frees it same as it would a human's. So the
	# durable claim is not "the addon outlives the swing" (it must not — see
	# `test_melee_temp_upgrade.gd`) but that it was REALLY attached, as a
	# real SkillNodeAddon, at some point during execution — i.e. it rode the
	# actual resolve, not a scoring-only fiction. `child_entered_tree` is the
	# same signal `SkillNode._on_addon_added` itself listens on, so this
	# observes the identical event production code reacts to.
	# An Array, not a bool local — a lambda captures outer locals BY VALUE
	# (`.claude/rules/testing.md`), so a bare `var seen := false` written
	# inside the callback would silently mutate its own copy and never
	# reach this assertion.
	var seen_real_clamp: Array[bool] = []
	_nodes[1].child_entered_tree.connect(func(c: Node) -> void:
		if c is ClampAddon:
			seen_real_clamp.append(true))
	var launched: bool = await _ai._execute_candidate(candidate)
	assert_true(launched, "a valid melee candidate must launch")
	assert_true(not seen_real_clamp.is_empty(),
			"the scored clamp must be armed as a REAL SkillNodeAddon on the launched plan " +
			"(even though it is then refunded post-swing like any temp upgrade), or the " +
			"swing that resolved is floppier than the one that was scored")


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
	await _await_enemy_turn_end()

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
	await _await_enemy_turn_end()

	assert_false(AiRecon.is_growth_capped(_enemy), "fixture guard: room was left to grow")
	assert_eq(walled.get_current_hp(), hp_before, "scenery takes no fire from an AI that can grow")
	assert_eq(_launches.size(), 0, "and there is nothing else visible to shoot")
	assert_false(_enemy.ai_growth_capped, "the stance should not have flipped")


func test_the_stance_does_not_outlive_the_turn_that_earned_it() -> void:
	await _wall_in_with_a_dormant_core()

	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()
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
	_tm.adopt_turn(null, _tm.turns_taken)
	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()

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
	await _await_enemy_turn_end()

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
	await _await_enemy_turn_end()

	assert_lt(walled.get_current_hp(), wall_hp, "the wall is the door — hit it")
	# #958: volleys cost no AP, so once the door is down the leftover shots
	# legitimately go to H0 — the property is ORDER: the door is picked first.
	var volleys := _decisions.filter(func(s: String) -> bool: return s.begins_with("[RANGED"))
	assert_gt(volleys.size(), 0, "it fired")
	assert_true(volleys[0].contains("→Walled"),
			"H0 borders nothing of the AI's, so the door outranks it")
	assert_true(hostile_hp > 0.0)


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


## #537 D1/D5 retired the exact-parity claim this test used to pin (Sage
## fence extension, 2026-09-13): above `AIController._CANDIDATE_GATE_K` a
## cheap heuristic now trims the sweep before it pays for a
## [method AttackPlan.resolve], so the promoted set is a K-sized SUBSET of the
## exhaustive one, not the whole thing. What must still hold — and does not
## hold vacuously, since `_widen_for_magic_characterization`'s 4 combos
## exceed K=3 — is (i) every promoted candidate really came from the
## exhaustive sweep, (ii) the promoted count is exactly `min(K, exhaustive
## count)`, and (iii) the sweep's own TRUE best candidate always survives the
## gate (D5: a gate that drops the true winner is worse than no gate at all).
func _same_magic_candidate(
		a: AiCombatScorer.ScoredCandidate, b: AiCombatScorer.ScoredCandidate) -> bool:
	return a.source_node == b.source_node and a.target == b.target and a.spell == b.spell


func test_magic_candidates_are_a_gate_accurate_subset_of_the_exhaustive_sweep() -> void:
	_widen_for_magic_characterization()
	var visible := AiRecon.visible_enemy_nodes(_enemy)
	assert_gt(visible.size(), 1, "fixture must offer more than one visible hostile target")

	var expected := _legacy_magic_candidates(_enemy, visible)
	var actual := _ai._gather_magic_candidates(visible)

	assert_gt(expected.size(), 1,
			"the oracle must produce a real candidate list, or this test is vacuous")
	assert_gt(expected.size(), AIController._CANDIDATE_GATE_K,
			"fixture guard: the exhaustive count must exceed K, or the gate never engages "
			+ "and this test would pass vacuously")
	assert_eq(actual.size(), mini(AIController._CANDIDATE_GATE_K, expected.size()),
			"promoted count is exactly min(K, exhaustive count)")

	for a in actual:
		var found := false
		for e in expected:
			if _same_magic_candidate(a, e):
				found = true
				break
		assert_true(found, "a promoted candidate must be one the exhaustive sweep " +
				"actually produced: %s" % a.trace)

	var true_winner: AiCombatScorer.ScoredCandidate = AiCombatScorer.pick_best(expected)
	assert_not_null(true_winner, "fixture guard: the oracle must have a best candidate")
	var winner_survived := false
	for a in actual:
		if _same_magic_candidate(a, true_winner):
			winner_survived = true
			break
	assert_true(winner_survived,
			"the exhaustive sweep's true best candidate must survive the two-tier gate (#537 D5): %s"
					% true_winner.trace)


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


# ---------------------------------------------------------------------------
# #958 — fire-to-kill / reload loop: the AI never single-shots
# ---------------------------------------------------------------------------

## Three leaves off the core (N1 + two more), all within range of H0.
func _grow_two_more_leaves() -> void:
	var added: Array[SkillNode] = []
	for i in 2:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "L%d" % i
		_graph.add_skill_node(sn)
		_add_edge(_nodes[0], sn)
		sn.global_position = _nodes[1].global_position + Vector2(0.0, 40.0 * (i + 1))
		added.append(sn)
	await get_tree().process_frame # the mirrors see the edge before allocation
	for sn in added:
		_alloc.force_allocate(_enemy, sn)


## A non-core hostile node off H0 — the one a "kill" actually removes (a core
## at 0 node-hp overflows into the entity's `health` pool instead, so the
## scorer's node-hp kill read is a prediction there, not a removal).
##
## H0 itself is parked out of `range` (400) but inside vision: killing the
## core kills the entity, which outscores any leaf kill and frees every node —
## the tests below are about the leaf volley, not that.
func _add_hostile_leaf(leaf_name: String = "H1") -> SkillNode:
	_enemy.stat_board.vision_range.base_value = 700.0
	_nodes[2].global_position = _nodes[1].global_position + Vector2(600.0, 0.0)
	var h := _SKILL_NODE_SCENE.instantiate() as SkillNode
	h.name = leaf_name
	_graph.add_skill_node(h)
	_add_edge(_nodes[2], h)
	h.global_position = _nodes[1].global_position + Vector2(150.0, 0.0)
	await get_tree().process_frame # the mirrors see the edge before allocation
	_alloc.force_allocate(_hostile, h)
	return h


func _set_stock(n: int) -> void:
	var quiver: Quiver = _enemy.stat_board.arrows
	quiver.take(AmmoTypeRoster.BASE_ID, quiver.stock_of(AmmoTypeRoster.BASE_ID))
	quiver.add(AmmoTypeRoster.BASE_ID, n)


func _stock() -> int:
	return (_enemy.stat_board.arrows as Quiver).stock_of(AmmoTypeRoster.BASE_ID)


## What one arrow from N1 actually lands on H0 — read off a shadow resolve
## (the node-local `ranged_damage` is a formula INPUT, not the landed number).
func _effective_per_arrow(target: SkillNode = _nodes[2]) -> float:
	var plan := RangedAttackPlan.new()
	plan.attacker = _enemy
	plan.target = target
	plan.ammo_counts = {AmmoTypeRoster.BASE_ID: 1}
	var outcome := plan.resolve()
	assert_eq(outcome.hits.size(), 1, "fixture: one arrow resolves: %s / reach=%s / hostile=%s" % [str(plan.validate()), plan.get_reaching_firing_positions().size(), target.ownership_bit(_enemy)])
	return outcome.hits[0].effective_amount


func test_one_volley_sized_to_the_kill_plus_margin_never_four_single_shots() -> void:
	# Owner (2026-09-18): stock 12, 3 leaves in range, a target worth 4 arrows
	# -> ONE volley of 4 + margin, never four 1-arrow volleys.
	await _grow_two_more_leaves()
	_set_stock(12)
	var h1: SkillNode = await _add_hostile_leaf()
	var per_arrow := _effective_per_arrow(h1)
	# The issue's worked example is 7 hp at 2/arrow = 4 arrows; the fixture
	# lands 3/arrow on a 10-hp leaf, so 2.5 arrows' worth -> 3 arrows to kill.
	_true_damage(h1, h1.get_current_hp() - per_arrow * 2.5)
	assert_almost_eq(h1.get_current_hp(), per_arrow * 2.5, 0.01, "fixture: H1 is worth 3 arrows")

	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()

	var volleys := _decisions.filter(func(d: String) -> bool: return d.begins_with("[RANGED"))
	assert_gt(volleys.size(), 0, "it fired")
	assert_true(volleys[0].begins_with("[RANGED→H1]"), "the kill came first: %s" % volleys[0])
	assert_true(volleys[0].ends_with(" n=%d" % (3 + AIController.KILL_MARGIN_ARROWS)),
			"the kill volley carried arrows-to-kill plus the margin: %s" % volleys[0])
	assert_ne(h1.owned_by, _hostile, "and it killed H1")
	var singles := volleys.filter(func(d: String) -> bool: return d.ends_with(" n=1"))
	assert_eq(singles.size(), 0, "never a 1-arrow volley: %s" % str(volleys))


func test_reloads_when_the_quiver_is_empty_then_fires_what_it_minted() -> void:
	_set_stock(0)
	_enemy.stat_board.action_points.set_current(1)
	var reloads: Array[Command] = []
	_applier.command_applied.connect(func(cmd: Command, ok: bool) -> void:
		if cmd is ReloadCommand and ok:
			reloads.append(cmd))

	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()

	assert_eq(reloads.size(), 1, "an empty quiver with 1 AP submits ONE ReloadCommand")
	assert_eq(_enemy.stat_board.action_points.current, 0.0, "which cost the AP")
	assert_eq(_launches.count(BattleSystem.AttackMode.RANGED), 1,
			"and the reload's mint went out as a volley the same turn")


func test_fires_before_reloading_when_a_kill_is_on_the_table() -> void:
	# Stock below the leaves' shot budget and a killable target: the volley
	# goes first; the reload comes after.
	_set_stock(3)
	var h1: SkillNode = await _add_hostile_leaf()
	var per_arrow := _effective_per_arrow(h1)
	_true_damage(h1, h1.get_current_hp() - per_arrow * 1.5)
	var events: Array[String] = []
	_bs.attack_launched.connect(func(_m: BattleSystem.AttackMode, _s: SpellDef) -> void:
		events.append("volley"))
	_applier.command_applied.connect(func(cmd: Command, _ok: bool) -> void:
		if cmd is ReloadCommand:
			events.append("reload"))

	_tm.start_turn(_enemy)
	await _await_enemy_turn_end()

	assert_gt(events.size(), 1, "it fired and reloaded: %s" % str(events))
	assert_eq(events[0], "volley", "the kill was taken before any reload")
	assert_true(events.has("reload"), "then the emptied quiver was reloaded")
	assert_ne(h1.owned_by, _hostile, "H1 died")


func test_never_exceeds_volleys_per_turn() -> void:
	# Two killable hostile leaves, plenty of arrows and shots — but the volley
	# counter is parked one below the cap once the turn has opened, so the
	# first kill takes the last slot and the second is left on the table.
	await _grow_two_more_leaves()
	var h1: SkillNode = await _add_hostile_leaf("H1")
	var h2: SkillNode = await _add_hostile_leaf("H2")
	var per_arrow := _effective_per_arrow(h1)
	_true_damage(h1, h1.get_current_hp() - per_arrow * 0.5)
	_true_damage(h2, h2.get_current_hp() - per_arrow * 0.5)
	var limit := int(_enemy.stat_board.volleys_per_turn.value)
	assert_gt(limit, 1, "fixture: more than one slot, so the park is what binds")

	# A non-zero delay parks take_turn on its opening beat, AFTER turn start
	# reset the counter and BEFORE the first pick.
	_ai.turn_delay = 0.01
	_tm.start_turn(_enemy)
	_enemy.volleys_launched_this_turn = limit - 1
	await _await_enemy_turn_end()

	assert_eq(_launches.count(BattleSystem.AttackMode.RANGED), 1, "one slot left, one volley")
	assert_eq(_enemy.volleys_launched_this_turn, limit, "at the cap, never past it")
	assert_true(h1.owned_by != _hostile or h2.owned_by != _hostile, "the slot bought a kill")
	assert_true(h1.owned_by == _hostile or h2.owned_by == _hostile, "and the other kill waits")
	assert_ne(_tm.current_entity, _enemy, "and the turn ended cleanly")
