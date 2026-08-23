extends GutTest

## The ordering flip (#540): [CommandApplier] validates, THEN confirms, THEN
## applies — so a confirm means "this is going to happen", not "this happened".
##
## `_validate` is private and is deliberately never called directly here. What
## matters is observable through the seam [CommandLink] actually uses: a command
## that fails its gate must never emit `command_confirmed`, because that signal
## is what puts a command on the wire. A test that poked `_validate` would pass
## while the wire leaked.
##
## Per-verb coverage below is one refusal per verb — the gate itself is the
## owning system's (`AllocationSystem.can_allocate` and friends) and is pinned by
## that system's own tests. What is pinned HERE is that the applier asks it at
## all, before confirming.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _applier: CommandApplier
var _player: Entity
var _nodes: Dictionary

## Everything `command_confirmed` announced, in order. The wire's-eye view.
var _confirmed: Array[StringName]
## Everything `command_applied` reported, as [tag, success].
var _applied: Array


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = {}
	for id in ["A", "B", "C", "D"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		_graph.add_skill_node(sn)
		_nodes[id] = sn
	_graph.add_edge(_n("A"), _n("B"))
	_graph.add_edge(_n("B"), _n("C"))
	_graph.add_edge(_n("C"), _n("D"))

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	_alloc.turn_manager = _tm
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _n("A")
	_alloc.force_allocate(_player, _n("A"))
	_tm.start_turn(_player)
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.deallocation_points.restore_to_full()
	_player.stat_board.movement_points.restore_to_full()

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	_confirmed = []
	_applied = []
	_applier.command_confirmed.connect(func(c: Command) -> void: _confirmed.append(c.type_tag()))
	_applier.command_applied.connect(
			func(c: Command, ok: bool) -> void: _applied.append([c.type_tag(), ok]))


func _n(id: String) -> SkillNode:
	return _nodes[id]


func _sid(id: String) -> int:
	return _graph.get_stable_id(_n(id))


## Submit and let the queue finish. The `is_applying` spin is the guard
## `.claude/rules/testing.md` documents: a test that returns mid-drain gets GUT
## autofreeing nodes out from under the applier, which Godot reports as an
## ABORT naming the applier rather than as a failure naming this file.
func _run(command: Command) -> void:
	_applier.submit(command)
	while _applier.is_applying:
		await _applier.applying_changed


## The single assertion every refusal case makes: nothing reached the wire, and
## the refusal was still REPORTED, because that is what drives player feedback.
func _assert_refused(tag: StringName) -> void:
	assert_eq(_confirmed, [] as Array[StringName],
			"a command that fails validation must never confirm — confirming is what puts it on the wire")
	assert_eq(_applied, [[tag, false]],
			"but it must still be reported as a failed outcome, or PIC's denial feedback dies")


# ── The flip itself ─────────────────────────────────────────────────────────

func test_confirm_fires_before_the_world_mutates() -> void:
	# The whole issue in one assertion. Before #540 the confirm could only fire
	# once `allocate` had already returned true, so the authority was always a
	# full mutation ahead of everyone it was telling.
	var owner_at_confirm: Array = [&"unset"]
	_applier.command_confirmed.connect(
			func(_c: Command) -> void: owner_at_confirm[0] = _n("B").owned_by)
	await _run(AllocateCommand.new(_player.entity_id, _sid("B")))
	assert_null(owner_at_confirm[0],
			"the node must still be unowned when the confirm fires — that is the ordering flip")
	assert_eq(_n("B").owned_by, _player, "and owned by the time the apply is done")


func test_confirm_still_precedes_applied() -> void:
	var order: Array[String] = []
	_applier.command_confirmed.connect(func(_c: Command) -> void: order.append("confirmed"))
	_applier.command_applied.connect(func(_c: Command, _ok: bool) -> void: order.append("applied"))
	await _run(AllocateCommand.new(_player.entity_id, _sid("B")))
	assert_eq(order, ["confirmed", "applied"] as Array[String],
			"the relative order of the two signals is unchanged by the flip")


# ── pre_fingerprint (decision 4) ────────────────────────────────────────────

func test_pre_fingerprint_is_the_world_before_the_command() -> void:
	var before := WorldFingerprint.compute(_graph)
	var command := AllocateCommand.new(_player.entity_id, _sid("B"))
	await _run(command)
	assert_eq(command.pre_fingerprint, before,
			"stamped at submit, so it is the PRE-mutation world")
	assert_ne(WorldFingerprint.compute(_graph), before,
			"and the allocation really did move the world, so the two are distinguishable")


func test_pre_fingerprint_is_stamped_even_when_validation_fails() -> void:
	# Uniform across every command, deliberately: no stage flag, and nothing had
	# to unwind when #545 stopped launch_attack being an exception.
	var command := AllocateCommand.new(_player.entity_id, _sid("D"))
	await _run(command)
	assert_eq(_applied, [[&"allocate", false]], "D is three hops out, so this is a refusal")
	assert_ne(command.pre_fingerprint, 0, "and it was still stamped")


func test_pre_fingerprint_is_not_serialized() -> void:
	# The tripwire #539 left: `test/fixtures/outcome/*.tres` IS a serialized
	# LaunchAttackCommand dict. A field added here invalidates every committed
	# fixture, so it stays CommandLink's envelope-level concern.
	var command := AllocateCommand.new(_player.entity_id, _sid("B"))
	command.pre_fingerprint = 123456
	assert_false(command.to_dict().has("pre_fingerprint"),
			"pre_fingerprint is transient applier state and must not enter the command dict")


func test_computed_here_is_not_serialized() -> void:
	# The second transient field, and the same tripwire (#545). It must not
	# cross the wire for a reason beyond the fixture hazard: a RECEIVED command
	# is by definition one this machine did not compute, so a serialized true
	# would send a peer down the authority's branch and have it read the live
	# `attack_plan` — someone else's plan, or none.
	var command := LaunchAttackCommand.new(_player.entity_id, {"mode": "ranged"}, 7)
	command.computed_here = true
	assert_false(command.to_dict().has("computed_here"),
			"computed_here is transient and must not enter the command dict")
	var back := LaunchAttackCommand.from_dict(command.to_dict())
	assert_false(back.computed_here,
			"and a command off the wire always reads false, whatever the sender did")


# ── One refusal per verb: none of them reach the wire ───────────────────────

func test_a_refused_allocate_does_not_confirm() -> void:
	# D is three hops out — not adjacent to the player's territory.
	await _run(AllocateCommand.new(_player.entity_id, _sid("D")))
	_assert_refused(&"allocate")
	assert_null(_n("D").owned_by, "and nothing mutated")


func test_a_refused_deallocate_does_not_confirm() -> void:
	# B is not the player's, so there is nothing to give up.
	await _run(DeallocateCommand.new(_player.entity_id, _sid("B")))
	_assert_refused(&"deallocate")


func test_a_refused_stake_does_not_confirm() -> void:
	await _run(StakeCommand.new(_player.entity_id, _sid("B")))
	_assert_refused(&"stake")


func test_a_refused_extract_does_not_confirm() -> void:
	# A is the core and sits at stake_level 1 — a 1/1 node is a deallocate, not
	# an extract.
	await _run(ExtractCommand.new(_player.entity_id, _sid("A")))
	_assert_refused(&"extract")


func test_a_refused_deallocate_set_does_not_confirm() -> void:
	# Ids that resolve to nothing leave an empty set, which is not a legal
	# cascade.
	await _run(DeallocateSetCommand.new(_player.entity_id, [9001, 9002] as Array[int]))
	_assert_refused(&"deallocate_set")


func test_a_refused_mass_allocate_does_not_confirm() -> void:
	# A path the player cannot pay for any of: no SP left.
	_player.stat_board.skill_points.spend(_player.stat_board.skill_points.available())
	await _run(MassAllocateCommand.new(
			_player.entity_id, [_sid("A"), _sid("B"), _sid("C")] as Array[int]))
	_assert_refused(&"mass_allocate")
	assert_null(_n("B").owned_by, "and not one hop was paid for")


func test_a_refused_move_core_does_not_confirm() -> void:
	# C is neither owned nor adjacent to the core.
	await _run(MoveCoreCommand.new(_player.entity_id, [_sid("C")] as Array[int]))
	_assert_refused(&"move_core")
	assert_eq(_player.core_location, _n("A"), "and the core did not move")


func test_a_refused_toggle_temp_upgrade_does_not_confirm() -> void:
	# No BattleSystem wired at all, so there is no live melee plan to toggle on.
	await _run(ToggleTempUpgradeCommand.new(_player.entity_id, _sid("B"), &"reach"))
	_assert_refused(&"toggle_temp_upgrade")


func test_a_refused_loot_round_does_not_confirm() -> void:
	# B carries no SkillDustAddon, so no round can run on it.
	await _run(LootRoundCommand.new(_player.entity_id, _sid("B")))
	_assert_refused(&"loot_round")


func test_a_refused_launch_attack_does_not_confirm() -> void:
	# No BattleSystem wired.
	await _run(LaunchAttackCommand.new(_player.entity_id, {}, 7))
	_assert_refused(&"launch_attack")


func test_a_command_naming_no_entity_does_not_confirm() -> void:
	await _run(AllocateCommand.new(9999, _sid("B")))
	_assert_refused(&"allocate")


# ── end_turn has no gate, deliberately ──────────────────────────────────────

func test_end_turn_validates_with_no_gate_of_its_own() -> void:
	# PIC documents this: `end_turn` never had a turn-holder gate and neither did
	# the direct TurnManager call it replaced. Validation must not invent one.
	await _run(EndTurnCommand.new(_player.entity_id))
	assert_eq(_confirmed, [&"end_turn"] as Array[StringName],
			"end_turn confirms — its only precondition is that a TurnManager exists")


# ── A refusal still drives player feedback ──────────────────────────────────

func test_a_refused_command_does_not_stall_the_ones_behind_it() -> void:
	_applier.submit(AllocateCommand.new(_player.entity_id, _sid("D")))
	_applier.submit(AllocateCommand.new(_player.entity_id, _sid("B")))
	while _applier.is_applying:
		await _applier.applying_changed
	assert_eq(_applied, [[&"allocate", false], [&"allocate", true]],
			"the refusal is an outcome, not a stall")
	assert_eq(_confirmed, [&"allocate"] as Array[StringName],
			"and only the one that passed validation reached the wire")
