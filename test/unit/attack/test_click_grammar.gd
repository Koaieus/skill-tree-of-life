extends GutTest

## #411: left-click always pushes forward (arms/sets origin/resolves a
## target); right-click always pops exactly one level off the plan's state
## stack, regardless of which node it lands on; a left-click on the armed
## origin that fails the mode's own target-validity check falls through to
## the same pop instead of a silent no-op. See docs/design/click_grammar.md.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

var _graph: Node
var _attacker: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_graph.add_child(_attacker)


func _spawn(owner: Entity = null) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(sn)
	sn.owned_by = owner
	return sn


# ── Melee ─────────────────────────────────────────────────────────────────

func test_melee_left_click_sets_pivot_when_unset() -> void:
	var plan: MeleeAttackPlan = autofree(MeleeAttackPlan.new())
	plan.attacker = _attacker
	var a := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	assert_eq(plan.source, a, "left-click on an owned node arms the pivot")


func test_melee_right_click_pops_pivot_and_blade() -> void:
	var plan: MeleeAttackPlan = autofree(MeleeAttackPlan.new())
	plan.attacker = _attacker
	var a := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	assert_true(plan._on_node_right_clicked(a), "pops the armed pivot")
	assert_null(plan.source, "pivot cleared")
	assert_true(plan.blade_nodes.is_empty(), "blade members cleared with the pivot")


func test_melee_right_click_with_nothing_armed_has_nothing_to_pop() -> void:
	var plan: MeleeAttackPlan = autofree(MeleeAttackPlan.new())
	plan.attacker = _attacker
	var somewhere := _spawn(_attacker)
	assert_false(plan._on_node_right_clicked(somewhere),
			"floor state (no pivot) returns false — caller exits the mode")


func test_melee_left_click_on_pivot_itself_pops_instead_of_denying() -> void:
	# Self-targeting fallthrough: the pivot is never a valid blade member, so
	# re-clicking it is "never mind", same as a right-click.
	var plan: MeleeAttackPlan = autofree(MeleeAttackPlan.new())
	plan.attacker = _attacker
	var a := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	plan._on_node_left_clicked(a)
	assert_null(plan.source, "left-clicking the armed pivot pops it")


# ── Ranged ────────────────────────────────────────────────────────────────

func test_ranged_right_click_pops_target_regardless_of_clicked_node() -> void:
	# The one behavioral widening in this issue: right-click used to require
	# landing on the current target; now it pops no matter where it lands.
	var plan: RangedAttackPlan = autofree(RangedAttackPlan.new())
	plan.attacker = _attacker
	# A second entity, no faction, so ownership_bit reads HOSTILE relative
	# to the player-faction attacker.
	var enemy: Entity = autofree(Entity.new())
	_graph.add_child(enemy)
	var hostile := _spawn(enemy)
	plan._on_node_left_clicked(hostile)
	assert_eq(plan.target, hostile, "precondition: target armed")
	var elsewhere := _spawn()
	assert_true(plan._on_node_right_clicked(elsewhere),
			"right-click pops the target even when clicked elsewhere")
	assert_null(plan.target)


func test_ranged_right_click_with_no_target_has_nothing_to_pop() -> void:
	var plan: RangedAttackPlan = autofree(RangedAttackPlan.new())
	plan.attacker = _attacker
	assert_false(plan._on_node_right_clicked(_spawn()),
			"floor state (no target) returns false — caller exits the mode")


# ── Magic ─────────────────────────────────────────────────────────────────

func _magic_targeting(filter: int) -> NodeTargeting:
	var t := NodeTargeting.new()
	t.ownership_filter = filter
	return t  # range_finder left null: unlimited reach, isolates the ownership check


func test_magic_left_click_sets_source_when_unset() -> void:
	var plan: MagicAttackPlan = autofree(MagicAttackPlan.new())
	plan.attacker = _attacker
	var a := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	assert_eq(plan.source, a, "left-click on an owned node arms the source")


func test_magic_right_click_pops_source_and_target() -> void:
	var plan: MagicAttackPlan = autofree(MagicAttackPlan.new())
	plan.attacker = _attacker
	var spell := SpellDef.new()
	spell.targeting = _magic_targeting(SkillNode.Ownership.MINE)
	plan.spell = spell
	var a := _spawn(_attacker)
	var b := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	plan._on_node_left_clicked(b)
	assert_eq(plan.target, b, "precondition: target armed")
	assert_true(plan._on_node_right_clicked(a), "pops source")
	assert_null(plan.source)
	assert_null(plan.target, "target cleared with the source")


func test_magic_right_click_with_nothing_armed_has_nothing_to_pop() -> void:
	var plan: MagicAttackPlan = autofree(MagicAttackPlan.new())
	plan.attacker = _attacker
	assert_false(plan._on_node_right_clicked(_spawn(_attacker)),
			"floor state (no source) returns false — caller exits the mode")


func test_magic_self_target_pops_when_source_is_not_a_legal_target() -> void:
	# Hostile-only spell: the attacker's own node is never a legal target.
	var plan: MagicAttackPlan = autofree(MagicAttackPlan.new())
	plan.attacker = _attacker
	var spell := SpellDef.new()
	spell.targeting = _magic_targeting(SkillNode.Ownership.HOSTILE)
	plan.spell = spell
	var a := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	assert_eq(plan.source, a, "precondition: source armed")
	plan._on_node_left_clicked(a)  # click the source again
	assert_null(plan.source, "invalid self-target falls through to a pop, not a denial")


