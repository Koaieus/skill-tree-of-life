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
## BEFORE the `CountingLedger` swap; keep `node_count_override` at 200 or more
## (40 cannot seat the sandbox's 7 participants); any NodePath authored on
## `Systems/TerrainLedger` needs its own `_EXPORT_DEPS` line in
## `test_game_root_wiring.gd`.

const _SANDBOX := preload("res://scenes/first_level_sandbox.tscn")


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


func _launch() -> GameRoot:
	var root: GameRoot = _SANDBOX.instantiate()
	root.get_node("%TurnManager").opens_first_turn = false
	root.node_count_override = 200
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
