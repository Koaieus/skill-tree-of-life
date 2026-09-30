extends GutTest

## [AttackPlanSlot] is the local plan-in-progress on its own: arming a mode,
## the sticky preferences that outlive a plan reset, the magic union's
## invalidation on allocation, and temp-upgrade toggling. Those cases run with
## NO [BattleSystem] in the tree; the last two pin that a wired BattleSystem
## mints no slot of its own and a bare one forwards to a private slot.

## A `var`, not a `const`: the parser constant-folds `CONST.kinds[i]`.
var _catalog: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")

const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _attacker: Entity
var _slot: AttackPlanSlot
var _source: SkillNode
var _joint: SkillNode
var _tip: SkillNode
var _spare: SkillNode


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_source = _spawn("Source")
	_joint = _spawn("Joint")
	_tip = _spawn("Tip")
	_spare = _spawn("Spare")
	_graph.add_edge(_source, _joint)
	_graph.add_edge(_joint, _tip)
	_graph.add_edge(_tip, _spare)

	_attacker = Entity.new()
	_attacker.faction = _PLAYER_FACTION
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 3.0
	_graph.add_child(_attacker)
	await get_tree().process_frame

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_alloc.force_allocate(_attacker, _source)
	_alloc.force_allocate(_attacker, _joint)
	_alloc.force_allocate(_attacker, _tip)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.start_turn(_attacker)

	_slot = AttackPlanSlot.new()
	_slot.turn_manager = tm
	_slot.allocation_system = _alloc
	_slot.temp_upgrade_catalog = _catalog
	add_child_autofree(_slot)


func test_no_battle_system_is_mounted() -> void:
	assert_eq(get_tree().root.find_children("*", "BattleSystem", true, false).size(), 0,
			"fixture: the slot must stand alone")


func test_arms_each_mode() -> void:
	var cases := {
		BattleSystem.AttackMode.MELEE: MeleeAttackPlan,
		BattleSystem.AttackMode.RANGED: RangedAttackPlan,
		BattleSystem.AttackMode.MAGIC: MagicAttackPlan,
	}
	for mode in cases:
		_slot.request_attack_mode(mode)
		assert_eq(_slot.attack_mode, mode, "request_attack_mode arms mode %d" % mode)
		assert_true(_slot.is_attacking)
		assert_eq(_slot.attack_plan.get_script(), cases[mode])
		assert_eq(_slot.attack_plan.attacker, _attacker,
				"the plan's attacker is the turn's entity")
	_slot.request_attack_mode(BattleSystem.AttackMode.NONE)
	assert_eq(_slot.attack_mode, BattleSystem.AttackMode.NONE)
	assert_false(_slot.is_attacking, "NONE cancels the plan")


func test_arming_emits_the_plan_signals() -> void:
	watch_signals(_slot)
	_slot.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_signal_emitted(_slot, "attack_plan_changed")
	assert_signal_emitted(_slot, "attack_plan_state_changed")


func test_next_melee_cw_is_sticky_across_reset_plan() -> void:
	_slot.next_melee_cw = true
	_slot.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _slot.attack_plan as MeleeAttackPlan
	assert_true(plan.swing_cw, "the new melee plan takes the sticky direction")
	_slot.reset_plan()
	assert_eq(_slot.attack_plan, plan, "reset_plan keeps the plan itself")
	assert_true(_slot.next_melee_cw, "reset_plan keeps the sticky direction")
	_slot.cancel_attack()
	_slot.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_true((_slot.attack_plan as MeleeAttackPlan).swing_cw,
			"a fresh melee plan still takes it")


func test_selected_spell_is_sticky_across_reset_plan() -> void:
	watch_signals(_slot)
	_slot.selected_spell = SpellCatalog.SPARK
	assert_signal_emitted(_slot, "selected_spell_changed")
	_slot.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	assert_eq((_slot.attack_plan as MagicAttackPlan).spell, SpellCatalog.SPARK)
	_slot.reset_plan()
	assert_eq(_slot.selected_spell, SpellCatalog.SPARK, "reset_plan keeps the spell")
	assert_eq((_slot.attack_plan as MagicAttackPlan).spell, SpellCatalog.SPARK)


func test_allocation_invalidates_the_magic_union() -> void:
	_slot.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	var plan := _slot.attack_plan as MagicAttackPlan
	watch_signals(plan)
	_alloc.force_allocate(_attacker, _spare)
	assert_signal_emitted(plan, "state_changed",
			"an allocation announces the union change on the plan's own signal")


func test_locked_refuses_cancel_reset_and_mode_change() -> void:
	_slot.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _slot.attack_plan
	_slot.locked = true
	_slot.request_attack_mode(BattleSystem.AttackMode.RANGED)
	assert_eq(_slot.attack_plan, plan, "a locked slot keeps its plan")
	_slot.cancel_attack()
	assert_eq(_slot.attack_plan, plan, "a locked slot refuses cancel")
	assert_push_warning("Cannot cancel attack")


func test_toggles_a_temp_upgrade() -> void:
	_slot.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _slot.attack_plan as MeleeAttackPlan
	plan.set_pivot(_source)
	plan.toggle_member(_joint)
	plan.toggle_member(_tip)
	var clamp := _slot.temp_upgrade_by_id(&"clamp")
	assert_not_null(clamp, "the wired catalog answers by id")
	assert_true(_slot.temp_upgrade_kinds().has(clamp))
	var before := _joint.get_addons().size()
	assert_true(plan.can_toggle_temp_upgrade(_joint, clamp))
	assert_true(plan.toggle_temp_upgrade(_joint, clamp), "first toggle applies")
	assert_eq(_joint.get_addons().size(), before + 1)
	assert_true(plan.toggle_temp_upgrade(_joint, clamp), "second toggle refunds")
	assert_eq(_joint.get_addons().size(), before)


# ── BattleSystem's two slot paths must not diverge ───────────────────────────

func test_a_wired_battle_system_mints_no_slot_of_its_own() -> void:
	var battle := BattleSystem.new()
	battle.plan_slot = _slot
	add_child_autofree(battle)
	assert_eq(battle.plan_slot, _slot)
	assert_eq(battle.get_child_count(true), 0, "a wired slot means no private child")
	watch_signals(battle)
	battle.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_eq(battle.attack_plan, _slot.attack_plan, "the forward reads the wired slot")
	assert_signal_emitted(battle, "attack_plan_changed", "the slot's signal is re-emitted")
	battle.is_launching = true
	assert_true(_slot.locked, "is_launching locks the slot")
	battle.is_launching = false


func test_a_bare_battle_system_forwards_to_a_self_made_slot() -> void:
	var battle := BattleSystem.new()
	battle.turn_manager = _slot.turn_manager
	battle.allocation_system = _alloc
	battle.temp_upgrade_catalog = _catalog
	add_child_autofree(battle)
	var own := battle.plan_slot
	assert_not_null(own)
	assert_ne(own, _slot)
	assert_eq(own.get_parent(), battle, "the private slot is the system's own child")
	assert_eq(own.turn_manager, battle.turn_manager, "seeded with the system's deps")
	assert_eq(own.allocation_system, _alloc)
	assert_eq(own.temp_upgrade_catalog, _catalog, "a forwarded export lands on the slot")
	battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	assert_eq(battle.attack_plan, own.attack_plan)
	watch_signals(own.attack_plan)
	_alloc.force_allocate(_attacker, _spare)
	assert_signal_emitted(own.attack_plan, "state_changed",
			"the private slot subscribed to allocation")
