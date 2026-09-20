extends GutTest
## The integration tier's first behavioural customer (#979): one full
## allocate → attack → kill → loot → XP cycle driven end to end on the shared
## `test/fixtures/integration_level.tscn`, on the logical clock
## (`BattleSystem.instant_mutation`).
##
## Every assert is a RELATION — XP rose, level rose, the victim is gone, a
## relic sits on the former core — never an authored magnitude: the owner
## tunes the numbers, this file tests the shape of the cycle.

const _LEVEL := preload("res://test/fixtures/integration_level.tscn")

var _root: GameRoot
var _player: Entity
var _enemy: Entity
var _enemy_core: SkillNode
var _enemy_nodes: Array[SkillNode]
var _xp_before: float
var _level_before: int


func before_each() -> void:
	_root = _LEVEL.instantiate()
	add_child_autofree(_root)
	_player = _root.player
	_enemy = _root.enemy
	_enemy_core = _root.enemy_core
	assert_true(await wait_until(
			func() -> bool: return _root.turn_manager.current_entity == _player, 5.0),
			"fixture: the player must hold the first turn")
	_enemy_nodes = []
	for node: SkillNode in _root.graph.get_skill_nodes():
		if node.owned_by == _enemy:
			_enemy_nodes.append(node)
	assert_gt(_enemy_nodes.size(), 0, "fixture: the enemy owns its core")
	_xp_before = _player.stat_board.xp.current
	_level_before = _player.level
	await _run_cycle()


## Allocate two steps toward the enemy through the GATED path, arm a melee
## plan pivoted on the first step with the second as its blade, launch it,
## and settle on `is_launching`.
func _run_cycle() -> void:
	var alloc: AllocationSystem = _root.allocation_system
	assert_true(alloc.allocate(_root.step1, _player), "allocate step 1 (gated)")
	assert_true(alloc.allocate(_root.step2, _player), "allocate step 2 (gated)")
	var bs: BattleSystem = _root.battle_system
	bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := bs.attack_plan as MeleeAttackPlan
	assert_not_null(plan, "a melee plan is armed")
	plan.source = _root.step1
	plan.blade_nodes = [_root.step2]
	plan.swing_cw = false
	assert_true(plan.is_valid(), "the plan validates: %s" % [plan.validate()])
	bs.launch_attack()
	assert_true(await wait_until(func() -> bool: return not bs.is_launching, 15.0),
			"the launch settles")


func test_the_victim_is_gone() -> void:
	assert_false(is_instance_valid(_enemy) and _enemy.get_parent() == _root.graph.entities_container,
			"the enemy is no longer in entities_container")


func test_every_node_the_enemy_owned_is_unowned() -> void:
	for node in _enemy_nodes:
		assert_null(node.owned_by, "%s is unowned after the kill" % node.name)


func test_the_killer_earned_xp_and_levelled() -> void:
	assert_gt(_player.stat_board.xp.current + float(_player.level - _level_before),
			_xp_before, "xp rose (or was spent on a level)")
	assert_gte(_player.level, _level_before + 1, "one kill levels on this fixture")


func test_a_relic_sits_on_the_former_core() -> void:
	assert_true(_enemy_core.has_addon(SkillDustAddon),
			"a skill-dust relic sits on the former enemy core")
