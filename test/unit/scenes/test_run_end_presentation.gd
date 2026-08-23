extends GutTest

## How a run-end reads on THIS screen (#517), and how it lets you leave (#526).
## The outcome is point-of-view-free, so the local reading is [HudRoot]'s to
## make, and it makes it from [SeatPolicy] — never from the bound hero.
##
## That distinction is the bug this pins. `GameRoot.bind_player` used to set
## `victory_system.local_camp = player.faction`, and `rebind_player` fires on
## every hot-seat handover (#459) — so on a versus couch the win/lose banner
## resolved from whichever rival acted last. Deriving it from `HudRoot._player`
## instead would have moved the same bug one layer down.
##
## **The assertions are about the READING, not about `overlay.visible`** — and
## deliberately so. Since #526 the overlay carries the way out of the level, so
## it comes up on every outcome; asserting visibility would make the
## turn-order test below pass trivially and stop guarding anything.
##
## Fixture shape copied from `test_seat_vision.gd`: a real `game_root.tscn`
## (through a probe subclass that counts departures instead of taking them), a
## two-camp roster, a hand-driven turn loop.

const _GAME_ROOT := preload("res://test/fixtures/route_probe_game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

var _root: RouteProbeGameRoot
var _p1: Entity
var _p2: Entity


## [param seating] decides the SeatPolicy this machine runs under; everything
## else about the run is identical, which is the point.
func _build(seating: SeatPolicy.Seating) -> void:
	_root = _GAME_ROOT.instantiate()
	_root.auto_start_turn = false
	# Routing is opt-in per test: the probe never actually swaps the scene, but
	# a live fallback timer would still fire into a torn-down fixture.
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	await wait_physics_frames(2)
	# The row's reveal delay is `test_run_end_overlay.gd`'s subject, not this
	# file's; zero it so nothing here waits on a timer it doesn't assert.
	_root.hud_root.run_end_overlay.action_row_delay = 0.0

	var nodes: Array[SkillNode] = []
	for i in 4:
		var sn := _SKILL_NODE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 120, 0)
		_root.graph.add_skill_node(sn)
		nodes.append(sn)
	for i in 3:
		_root.graph.add_edge(nodes[i], nodes[i + 1])

	_p1 = _root.spawn_entity("P1", Color.CYAN, nodes[0], _BALANCED)
	_p2 = _root.spawn_entity("P2", Color.ORANGE, nodes[3], _BALANCED)

	var roster := ParticipantRoster.new()
	for i in 2:
		var p := Participant.new()
		p.id = i
		p.kind = Participant.Kind.LOCAL_HUMAN
		p.camp = _CAMP_1 if i == 0 else _CAMP_2
		roster.add(p)
	GameRoot.apply_roster({0: _p1, 1: _p2}, roster)
	_root.seat_policy = (SeatPolicy.couch() if seating == SeatPolicy.Seating.COUCH
			else SeatPolicy.seat(_p1.entity_id))

	_root.bind_player(_p1)
	await wait_physics_frames(1)


## One test starts a real session to watch the route close it; nothing here may
## leave a live run behind for the next file.
func after_each() -> void:
	GameSession.end()


## A hot-seat handover, which is what used to decide the outcome's point of
## view. Only lands under COUCH — `follows_active_turn()` gates it.
func _hand_turn_to(ent: Entity) -> void:
	var tm := _root.turn_manager
	if tm.current_entity != null:
		var prev := tm.current_entity
		tm.current_entity = null
		tm.turn_ended.emit(prev)
	tm.start_turn(ent)


func _end_run(winner: Faction) -> void:
	var outcome := RunOutcome.new()
	outcome.winning_camp = winner
	Events.run_ended.emit(outcome)
	await wait_physics_frames(1)


func _overlay() -> RunEndOverlay:
	return _root.hud_root.run_end_overlay


func _reading() -> RunEndOverlay.Reading:
	return _overlay().reading


# --- Couch: neutral, whatever the turn order -------------------------------

## The parked bug, from the seat-policy comment on #517: two rivals share one
## screen, so there is no camp for that screen to have lost from.
func test_a_couch_reads_a_finished_run_as_neutral() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	await _end_run(_CAMP_2)

	assert_eq(_reading(), RunEndOverlay.Reading.NEUTRAL,
			"a couch narrates a winner; it has no camp to lose from")


## The #517 regression guard. A reading derived from the bound hero would come
## back DEFEAT here (P2 acted last, P2's camp lost) and VICTORY if P1 had.
func test_a_couch_reading_does_not_depend_on_who_acted_last() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p2, "the handover must actually have landed")

	await _end_run(_CAMP_1)

	assert_eq(_reading(), RunEndOverlay.Reading.NEUTRAL,
			"P2 acted last and P2's camp lost — the couch still reads neutral")
	assert_eq(_overlay().title_label.text, "RUN OVER",
			"and the copy follows the reading, not the turn order")


# --- Seat: one human, one machine, one answer ------------------------------

func test_a_seat_reads_defeat_when_its_hero_lost() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(_CAMP_2)

	assert_eq(_reading(), RunEndOverlay.Reading.DEFEAT,
			"the seated hero's camp did not win")
	assert_eq(_overlay().title_label.text, "DEFEAT")


func test_a_seat_reads_victory_when_its_hero_won() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(_CAMP_1)

	assert_eq(_reading(), RunEndOverlay.Reading.VICTORY)
	assert_eq(_overlay().title_label.text, "VICTORY")


