extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Armed-mode viewport glow colour resolution (#412).
##
## The visual half — does it actually bloom, does the falloff read as
## peripheral — cannot be judged headless (`docs/domain/godot-workflow.md`), so
## the whole point of `PlayerInputController.get_armed_tint()` being a pure
## function is that THIS is testable. It is the only thing the overlay reads.
##
## Two rules under test that a plausible refactor would silently break:
##   - Attack modes tint; every other armed level contributes nothing.
##     **Owner call 2026-08-21:** "in Manage mode: no outline".
##   - The BASE of the stack decides, not the top — the opposite end from the
##     pop order. Pinned by `test_temp_upgrade_over_melee_still_reads_melee`.
##
## Expected colours are computed from `StatDef.tint_color`, never from a
## literal `Color`. A hardcoded expectation would recreate exactly the second
## per-mode palette `.claude/rules/ui-palette.md` forbids, and would keep
## passing after someone retuned the real one.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_battle = autofree(BattleSystem.new())
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _nodes[0]
	_alloc.force_allocate(_player, _nodes[0])
	_alloc.force_allocate(_player, _nodes[1])

	_tm.start_turn(_player)
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.action_points.restore_to_full()

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _player
	add_child_autofree(_ctl)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


## The colour a given attribute's identity tint should produce, derived the
## same way production does — not a literal.
func _expected(stat_id: StringName) -> Color:
	var def := StatRegistry.get_def(stat_id)
	assert_not_null(def, "StatRegistry has no def for %s" % stat_id)
	return Emissive.tint_peak(def.tint_color, Emissive.ALERT)


func test_nothing_armed_is_transparent() -> void:
	assert_eq(_ctl.get_armed_tint().a, 0.0,
			"an idle board must show no glow at all")


func test_melee_reads_strength_red() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	assert_eq(_ctl.get_armed_tint(), _expected(&"strength"))


func test_ranged_reads_dexterity_green() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	assert_eq(_ctl.get_armed_tint(), _expected(&"dexterity"))


func test_magic_reads_intelligence_blue() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MAGIC)
	assert_eq(_ctl.get_armed_tint(), _expected(&"intelligence"))


func test_the_three_modes_are_distinct() -> void:
	# Cheap guard against a mapping typo that points two modes at one stat.
	var melee := _expected(&"strength")
	var ranged := _expected(&"dexterity")
	var magic := _expected(&"intelligence")
	assert_ne(melee, ranged)
	assert_ne(ranged, magic)
	assert_ne(melee, magic)


func test_manage_verbs_show_no_outline() -> void:
	# Owner call 2026-08-21: "in Manage mode: no outline".
	for verb in [
		PlayerInputController.ManageVerb.STAKE,
		PlayerInputController.ManageVerb.EXTRACT,
		PlayerInputController.ManageVerb.DEALLOCATE,
	]:
		_ctl.arm_manage_verb(verb)
		assert_true(_ctl._has_armed_mode(),
				"fixture check: %s should actually be armed" % verb)
		assert_eq(_ctl.get_armed_tint().a, 0.0,
				"Manage verb %s must contribute no glow" % verb)
		_ctl.arm_manage_verb(PlayerInputController.ManageVerb.NONE)


func test_core_move_targeting_shows_no_outline() -> void:
	_ctl.enter_core_move_targeting()
	assert_true(_ctl._has_armed_mode(), "fixture check: core-move should be armed")
	assert_eq(_ctl.get_armed_tint().a, 0.0)


func test_temp_upgrade_over_melee_still_reads_melee() -> void:
	# The owner's worked example: "Melee -> Blade select mode -> place Spike
	# Addon mode [armed] -> still just red outline (Melee)". TempUpgrade is
	# EARLIER in _armed_modes than AttackPlan (it pops first), so a
	# topmost-wins walk would return transparent here and the glow would blink
	# off mid-combo.
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	_ctl.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0])
	assert_true(_ctl._temp_upgrade_arm != null,
			"fixture check: the temp upgrade should be armed on top")
	assert_eq(_ctl.get_armed_tint(), _expected(&"strength"),
			"the base of the stack decides, not the top")


func test_disarming_returns_to_transparent() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	_battle.cancel_attack()
	assert_eq(_ctl.get_armed_tint().a, 0.0)


func test_signal_fires_once_per_tint_transition() -> void:
	watch_signals(_ctl)

	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	assert_signal_emit_count(_ctl, "armed_tint_changed", 1,
			"arming melee is one tint transition, even though several " \
			+ "listeners refresh the armed state")
	assert_signal_emitted_with_parameters(
			_ctl, "armed_tint_changed", [_expected(&"strength")], 0)

	# A refresh with nothing actually changed must not re-fire — the overlay
	# would otherwise restart any future transition animation on every click.
	_ctl._refresh_armed_state()
	assert_signal_emit_count(_ctl, "armed_tint_changed", 1)

	_battle.cancel_attack()
	assert_signal_emit_count(_ctl, "armed_tint_changed", 2)
	assert_signal_emitted_with_parameters(
			_ctl, "armed_tint_changed", [Color.TRANSPARENT], 1)


func test_arming_a_manage_verb_emits_nothing() -> void:
	# Deliberate: the signal carries the TINT, and a Manage verb has none. A
	# future per-verb colour would make this fire — which is the point of
	# naming it armed_tint_changed rather than armed_mode_changed.
	watch_signals(_ctl)
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE)
	assert_signal_emit_count(_ctl, "armed_tint_changed", 0)


func test_turn_ending_clears_the_glow() -> void:
	# can_player_act() gates AttackPlanArmedMode.is_armed(), and NO arm/disarm
	# setter runs on the turn-end path — _emit_gate_changed has to carry it, or
	# a glow stays burning through the AI's turn saying the player can act.
	#
	# Asserted through the signal rather than a final read: the player is the
	# only entity in this fixture, so _tick_until_ready hands the turn straight
	# back and the end state is armed again. The transient is the whole point.
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	assert_eq(_ctl.get_armed_tint(), _expected(&"strength"))

	watch_signals(_ctl)
	_tm.end_turn()
	# turn_ended must darken the glow before anyone else acts.
	assert_signal_emitted_with_parameters(
			_ctl, "armed_tint_changed", [Color.TRANSPARENT], 0)
