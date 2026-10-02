extends GutTest

## Shared fixture for the save/load round-trip scripts — one level pair each,
## to stay inside the integration budget. A save taken mid-turn reopens as the
## same world: `SaveFile.capture` + `write_slot` on a live `level.tscn`, the level freed, then `read_slot` →
## `GameSession.open_saved` → the level opened again from the save's own
## `level_scene_path`. Saves are taken directly at a quiescent point — the save
## gate is not under test here.

const _LEVEL := preload("res://scenes/level.tscn")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _SLOT := "user://test_save_load_round_trip.bin"
const _NODE_COUNT := 140

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


func _territory_hp(root: GameRoot, who: Entity) -> float:
	var total := 0.0
	for n in root.graph.get_skill_nodes():
		if n.owned_by == who:
			total += n.get_current_hp()
	return total


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


## Fixture: claim the path from [param who]'s core up to [param rival]'s border,
## so the rival core is in volley range. Not under test — a primitive suffices.
func _march_to(root: GameRoot, who: Entity, rival: Entity) -> void:
	for n in root.graph.navigator.path_between(who.core_location, rival.core_location):
		if n.owned_by == rival:
			return
		if n.owned_by == null:
			root.allocation_system.force_allocate(who, n)


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
	var now := WorldImage.capture(_root.graph)
	var saved := WorldImage.from_bytes(before.image)
	assert_eq(now.entity_bytes, saved.entity_bytes, "the entity half re-captures identically")
	assert_eq(now.graph_bytes, saved.graph_bytes, "the graph half re-captures identically")
	assert_eq(WorldFingerprint.compute(_root.graph), before.fingerprint, "WorldFingerprint")
	assert_eq(_stats(_root), before.stats, "every entity's stats and pool currents")
	var holder := _root.turn_manager.current_entity
	assert_not_null(holder, "a turn holder after load")
	if holder != null:
		assert_eq(holder.entity_id, before.holder, "the same seat holds the turn")
