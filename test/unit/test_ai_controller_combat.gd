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
	add_child(_bs)

	# Idle second entity so the clock parks somewhere after the AI ends its
	# turn (see test_ai_controller.gd's before_each for why).
	_player = _make_entity("Player")
	_graph.add_child(_player)
	_player.add_child(PlayerController.new())

	_enemy = _make_entity("Enemy")
	_graph.add_child(_enemy)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.allocation_system_override = _alloc
	_ai.battle_system_override = _bs
	_enemy.add_child(_ai)

	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.add_child(_hostile)

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
