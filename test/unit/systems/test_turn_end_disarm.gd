extends GutTest

## Two "what happens when a thing is over" contracts on the armed stack:
##
##   * ending the seated player's turn drops back to the [ManageMode] root —
##     armed levels are turn-local intent, so a verb/arm/confirm that survives
##     the handover re-arms a stale plan onto the next turn.
##   * a magic launch pops the [TargetMode] step and re-arms MAGIC with a fresh
##     plan — the arm stays up, the sub-stack does not (melee's twin lives in
##     test_click_grammar.gd).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
var _graph: Graph
var _tm: TurnManager
var _bs: BattleSystem
var _ctl: PlayerInputController
var _player: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_bs = autofree(BattleSystem.new())
	_bs.graph = _graph
	_bs.turn_manager = _tm
	_bs.instant_mutation = true
	add_child(_bs)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.faction = _PLAYER_FACTION
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	# The controller early-returns on a missing dep, so all three ARE needed
	# (clicks won't route, but the turn-ended subscription only lands with all).
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.battle_system = _bs
	_ctl.turn_manager = _tm
	_ctl.allocation_system = alloc
	add_child_autofree(_ctl)
	_ctl.player = _player

	_tm.start_turn(_player)
	_player.stat_board.action_points.restore_to_full()


func _enemy() -> Entity:
	var npc: Entity = autofree(Entity.new())
	npc.display_name = "Enemy"
	npc.faction = _NPC_FACTION
	npc.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(npc)
	return npc


# ── Ending the turn drops back to Manage ─────────────────────────────────────

func test_the_players_turn_ending_clears_the_armed_stack_to_its_root() -> void:
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MAGIC),
			"fixture: the magic arm should have landed")
	assert_true(_ctl.has_armed_level(), "fixture: something is armed")

	_tm.abandon_turn(_player)

	assert_false(_ctl.has_armed_level(), "the stack is just the Manage root")
	assert_null(_bs.attack_plan, "the arm's plan went with the arm")


func test_ending_a_turn_the_seat_is_not_holding_leaves_the_stack_armed() -> void:
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MAGIC), "fixture: armed")
	assert_true(_ctl.has_armed_level(), "fixture: armed")

	# An NPC's turn ending must not touch this seat's stack — the guard reads
	# the entity the signal names.
	var npc: Entity = _enemy()
	_tm.adopt_turn(npc, _tm.turns_taken)
	_tm.abandon_turn(npc)

	assert_true(_ctl.has_armed_level(),
			"an NPC's turn ending is not this seat's turn being over")


# ── A cast pops Target and re-arms Magic ─────────────────────────────────────

## The castable pair test_attack_record_replay.gd uses, with the same one
## caveat it documents: without the core→leaf edge the caster's OWNED-subgraph
## degree is 0 and `_source_meets_min_degree` refuses everyone. Awaited — the
## union's eligibility question reads the navigator mirror, which needs frames
## (incl. physics) to see the allocation. The caller assumes the fixture stood.
func _cast_fixture() -> Dictionary:
	var core := _node("Core", Vector2(0, 0))
	var leaf := _node("Leaf", Vector2(150, 0))
	var target := _node("Target", Vector2(300, 0))
	_graph.add_edge(core, leaf)
	_graph.add_edge(leaf, target)

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_player, core)
	alloc.force_allocate(_player, leaf)
	_player.core_location = core
	var npc: Entity = _enemy()
	npc.faction = _NPC_FACTION
	alloc.force_allocate(npc, target)
	npc.core_location = target

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_bs.selected_spell = SpellCatalog.SPARK
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MAGIC), "fixture: magic armed")
	var plan: MagicAttackPlan = _bs.attack_plan as MagicAttackPlan
	assert_not_null(plan, "fixture: a magic plan stands")
	# Through the click grammar, so MagicMode pushes its TargetMode step.
	_ctl.route_left_click(target)
	assert_eq(plan.target, target, "fixture: the target landed")
	return {plan = plan, target = target, npc = npc}


func _node(node_name: String, pos: Vector2) -> SkillNode:
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	node.name = node_name
	_graph.add_skill_node(node)
	node.global_position = pos
	return node


func test_a_launched_spell_pops_target_and_returns_to_magic() -> void:
	await _cast_fixture()
	assert_eq(_ctl.armed_stack.branch().size(), 3, "fixture: Manage / Magic / Target")

	_player.stat_board.mana.current = 20.0
	await _bs.launch_attack(_bs.attack_plan)
	await get_tree().process_frame

	# Magic alone on top of the root: TargetMode popped on the launch, and the
	# re-arm minted a fresh plan for the same mode.
	assert_eq(_ctl.armed_stack.branch().size(), 2,
			"back to Magic mode (no Target level)")
	assert_true(_bs.attack_plan is MagicAttackPlan, "the re-arm landed a magic plan")
	assert_null((_bs.attack_plan as MagicAttackPlan).target,
			"the fresh plan carries no target from the cast")
