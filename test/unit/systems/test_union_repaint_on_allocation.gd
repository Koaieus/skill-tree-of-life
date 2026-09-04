extends GutTest

## The pick-spell-first union (#728) depends on OWNERSHIP, so [BattleSystem]
## pushes an invalidation on every allocation. This pins the other half of that
## — the invalidation has to be ANNOUNCED on the signal the highlight overlays
## actually listen to.
##
## [signal BattleSystem.attack_plan_state_changed] is not it: it reaches the HUD
## command-tray bodies and [PlayerInputController], while
## [NodeHighlightOverlay] / [EdgeHighlightOverlay] repaint off
## [signal HighlightController.provider_state_changed], which is a straight
## re-emit of the active provider's own [signal HighlightProvider.state_changed]
## — i.e. the plan's. Emitting only the former left the painted caster and
## target rings stale after an allocation until an unrelated hover forced a
## redraw, which is precisely the case #728 called out as load-bearing:
## "allocating a high-degree node mid-turn has to make the spell castable
## immediately".
##
## Asserted at the plan's signal rather than through an overlay on purpose:
## the overlay's own contract (repaint on `provider_state_changed`) is already
## pinned by test_highlight_controller.gd, and a role assertion here would test
## the union's contents a second time instead of the wiring.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _attacker: Entity
var _owned: SkillNode
var _spare: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_owned = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_spare = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.add_skill_node(_owned)
	_graph.add_skill_node(_spare)
	_graph.add_edge(_owned, _spare)

	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_attacker)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _owned)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = _attacker

	_battle = BattleSystem.new()
	_battle.turn_manager = tm
	_battle.allocation_system = _alloc
	_battle.graph = _graph
	add_child_autofree(_battle)


func _magic_plan() -> MagicAttackPlan:
	_battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	return _battle.attack_plan as MagicAttackPlan


func test_allocating_announces_the_union_change_on_the_plans_own_signal() -> void:
	var plan := _magic_plan()
	assert_not_null(plan, "fixture: magic mode arms a MagicAttackPlan")
	watch_signals(plan)
	_alloc.force_allocate(_attacker, _spare)
	assert_signal_emitted(plan, "state_changed",
			"the overlays repaint off THIS signal, not attack_plan_state_changed")


func test_deallocating_announces_it_too() -> void:
	_alloc.force_allocate(_attacker, _spare)
	var plan := _magic_plan()
	watch_signals(plan)
	_alloc.force_deallocate(_spare)
	assert_signal_emitted(plan, "state_changed",
			"losing territory can strand a caster just as gaining it creates one")


func test_the_announcement_reaches_the_system_signal_as_well() -> void:
	# Routing through the plan must not COST the HUD bodies their refresh —
	# BattleSystem re-emits the plan's signal as its own.
	var plan := _magic_plan()
	watch_signals(_battle)
	_alloc.force_allocate(_attacker, _spare)
	assert_signal_emitted(_battle, "attack_plan_state_changed",
			"the command-tray bodies still hear it")
	assert_not_null(plan)
