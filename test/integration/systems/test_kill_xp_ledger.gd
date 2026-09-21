extends GutTest

## The attack-scoped removal ledger — kill XP must be a function of what the
## attack REMOVED, never of internal cascade ordering.
##
## The bug this pins: `_award_kill_xp` used to read only the victim's live
## owned-subgraph at the instant of death. BattleSystem's cascade strips nodes
## one at a time and chips the defender's core HP per node, so the core can die
## anywhere inside that loop — and everything already stripped had vanished from
## the count. Measured on this exact fixture (pre-#774 numbers): **35 XP vs 15
## XP** for the same attack on the same victim, differing only in the
## defender's starting health. It paid you LESS the more of the victim you had
## actually destroyed.
##
## Chain: K (killer core) – V (victim core) – A – B – C – D
## Depleting A (a cut vertex) islands B/C/D, so the cascade removes 4 nodes and
## deals 4 chip damage. Vary health to move the death around inside that loop.
##
## #774 reworked the payout to strictly additive (`xp_per_node_killed × nodes
## removed, core included, + core_kill_xp only if the core died` — no
## multiplier, no netting), but the INVARIANT this file exists to pin —
## "the payout depends on what the attack removed, never on cascade
## iteration order" — is unchanged, so the scenarios below survive with the
## new arithmetic substituted in. Per `owner_tunes_agents_test`: `core_kill_xp`
## is set on the hand-built victim board here, never asserted at a shipped
## `.tres` value.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

const _PER_NODE := 5.0
const _CORE_BONUS := 7.0
## The victim owns 5 nodes (core + 4). Whatever the sequencing, a kill that
## removes all of them is worth 5 nodes at the per-node rate plus the core bonus.
const _WHOLE_VICTIM_XP := 5.0 * _PER_NODE + _CORE_BONUS

var _graph: Graph
var _loot: LootSystem
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _victim: Entity
var _killer: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 6:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	for i in 5:
		var e := _EDGE_SCENE.instantiate() as Edge
		e.from = _nodes[i]
		e.to = _nodes[i + 1]
		_graph.edges_container.add_child(e)

	_tm = TurnManager.new()
	add_child_autofree(_tm)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_battle = BattleSystem.new()
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)

	_loot = LootSystem.new()
	_loot.turn_manager = _tm
	_loot.battle_system = _battle
	_loot.xp_per_node_killed = _PER_NODE
	add_child_autofree(_loot)  # _ready connects the ledger to _battle

	_killer = autofree(Entity.new())
	_killer.faction = _PLAYER_FACTION  # #384/#386: HOSTILE to the victim's default npc faction
	_killer.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_killer)
	_victim = autofree(Entity.new())
	_victim.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_victim.core_class = _BALANCED
	_graph.add_child(_victim)
	await get_tree().process_frame
	_victim.stat_board.core_kill_xp.base_value = _CORE_BONUS

	_alloc.force_allocate(_killer, _nodes[0])
	_killer.core_location = _nodes[0]
	for i in range(1, 6):
		_alloc.force_allocate(_victim, _nodes[i])
	_victim.core_location = _nodes[1]
	_tm.start_turn(_killer)


## XP is a growing pool, so a raw `current` delta undercounts once it levels.
## Reconstruct the total: each level consumed its cap (5, 10, 15, ... per the
## xp def's growth_flat).
func _xp_gained(before: float, lvl_before: int) -> float:
	var consumed := 0.0
	for l in range(lvl_before, _killer.level):
		consumed += 5.0 * float(l)
	return consumed + _killer.stat_board.xp.current - before


func _cut_the_arm_with_health(health: float) -> float:
	_victim.stat_board.health.set_current(health)
	var before := _killer.stat_board.xp.current
	var lvl_before := _killer.level
	_nodes[2].take_damage(10000.0, null)  # deplete A, the cut vertex
	assert_true(_victim.is_dead, "chip damage kills the core mid-cascade")
	return _xp_gained(before, lvl_before)


func test_payout_is_invariant_to_where_in_the_cascade_the_core_dies() -> void:
	# Health 2 → dies on the 2nd of 4 cascade nodes, 2 still unstripped.
	var early := _cut_the_arm_with_health(2.0)
	assert_eq(early, _WHOLE_VICTIM_XP,
			"an arm-cut kill pays for the whole victim, whenever the core pops")


func test_same_attack_surviving_the_whole_cascade_pays_the_same() -> void:
	# Health 4 → dies on the LAST cascade node, 0 unstripped. Pre-ledger this
	# paid 15 where the case above paid 35 (pre-#774 numbers).
	var late := _cut_the_arm_with_health(4.0)
	assert_eq(late, _WHOLE_VICTIM_XP,
			"identical attack, identical payout regardless of where the core popped")