func test_magic_self_target_resolves_when_source_is_a_legal_target() -> void:
	# Heal-shaped spell: Mine is in the filter, so the source is a legal
	# target for itself — resolves normally, no special case.
	var plan: MagicAttackPlan = autofree(MagicAttackPlan.new())
	plan.attacker = _attacker
	var spell := SpellDef.new()
	spell.targeting = _magic_targeting(SkillNode.Ownership.MINE)
	plan.spell = spell
	var a := _spawn(_attacker)
	plan._on_node_left_clicked(a)
	plan._on_node_left_clicked(a)  # click the source again
	assert_eq(plan.source, a, "source untouched — this was a resolve, not a pop")
	assert_eq(plan.target, a, "self is a legal target, so it resolves as the target")


# ── PlayerInputController integration: two pops reach idle ─────────────────

func test_right_click_with_nothing_armed_exits_attack_mode() -> void:
	var ctl := PlayerInputController.new()
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	var tm: TurnManager = autofree(TurnManager.new())
	add_child(tm)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	add_child_autofree(bs)

	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	tm.start_turn(_attacker)

	# Node must exist before PlayerInputController._ready() runs (it wires
	# left_clicked for the nodes present at that point; a node added straight
	# to skill_nodes_container afterward, as _spawn does, doesn't fire
	# Graph.node_added — see .claude/rules/graph.md).
	var a := _spawn(_attacker)

	ctl.graph = _graph
	ctl.allocation_system = alloc
	ctl.turn_manager = tm
	ctl.battle_system = bs
	ctl.player = _attacker
	add_child_autofree(ctl)

	bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	assert_true(bs.is_attacking, "precondition: melee mode armed")

	a.left_clicked.emit(a)  # arm the pivot
	assert_eq((bs.attack_plan as MeleeAttackPlan).source, a, "precondition: pivot armed")

	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true

	ctl._unhandled_input(rmb)  # pop 1: clears the pivot, stays in melee mode
	assert_true(bs.is_attacking, "first pop clears the pivot but stays armed")
	assert_null((bs.attack_plan as MeleeAttackPlan).source)

	ctl._unhandled_input(rmb)  # pop 2: nothing left to pop — exits the mode
	assert_false(bs.is_attacking, "second pop, with nothing armed, exits the mode entirely")


# ── #404: Esc aliases the same pop primitive as right-click ────────────────

func test_esc_pops_one_level_same_as_right_click() -> void:
	var ctl := PlayerInputController.new()
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	var tm: TurnManager = autofree(TurnManager.new())
	add_child(tm)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	add_child_autofree(bs)

	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	tm.start_turn(_attacker)
	var a := _spawn(_attacker)

	ctl.graph = _graph
	ctl.allocation_system = alloc
	ctl.turn_manager = tm
	ctl.battle_system = bs
	ctl.player = _attacker
	add_child_autofree(ctl)

	bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	a.left_clicked.emit(a)  # arm the pivot
	assert_eq((bs.attack_plan as MeleeAttackPlan).source, a, "precondition: pivot armed")

	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true

	ctl._unhandled_key_input(esc)  # pop 1: clears the pivot, stays in melee mode
	assert_true(bs.is_attacking, "Esc pop 1 clears the pivot but stays armed")
	assert_null((bs.attack_plan as MeleeAttackPlan).source)

	ctl._unhandled_key_input(esc)  # pop 2: nothing left to pop — exits the mode
	assert_false(bs.is_attacking, "Esc pop 2, with nothing armed, exits the mode entirely")


func test_esc_with_nothing_armed_leaves_event_unhandled() -> void:
	var ctl := PlayerInputController.new()
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	var tm: TurnManager = autofree(TurnManager.new())
	add_child(tm)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	add_child_autofree(bs)

	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	tm.start_turn(_attacker)

	ctl.graph = _graph
	ctl.allocation_system = alloc
	ctl.turn_manager = tm
	ctl.battle_system = bs
	ctl.player = _attacker
	add_child_autofree(ctl)

	assert_false(bs.is_attacking, "precondition: nothing armed")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	# _pop_armed_mode() returning false means _unhandled_key_input never calls
	# set_input_as_handled() — verified by reading the method, not asserted via
	# viewport state here (that state isn't reliably isolated per-call outside
	# the real input pipeline). This just proves the no-op path doesn't error
	# or spuriously arm/cancel anything.
	ctl._unhandled_key_input(esc)
	assert_false(bs.is_attacking, "Esc with nothing armed still leaves nothing armed")


func test_d_gated_while_attack_plan_armed() -> void:
	var ctl := PlayerInputController.new()
	var alloc := AllocationSystem.new()
	alloc.graph = _graph
	add_child_autofree(alloc)
	var tm: TurnManager = autofree(TurnManager.new())
	add_child(tm)
	var bs := BattleSystem.new()
	bs.turn_manager = tm
	add_child_autofree(bs)

	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	tm.start_turn(_attacker)
	var a := _spawn(_attacker)
	var b := _spawn(_attacker)

	ctl.graph = _graph
	ctl.allocation_system = alloc
	ctl.turn_manager = tm
	ctl.battle_system = bs
	ctl.player = _attacker
	add_child_autofree(ctl)

	bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	a.left_clicked.emit(a)  # arm the pivot
	assert_true(bs.is_attacking, "precondition: melee mode armed")

	Events.skill_node_hovered.emit(b)
	var d := InputEventKey.new()
	d.physical_keycode = KEY_D
	d.pressed = true
	ctl._unhandled_input(d)
	assert_eq(b.owned_by, _attacker, "D is gated off while an attack plan is armed (#404)")
