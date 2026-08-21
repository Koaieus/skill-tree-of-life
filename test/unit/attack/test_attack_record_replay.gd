extends GutTest

## #511 — the record replay test, and it is the point of this child.
##
## Apply an attack on the HOST. Capture the post-apply record. Push it through
## the real wire path ([method LaunchAttackCommand.to_dict] →
## `var_to_bytes`/`bytes_to_var` → [method CommandCodec.from_dict]). Replay it
## against a SECOND, identically-built world. Assert the two end states match.
##
## Per the owner call settled on #511 2026-08-21, this is deliberately NOT
## "serialize the resolve-time outcome and apply it": a client cannot re-derive
## a combat number (mitigation is read node-locally at land time, an earlier
## beat's cascade changes what a later beat lands on, and a target may sit
## under fog). The host runs its natural logic and what crosses is the record
## of what each landing actually did.
##
## [b]Crit is deliberately left ON here[/b] — the fixture does not zero
## `crit_chance`. The two worlds never roll the same crits, because only the
## host rolls at all: the peer replays a number that already includes the
## multiplier. A test that zeroed crit could not tell those two designs apart.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

## The peer world is built far away in the SAME physics space, because a GUT
## test has only one. Melee's hit detection is a real physics query, so two
## worlds sitting on top of each other would have the host's blade sweep the
## peer's colliders — a test artifact that reads exactly like a broken record.
## Positions are not wire state (the record and the plan both travel as ids),
## so the offset costs the test nothing.
const _PEER_ORIGIN := Vector2(100000, 100000)


