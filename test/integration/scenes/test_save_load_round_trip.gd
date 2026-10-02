extends GutTest

## A save taken mid-turn reopens as the same world: `SaveFile.capture` +
## `write_slot` on a live `level.tscn`, the level freed, then `read_slot` →
## `GameSession.open_saved` → the level opened again from the save's own
## `level_scene_path`. Saves are taken directly at a quiescent point — the save
## gate is not under test here.

const _LEVEL := preload("res://scenes/level.tscn")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _SLOT := "user://test_save_load_round_trip.bin"
const _NODE_COUNT := 80

var _root: GameRoot


func before_each() -> void:
	GameSession.end()
	GameSession.local_peer_id = 0


func after_each() -> void:
	await _free_level()
	GameSession.end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_SLOT))


func _participant(id: int, kind: Participant.Kind, camp: Faction) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	return p


func _start_run() -> void:
	var cfg := RunConfig.new()
	cfg.seed = 7331
	cfg.stagger_initiative = false
	cfg.participants = [
		_participant(1, Participant.Kind.HUMAN, _CAMP_1),
		_participant(2, Participant.Kind.AI, _CAMP_2),
	] as Array[Participant]
	GameSession.start(cfg)


func _launch(scene: PackedScene) -> GameRoot:
	var root: GameRoot = scene.instantiate()
	root.node_count_override = _NODE_COUNT
	root.enemy_territory_size = 3
	add_child(root)
	_root = root
	# Freeing a level mid-`_setup_level` crashes the engine: wait for the reveal.
	await wait_until(func() -> bool: return root._reveal_ready, 10.0, "level never revealed")
	return root


func _free_level() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await wait_physics_frames(3)


func _human(root: GameRoot) -> Entity:
	return root.player


func _ai(root: GameRoot) -> Entity:
	for c in root.graph.entities_container.get_children():
		var e := c as Entity
		if e != null and not e.is_human_controlled and e.faction != null \
				and e.faction.id != &"blocker":
			return e
	return null


func _settle(root: GameRoot) -> void:
	await wait_until(root.command_applier.is_quiescent, 10.0, "applier never went quiescent")


## Every entity's stat values and pool `current`s, by entity id.
func _stats(root: GameRoot) -> Dictionary:
	var out := {}
	for c in root.graph.entities_container.get_children():
		var e := c as Entity
		if e == null or e.stat_board == null:
			continue
		var row := {}
		for id in e.stat_board.get_stat_ids():
			row[id] = e.stat_board.get_value(id)
			var s := e.stat_board.get_stat(id)
			if s is PoolStat:
				row[String(id) + ".current"] = (s as PoolStat).current
		out[e.entity_id] = row
	return out


func _allocate_frontier(root: GameRoot, who: Entity, count: int) -> void:
	for _i in count:
		var pick: SkillNode = null
		for n in root.graph.get_skill_nodes():
			if root.allocation_system.can_allocate(n, who):
				pick = n
				break
		if pick == null:
			return
		root.command_applier.submit(AllocateCommand.new(who.entity_id, root.graph.get_stable_id(pick)))
		await _settle(root)


## Save at a quiescent point, free the level, load it back from disk. Returns
## the saved image bytes and the pre-save readings to compare against.
func _save_and_reload(root: GameRoot) -> Dictionary:
	await _settle(root)
	var save := SaveFile.capture(root.graph)
	assert_eq(save.write_slot(_SLOT), OK, "write_slot")
	var before := {
		"image": save.world.to_bytes(),
		"fingerprint": WorldFingerprint.compute(root.graph),
		"stats": _stats(root),
		"holder": root.turn_manager.current_entity.entity_id,
		"path": save.level_scene_path,
	}
	await _free_level()
	GameSession.end()

	var loaded := SaveFile.read_slot(_SLOT)
	assert_eq(loaded.load_result, SaveFile.LoadResult.OK, "read_slot")
	assert_true(GameSession.open_saved(loaded), "open_saved accepts an OK save")
	assert_eq(GameSession.world_source, GameSession.WorldSource.ARRIVES)
	await _launch(load(loaded.level_scene_path) as PackedScene)
	return before