func test_a_clean_decapitation_pays_the_same_as_dismantling_in_one_attack() -> void:
	# No cascade at all: hit the core directly while all 4 limbs stand. The
	# territory is destroyed by the death strip either way, so it pays the same
	# as cutting the arm out from under it.
	_victim.stat_board.health.set_current(1.0)
	var before := _killer.stat_board.xp.current
	var lvl_before := _killer.level
	_victim.core_location.take_damage(10000.0, null)
	assert_true(_victim.is_dead)
	assert_eq(_xp_gained(before, lvl_before), _WHOLE_VICTIM_XP,
			"snipe and same-attack dismantle are worth the same")


func test_a_non_killing_cut_pays_the_trickle_only() -> void:
	# The victim survives (health high enough to eat 4 chip damage). Four nodes
	# left the board; each pays 1x, no core bonus (the core never died).
	_victim.stat_board.health.set_current(100.0)
	var before := _killer.stat_board.xp.current
	var lvl_before := _killer.level
	_nodes[2].take_damage(10000.0, null)
	assert_false(_victim.is_dead, "the victim survives this one")
	assert_eq(_xp_gained(before, lvl_before), 4.0 * _PER_NODE,
			"4 removed nodes at the plain rate, no core bonus")


func test_whittling_across_attacks_pays_the_same_as_one_decisive_blow() -> void:
	# #774 (owner, 2026-09-07): the strictly-additive rework deliberately drops
	# the old whittle/snipe premium — "no more killing entity that has many
	# nodes makes those nodes count for more XP". A node is worth the same
	# whether it fell in an earlier attack or the killing blow, and the core
	# bonus applies exactly once regardless of when the rest of the board went.
	# Attack 1: cut the arm, victim survives → 4 nodes at 1x, no core bonus.
	_victim.stat_board.health.set_current(100.0)
	var before := _killer.stat_board.xp.current
	var lvl_before := _killer.level
	_nodes[2].take_damage(10000.0, null)
	# Attack 2: a new attack clears the ledger; only the core is left to remove.
	_battle.attack_launched.emit(0, null)
	_victim.stat_board.health.set_current(1.0)
	_victim.core_location.take_damage(10000.0, null)
	assert_true(_victim.is_dead)
	var total := _xp_gained(before, lvl_before)
	assert_eq(total, 4.0 * _PER_NODE + (1.0 * _PER_NODE + _CORE_BONUS),
			"limbs at 1x from the earlier attack, only the core kill pays the bonus")
	assert_eq(total, _WHOLE_VICTIM_XP, "no premium for a decisive attack anymore — same total either way")


func test_ledger_is_scoped_to_one_attack() -> void:
	_victim.stat_board.health.set_current(100.0)
	_nodes[2].take_damage(10000.0, null)  # 4 nodes into the ledger
	_battle.attack_launched.emit(0, null)
	assert_eq(_loot._removed_this_attack.size(), 0, "a new attack starts an empty ledger")


## #774 acceptance: a node pays IDENTICALLY whether the trickle
## (`award_xp_on_node_kill`) is on or off — the kill-side total absorbs
## whatever the trickle didn't already pay, never double-counting or
## under-paying. Same chain, same mid-cascade death as the invariance test
## above — only the switch differs.
func test_total_payout_is_the_same_with_the_trickle_switched_off() -> void:
	_loot.award_xp_on_node_kill = false
	var without_trickle := _cut_the_arm_with_health(2.0)
	assert_eq(without_trickle, _WHOLE_VICTIM_XP,
			"same total with the trickle switched off — nothing double-paid or lost")


func test_game_root_wires_the_ledger_at_scene_load() -> void:
	# The ledger hookup lives in LootSystem._ready, which fires DURING scene
	# instantiation. That's only safe because `battle_system` is a NodePath
	# @export resolved by the .tscn (not a field GameRoot injects afterwards —
	# see .claude/rules/godot-workflow.md on that distinction). Assert the real
	# composition root, not just the hand-wired fixture above.
	var root := preload("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await get_tree().process_frame
	var loot: LootSystem = root.get_node("%LootSystem")
	var battle: BattleSystem = root.get_node("%BattleSystem")
	assert_not_null(loot.battle_system, "game_root.tscn wires LootSystem.battle_system")
	assert_eq(loot.battle_system, battle, "and it points at the real BattleSystem")
	assert_true(battle.cascade_started.is_connected(loot._on_cascade_started),
			"_ready got a live BattleSystem — the ledger is actually listening")
	assert_true(battle.attack_launched.is_connected(loot._on_attack_launched),
			"and the per-attack reset is wired")
