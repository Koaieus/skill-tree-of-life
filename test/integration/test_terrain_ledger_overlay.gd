extends GutTest
## The terrain-ledger readout on a real level: the level places a
## [TerrainLedger] and wires the HUD's [TerrainLedgerOverlay] to it, F4 shows
## and hides the overlay, and a hidden overlay does no work — it neither reads
## the ledger nor redraws its plots when a sample closes.
##
## One launch for every assert: a procgen level is the expensive part. The
## overlay is fed through the ledger's public API only — a counting test
## subclass swapped in through the overlay's public `ledger` export, and
## `sample_closed` emitted the way the real ledger closes a world turn.
##
## For the ledger unit's non-empty-after-attack assert: read `%TerrainLedger`
## BEFORE the `CountingLedger` swap; keep the pinned roster, seed and node
## count of [method _launch] (the sandbox's own 7 do not always seat); any NodePath authored on
## `Systems/TerrainLedger` needs its own `_EXPORT_DEPS` line in
## `test_game_root_wiring.gd`.

const _SANDBOX := preload("res://scenes/first_level_sandbox.tscn")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
## Pinned so the map, and so whether the roster seats, never varies by run.
const _SEED := 1845


## Counts every read the overlay makes of the ledger.
class CountingLedger extends TerrainLedger:
	var reads := 0

	func samples() -> Array[Dictionary]:
		reads += 1
		return super()

	func current() -> Dictionary:
		reads += 1
		return super()


var _root: GameRoot


func before_each() -> void:
	GameSession.end()
	GameSession.roster = null
	GameSession.local_peer_id = 0


func after_each() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	await wait_physics_frames(3)
	GameSession.end()
	GameSession.roster = null
	GameSession.local_peer_id = 0


func _participant(id: int, kind: Participant.Kind, camp: Faction, peer_id: int = 0) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = camp
	p.peer_id = peer_id
	return p


## A fixed two-camp roster and seed on a 300-node map, the shape
## `test_level_consumes_session_roster.gd` shows seats: the sandbox's own
## bootstrap roster (7 participants) does not always fit a small map.
func _launch() -> GameRoot:
	var roster := ParticipantRoster.new()
	roster.add(_participant(1, Participant.Kind.HUMAN, _CAMP_1, 5))
	roster.add(_participant(2, Participant.Kind.AI, _CAMP_2))
	var config := RunConfig.new()
	config.seed = _SEED
	GameSession.start(config)
	GameSession.roster = roster
	GameSession.local_peer_id = 5
	var root: GameRoot = _SANDBOX.instantiate()
	root.get_node("%TurnManager").opens_first_turn = false
	root.node_count_override = 300
	root.enemy_territory_size = 1
	add_child(root)
	_root = root
	# `_setup_level` is asynchronous; freeing the level mid-await crashes the
	# engine, so wait for the spawn to land.
	for _f in 900:
		if not _spawned_entities(root).is_empty():
			break
		await wait_physics_frames(1)
	assert_false(_spawned_entities(root).is_empty(),
			"level setup never completed — nothing spawned")
	return root


## The roster's entities only — `entities_container` also holds blockers.
func _spawned_entities(root: GameRoot) -> Array[Entity]:
	var out: Array[Entity] = []
	for c in root.graph.entities_container.get_children():
		if c is Entity and (c as Entity).faction != null \
				and (c as Entity).faction.id != &"blocker":
			out.append(c)
	return out


## One gathered hit on the live world: a hostile node with neighbours primed
## in Lightning, hit by the other camp, its head landed as a replay lands it.
func _attack_once(root: GameRoot) -> bool:
	var es := _spawned_entities(root)
	if es.size() < 2:
		return false
	var light := ElementRoster.shared().by_id(&"lightning")
	var live := CombatWorld.live()
	for n: SkillNode in root.graph.get_skill_nodes():
		if n.owned_by != es[1] or n.get_graph_degree(n.get_graph()) < 2:
			continue
		var c := live.combat_for(n) as NodeCombat
		c.add_terrain(light, c.terrain_threshold() + 1 - c.charge())
		var d := DamageInstance.new()
		d.amount = 1.0
		d.type = DamageInstance.Type.TRUE
		d.is_head = true
		d.target = n
		d.attacker = es[0]
		var span: Array[HitInstance] = [d]
		HitGather.stage_one(span.duplicate(), live, HitQueue.over(span.duplicate()))
		OutcomeApplier.land_one(d, live)
		return true
	return false


func _moved(sample: Dictionary) -> bool:
	for e: StringName in TerrainLedger.ELEMENTS:
		for f: StringName in [&"produced", &"effect", &"voided", &"decayed"]:
			if int(sample[e][f]) != 0:
				return true
	return false


func _press_toggle(overlay: TerrainLedgerOverlay) -> void:
	var ev := InputEventKey.new()
	ev.keycode = overlay.toggle_key
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up)


func test_f4_shows_the_overlay_and_hidden_stops_its_draw() -> void:
	var root := await _launch()
	var overlay: TerrainLedgerOverlay = root.hud_root.terrain_ledger_overlay
	assert_not_null(overlay, "HudRoot mounts a TerrainLedgerOverlay")
	assert_same(overlay.ledger, root.get_node("%TerrainLedger"),
			"game_root wires the overlay to the level's TerrainLedger")
	assert_false(overlay.visible, "the overlay starts hidden")

	# The level's own ledger: one attack and one world turn close a sample
	# with the attack's terrain in it.
	var ledger: TerrainLedger = root.get_node("%TerrainLedger")
	assert_true(_attack_once(root), "fixture: a primed hostile node to hit")
	root.get_node("%TurnManager").run_world_turn()
	assert_false(ledger.samples().is_empty(), "a world turn closes a sample")
	if not ledger.samples().is_empty():
		assert_true(_moved(ledger.samples().back()), "the latest sample is non-empty")

	var counting := CountingLedger.new()
	add_child_autofree(counting)
	overlay.ledger = counting
	var plot: LinePlot = overlay.get_node("%HeatPlot")
	var draws := [0]
	plot.draw.connect(func() -> void: draws[0] += 1)

	var payload := TerrainLedger.empty_sample()
	counting.reads = 0

	# Hidden: a closing sample and the refresh clock cost nothing.
	counting.sample_closed.emit(payload)
	await wait_seconds(0.6)
	assert_eq(counting.reads, 0, "a hidden overlay never reads the ledger")

	_press_toggle(overlay)
	await wait_physics_frames(2)
	assert_true(overlay.visible, "F4 shows the overlay")
	assert_gt(counting.reads, 0, "showing the overlay reads the ledger")

	draws[0] = 0
	counting.sample_closed.emit(payload)
	await wait_physics_frames(2)
	assert_gt(draws[0], 0, "a closing sample redraws a shown overlay's plots")

	_press_toggle(overlay)
	await wait_physics_frames(2)
	assert_false(overlay.visible, "F4 again hides it")
	counting.reads = 0
	draws[0] = 0
	counting.sample_closed.emit(payload)
	await wait_seconds(0.6)
	assert_eq(counting.reads, 0, "hidden again: no reads on a closing sample or a refresh tick")
	assert_eq(draws[0], 0, "hidden again: no redraw")
