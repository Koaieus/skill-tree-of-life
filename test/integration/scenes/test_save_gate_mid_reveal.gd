extends GutTest

## A save requested while an attack is still replaying is held, and lands once
## [method CommandApplier.is_quiescent] turns true — the slot holds the
## post-attack world, never a half-applied one. Driven on `dev_sandbox.tscn`:
## a ranged volley at the enemy core is the damaging attack.

const _SANDBOX := preload("res://scenes/dev_sandbox.tscn")
const _TEST_SLOT := "user://test_save_gate_mid_reveal.bin"

var _root: GameRoot
var _gate: SaveGate


func before_each() -> void:
	_root = _SANDBOX.instantiate()
	add_child_autofree(_root)
	for _i in 60:
		await wait_physics_frames(1)
		if _root.turn_manager.current_entity != null:
			break
	assert_eq(_root.turn_manager.current_entity, _root.player, "fixture: player holds the first turn")
	_gate = _root.get_node("%SaveGate")
	_gate.slot_path = _TEST_SLOT


func after_each() -> void:
	for path in [_TEST_SLOT, _TEST_SLOT + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_save_requested_mid_reveal_lands_the_post_attack_world() -> void:
	var applier := _root.command_applier
	_root.input_ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	_root.input_ctl.request_reload()
	while applier.is_applying:
		await applier.applying_changed
	assert_gt(_root.player.stat_board.arrows.stock_of(&"arrow"), 0, "fixture: a reload fills the quiver")
	var plan := _root.input_ctl.armed_stack.attack_plan() as RangedAttackPlan
	plan.set_target(_root.graph.get_node("Nodes/Enemy_Core"))
	await wait_physics_frames(2)
	var before := WorldImage.capture(_root.graph).to_bytes()
	_root.battle_system.launch_attack(plan)
	if not applier.is_applying:
		await wait_for_signal(applier.applying_changed, 2.0)
	assert_true(applier.is_applying, "fixture: the reveal is under way")

	assert_true(_gate.request_save())
	assert_true(_gate.is_save_held, "a mid-reveal request is held")
	assert_false(FileAccess.file_exists(_TEST_SLOT), "nothing written mid-reveal")

	await wait_for_signal(_gate.saved, 10.0)
	assert_true(applier.is_quiescent(), "the held save fired at a quiescent boundary")
	var after := WorldImage.capture(_root.graph).to_bytes()
	assert_ne(after, before, "fixture: the volley changed the world")
	var loaded := SaveFile.read_slot(_TEST_SLOT)
	assert_eq(loaded.load_result, SaveFile.LoadResult.OK)
	assert_eq(loaded.world.to_bytes(), after, "the slot holds the post-attack world")
