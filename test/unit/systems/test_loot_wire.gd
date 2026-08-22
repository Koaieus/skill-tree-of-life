extends GutTest

## Loot on the wire (#522) — the three halves that had to exist before a peer
## could agree with the host across a relic claim:
##
##   1. [StatModifierCodec] — candidates travel BY VALUE, formula and all.
##   2. [LootRoundCommand] — the round, not the pick, is the wire unit, in the
##      two-states-one-type shape [LaunchAttackCommand] proved.
##   3. [LootPickRegistry] — one authority mints request ids and parks the
##      requests a REMOTE picker owes an answer to.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _LEVEL_SCALING := preload("res://stats_system/formulas/level_scaling.tres")

var _graph: Graph
var _collector: Entity
var _relic: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_relic = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_relic.name = "Relic"
	_graph.skill_nodes_container.add_child(_relic)

	_collector = autofree(Entity.new())
	_collector.display_name = "Collector"
	_collector.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	# entities_container, not the graph root: `entity_id` mints on entry there,
	# and a command carrying 0 resolves to nothing (see .claude/rules/graph.md).
	_graph.entities_container.add_child(_collector)
	await get_tree().process_frame
	_collector.core_location = _relic


# ── 1. Candidates travel by value ────────────────────────────────────────────

func test_a_plain_modifier_round_trips() -> void:
	var m := _mod(&"armor", StatModifier.Operation.ADD_BONUS, 4.0)
	m.priority = 7

	var back := StatModifierCodec.from_dict(m.to_dict())

	assert_not_null(back)
	assert_eq(back.stat_id, &"armor")
	assert_eq(back.operation, StatModifier.Operation.ADD_BONUS)
	assert_eq(back.value, 4.0)
	assert_eq(back.priority, 7)
	assert_null(back.formula, "no formula in, no formula out")


func test_a_linear_formula_round_trips() -> void:
	var m := _mod(&"vision_range", StatModifier.Operation.INCREASE, 2.0)
	var f := LinearFormula.new()
	f.source_stat_id = &"perception"
	m.formula = f

	var back := StatModifierCodec.from_dict(m.to_dict())

	assert_true(back.formula is LinearFormula)
	assert_eq((back.formula as LinearFormula).source_stat_id, &"perception")
	assert_eq(back.formula.get_input_ids(), [&"perception"] as Array[StringName])


func test_a_ratio_formula_keeps_its_divisor() -> void:
	var m := _mod(&"mana", StatModifier.Operation.ADD_BASE, 1.0)
	var f := RatioFormula.new()
	f.source_stat_id = &"intelligence"
	f.divisor = 10.0
	m.formula = f

	var back := StatModifierCodec.from_dict(m.to_dict())

	assert_true(back.formula is RatioFormula)
	assert_eq((back.formula as RatioFormula).divisor, 10.0,
			"the divisor is the whole tuning value — dropping it silently retunes the mod")


## #323 makes stealing a level-scaler the intended roguelite loop, so a wire
## format that cannot carry an [ExpressionFormula] guts the feature. This is the
## case the "send locators, not values" design could not have handled either —
## it computes on the LOOTER's board, from a formula it had to arrive with.
func test_a_level_scaler_loots_over_the_wire_and_still_computes() -> void:
	var m := _mod(&"strength", StatModifier.Operation.ADD_BASE, 1.0)
	m.formula = _LEVEL_SCALING  # ExpressionFormula("level - 1")

	var back := StatModifierCodec.from_dict(m.to_dict())

	assert_true(back.formula is ExpressionFormula)
	assert_eq((back.formula as ExpressionFormula).formula, "level - 1")
	assert_eq(back.formula.get_input_ids(), [&"level"] as Array[StringName])

	# The decoded Expression is compiled lazily on first compute() — nothing has
	# to re-parse it by hand.
	_collector.level = 5
	assert_eq(back.get_effective_value(_collector.stat_board), 4.0,
			"a decoded level-scaler reads the LOOTER's level")


func test_a_composite_round_trips_with_its_children_and_loot_atomicity() -> void:
	var pack := CompositeStatModifier.new()
	pack.loots_as_unit = true
	pack.children = [
		_mod(&"deallocation_points", StatModifier.Operation.ADD_BASE, 2.0),
		_mod(&"skill_points", StatModifier.Operation.ADD_BASE, -1.0),
	]

	var back := StatModifierCodec.from_dict(pack.to_dict()) as CompositeStatModifier

	assert_not_null(back)
	assert_true(back.loots_as_unit, "a buff/debuff pack that loots as a unit must stay one")
	assert_eq(back.children.size(), 2)
	assert_eq(back.flatten().size(), 2, "and it still flattens on apply")
	assert_eq(back.children[1].value, -1.0, "the debuff half survives")


