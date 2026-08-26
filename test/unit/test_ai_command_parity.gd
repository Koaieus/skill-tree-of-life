extends GutTest

## Full-turn parity for #512: an AI turn that emits [Command]s through the one
## [CommandApplier] must reach the SAME end state as the direct
## `allocation_system.allocate(...)` / `turn_manager.end_turn()` path it
## replaced — same nodes allocated, same ownership, same SP/AP/mana, same
## initiative, same decision trace.
##
## [b]The expected snapshot is a golden, not a description of the new code.[/b]
## It was captured by running this exact fixture against the pre-#512
## controller (branch point 5349743, direct calls), then frozen into
## [constant _GOLDEN]. Rerunning it after the reroute is the parity assertion.
## If a future change to AI scoring or the stat economy moves these numbers,
## recapture the golden the same way — do not "fix" it to whatever the code
## currently does.
##
## Fixture is shaped after test_ai_controller_combat.gd (a real hostile plus a
## headless BattleSystem so the attack step engages), with two deliberate
## differences:
##   - entities live under `graph.entities_container`, because `entity_id` is
##     minted on entry to THAT container (#509) and a command naming an
##     unminted id resolves to nothing;
##   - SP is granted, so one turn exercises frontier growth AND the AP loop.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

## Set true to print the observed snapshot instead of asserting against
## [constant _GOLDEN] — how the golden below was captured in the first place.
const _CAPTURE := false

## End state of one AI turn on the pre-#512 direct-call path, captured with
## [constant _CAPTURE] on at 5349743. See the class note before touching these.
## The two decisions are the AP×2 ranged loop: one dent, then the re-evaluated
## finisher — `kill=yes` is the scorer's PREDICTION, not an outcome, which is
## why N3 is still the hostile's at the end.
##
## [b]One post-capture amendment, #604[/b] — the ` door=500.0` trailer and the
## +500 it adds to each `total`. This fixture's AI ends its growth step
## growth-capped (it owns N0-N2, and N3 is the hostile's), so the breakout
## bonus applies to N3, which borders N2. What did NOT change is everything the
## parity assertion is actually about: same target, same two shots, same
## ownership / SP / AP / mana / initiative / current_entity, all still the
## values captured at 5349743. The scoring term is new behaviour, deliberately
## added, and it moved the trace strings only — it could not be recaptured on
## the pre-#512 controller because it did not exist there.
const _GOLDEN := {
	"ap": 0.0,
	"current_entity": "Player",
	"decisions": [
		"[RANGED→N3] ev=6.0 kill=no cut=0.0 weak=0.0 risk=0.0 total=506.0 door=500.0",
		"[RANGED→N3] ev=6.0 kill=yes cut=0.0 weak=0.0 risk=0.0 total=1506.0 door=500.0",
	],
	"enemy_owned": ["N0", "N1", "N2"],
	"initiative": 0.0,
	"mana": 11.0,
	"ownership": {"N0": "Enemy", "N1": "Enemy", "N2": "Enemy", "N3": "Hostile"},
	"sp": 2.0,
}

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _applier: CommandApplier
var _player: Entity
var _enemy: Entity
var _hostile: Entity
var _ai: AIController
var _nodes: Array[SkillNode]

var _decisions: Array[String] = []


func _make_entity(ent_name: String, faction: Faction = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# Zero the 5 % baseline crit: since #507 a ranged crit rolls off a fresh
	# per-attack seed, and a golden snapshot cannot flake on a doubled shot.
	e.stat_board.get_stat(&"crit_chance").base_value = 0.0
	if faction != null:
		e.faction = faction
	return e


func before_each() -> void:
	_decisions = []

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	# N0 - N1 - N2 - H0, a line. AI cores on N0 owning nothing else; N1/N2 are
	# the frontier it grows into; the hostile cores on H0.
	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])
	_graph.add_edge(_nodes[1], _nodes[2])
	_graph.add_edge(_nodes[2], _nodes[3])

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	_alloc.turn_manager = _tm
	add_child_autofree(_alloc)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	# #504: land each attack in one go — this test is about end state, not
	# presentation timing, and the real beat clock would make it seconds long.
	_bs.instant_mutation = true
	add_child(_bs)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.allocation_system = _alloc
	_applier.battle_system = _bs
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	# Idle second entity so the clock has somewhere to park after the AI ends
	# its turn (see test_ai_controller.gd's before_each for why).
	_player = _make_entity("Player")
	_graph.entities_container.add_child(_player)
	_player.add_child(PlayerController.new())

	_enemy = _make_entity("Enemy")
	_graph.entities_container.add_child(_enemy)

	_hostile = _make_entity("Hostile", _PLAYER_FACTION)
	_graph.entities_container.add_child(_hostile)

	await get_tree().process_frame

	# Controllers attach AFTER the entity is in the tree, mirroring
	# GameRoot._ensure_controllers — upkeep must register before take_turn.
	_ai = AIController.new()
	_ai.turn_delay = 0.0
	_ai.command_applier_override = _applier
	_ai.battle_system_override = _bs
	_enemy.add_child(_ai)

	await get_tree().process_frame

	_alloc.force_allocate(_enemy, _nodes[0])
	_enemy.core_location = _nodes[0]
	_alloc.force_allocate(_hostile, _nodes[3])
	_hostile.core_location = _nodes[3]

	_nodes[0].global_position = Vector2.ZERO
	_nodes[1].global_position = Vector2(100.0, 0.0)
	_nodes[2].global_position = Vector2(200.0, 0.0)
	_nodes[3].global_position = Vector2(300.0, 0.0)

	Events.ai_decision.connect(_on_ai_decision)


