extends GutTest

## "Launch takes the plan": the AI launches a plan it built itself, a mirror
## replays a plan it decoded, and neither ever writes the local
## [AttackPlanSlot] — the slot is the seated human's plan-in-progress and
## nobody else's. See [method BattleSystem.launch_attack].

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _CATALOG := preload("res://attack/melee/temp_upgrade_catalog.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _bs: BattleSystem
var _preview: MeleePreview
var _player: Entity
var _enemy: Entity
var _hostile: Entity
var _ai: AIController
var _nodes: Array[SkillNode]
## Every plan the slot was handed while a test watched it.
var _slot_writes: Array = []


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = TestBoards.flat_entity_board()
	e.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	e.stat_board.get_stat(&"crit_chance").base_value = 0.0
	e.stat_board.blade_size.base_value = 3.0
	if faction != null:
		e.faction = faction
	return e


func before_each() -> void:
	_slot_writes = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_preview = MeleePreview.new()
	add_child_autofree(_preview)

	_bs = autofree(BattleSystem.new())
	_bs.temp_upgrade_catalog = _CATALOG
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.melee_preview = _preview
	_preview.battle_system = _bs
	_bs.instant_mutation = true
	add_child(_bs)
	_preview._ready()

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _bs
	_applier.turn_manager = _tm
	add_child_autofree(_applier)
	_bs.command_applier = _applier

	_player = _make_entity("Player")
	_graph.entities_container.add_child(_player)
	_player.add_child(PlayerController.new())
	# The AI is driven by hand through `_execute_candidate`; it is not the
	# entity's child, so starting its turn races no `take_turn`.
	_enemy = _make_entity("Enemy")
	_graph.entities_container.add_child(_enemy)
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.command_applier = _applier
	_ai.battle_system = _bs
	add_child_autofree(_ai)
	# Wired after `_ready`, so it never subscribes to `turn_began`.
	_ai.entity = _enemy
	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.entities_container.add_child(_hostile)

	await get_tree().process_frame
	_alloc.force_allocate(_enemy, _nodes[0])
	_enemy.core_location = _nodes[0]
	_alloc.force_allocate(_enemy, _nodes[1])
	_alloc.force_allocate(_hostile, _nodes[2])
	_hostile.core_location = _nodes[2]
	_nodes[0].global_position = Vector2.ZERO
	_nodes[1].global_position = Vector2(100.0, 0.0)
	_nodes[2].global_position = Vector2(300.0, 0.0)
	_tm.start_turn(_enemy)


func _melee_candidate(cw: bool) -> AiCombatScorer.ScoredCandidate:
	var c := AiCombatScorer.ScoredCandidate.new()
	c.mode = BattleSystem.AttackMode.MELEE
	c.source_node = _nodes[0]
	var members: Array[SkillNode] = [_nodes[1]]
	c.blade_nodes = members
	c.swing_cw = cw
	return c


## A plan the seated human has armed and is still building.
func _arm_human_plan() -> AttackPlan:
	var plan := RangedAttackPlan.new()
	plan.attacker = _player
	_bs.plan_slot.attack_plan = plan
	return plan


func _watch_slot() -> void:
	_bs.plan_slot.attack_plan_changed.connect(func(p: AttackPlan) -> void:
		_slot_writes.append(p))


# (a) ------------------------------------------------------------------------

func test_ai_launch_leaves_an_empty_slot_empty() -> void:
	_watch_slot()
	var launched: bool = await _ai._execute_candidate(_melee_candidate(true))
	assert_true(launched, "sanity: the melee candidate launches")
	assert_null(_bs.plan_slot.attack_plan, "the AI never parks its plan in the slot")
	assert_eq(_slot_writes.size(), 0, "the slot was never written during the AI's swing")


func test_ai_launch_leaves_the_humans_armed_plan_armed() -> void:
	var human := _arm_human_plan()
	_watch_slot()
	var launched: bool = await _ai._execute_candidate(_melee_candidate(true))
	assert_true(launched, "sanity: the melee candidate launches")
	assert_eq(_bs.plan_slot.attack_plan, human, "the human's armed plan survives the AI's swing")
	assert_eq(_slot_writes.size(), 0, "the slot was never written during the AI's swing")


# (b) ------------------------------------------------------------------------

func test_mirror_replay_leaves_the_slot_untouched() -> void:
	var authored := MeleeAttackPlan.new()
	authored.attacker = _enemy
	authored.source = _nodes[0]
	authored.blade_nodes = [_nodes[1]] as Array[SkillNode]
	_bs.plan_slot.attack_plan = authored
	var cmd := _bs.build_launch_command()
	assert_not_null(cmd, "sanity: the authored plan builds a command")
	assert_true(_bs.prepare_launch_command(cmd), "sanity: the authority computes a record")
	var replay := LaunchAttackCommand.from_dict(cmd.to_dict())
	assert_false(replay.computed_here, "sanity: the wire copy is a replay")
	_bs.plan_slot.attack_plan = null
	var human := _arm_human_plan()
	_watch_slot()
	var applied: bool = await _bs.apply_launch_command(replay)
	assert_true(applied, "sanity: the replay applies")
	assert_eq(_bs.plan_slot.attack_plan, human, "a replay never writes the slot")
	assert_eq(_slot_writes.size(), 0, "the slot was never written during the replay")


# (c) ------------------------------------------------------------------------

func _confirmed_swing_cw(candidate_cw: bool, sticky_cw: bool) -> Array:
	_bs.next_melee_cw = sticky_cw
	var seen: Array = []
	_applier.command_confirmed.connect(func(c: Command) -> void:
		if c is LaunchAttackCommand:
			seen.append(bool((c as LaunchAttackCommand).plan.get("swing_cw", not candidate_cw))))
	await _ai._execute_candidate(_melee_candidate(candidate_cw))
	return seen


func test_ai_swings_the_candidates_direction_cw_against_a_ccw_sticky() -> void:
	var seen := await _confirmed_swing_cw(true, false)
	assert_eq(seen, [true], "the AI swings what was scored, not the human's toggle")


func test_ai_swings_the_candidates_direction_ccw_against_a_cw_sticky() -> void:
	var seen := await _confirmed_swing_cw(false, true)
	assert_eq(seen, [false], "the AI swings what was scored, not the human's toggle")


# (d) ------------------------------------------------------------------------

func test_presenter_is_live_during_an_ai_melee_launch() -> void:
	var presenters: Array = []
	_bs.attack_committed.connect(func(_o: AttackOutcome, _e: Entity) -> void:
		presenters.append(_bs.presenter()))
	await _ai._execute_candidate(_melee_candidate(true))
	assert_eq(presenters.size(), 1, "sanity: one commit")
	assert_eq(presenters[0], _preview, "the melee presenter answers for the AI's in-flight plan")
