extends GutTest

## [WorldImage] round-trips a played world: capture on a seated, procgen'd level
## after allocations and a damaging attack, apply onto the client shape (the
## roster seated, nothing generated), capture again. The bytes and the
## fingerprint must agree, and so must every entity's every stat value and pool
## `current` — [WorldFingerprint] folds graph-side facts only, so that last
## check is the tripwire for entity state no snapshot carries.
##
## Two [GameRoot]s in one process, wire never linked: what is under test is the
## image, not the transport. Same two-worlds hazard as
## `test/integration/network/test_mp_procgen_join.gd` (whose fixture this
## clones), kept safe the same way — nothing dies, no turn ends.

const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _RED_COLOR := Color(0.4, 0.8, 1.0)
const _BLUE_COLOR := Color(0.95, 0.4, 0.4)
const _FIXED_SEED := 90211332

var _host_root: GameRoot
var _client_root: GameRoot


func before_each() -> void:
	GameSession.end()


func after_each() -> void:
	GameSession.end()


func _build_root(label: String) -> GameRoot:
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	root.name = "GameRoot_%s" % label
	root.get_node("%TurnManager").opens_first_turn = false
	add_child_autofree(root)
	return root


## Hides every OTHER world's TurnManager from the group for one spawn, so a
## group reader during bring-up finds the spawning world's own.
func _spawn_scoped(root: GameRoot, ent_name: String, color: Color,
		core_location: SkillNode, core_class: CoreClass) -> Entity:
	var hidden: Array[Node] = []
	for other in get_tree().get_nodes_in_group(TurnManager.GROUP):
		if other != root.turn_manager:
			hidden.append(other)
			other.remove_from_group(TurnManager.GROUP)
	var ent := root.spawn_entity(ent_name, color, core_location, core_class)
	for other in hidden:
		other.add_to_group(TurnManager.GROUP)
	return ent


func _roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	var red := Participant.new()
	red.id = 0
	red.display_name = "Red"
	red.color = _RED_COLOR
	red.camp = _PLAYER_FACTION
	red.kind = Participant.Kind.HUMAN
	roster.add(red)
	var blue := Participant.new()
	blue.id = 1
	blue.display_name = "Blue"
	blue.color = _BLUE_COLOR
	blue.camp = _NPC_FACTION
	blue.kind = Participant.Kind.AI
	roster.add(blue)
	return roster


func _local_set(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _first_frontier_node(graph: Graph, owner: Entity) -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == owner:
				return node
	return null


## The host plays a little: a few allocations, then one non-lethal volley on
## Blue's core. Returns the host's Red and Blue.
func _played_host() -> Array[Entity]:
	_host_root = _build_root("host")
	await wait_physics_frames(2)
	var cfg := RunConfig.new()
	cfg.seed = _FIXED_SEED
	GameSession.start(cfg)
	var gcfg: GraphProcgenConfig = _PRESET.duplicate(true)
	gcfg.topology = gcfg.topology.duplicate(true)
	gcfg.topology.node_count = 60
	gcfg.camp_sizes = [2]
	gcfg.seed = GameSession.config.seed
	var result: Dictionary = await GraphProcgen.generate(gcfg, _host_root.graph)
	var starts: Array = result.get("starting_nodes", [])
	assert_eq(starts.size(), 2, "sanity: two starters")
	GameSession.roster = _roster()
	var red := _spawn_scoped(_host_root, "Red", _RED_COLOR, starts[0], _BALANCED)
	var blue := _spawn_scoped(_host_root, "Blue", _BLUE_COLOR, starts[1], _BASIC_ENEMY)
	GameRoot.apply_roster({0: red, 1: blue}, GameSession.roster)

	red.stat_board.action_points.base_value = 20.0
	red.stat_board.action_points.current = 20.0
	red.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	red.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_host_root.turn_manager.start_turn(red)

	var graph := _host_root.graph
	for i in 3:
		var target := _first_frontier_node(graph, red)
		if target == null:
			break
		_host_root.command_applier.submit(
				AllocateCommand.new(red.entity_id, graph.get_stable_id(target)))
		await get_tree().process_frame

	var blue_core := blue.core_location
	var hp_before := blue_core.get_current_hp()
	_local_set(red.core_location, &"range", 100000.0)
	_local_set(red.core_location, &"ranged_damage", 1.0)
	var bs := _host_root.battle_system
	bs.instant_mutation = true
	var plan := bs.new_plan(BattleSystem.AttackMode.RANGED, red) as RangedAttackPlan
	plan.set_target(blue_core)
	assert_true(plan.is_valid(), "sanity: the volley is a legal plan")
	bs.launch_attack(plan)
	await get_tree().process_frame
	assert_lt(blue_core.get_current_hp(), hp_before, "sanity: the attack did damage")
	assert_true(is_instance_valid(blue) and blue.core_location != null,
			"sanity: the volley was not lethal")
	return [red, blue]


## The client shape: the roster seated in the host's spawn order, no graph.
func _seated_client() -> void:
	_client_root = _build_root("client")
	await wait_physics_frames(2)
	var red := _spawn_scoped(_client_root, "Red", _RED_COLOR, null, _BALANCED)
	var blue := _spawn_scoped(_client_root, "Blue", _BLUE_COLOR, null, _BASIC_ENEMY)
	GameRoot.apply_roster({0: red, 1: blue}, GameSession.roster)
	assert_true(_client_root.graph.get_skill_nodes().is_empty(), "sanity: nothing generated")


static func _entity_state(graph: Graph) -> Dictionary:
	var out := {}
	for e in EntitySnapshot.entities_of(graph):
		var stats := {}
		for s in e.stat_board._all_stats():
			var key := String(s.definition.id) if s.definition != null else str(s)
			stats[key] = s.get_value()
			if s is PoolStat:
				stats[key + ".current"] = (s as PoolStat).current
		out[e.entity_id] = stats
	return out


func test_a_played_world_round_trips_through_the_image() -> void:
	await _played_host()
	var image := WorldImage.capture(_host_root.graph)
	var host_fp := WorldFingerprint.compute(_host_root.graph)
	var host_state := _entity_state(_host_root.graph)

	await _seated_client()
	image.apply(_client_root.graph, _client_root.entity_factory.spawn_snapshot_entity,
			_client_root.turn_manager)
	var again := WorldImage.capture(_client_root.graph)

	assert_false(image.to_bytes().is_empty(), "the image carries a world")
	assert_eq(again.to_bytes(), image.to_bytes(), "capture → apply → capture is byte-identical")
	assert_eq(WorldFingerprint.compute(_client_root.graph), host_fp, "the fingerprints agree")
	var client_state := _entity_state(_client_root.graph)
	assert_eq_deep(client_state.keys(), host_state.keys())
	for id in host_state:
		var want: Dictionary = host_state[id]
		var got: Dictionary = client_state.get(id, {})
		for key in want:
			assert_eq(got.get(key), want[key], "entity %d: %s" % [id, key])


func test_the_disk_form_round_trips() -> void:
	await _played_host()
	var image := WorldImage.capture(_host_root.graph)
	var reread := WorldImage.from_bytes(image.to_bytes())
	assert_not_null(reread)
	assert_eq(reread.to_bytes(), image.to_bytes(), "to_bytes ∘ from_bytes is the identity")