func after_each() -> void:
	if Events.ai_decision.is_connected(_on_ai_decision):
		Events.ai_decision.disconnect(_on_ai_decision)


func _on_ai_decision(_entity: Entity, summary: String) -> void:
	_decisions.append(summary)


## Everything #512's acceptance names, plus the decision trace — the AI's own
## account of what it chose, which is what proves the reroute changed plumbing
## and not behaviour.
func _snapshot() -> Dictionary:
	var ownership := {}
	for n in _nodes:
		# String(n.name), not n.name: a StringName key never matches the golden's
		# String key, and Dictionary == compares keys.
		ownership[String(n.name)] = n.owned_by.display_name if n.owned_by != null else ""
	var board := _enemy.stat_board
	return {
		"ownership": ownership,
		"enemy_owned": _owned_names(_enemy),
		"sp": board.skill_points.current,
		"ap": board.action_points.current,
		"mana": board.mana.current,
		"initiative": board.initiative.current,
		"current_entity": _tm.current_entity.display_name if _tm.current_entity != null else "",
		"decisions": _decisions.duplicate(),
	}


func _owned_names(e: Entity) -> Array:
	var out: Array = []
	for n in _nodes:
		if n.owned_by == e:
			out.append(String(n.name))
	return out


func _run_one_ai_turn() -> void:
	_enemy.stat_board.skill_points.set_current(2)
	_tm.start_turn(_enemy)
	await get_tree().create_timer(0.3).timeout


# ---------------------------------------------------------------------------
# Parity
# ---------------------------------------------------------------------------

func test_full_ai_turn_matches_the_direct_call_end_state() -> void:
	await _run_one_ai_turn()
	var observed := _snapshot()
	if _CAPTURE:
		print_rich("[AI PARITY CAPTURE] %s" % JSON.stringify(observed, "  "))
		pass_test("capture mode")
		return
	for key in _GOLDEN:
		assert_eq(observed[key], _GOLDEN[key],
				"'%s' drifted from the pre-#512 direct-call golden" % key)


# ---------------------------------------------------------------------------
# The AI reaches the world only through the queue
# ---------------------------------------------------------------------------

func test_the_turns_commands_reach_the_applier_in_decided_order() -> void:
	var seen: Array = []
	_applier.command_applied.connect(func(cmd: Command, _ok: bool) -> void:
		seen.append([cmd.type_tag(), cmd.entity_id,
				cmd.node_id if cmd is NodeCommand else 0]))

	await _run_one_ai_turn()

	var eid := _enemy.entity_id
	# The whole turn, and nothing outside it: growth outward from the core, the
	# AP×2 attack loop, then the hand-back. The two launches are here because
	# `BattleSystem.launch_attack` submits a LaunchAttackCommand itself (#511) —
	# the AI never builds one, which is why this list is the proof that every
	# mutation an AI turn makes reaches the one queue, whoever built it.
	assert_eq(seen, [
		[&"allocate", eid, _graph.get_stable_id(_nodes[1])],
		[&"allocate", eid, _graph.get_stable_id(_nodes[2])],
		[&"launch_attack", eid, 0],
		[&"launch_attack", eid, 0],
		[&"end_turn", eid, 0],
	], "growth, both attacks, then the hand-back — the AI's own order")


