extends GutTest

## The attack click grammar on the [ArmedStack] (#1223): each step of an
## attack is its own level. Melee pushes Blade on a pivot; Ranged and Magic
## push Target on a target. Right-click / Esc pops the top level, so two pops
## from anywhere reach the root. The plan owns *which node*; the stack owns
## *what the next click means*. See docs/domain/click-grammar.md.
##
## Board: Pivot - Joint - Tip owned by the attacker; Hostile adjacent to Tip,
## Far adjacent to Hostile, both owned by an NPC.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

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
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	sn.position = pos
	_graph.add_skill_node(sn)
	return sn


func _entity(faction: Faction) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.faction = faction
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_pivot = _spawn("Pivot", Vector2(0, 0))
	_joint = _spawn("Joint", Vector2(200, 0))
	_tip = _spawn("Tip", Vector2(400, 0))
	_enemy = _spawn("Hostile", Vector2(450, 0))
	_far = _spawn("Far", Vector2(600, 0))
	_graph.add_edge(_pivot, _joint)
	_graph.add_edge(_joint, _tip)
	_graph.add_edge(_tip, _enemy)
	_graph.add_edge(_enemy, _far)
	_attacker = _entity(_PLAYER_FACTION)
	var hostile := _entity(_NPC_FACTION)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
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


func _branch() -> Array:
	return _ctl.armed_stack.branch().map(func(m: ArmedMode) -> Script: return m.get_script())


func _melee() -> MeleeAttackPlan:
	return _ctl.armed_stack.attack_plan() as MeleeAttackPlan


func _upgrade() -> PackedScene:
	return preload("res://test/fixtures/addons/second_dot_addon.tscn")


func _heal_spell() -> SpellDef:
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.MINE
	var spell := SpellDef.new()
	spell.targeting = t
	spell.min_degree = 0
	return spell


# ── Melee / Blade ─────────────────────────────────────────────────────────

func test_melee_pivot_pushes_blade_and_two_pops_reach_the_root() -> void:
	assert_true(_ctl.arm_attack(BattleSystem.AttackMode.MELEE))
	assert_eq(_branch(), [ManageMode, MeleeMode])
	_ctl.route_left_click(_pivot)
	assert_eq(_branch(), [ManageMode, MeleeMode, BladeMode], "a pivot pushes Blade")
	assert_eq(_melee().source, _pivot)
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode, MeleeMode], "pop 1 drops Blade")
	assert_null(_melee().source, "and Blade's pop clears the pivot")
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode], "pop 2 exits melee")
	assert_false((_ctl.armed_stack.attack_plan() != null), "with no plan left")
	assert_false(_ctl.pop_armed_level(), "the root does not pop")


func test_clicking_the_pivot_at_blade_pops_blade() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	_ctl.route_left_click(_pivot)
	_ctl.route_left_click(_joint)
	assert_eq(_melee().blade_nodes, [_joint] as Array[SkillNode], "precondition: a member")
	watch_signals(Events)
	_ctl.route_left_click(_pivot)
	assert_eq(_branch(), [ManageMode, MeleeMode], "the pivot click pops Blade")
	assert_null(_melee().source)
	assert_signal_not_emitted(Events, "node_action_denied", "no denial shake")


func test_reset_button_pops_blade() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	_ctl.route_left_click(_pivot)
	_ctl.armed_stack.reset_plan()
	assert_eq(_branch(), [ManageMode, MeleeMode], "RESET is Blade's pop event")
	assert_null(_melee().source)


func test_a_launch_pops_blade_and_melee_stays_armed_then_reform_pushes_blade() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	_ctl.route_left_click(_pivot)
	_ctl.route_left_click(_joint)
	assert_true(_melee().is_valid(), "precondition: %s" % str(_melee().validate()))
	_bs.launch_attack(_ctl.armed_stack.attack_plan())
	await wait_until(func() -> bool: return not _bs.is_launching and (_ctl.armed_stack.attack_plan() != null), 5.0)
	assert_eq(_branch(), [ManageMode, MeleeMode], "Blade is gone, Melee stays armed")
	assert_true((_ctl.armed_stack.attack_plan() != null), "with a fresh melee plan")
	assert_null(_melee().source if _melee() != null else null, "the fresh plan is empty")
	assert_true(_ctl.reform_blade(), "precondition: the last blade reforms")
	assert_eq(_branch(), [ManageMode, MeleeMode, BladeMode], "reform pushes Blade")
	assert_eq(_melee().source, _pivot)
	assert_eq(_melee().blade_nodes, [_joint] as Array[SkillNode], "with the reformed members")