## Under SEAT `follows_active_turn()` is false, so the rival taking a turn
## cannot re-point the bound player — which is what makes reading `_player`
## legitimate there and only there.
func test_a_seats_reading_survives_a_rivals_turn() -> void:
	await _build(SeatPolicy.Seating.SEAT)
	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p1, "a seated view does not follow the turn")

	await _end_run(_CAMP_2)

	assert_eq(_reading(), RunEndOverlay.Reading.DEFEAT,
			"still judged from the seat, not the turn")


# --- Draw ------------------------------------------------------------------

func test_a_draw_reads_as_a_draw_on_a_seat() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(null)

	assert_eq(_reading(), RunEndOverlay.Reading.DRAW,
			"nobody won — there is no camp to read it against")


func test_a_draw_reads_as_a_draw_on_a_couch() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	await _end_run(null)

	assert_eq(_reading(), RunEndOverlay.Reading.DRAW)


# --- One surface, every outcome (#526) -------------------------------------

## The old stub came up only on a local loss, so a draw got a banner and no way
## out of the level. All three now land on the same surface.

func test_a_win_raises_the_overlay() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(_CAMP_1)

	assert_true(_overlay().visible, "a win still needs the way out")


func test_a_loss_raises_the_overlay() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(_CAMP_2)

	assert_true(_overlay().visible)


func test_a_draw_raises_the_overlay() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	await _end_run(null)

	assert_true(_overlay().visible,
			"the case that had no exit at all before #526")


# --- The way out -----------------------------------------------------------

## The wiring, end to end: the overlay only ASKS to leave, and HudRoot is what
## hands that to the GameRoot that owns the route.
func test_the_overlays_request_routes_out_of_the_run() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	_root.route_to_meta_on_run_end = true
	GameSession.start(RunConfig.new())

	_overlay().main_menu_pressed.emit()

	assert_eq(_root.departures, 1, "clicking out leaves immediately")
	assert_false(GameSession.is_active(), "and closes the run's session (#457)")


## Acceptance: clicking out cancels the pending auto-route — one departure, not
## two, and `GameSession.end()` therefore does not run twice.
func test_leaving_early_does_not_leave_again_when_the_fallback_fires() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	_root.route_to_meta_on_run_end = true
	_root.run_end_route_delay = 0.15
	await _end_run(_CAMP_1)

	_overlay().main_menu_pressed.emit()
	await wait_seconds(0.4)

	assert_eq(_root.departures, 1, "the fallback timer must find it already gone")


## Acceptance: not clicking still routes, after the fallback timeout.
func test_not_leaving_routes_on_the_fallback_timeout() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	_root.route_to_meta_on_run_end = true
	_root.run_end_route_delay = 0.15

	await _end_run(_CAMP_1)
	assert_eq(_root.departures, 0, "not yet — the delay is the point")
	await wait_seconds(0.4)

	assert_eq(_root.departures, 1)


## Acceptance: a neutered GameRoot (a dev sandbox, an editor-tab showcase) never
## leaves its scene — the export vetoes the button as well as the timeout.
func test_a_neutered_game_root_never_leaves_even_when_asked() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	await _end_run(_CAMP_1)
	assert_true(_overlay().action_row.visible,
			"the row is still offered — the veto is on the route, not the UI")

	_overlay().main_menu_pressed.emit()
	await wait_seconds(0.4)

	assert_eq(_root.departures, 0, "route_to_meta_on_run_end vetoes both ways out")


## Both dev sandboxes set the veto, and a run ends in them regularly. Without
## this the surface would be a permanent full-screen dim over a level you were
## still poking at, with a button that does nothing — strictly worse than the
## banner-only run-end it replaced.
func test_a_vetoed_press_dismisses_the_overlay_instead_of_stranding_it() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	await _end_run(_CAMP_1)
	assert_true(_overlay().visible, "precondition")

	_overlay().main_menu_pressed.emit()

	assert_false(_overlay().visible, "the one action always gets you out of something")


# --- The banner is camp-authored -------------------------------------------

## The wire, not just the request: everything else here would still pass if
## `enqueue_now` silently no-oped (no layer, or no TITLE band bound), because
## the other banner tests build the request and never post it.
func test_the_run_end_banner_actually_reaches_the_title_band() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	await _end_run(_CAMP_2)

	var layer := _root.hud_root.announcement_layer
	var playing: AnnouncementRequest = layer._current_by_kind.get(
			AnnouncementRequest.Kind.TITLE)
	assert_not_null(playing, "the terminal beat must be on screen, once")
	assert_eq(playing.main_text, "%s wins!" % _CAMP_2.display_name)
	assert_eq(playing.stack_count, 1, "one announcement, from the camp")


func test_the_winner_banner_reads_and_tints_from_the_camp_alone() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	var req := _root.hud_root._run_end_banner(_make_outcome(_CAMP_2))

	assert_eq(req.main_text, "%s wins!" % _CAMP_2.display_name)
	assert_true(req.has_tint(), "a camp-coloured line, not a semantic Style")
	assert_eq(req.tint, _CAMP_2.color)
	assert_true(req.context.is_empty(),
			"no acting entity to go stale against — the run is over")


func test_the_draw_banner_names_no_camp() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	var req := _root.hud_root._run_end_banner(_make_outcome(null))

	assert_eq(req.main_text, "DRAW")
	assert_false(req.has_tint())


func _make_outcome(winner: Faction) -> RunOutcome:
	var outcome := RunOutcome.new()
	outcome.winning_camp = winner
	return outcome