func test_an_unknown_tag_decodes_to_null_rather_than_half_a_modifier() -> void:
	assert_null(StatModifierCodec.from_dict({"type": "no_such_kind"}))
	assert_null(StatModifierCodec.from_dict({}), "an empty payload is 'nothing granted'")
	assert_null(StatModifierCodec.from_dict(null))


# ── 2. The round is the wire unit ────────────────────────────────────────────

func test_a_loot_round_command_round_trips_through_the_codec() -> void:
	var command := LootRoundCommand.new(3, 11)
	command.record(_mod(&"armor", StatModifier.Operation.ADD_BASE, 5.0), &"", false)

	var back := CommandCodec.from_dict(command.to_dict()) as LootRoundCommand

	assert_not_null(back, "the codec knows the tag")
	assert_eq(back.entity_id, 3)
	assert_eq(back.carrier_id, 11)
	assert_true(back.is_replay(), "a stamped record makes it a replay on the far side")
	assert_eq(back.granted_modifier().value, 5.0)
	assert_false(back.is_final())


func test_an_unstamped_command_is_an_initiate() -> void:
	assert_false(LootRoundCommand.new(1, 2).is_replay(),
			"empty record means 'not applied yet' — the authority runs it for real")


## The forfeit / terminal payloads are the ones most easily lost: a round that
## granted nothing still has to be distinguishable from one that has not run.
func test_a_terminal_round_carries_no_grant_and_still_reads_as_applied() -> void:
	var command := LootRoundCommand.new(1, 2)
	command.record(null, &"", true)

	var back := CommandCodec.from_dict(command.to_dict()) as LootRoundCommand

	assert_true(back.is_replay(), "granting nothing is an OUTCOME, not an un-run round")
	assert_true(back.is_final(), "and it is what frees the relic on every peer")
	assert_null(back.granted_modifier())
	assert_null(back.granted_spell())


func test_a_spell_round_travels_by_id() -> void:
	var command := LootRoundCommand.new(1, 2)
	command.record(null, SpellCatalog.SPARK.id, false)

	var back := CommandCodec.from_dict(command.to_dict()) as LootRoundCommand

	assert_eq(back.granted_spell(), SpellCatalog.SPARK,
			"resolves to the authored def itself — spells have real identity, unlike a "
			+ "runtime-minted StatModifier")


# ── The replay path ──────────────────────────────────────────────────────────

## A peer holds the relic but never rolls: it grants exactly what arrived.
func test_a_peer_grants_what_the_record_says() -> void:
	# Claimed BEFORE the addon is parented: `owner_changed` is what opens a real
	# round, and an addon with no applier runs one inline (the offline path).
	_relic.owned_by = _collector
	var dust := _dust([_mod(&"armor", StatModifier.Operation.ADD_BASE, 99.0)])
	var command := LootRoundCommand.new(_collector.entity_id, 0)
	command.record(_mod(&"strength", StatModifier.Operation.ADD_BASE, 6.0), &"", false)

	await dust.run_round(command)

	assert_eq(_collector.core_modifiers.size(), 1, "the recorded grant landed")
	assert_eq(_collector.core_modifiers[0].stat_id, &"strength",
			"and it is the RECORDED one, not something the peer rolled off its own pool")


func test_a_final_replayed_round_frees_the_relic() -> void:
	_relic.owned_by = _collector
	var dust := _dust([_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0)])
	var command := LootRoundCommand.new(_collector.entity_id, 0)
	command.record(null, &"", true)

	await dust.run_round(command)
	await get_tree().process_frame

	assert_false(is_instance_valid(dust) and not dust.is_queued_for_deletion(),
			"the terminal record is what consumes the relic on a peer too")


