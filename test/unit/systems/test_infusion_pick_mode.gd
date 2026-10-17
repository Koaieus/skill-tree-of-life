extends GutTest

## [InfusionPickMode]: one socket's aspect chooser as an [ArmedStack] leaf over
## [MagicMode], mirroring [SpellPickMode]. [method MagicMode.toggle_socket]
## opens it, or closes it when that socket is already open; a pick writes the
## plan through [method MagicAttackPlan.set_socket] and closes; a pop (Esc,
## right-click), a graph click and a launch close it without touching the plan.
##
## Board: Pivot - Joint - Tip owned by the attacker; Hostile adjacent to Tip,
## Far adjacent to Hostile, both owned by an NPC.

const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _world: TestWorld
var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _ctl: PlayerInputController
var _attacker: Entity
var _pivot: SkillNode
var _joint: SkillNode
var _tip: SkillNode
var _enemy: SkillNode
var _far: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	return _world.add_node(StringName(nm), pos)


func _entity(faction: Faction) -> Entity:
	var e := TestWorld.new_entity("", null, faction)
	_graph.add_child(e)
	return e


func before_each() -> void:
	_world = TestWorld.create(self)
	_graph = _world.graph
	_pivot = _spawn("Pivot", Vector2(0, 0))
	_joint = _spawn("Joint", Vector2(200, 0))
	_tip = _spawn("Tip", Vector2(400, 0))
	_enemy = _spawn("Hostile", Vector2(450, 0))
	_far = _spawn("Far", Vector2(600, 0))
	_world.link(_pivot, _joint)
	_world.link(_joint, _tip)
	_world.link(_tip, _enemy)
	_world.link(_enemy, _far)
	_attacker = _entity(_PLAYER_FACTION)
	var hostile := _entity(_NPC_FACTION)
	_alloc = TestWorld.around(_graph).allocator()
	for n in [_pivot, _joint, _tip]:
		_alloc.force_allocate(_attacker, n)
	_alloc.force_allocate(hostile, _enemy)
	_alloc.force_allocate(hostile, _far)
	_tm = TurnManager.new()
	add_child_autofree(_tm)
	_tm.start_turn(_attacker)
	_bs = BattleSystem.new()
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.instant_mutation = true
	add_child_autofree(_bs)
	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.turn_manager = _tm
	_ctl.battle_system = _bs
	_ctl.player = _attacker
	add_child_autofree(_ctl)


func _upgrade() -> PackedScene:
	return preload("res://test/support/addons/second_dot_addon.tscn")


func _heal_spell() -> SpellDef:
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.MINE
	var spell := SpellDef.new()
	spell.targeting = t
	spell.min_degree = 0
	return spell

func _magic() -> MagicAttackPlan:
	return _ctl.armed_stack.attack_plan() as MagicAttackPlan


func _picker() -> InfusionPickMode:
	return _ctl.armed_stack.find(InfusionPickMode) as InfusionPickMode


func _magic_level() -> MagicMode:
	return _ctl.armed_stack.find(MagicMode) as MagicMode


## Arms magic on a held-poison, held-curse caster with three sockets.
func _arm() -> void:
	var board := _attacker.stat_board
	board.intelligence.base_value = 10000.0
	board.facet(&"poison", StatDef.Role.ASPECT).base_value = 5.0
	board.facet(&"curse", StatDef.Role.ASPECT).base_value = 3.0
	_ctl.armed_stack.select_spell(_ctl.player, _heal_spell())
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	assert_not_null(_magic_level(), "precondition: magic armed")


func test_toggle_opens_then_closes_the_same_socket() -> void:
	_arm()
	assert_true(_magic_level().toggle_socket(1))
	assert_not_null(_picker())
	assert_eq(_picker().socket, 1)
	assert_false(_magic_level().toggle_socket(1), "same socket: closes")
	assert_null(_picker())


func test_toggle_another_socket_retargets_the_chooser() -> void:
	_arm()
	_magic_level().toggle_socket(0)
	assert_true(_magic_level().toggle_socket(1))
	assert_eq(_picker().socket, 1)
	assert_eq(_ctl.armed_stack.branch().filter(func(m: ArmedMode) -> bool: return m is InfusionPickMode).size(), 1,
			"one chooser at a time")


func test_pick_writes_the_plan_and_closes() -> void:
	_arm()
	_magic_level().toggle_socket(0)
	_picker().pick(&"poison")
	assert_null(_picker(), "closed")
	assert_eq(_magic().infusion.points.get(&"poison", 0), 5, "socketed at depth = held")


func test_a_pop_closes_without_changing_the_plan() -> void:
	_arm()
	_magic_level().toggle_socket(0)
	_ctl.armed_stack.pop_top()
	assert_null(_picker())
	assert_true(_magic().infusion.points.is_empty(), "plan untouched")
	assert_not_null(_magic_level(), "only the chooser popped")


func test_a_graph_click_closes_the_chooser_and_falls_through() -> void:
	_arm()
	_magic_level().toggle_socket(0)
	assert_false(_picker().handle_left_click(_enemy), "falls through")
	assert_null(_picker())
	assert_true(_magic().infusion.points.is_empty(), "plan untouched")


func test_a_launch_with_the_chooser_open_pops_it() -> void:
	_ctl.armed_stack.select_spell(_ctl.player, SpellCatalog.SPARK)
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	assert_true(_magic_level().set_target(_enemy), "precondition")
	assert_true(_magic_level().toggle_socket(0), "precondition")
	assert_true(_magic().is_valid(), "precondition: %s" % str(_magic().validate()))
	await _bs.launch_attack(_magic())
	await get_tree().process_frame
	assert_null(_picker(), "the launch popped the chooser")