func _set_local(node: SkillNode, stat_id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.SET
	m.value = value
	node.add_local_modifier(m)


## One complete world. Built twice per test, from the same code, so the two are
## identical down to `stable_id` — which the fingerprint assertion in
## [method _assert_worlds_agree] proves rather than assumes.
##
## Melee needs the two blade-reachable nodes to coincide with the target at
## t=0 (the same trick `test_melee_swing_characterization.gd` uses) so the
## physics scan does not depend on server sync timing.
func _build(origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)

	var nodes: Dictionary = {}
	for entry in [["core", Vector2(0, 0)], ["leaf", Vector2(150, 0)],
			["target", Vector2(150, 0)], ["neighbour", Vector2(300, 0)]]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.name = str(entry[0])
		graph.add_skill_node(node)
		node.global_position = origin + (entry[1] as Vector2)
		nodes[entry[0]] = node
	graph.add_edge(nodes.core, nodes.leaf)
	# The contested frontier: without it a spell has no path from the leaf to
	# the target and `MagicAttackPlan.validate` refuses the cast.
	graph.add_edge(nodes.leaf, nodes.target)
	graph.add_edge(nodes.target, nodes.neighbour)

	var attacker := Entity.new()
	attacker.display_name = "Attacker"
	attacker.faction = _PLAYER_FACTION
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	attacker.stat_board.blade_size.base_value = 2.0
	attacker.stat_board.action_points.set_base_ratcheted(4.0)
	attacker.stat_board.action_points.current = 4.0
	attacker.stat_board.mana.set_base_ratcheted(10.0)
	attacker.stat_board.mana.current = 10.0
	# entities_container, NOT the Graph itself — entity_id mints on entry to
	# that container (#509), and a command naming an unminted id resolves to
	# nothing.
	graph.entities_container.add_child(attacker)

	var defender := Entity.new()
	defender.display_name = "Defender"
	defender.faction = _NPC_FACTION
	defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(defender)

	await get_tree().process_frame

	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(attacker, nodes.core)
	alloc.force_allocate(attacker, nodes.leaf)
	attacker.core_location = nodes.core
	alloc.force_allocate(defender, nodes.target)
	alloc.force_allocate(defender, nodes.neighbour)
	defender.core_location = nodes.neighbour

	_set_local(nodes.leaf, &"range", 400.0)
	# Overkill, deliberately: a volley that only chips HP leaves ownership
	# untouched, and the fingerprint half of `_assert_worlds_agree` would then
	# pass vacuously (X == X, both unchanged from the starting value). A lethal
	# hit runs the whole cascade — `notify_depleted` -> force-dealloc ->
	# wounded SP -> the owner's health chip — which is the machinery a replay
	# is most likely to get wrong, because the peer must re-derive it locally
	# from an identical HP delta rather than receive it.
	_set_local(nodes.leaf, &"ranged_damage", 9999.0)

	var tm := TurnManager.new()
	add_child_autofree(tm)
	tm.current_entity = attacker

	var bs := BattleSystem.new()
	bs.turn_manager = tm
	bs.allocation_system = alloc
	bs.graph = graph
	# Land the whole outcome on one line. This test measures the record, not
	# the beat clock; both worlds get the same flag so it is never a variable.
	bs.instant_mutation = true
	add_child_autofree(bs)

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	return {"graph": graph, "bs": bs, "attacker": attacker,
			"defender": defender, "nodes": nodes}


## The full wire trip, not just `to_dict` — `var_to_bytes` is what a transport
## actually does, and it is the step that would reject a payload holding a
## live Object. [AttackRecord] encodes as Packed* arrays; this proves they
## survive.
func _over_the_wire(command: LaunchAttackCommand) -> LaunchAttackCommand:
	var bytes := var_to_bytes(command.to_dict())
	var decoded: Variant = bytes_to_var(bytes)
	assert_true(decoded is Dictionary, "the wire form must decode as a Dictionary")
	var back := CommandCodec.from_dict(decoded as Dictionary)
	assert_true(back is LaunchAttackCommand,
			"the codec must dispatch a launch_attack tag back to its own type")
	return back as LaunchAttackCommand


## Fire on [param host] and replay the resulting record on [param peer].
func _fire_and_replay(host: Dictionary, peer: Dictionary) -> LaunchAttackCommand:
	var bs: BattleSystem = host.bs
	var command := bs.build_launch_command()
	assert_not_null(command, "the fixture plan must be launchable")
	await bs.apply_launch_command(command)
	assert_false(command.record.is_empty(),
			"the authority must stamp the record it produced onto the command")

	var wired := _over_the_wire(command)
	var peer_bs: BattleSystem = peer.bs
	await peer_bs.apply_launch_command(wired)
	return command


func _assert_worlds_agree(host: Dictionary, peer: Dictionary, what: String) -> void:
	# The same oracle the two-process harness compares with, so a green test
	# here and a green ✓ there are checking the same thing.
	assert_eq(WorldFingerprint.compute(host.graph), WorldFingerprint.compute(peer.graph),
			"%s: ownership must match (host %s / peer %s)" % [what,
			WorldFingerprint.describe(host.graph), WorldFingerprint.describe(peer.graph)])
	# The fingerprint covers ownership only, by design — HP is what a replay
	# most easily gets wrong (double-mitigation, a re-rolled crit), so it is
	# asserted separately rather than folded in.
	for key in (host.nodes as Dictionary):
		var host_node: SkillNode = host.nodes[key]
		var peer_node: SkillNode = peer.nodes[key]
		assert_almost_eq(peer_node.get_current_hp(), host_node.get_current_hp(), 0.0001,
				"%s: node '%s' HP must match" % [what, key])
	for role in ["attacker", "defender"]:
		var host_board: EntityStatBoard = (host[role] as Entity).stat_board
		var peer_board: EntityStatBoard = (peer[role] as Entity).stat_board
		assert_almost_eq(peer_board.action_points.current, host_board.action_points.current,
				0.0001, "%s: %s AP must match" % [what, role])
		assert_almost_eq(peer_board.mana.current, host_board.mana.current,
				0.0001, "%s: %s mana must match" % [what, role])
		assert_almost_eq(peer_board.health.current, host_board.health.current,
				0.0001, "%s: %s health must match" % [what, role])
		assert_almost_eq(peer_board.skill_points.wounded, host_board.skill_points.wounded,
				0.0001, "%s: %s wounded SP must match" % [what, role])


func _arm_ranged(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.RANGED)
	(bs.attack_plan as RangedAttackPlan)._on_node_left_clicked(ctx.nodes.target)


func _arm_melee(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(ctx.nodes.core)
	plan._on_node_left_clicked(ctx.nodes.leaf)


func _arm_magic(ctx: Dictionary) -> void:
	var bs: BattleSystem = ctx.bs
	bs.selected_spell = SpellCatalog.SPARK
	bs.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	var plan := bs.attack_plan as MagicAttackPlan
	plan._on_node_left_clicked(ctx.nodes.leaf)
	plan._on_node_left_clicked(ctx.nodes.target)


# ── The three modes ─────────────────────────────────────────────────────────

func test_a_ranged_volleys_record_replays_to_the_same_world() -> void:
	var host: Dictionary = await _build()
	var peer: Dictionary = await _build(_PEER_ORIGIN)
	_arm_ranged(host)
	var fp_before := WorldFingerprint.compute(host.graph)
	var command := await _fire_and_replay(host, peer)
	assert_gt((command.record[AttackRecord.KEY_HIT_AMOUNT] as PackedFloat64Array).size(), 0,
			"the fixture must actually land something")
	assert_ne(WorldFingerprint.compute(host.graph), fp_before,
			"the volley must actually change ownership, or the agreement below is vacuous")
	_assert_worlds_agree(host, peer, "ranged")


func test_a_melee_swings_record_replays_to_the_same_world() -> void:
	# Melee is the discriminator per the 2026-08-21 owner call: its hit
	# detection is a physics query and its damage passes through a live gate
	# that accumulates across the swing, so a test covering only magic would
	# not satisfy this child.
	var host: Dictionary = await _build()
	var peer: Dictionary = await _build(_PEER_ORIGIN)
	_arm_melee(host)
	var command := await _fire_and_replay(host, peer)
	assert_gt((command.record[AttackRecord.KEY_HIT_AMOUNT] as PackedFloat64Array).size(), 0,
			"the fixture swing must actually produce landings")
	_assert_worlds_agree(host, peer, "melee")


func test_a_spells_record_replays_to_the_same_world_with_its_timeline() -> void:
	var host: Dictionary = await _build()
	var peer: Dictionary = await _build(_PEER_ORIGIN)
	_arm_magic(host)
	# Read AFTER the board settles: `mana`'s cap is base + INT//10 and
	# `set_base_ratcheted` refills to it, so the fixture's own 10.0 is not the
	# starting value. Asserting a delta rather than an absolute keeps this
	# about the record.
	var mana_before: float = (host.attacker as Entity).stat_board.mana.current
	var command := await _fire_and_replay(host, peer)
	assert_gt((command.record[AttackRecord.KEY_EVENT_BEAT] as PackedInt32Array).size(), 0,
			"the fixture cast must produce a timeline — it is what magic VFX replays")
	_assert_worlds_agree(host, peer, "magic")
	assert_almost_eq((host.attacker as Entity).stat_board.mana.current,
			mana_before - float(SpellCatalog.SPARK.mana_cost), 0.0001,
			"the host paid mana, so the peer had something to match")


# ── The record's own invariants ─────────────────────────────────────────────

func test_the_timeline_rebuilds_its_ALIASING_not_just_its_values() -> void:
	# A PropagationEvent's hits are SHARED REFERENCES into AttackOutcome.hits,
	# never copies (propagation_event.gd). A rebuild that produced independent
	# hit objects per event would satisfy every value assertion above and still
	# be wrong — MagicBounceCoordinator walks the timeline while the applier
	# lands the flat list, and they must be looking at the same objects.
	var host: Dictionary = await _build()
	_arm_magic(host)
	var bs: BattleSystem = host.bs
	var command := bs.build_launch_command()
	await bs.apply_launch_command(command)

	var rebuilt := AttackRecord.rebuild(command.record, host.graph)
	assert_gt(rebuilt.timeline.size(), 0, "fixture must produce a timeline")
	var aliased := 0
	for event in rebuilt.timeline:
		for hit in event.hits:
			assert_true(rebuilt.hits.has(hit),
					"a timeline hit must BE an entry of the flat list, not a copy of one")
			aliased += 1
	assert_gt(aliased, 0, "…and at least one event must carry a hit")


func test_the_record_carries_the_seed_the_attack_resolved_under() -> void:
	var host: Dictionary = await _build()
	_arm_ranged(host)
	var bs: BattleSystem = host.bs
	var command := bs.build_launch_command()
	assert_ne(command.resolve_seed, 0, "the authority mints a fresh seed per attack")
	await bs.apply_launch_command(command)
	var wired := _over_the_wire(command)
	assert_eq(wired.resolve_seed, command.resolve_seed,
			"the seed survives the wire — it is the 'verify by re-resolving' half")
	assert_eq(int(wired.record[AttackRecord.KEY_SEED]), command.resolve_seed,
			"and the record is self-describing about which seed produced it")


func test_no_live_reference_and_no_source_field_reaches_the_wire() -> void:
	var host: Dictionary = await _build()
	_arm_magic(host)
	var bs: BattleSystem = host.bs
	var command := bs.build_launch_command()
	await bs.apply_launch_command(command)
	var d := command.to_dict()
	# Scoped to the RECORD half. A plan legitimately carries a `source` key —
	# that is melee's pivot / magic's cast-from node, an id. What must not
	# exist is `HitInstance.source`, the untyped Variant of resolve-local
	# residue whose one real reader now goes through `hit.attacker` instead.
	for key in (d["record"] as Dictionary):
		assert_false(str(key) == "source",
				"HitInstance.source is resolve-local residue, not wire state")
	_assert_no_live_references(d)
	# var_to_bytes is the real proof: it cannot encode a live Object without
	# `full_objects`, so a payload that survives this holds none.
	assert_gt(var_to_bytes(d).size(), 0)


func _assert_no_live_references(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			_assert_no_live_references(value[key])
		return
	if value is Array:
		for item in value:
			_assert_no_live_references(item)
		return
	assert_false(value is SkillNode, "a SkillNode reference reached the wire")
	assert_false(value is Entity, "an Entity reference reached the wire")


func test_a_gated_landing_replays_as_a_dud_rather_than_a_hit() -> void:
	# #503's `gated` flag is deliberately distinct from `effective_amount == 0`
	# (a dud vs. "their armour held"), and it must stay distinguishable on the
	# far side — the VFX layer renders the two differently. Hand-built, because
	# provoking a real mid-volley veto needs a cascade this fixture would have
	# to be reshaped around; what is under test is the encoding, not the gate.
	var host: Dictionary = await _build()
	var outcome := AttackOutcome.new()
	var gated := DamageInstance.new()
	gated.target = host.nodes.target
	gated.attacker = host.attacker
	gated.effective_amount = 12.0
	gated.gated = true
	outcome.hits.append(gated)
	var landed := DamageInstance.new()
	landed.target = host.nodes.target
	landed.attacker = host.attacker
	landed.effective_amount = 3.0
	outcome.hits.append(landed)

	var rebuilt := AttackRecord.rebuild(
			AttackRecord.capture(outcome, host.graph), host.graph)
	assert_true(rebuilt.hits[0].gated, "the veto verdict crosses")
	assert_eq(rebuilt.hits[0].amount, 0.0, "and a gated hit lands nothing on replay")
	assert_eq(rebuilt.hits[0].effective_amount, 12.0,
			"…while still reporting what the host's number would have been")
	assert_false(rebuilt.hits[1].gated)
	assert_eq(rebuilt.hits[1].amount, 3.0,
			"an ungated landing replays its post-mitigation amount")