## The second blocker the issue named: a peer applies the confirmed
## AllocateCommand, `owned_by` flips, and without the gate its own addon opens
## its own round with its own roll.
func test_a_peer_never_opens_a_round_of_its_own() -> void:
	var applier := CommandApplier.new()
	applier.graph = _graph
	applier.is_authority = false
	add_child_autofree(applier)

	var dust := _dust([
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"strength", StatModifier.Operation.ADD_BASE, 1.0),
	])
	dust.command_applier = applier

	var requests := 0
	var handler := func(_req: LootPickRequest) -> void: requests += 1
	Events.loot_pick_requested.connect(handler)
	_relic.owned_by = _collector  # the real trigger — same as applying an AllocateCommand
	Events.loot_pick_requested.disconnect(handler)

	assert_eq(requests, 0, "a peer raises no request")
	assert_eq(_collector.core_modifiers.size(), 0, "and grants nothing on its own")
	assert_eq(applier.pending_count(), 0, "and submits no round")


# ── 3. The registry ──────────────────────────────────────────────────────────

func test_a_pick_resolves_the_parked_request_by_index() -> void:
	var registry := _registry()
	var chosen: Array = []
	var request := _request(func(picked: Array) -> void: chosen.assign(picked))
	var id := registry.park(request)

	assert_true(registry.resolve_pick(id, 1))
	assert_eq(chosen.size(), 1)
	assert_eq(chosen[0], request.candidates[1], "index 1 grants candidate 1")


## -1, not an empty array: a forfeit serialized as `[]` and read back as index 0
## would silently grant the first candidate.
func test_minus_one_forfeits_the_round() -> void:
	var registry := _registry()
	var chosen: Array = [null]
	var request := _request(func(picked: Array) -> void: chosen.assign(picked))
	var id := registry.park(request)

	assert_true(registry.resolve_pick(id, -1))
	assert_true(chosen.is_empty(), "the resolver's documented empty-`chosen` branch")


func test_an_out_of_range_pick_is_refused_and_the_round_forfeits() -> void:
	var registry := _registry()
	var chosen: Array = [null]
	var request := _request(func(picked: Array) -> void: chosen.assign(picked))
	var id := registry.park(request)

	assert_false(registry.resolve_pick(id, 99),
			"host-side membership validation — a client may shuffle, not invent")
	assert_true(chosen.is_empty(), "the relic still advances rather than stalling")


func test_a_stale_or_duplicate_pick_is_a_normal_outcome() -> void:
	var registry := _registry()
	var id := registry.park(_request(func(_p: Array) -> void: pass))

	assert_true(registry.resolve_pick(id, 0))
	assert_false(registry.resolve_pick(id, 0), "the second answer names nothing")
	assert_false(registry.resolve_pick(9999, 0), "and neither does an id nobody minted")


func test_a_disconnect_forfeits_rather_than_deadlocking_the_table() -> void:
	var registry := _registry()
	var chosen: Array = [null]
	var request := _request(func(picked: Array) -> void: chosen.assign(picked))
	request.collector = _collector
	registry.park(request)

	registry.forfeit_for(_collector)

	assert_true(chosen.is_empty(), "the player left — this is not 'escaping the pick'")
	assert_eq(registry.pending_count(), 0)


func test_the_applier_routes_a_pick_command_for_real() -> void:
	var registry := _registry()
	var applier := _applier(registry)

	var chosen: Array = []
	var request := _request(func(picked: Array) -> void: chosen.assign(picked))
	request.collector = _collector
	var id := registry.park(request)

	applier.submit(PickLootCommand.new(_collector.entity_id, id, 1))

	assert_eq(chosen.size(), 1, "no push-warn stub left — the branch answers the request")
	assert_eq(chosen[0], request.candidates[1])


## REGRESSION: an answer must never be ENQUEUED. A round runs inside its own
## LootRoundCommand's application, so the queue is parked on the very await the
## answer releases — an enqueued answer can never be reached, and the drain
## hangs forever rather than merely being delayed. `submit` therefore routes a
## PickLootCommand past the queue. This test deadlocks the whole suite if that
## ever regresses, which is the loudest available failure for a hang.
func test_a_pick_answers_a_request_parked_while_the_queue_is_blocked() -> void:
	var registry := _registry()
	var applier := _applier(registry)

	var chosen: Array = []
	var request := _request(func(picked: Array) -> void: chosen.assign(picked))
	var id := registry.park(request)

	# Stand in for the round: hold the queue open exactly as an awaiting
	# LootRoundCommand application does.
	applier.is_applying = true
	applier.submit(PickLootCommand.new(_collector.entity_id, id, 0))
	applier.is_applying = false

	assert_eq(applier.pending_count(), 0,
			"the answer did NOT join the queue it would be waiting behind")
	assert_eq(chosen.size(), 1, "and it landed while the queue was still blocked")