func _assert_same_world(before: Dictionary) -> void:
	assert_null(GameSession.pending_world, "the level consumed the parked image")
	assert_eq(WorldImage.capture(_root.graph).to_bytes(), before.image,
			"the loaded world re-captures to the saved image")
	assert_eq(WorldFingerprint.compute(_root.graph), before.fingerprint, "WorldFingerprint")
	assert_eq(_stats(_root), before.stats, "every entity's stats and pool currents")
	var holder := _root.turn_manager.current_entity
	assert_not_null(holder, "a turn holder after load")
	if holder != null:
		assert_eq(holder.entity_id, before.holder, "the same seat holds the turn")


func test_a_save_after_one_volley_resumes_the_same_turn() -> void:
	_start_run()
	var root := await _launch(_LEVEL)
	assert_eq(root.turn_manager.current_entity, _human(root), "fixture: the human opens")
	await _allocate_frontier(root, _human(root), 3)

	var enemy := _ai(root)
	assert_not_null(enemy, "fixture: an AI rival")
	root.input_ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	var plan := root.input_ctl.armed_stack.attack_plan() as RangedAttackPlan
	plan.set_target(enemy.core_location)
	var enemy_hp_before: Dictionary = _stats(root)[enemy.entity_id].duplicate()
	await root.battle_system.launch_attack(plan)
	await _settle(root)
	assert_eq(_human(root).volleys_launched_this_turn, 1, "fixture: one volley launched")
	assert_ne(_stats(root)[enemy.entity_id], enemy_hp_before, "fixture: the volley did damage")

	var before := await _save_and_reload(root)
	_assert_same_world(before)
	var human := _human(_root)
	assert_eq(human.volleys_launched_this_turn, 1, "the volley budget is not refilled")
	assert_true(human.is_taking_turn, "the human's turn resumed")

	# The turn cursor really resumed: ending it hands the turn on and back.
	_ai(_root).get_node("AIController").turn_delay = 0.0
	_root.command_applier.submit(EndTurnCommand.new(human.entity_id))
	await wait_until(func() -> bool: return _root.turn_manager.current_entity != human,
			5.0, "the turn left the human")
	await wait_until(func() -> bool: return _root.turn_manager.current_entity == human,
			5.0, "the AI handed the turn back")


func test_a_save_between_two_ai_actions_resumes_the_ai() -> void:
	_start_run()
	var root := await _launch(_LEVEL)
	var ai := _ai(root)
	(ai.get_node("AIController") as AIController).turn_delay = 0.3
	var nodes_before := root.graph.get_skill_nodes().filter(
			func(n: SkillNode) -> bool: return n.owned_by == ai).size()
	root.command_applier.submit(EndTurnCommand.new(_human(root).entity_id))
	await wait_until(func() -> bool: return root.turn_manager.current_entity == ai,
			5.0, "fixture: the AI takes the turn")
	# Its first action lands; the save is taken in the pause before the next.
	await wait_until(func() -> bool:
			return root.graph.get_skill_nodes().filter(
					func(n: SkillNode) -> bool: return n.owned_by == ai).size() > nodes_before,
			5.0, "fixture: the AI's first allocation")
	assert_eq(root.turn_manager.current_entity, ai, "fixture: still mid-AI-turn")

	var before := await _save_and_reload(root)
	_assert_same_world(before)
	var loaded_ai := _ai(_root)
	assert_true(loaded_ai.is_taking_turn, "the AI holds the turn after load")
	(loaded_ai.get_node("AIController") as AIController).turn_delay = 0.0
	await wait_until(func() -> bool: return _root.turn_manager.current_entity == _root.player,
			5.0, "the resumed AI finished its turn and handed it on")