func test_temp_upgrade_arms_only_with_blade_up() -> void:
	var def := _upgrade()
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	assert_false(_ctl.can_arm_temp_upgrade(), "no blade, no temp upgrade")
	_ctl.arm_temp_upgrade(def)
	assert_eq(_branch(), [ManageMode, MeleeMode], "refused: nothing pushed")
	_ctl.route_left_click(_pivot)
	_ctl.route_left_click(_joint)
	assert_true(_ctl.can_arm_temp_upgrade())
	_ctl.arm_temp_upgrade(def)
	assert_eq(_branch(), [ManageMode, MeleeMode, BladeMode, TempUpgradeMode])
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode, MeleeMode, BladeMode], "right-click pops only the upgrade")
	assert_eq(_melee().source, _pivot, "pivot intact")
	assert_eq(_melee().blade_nodes, [_joint] as Array[SkillNode], "members intact")


func test_melee_tint_is_the_same_at_every_depth() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	var at_melee := _ctl.get_armed_tint()
	assert_gt(at_melee.a, 0.0, "melee lends a tint")
	_ctl.route_left_click(_pivot)
	assert_eq(_ctl.get_armed_tint(), at_melee, "same at Blade")
	_ctl.arm_temp_upgrade(_upgrade())
	assert_eq(_branch().back(), TempUpgradeMode, "precondition")
	assert_eq(_ctl.get_armed_tint(), at_melee, "same at TempUpgrade")


# ── Ranged / Magic → Target ───────────────────────────────────────────────

func test_ranged_target_pushes_target_retargets_in_place_and_two_pops_exit() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.RANGED)
	assert_eq(_branch(), [ManageMode, RangedMode])
	_ctl.route_left_click(_enemy)
	assert_eq(_branch(), [ManageMode, RangedMode, TargetMode], "a target pushes Target")
	_ctl.route_left_click(_far)
	assert_eq(_branch(), [ManageMode, RangedMode, TargetMode], "retarget keeps the depth")
	assert_eq((_ctl.armed_stack.attack_plan() as RangedAttackPlan).target, _far)
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode, RangedMode])
	assert_null((_ctl.armed_stack.attack_plan() as RangedAttackPlan).target, "the pop clears the target")
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode], "the next pop exits")
	assert_false((_ctl.armed_stack.attack_plan() != null))


func test_magic_target_pushes_target_retargets_in_place_and_two_pops_exit() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_ctl.armed_stack.selected_spell = _heal_spell()
	_ctl.route_left_click(_joint)
	assert_eq(_branch(), [ManageMode, MagicMode, TargetMode], "a target pushes Target")
	_ctl.route_left_click(_tip)
	assert_eq(_branch(), [ManageMode, MagicMode, TargetMode], "retarget keeps the depth")
	var plan := _ctl.armed_stack.attack_plan() as MagicAttackPlan
	assert_eq(plan.target, _tip)
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode, MagicMode])
	assert_null(plan.target, "the pop clears the target")
	assert_null(plan.source, "and its auto-picked caster")
	assert_true(_ctl.pop_armed_level())
	assert_eq(_branch(), [ManageMode])


func test_a_spell_swap_that_drops_the_target_pops_target() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MAGIC)
	_ctl.armed_stack.selected_spell = _heal_spell()
	_ctl.route_left_click(_joint)
	assert_eq(_branch(), [ManageMode, MagicMode, TargetMode], "precondition")
	var hostile_only := _heal_spell()
	(hostile_only.targeting as NodeTargeting).ownership_filter = SkillNode.Ownership.HOSTILE
	_ctl.armed_stack.selected_spell = hostile_only
	assert_null((_ctl.armed_stack.attack_plan() as MagicAttackPlan).target, "precondition: the swap dropped it")
	assert_eq(_branch(), [ManageMode, MagicMode], "the spell swap is Target's pop event")


# ── Controller-wide ───────────────────────────────────────────────────────

func test_esc_pops_one_level_same_as_right_click() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	_ctl.route_left_click(_pivot)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	_ctl._unhandled_key_input(esc)
	assert_eq(_branch(), [ManageMode, MeleeMode], "Esc pop 1 drops Blade")
	_ctl._unhandled_key_input(esc)
	assert_eq(_branch(), [ManageMode], "Esc pop 2 exits the mode")
	assert_false((_ctl.armed_stack.attack_plan() != null))


func test_d_gated_while_attack_plan_armed() -> void:
	_ctl.arm_attack(BattleSystem.AttackMode.MELEE)
	_ctl.route_left_click(_pivot)
	Events.skill_node_hovered.emit(_joint)
	var d := InputEventKey.new()
	d.physical_keycode = KEY_D
	d.pressed = true
	_ctl._unhandled_input(d)
	assert_eq(_joint.owned_by, _attacker, "D is gated off while an attack plan is armed (#404)")
