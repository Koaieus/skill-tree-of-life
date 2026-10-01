extends GutTest

## #1240 — a temp upgrade is plan content (ADR 0035). A remote seat's launch
## reaches the host as nothing but [member LaunchAttackCommand.plan]; the host
## rebuilds it — temp upgrades included — and judges only affordability.

const _CATALOG: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _graph: Graph
var _bs: BattleSystem
var _applier: CommandApplier
var _attacker: Entity
var _defender: Entity
var _nodes: Dictionary = {}


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	# "spare" is unowned and adjacent to the core — the one node in this fixture
	# an allocate can legally take, which the interleaving test needs.
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(300, 0)], ["spare", Vector2(0, 150)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		_graph.add_skill_node(node)
		node.global_position = entry[1]
		_nodes[entry[0]] = node
	_graph.add_edge(_nodes.core, _nodes.leaf)
	_graph.add_edge(_nodes.leaf, _nodes.target)
	_graph.add_edge(_nodes.core, _nodes.spare)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# #957: a volley needs arrows; the default board's quiver starts empty.
	_attacker.stat_board.arrows.add(AmmoTypeRoster.BASE_ID, 40)
	_attacker.stat_board.action_points.base_value = 4.0
	_graph.entities_container.add_child(_attacker)
	_defender = Entity.new()
	_defender.faction = _NPC_FACTION
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_defender)
	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	alloc.force_allocate(_attacker, _nodes.core)
	alloc.force_allocate(_attacker, _nodes.leaf)
	_attacker.core_location = _nodes.core
	alloc.force_allocate(_defender, _nodes.target)
	_defender.core_location = _nodes.target
	_set_local(_nodes.leaf, &"range", 400.0)
	_set_local(_nodes.leaf, &"ranged_damage", 3.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)

	_bs = BattleSystem.new()
	_bs.turn_manager = tm
	_bs.allocation_system = alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = alloc
	_applier.battle_system = _bs
	_applier.turn_manager = tm
	add_child_autofree(_applier)
	await get_tree().process_frame


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


func _clamp() -> TempUpgradeDef:
	return _CATALOG.by_id(&"clamp")


## The launch as it leaves a remote seat: built there, clamp placed there, then
## the preview addon freed — the host's live node never saw it. What arrives is
## the decoded command, with no local plan.
func _remote_launch(def: TempUpgradeDef = null) -> LaunchAttackCommand:
	if def == null:
		def = _clamp()
	_bs.temp_upgrade_catalog = _CATALOG
	_attacker.stat_board.blade_size.base_value = 3.0
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.set_pivot(_nodes.core)
	plan.toggle_member(_nodes.leaf)
	assert_true(plan.toggle_temp_upgrade(_nodes.leaf, def),
			"fixture: the seat placed the upgrade")
	var sent := _bs.build_launch_command(plan)
	assert_not_null(sent, "fixture: the seat's plan is launchable")
	plan.reset()
	var received := CommandCodec.from_dict(sent.to_dict()) as LaunchAttackCommand
	assert_null(received.local_plan, "fixture: nothing but the dict crossed")
	return received


func _temp_addons(node: SkillNode) -> int:
	var n := 0
	for a in node.get_addons():
		if a.is_temporary:
			n += 1
	return n


func test_the_host_rebuilds_a_remote_seats_plan_with_its_temp_upgrade() -> void:
	var command := _remote_launch()
	assert_true(_bs.prepare_launch_command(command),
			"the host decodes the remote plan rather than refusing it")
	assert_false(command.record.is_empty(), "…and resolves it into a record")
	var plan := command.local_plan as MeleeAttackPlan
	assert_not_null(plan, "the decoded plan is the one the apply commits")
	assert_eq(plan.temp_upgrade_cost_for(_clamp()), SkillNodeAddon.temp_costs_of(_clamp().scene)[&"blade_size"],
			"the upgrade is in the swing the host resolved")
	assert_eq(_temp_addons(_nodes.leaf), 1, "mounted on the node the seat chose")


func test_a_confirmed_remote_launch_lands_and_frees_its_temp_addons() -> void:
	var command := _remote_launch()
	var applied: Array[bool] = []
	_applier.command_applied.connect(func(_cmd: Command, ok: bool): applied.append(ok))
	_applier.submit(command)
	while _applier.is_applying:
		await _applier.applying_changed
	assert_eq(applied, [true] as Array[bool], "the remote seat's swing is accepted")
	assert_eq(_temp_addons(_nodes.leaf), 0, "the swing's temp addons go with the swing")


func test_a_launch_over_its_blade_budget_is_refused_whole() -> void:
	var command := _remote_launch()
	# The seat planned against 3; the host's board says 1 — members plus the
	# clamp's cost no longer fit.
	_attacker.stat_board.blade_size.base_value = 1.0
	var applied: Array[bool] = []
	_applier.command_applied.connect(func(_cmd: Command, ok: bool): applied.append(ok))
	var confirmed: Array[Command] = []
	_applier.command_confirmed.connect(func(cmd: Command): confirmed.append(cmd))
	_applier.submit(command)
	while _applier.is_applying:
		await _applier.applying_changed
	assert_eq(applied, [false] as Array[bool],
			"refused — the refusal is what the seat's launch-denial reads")
	assert_eq(confirmed, [] as Array[Command], "never confirmed, so never crosses")
	assert_eq(_temp_addons(_nodes.leaf), 0, "and the decode left nothing mounted")


## #1268 — the aspect cap is judged at the same door as the budget: a remote
## plan carrying more toxins than the attacker's poison_aspect is refused.
func test_a_launch_over_its_poison_aspect_is_refused_whole() -> void:
	_attacker.stat_board.poison_aspect.base_value = 1.0
	var command := _remote_launch(_CATALOG.by_id(&"toxin"))
	# The seat planned against poison_aspect 1; the host's board says 0.
	_attacker.stat_board.poison_aspect.base_value = 0.0
	var applied: Array[bool] = []
	_applier.command_applied.connect(func(_cmd: Command, ok: bool): applied.append(ok))
	_applier.submit(command)
	while _applier.is_applying:
		await _applier.applying_changed
	assert_eq(applied, [false] as Array[bool], "refused — more toxins than poison_aspect")
	assert_eq(_temp_addons(_nodes.leaf), 0, "and the decode left nothing mounted")