## An answer travelling UP must not be echoed back DOWN. Bypassing the queue
## means it never confirms, so CommandLink needs no guard of its own.
func test_a_pick_never_confirms_and_so_never_mirrors() -> void:
	var registry := _registry()
	var applier := _applier(registry)
	var confirmed: Array[Command] = []
	applier.command_confirmed.connect(func(c: Command) -> void: confirmed.append(c))

	var id := registry.park(_request(func(_p: Array) -> void: pass))
	applier.submit(PickLootCommand.new(_collector.entity_id, id, 0))

	assert_true(confirmed.is_empty(), "an intent is not a confirmed command")


# ── The round through the applier ────────────────────────────────────────────

## The primary wire path end to end: a stamped round encodes, decodes, resolves
## its carrier by `stable_id` and its collector by `entity_id`, and grants.
## Same shape as `test/unit/attack/test_attack_record_replay.gd` — calling
## `run_round` directly would skip the id resolution, which is exactly where a
## lazily-minted `stable_id` reads 0 and resolves to nothing SILENTLY.
func test_a_round_applies_through_the_applier_after_a_wire_round_trip() -> void:
	var applier := _applier(_registry())
	_relic.owned_by = _collector
	var dust := _dust([_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0)])

	var sent := LootRoundCommand.new(
			_collector.entity_id, _graph.get_stable_id(_relic))
	sent.record(_mod(&"strength", StatModifier.Operation.ADD_BASE, 6.0), &"", false)

	var received := CommandCodec.from_dict(sent.to_dict())
	applier.submit(received)
	if applier.is_applying:
		await applier.applying_changed

	assert_eq(_collector.core_modifiers.size(), 1, "the round found its relic and its collector")
	assert_eq(_collector.core_modifiers[0].stat_id, &"strength")
	assert_true(is_instance_valid(dust), "a non-final round leaves the relic standing")


func test_a_round_naming_an_unminted_carrier_is_refused_not_silent() -> void:
	var applier := _applier(_registry())
	var command := LootRoundCommand.new(_collector.entity_id, 0)
	command.record(_mod(&"strength", StatModifier.Operation.ADD_BASE, 6.0), &"", false)

	applier.submit(command)
	if applier.is_applying:
		await applier.applying_changed

	assert_eq(_collector.core_modifiers.size(), 0,
			"carrier_id 0 grants nothing — the trap in .claude/rules/graph.md")


## The "no ending the turn while picking" rule (owner call, 2026-08-22) needs no
## gate of its own: the round holds the applier, and `can_player_act` already
## reads that.
func test_a_round_in_flight_is_what_blocks_the_player_from_acting() -> void:
	var applier := _applier(_registry())
	var input_ctl := PlayerInputController.new()
	input_ctl.graph = _graph
	input_ctl.command_applier = applier
	input_ctl.player = _collector
	add_child_autofree(input_ctl)

	applier.is_applying = true
	assert_false(input_ctl.can_player_act(),
			"the End Turn button greys out through the gate that already exists")
	applier.is_applying = false


# ── helpers ──────────────────────────────────────────────────────────────────

func _applier(registry: LootPickRegistry) -> CommandApplier:
	var applier := CommandApplier.new()
	applier.graph = _graph
	applier.loot_pick_registry = registry
	add_child_autofree(applier)
	return applier


func _registry() -> LootPickRegistry:
	var registry := LootPickRegistry.new()
	add_child_autofree(registry)
	return registry


func _request(resolver: Callable) -> LootPickRequest:
	var candidates: Array[StatModifier] = [
		_mod(&"armor", StatModifier.Operation.ADD_BASE, 1.0),
		_mod(&"strength", StatModifier.Operation.ADD_BASE, 2.0),
	]
	return LootPickRequest.new(null, candidates, resolver)


func _dust(candidates: Array[StatModifier]) -> SkillDustAddon:
	var dust := SkillDustAddon.new()
	dust.candidates = candidates
	var weights: Array[float] = []
	for _c in candidates:
		weights.append(1.0)
	dust.weights = weights
	dust.rounds = candidates.size()
	_relic.add_child(dust)
	return dust


func _mod(id: StringName, op: StatModifier.Operation, v: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = v
	return m