func test_a_command_submitted_mid_ai_turn_queues_rather_than_reentering() -> void:
	# The player pokes the queue from a command_applied handler, which runs
	# INSIDE the applier's guard — the exact interleave #512 calls out, and the
	# only actor that submits a burst is the AI, so this is where it bites.
	var order: Array = []
	var poked: Array[bool] = [false] # Array, not a bool: lambdas copy locals.
	_applier.command_applied.connect(func(cmd: Command, _ok: bool) -> void:
		order.append(cmd.entity_id)
		if poked[0] or cmd.entity_id != _enemy.entity_id:
			return
		poked[0] = true
		# N1 is not adjacent to the player's (empty) territory, so this fails
		# its gate — the point is WHEN it is applied, not whether it lands.
		_applier.submit(AllocateCommand.new(
				_player.entity_id, _graph.get_stable_id(_nodes[1])))
		assert_true(_applier.is_applying,
				"still inside the drain — the poke must not have re-entered")
		assert_eq(_applier.pending_count(), 1, "it queued behind the AI's turn"))

	await _run_one_ai_turn()

	assert_true(poked[0], "the AI applied at least one command to poke from")
	assert_eq(order.count(_player.entity_id), 1, "the player's command applied once")
	assert_gt(order.find(_player.entity_id), 0,
			"and after the AI command it was raised from, never nested inside it")
	# The AI's turn still reached the same end state with a foreign command
	# spliced into its burst.
	assert_eq(_owned_names(_enemy), ["N0", "N1", "N2"])


## The nastiest arrival shape, and the one production actually takes: the AI's
## whole turn runs INSIDE an [EndTurnCommand]'s application, so every command it
## raises is queued behind the drain it is standing in. It completes only
## because [method AIController._submit_and_wait] awaits a signal — yielding
## back up to that drain — instead of blocking on a verdict the drain cannot
## produce until it returns.
##
## Same reason [method BattleSystem.launch_attack] waits on `command_applied`
## rather than `applying_changed` (#511): the latter cannot fire until the drain
## ends, so a launch raised from inside one would hang on it. This is the
## deadlock's front door; nothing else in the suite walks through it.
##
## [b]Known residual, deliberately not designed around[/b] (#511, warp-511's
## call): if anything ever awaits [method BattleSystem.launch_attack]
## SYNCHRONOUSLY from inside [method CommandApplier._apply] — rather than from
## an already-detached coroutine, which is what the AI is — the drain blocks on
## a launch command sitting in the queue behind it, and deadlocks. Nothing does
## that today, and this test does not cover it.
func test_an_ai_turn_raised_from_inside_a_drain_still_completes() -> void:
	# Whether the attack was raised INSIDE the drain, rather than inferred from
	# AP afterwards — that is the bit #511's `command_applied` await hinges on.
	var launched_while_applying: Array[bool] = []
	_bs.attack_launched.connect(
			func(_mode: BattleSystem.AttackMode, _spell: SpellDef) -> void:
				launched_while_applying.append(_applier.is_applying))

	_player.stat_board.initiative.restore_to_full()
	_tm.start_turn(_player)
	_enemy.stat_board.skill_points.set_current(2)
	_enemy.stat_board.initiative.set_current(50.0) # head start: enemy is next

	# The player ends their turn THROUGH the applier, which is what nests the
	# AI's entire turn inside _apply(EndTurnCommand).
	_applier.submit(EndTurnCommand.new(_player.entity_id))
	await get_tree().create_timer(0.3).timeout

	assert_false(_applier.is_applying, "the drain finished — no deadlock")
	assert_eq(_applier.pending_count(), 0, "and it drained everything it queued")
	assert_eq(_owned_names(_enemy), ["N0", "N1", "N2"],
			"the nested turn grew exactly as the un-nested one does")
	assert_eq(_enemy.stat_board.action_points.current, 0.0, "and spent its AP")
	assert_ne(_tm.current_entity, _enemy, "and handed the turn back")
	assert_false(launched_while_applying.is_empty(), "it did attack")
	assert_false(launched_while_applying.has(false),
			"and every launch was raised from INSIDE the drain — the path #511's "
			+ "command_applied await exists for")


# ---------------------------------------------------------------------------
# #512's grep-provable acceptance, as a test rather than a habit
# ---------------------------------------------------------------------------

func test_the_controller_holds_no_direct_mutating_system_call() -> void:
	var src := FileAccess.get_file_as_string("res://entity/controller/ai_controller.gd")
	assert_ne(src, "", "controller source should be readable")
	# `battle_system.launch_attack` is deliberately NOT on this list, though
	# #512's acceptance named it. Since #511 `launch_attack` itself submits a
	# LaunchAttackCommand and awaits it, so forbidding the call would forbid the
	# very line that satisfies the criterion. **Owner call 2026-08-21:** *"hmm
	# well AI will only be ran by the host, so to me it matters little how they
	# do it, via a command or directly. clients won't ever run AI controllers
	# anyway."* That settles it; don't re-derive it from the acceptance text.
	for forbidden in [
		"allocation_system.allocate", "allocation_system.deallocate",
		"allocation_system.stake", "allocation_system.extract",
		"allocation_system.move_core", "allocation_system.mass_allocate",
		"allocation_system.deallocate_set", "alloc.allocate",
		"_turn_manager.end_turn",
	]:
		assert_false(src.contains(forbidden),
				"ai_controller.gd must not call '%s' — submit a Command" % forbidden)
