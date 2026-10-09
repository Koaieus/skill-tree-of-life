extends GutTest

## Scout discs on [VisionSystem], read from rows (#1346): a scout arrow lands
## one `scout` stack ([member VisionSystem.scouted_def]) keyed by the firer's
## camp; every viewer of that camp sees a disc of
## [method ScoutStatus.radius_for] on the node, another camp sees nothing, the
## row decays on the victim's turn end like any node status, and a mirror
## rebuilt from the [AttackRecord] draws the same disc.
##
## Layout (world units, all on y=0): the attacker (player camp) owns core x=0
## and leaf x=100, both sight 50; the defender (npc camp) owns target x=400
## (sight 200) and neighbour x=700. P at x=590 is unowned, 190 past the target:
## inside `radius_for(target, 4)` = 0.5·√4·200 = 200, outside
## `radius_for(target, 3)` ≈ 173.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _SCOUTED: ScoutStatus = preload("res://effects/status/scouted.tres")

var _graph: Graph
var _bs: BattleSystem
var _vision: VisionSystem
var _attacker: Entity
var _defender: Entity
var _nodes: Dictionary = {}


func before_each() -> void:
	_nodes = {}
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	for entry in [["core", 0.0], ["leaf", 100.0], ["target", 400.0],
			["neighbour", 700.0], ["probe", 590.0]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		_graph.add_skill_node(node)
		node.global_position = Vector2(float(entry[1]), 0.0)
		_nodes[entry[0]] = node
	_graph.add_edge(_nodes.core, _nodes.leaf)
	_graph.add_edge(_nodes.leaf, _nodes.target)
	_graph.add_edge(_nodes.target, _nodes.neighbour)

	_attacker = _entity("Attacker", _PLAYER_FACTION)
	assert_eq(_attacker.stat_board.arrows.add(&"scout", 4), 4, "fixture quiver must hold the scouts")
	_defender = _entity("Defender", _NPC_FACTION)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _nodes.core)
	alloc.force_allocate(_attacker, _nodes.leaf)
	_attacker.core_location = _nodes.core
	alloc.force_allocate(_defender, _nodes.target)
	alloc.force_allocate(_defender, _nodes.neighbour)
	_defender.core_location = _nodes.neighbour

	_set_local(_nodes.leaf, &"range", 400.0)
	_set_local(_nodes.leaf, &"max_shots_per_leaf", 5.0)
	_set_local(_nodes.core, &"max_shots_per_leaf", 0.0)
	_set_local(_nodes.leaf, &"vision_range", 50.0)
	_set_local(_nodes.core, &"vision_range", 50.0)
	_set_local(_nodes.target, &"vision_range", 200.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)

	_bs = BattleSystem.new()
	_bs.turn_manager = tm
	_bs.allocation_system = alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)

	_vision = _viewer(_attacker)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_vision._recompute()
	assert_false(_vision.is_visible(_nodes.probe), "fixture: P is outside the attacker's own sight")


func _entity(nm: String, faction: Faction) -> Entity:
	var en := Entity.new()
	en.display_name = nm
	en.faction = faction
	en.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(en)
	return en


func _viewer(who: Entity) -> VisionSystem:
	var v := VisionSystem.new()
	v.graph = _graph
	v.viewers = [who]
	v.ease_rate = 0.0
	add_child_autofree(v)
	return v


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _plan(scouts: int) -> RangedAttackPlan:
	var plan := _bs.new_plan(BattleSystem.AttackMode.RANGED, _attacker) as RangedAttackPlan
	plan.set_target(_nodes.target)
	plan.ammo = [{"type": &"scout", "count": scouts}]
	return plan


## The real path: build, validate and apply the launch command.
func _launch(scouts: int) -> void:
	var command := _bs.build_launch_command(_plan(scouts))
	assert_not_null(command, "the fixture plan must be launchable")
	assert_true(_bs.prepare_launch_command(command), "the fixture attack must survive validation")
	@warning_ignore("redundant_await")
	await _bs.apply_launch_command(command)


func _row(camp: Faction) -> float:
	return (_nodes.target as SkillNode).get_combat().get_status_power(_SCOUTED.id, camp.id)


func _scout_sources(v: VisionSystem, who: Entity) -> Array[VisionSource]:
	var out: Array[VisionSource] = []
	for s in v.sources_for([who] as Array[Entity]):
		if s.kind == VisionSource.Kind.SCOUT:
			out.append(s)
	return out


## The disc the renderer gets at [param node], or 0.
func _disc_at(v: VisionSystem, node: SkillNode) -> float:
	var best := 0.0
	for src in v.get_vision_sources():
		if src.pos.is_equal_approx(node.global_position):
			best = maxf(best, src.radius)
	return best


func test_a_volley_of_four_lands_row_a_four_and_draws_its_disc() -> void:
	await _launch(4)
	assert_eq(_row(_PLAYER_FACTION), 4.0, "one stack per arrow, keyed by the firer's camp")
	assert_eq(_row(_NPC_FACTION), 0.0, "no row for the victim's camp")
	await get_tree().process_frame
	var r4 := _SCOUTED.radius_for(_nodes.target, 4)
	assert_almost_eq(r4, 200.0, 0.001, "fixture: 0.5 · √4 · 200")
	var scout := _scout_sources(_vision, _attacker)
	assert_eq(scout.size(), 1, "one scout disc for camp A")
	if scout.size() == 1:
		assert_eq(scout[0].node, _nodes.target)
		assert_almost_eq(scout[0].radius, r4, 0.001)
	assert_true(_vision.is_visible(_nodes.target), "the node itself")
	assert_true(_vision.is_visible(_nodes.probe), "P at 190 is inside the 200 disc")
	assert_false(_vision.is_visible(_nodes.neighbour), "the neighbour at 300 is not")
	await get_tree().process_frame  # the recompute is deferred; the ease snaps on the next process
	assert_almost_eq(_disc_at(_vision, _nodes.target), r4, 0.001, "the renderer draws it")
	assert_true((_nodes.target as SkillNode).scouted, "the local camp's ring is on")


func test_a_camp_b_viewer_gains_nothing() -> void:
	await _launch(4)
	var other := _viewer(_defender)
	await get_tree().process_frame
	other._recompute()
	assert_eq(_scout_sources(other, _defender).size(), 0, "B holds no disc of A's rows")
	assert_false((_nodes.target as SkillNode).scouted, "B's machine shows no ring")


func test_one_victim_turn_end_shrinks_the_disc_to_three_stacks() -> void:
	await _launch(4)
	_defender.resolve_turn_end()
	assert_eq(_row(_PLAYER_FACTION), 3.0, "one stack fades per victim turn end")
	await get_tree().process_frame
	var scout := _scout_sources(_vision, _attacker)
	assert_eq(scout.size(), 1)
	if scout.size() == 1:
		assert_almost_eq(scout[0].radius, _SCOUTED.radius_for(_nodes.target, 3), 0.001)
	assert_false(_vision.is_visible(_nodes.probe), "P at 190 is outside the ~173 disc, no explicit recompute")


func test_a_mirror_rebuilt_from_the_record_draws_the_same_disc() -> void:
	# The authority resolves on a shadow; the live world here plays the mirror
	# that only ever sees the wired record.
	var shadow := CombatWorld.shadow()
	var outcome := _plan(4).resolve_against(shadow)
	shadow.free_shadow()
	assert_eq(_row(_PLAYER_FACTION), 0.0, "fixture: the shadow resolve left the live board alone")
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _graph)))
	OutcomeApplier.apply(AttackRecord.rebuild(wired, _graph), CombatWorld.live())
	assert_eq(_row(_PLAYER_FACTION), 4.0, "the mirror lands row A = 4")
	await get_tree().process_frame
	var scout := _scout_sources(_vision, _attacker)
	assert_eq(scout.size(), 1)
	if scout.size() == 1:
		assert_almost_eq(scout[0].radius, _SCOUTED.radius_for(_nodes.target, 4), 0.001)
	assert_true(_vision.is_visible(_nodes.probe), "the mirror sees what the authority sees")


func test_pick_sensed_makes_a_sensed_only_node_pickable() -> void:
	_set_local(_nodes.leaf, &"sensor_range", 1.0)
	_vision._recompute()
	assert_true(_vision.is_sensed(_nodes.target), "fixture: target is one hop from the leaf")
	assert_false(_vision.is_visible(_nodes.target), "fixture: and out of sight")
	assert_false((_nodes.target as SkillNode).input_pickable, "sensed-only is not pickable by default")
	_vision.pick_sensed = true
	_vision._recompute()
	assert_true((_nodes.target as SkillNode).input_pickable, "pick_sensed opens sensed-only nodes to input")
