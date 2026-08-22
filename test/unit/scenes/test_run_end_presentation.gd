extends GutTest

## How a run-end reads on THIS screen (#517). The outcome is point-of-view-free,
## so the local reading is [HudRoot]'s to make, and it makes it from
## [SeatPolicy] — never from the bound hero.
##
## That distinction is the bug this pins. `GameRoot.bind_player` used to set
## `victory_system.local_camp = player.faction`, and `rebind_player` fires on
## every hot-seat handover (#459) — so on a versus couch the win/lose banner
## resolved from whichever rival acted last. Deriving it from `HudRoot._player`
## instead would have moved the same bug one layer down.
##
## Fixture shape copied from `test_seat_vision.gd`: a real `game_root.tscn`, a
## two-camp roster, a hand-driven turn loop.

const _GAME_ROOT := preload("res://scenes/game_root.tscn")
const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")

var _root: GameRoot
var _p1: Entity
var _p2: Entity


## [param seating] decides the SeatPolicy this machine runs under; everything
## else about the run is identical, which is the point.
func _build(seating: SeatPolicy.Seating) -> void:
	_root = _GAME_ROOT.instantiate()
	_root.auto_start_turn = false
	# The run ends in here; routing away mid-test would tear the fixture down.
	_root.route_to_meta_on_run_end = false
	add_child_autofree(_root)
	await wait_physics_frames(2)

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


func _overlay_shown() -> bool:
	return _root.hud_root.game_over_overlay.visible


# --- Couch: banner only, whatever the turn order ---------------------------

## The parked bug, from the seat-policy comment on #517: two rivals share one
## screen, so there is no camp for that screen to have lost from.
func test_a_couch_never_shows_the_loss_overlay() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	await _end_run(_CAMP_2)

	assert_false(_overlay_shown(),
			"a couch narrates a winner; it has no camp to lose from")


func test_a_couch_outcome_does_not_depend_on_who_acted_last() -> void:
	await _build(SeatPolicy.Seating.COUCH)
	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p2, "the handover must actually have landed")

	await _end_run(_CAMP_1)

	assert_false(_overlay_shown(),
			"P2 acted last and P2's camp lost — the couch still shows no overlay")


# --- Seat: one human, one machine, one answer ------------------------------

func test_a_seat_shows_the_overlay_when_its_hero_lost() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(_CAMP_2)

	assert_true(_overlay_shown(), "the seated hero's camp did not win")


func test_a_seat_shows_no_overlay_when_its_hero_won() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(_CAMP_1)

	assert_false(_overlay_shown())


## Under SEAT `follows_active_turn()` is false, so the rival taking a turn
## cannot re-point the bound player — which is what makes reading `_player`
## legitimate there and only there.
func test_a_seats_answer_survives_a_rivals_turn() -> void:
	await _build(SeatPolicy.Seating.SEAT)
	_hand_turn_to(_p2)
	await wait_physics_frames(1)
	assert_eq(_root.player, _p1, "a seated view does not follow the turn")

	await _end_run(_CAMP_2)

	assert_true(_overlay_shown(), "still judged from the seat, not the turn")


# --- Draw ------------------------------------------------------------------

## Deliberate behaviour change: GameRoot used to emit `game_over` on anything
## that was not a local WIN, so a mutual wipe dimmed the screen.
func test_a_draw_shows_no_overlay_on_a_seat() -> void:
	await _build(SeatPolicy.Seating.SEAT)

	await _end_run(null)

	assert_false(_overlay_shown(), "a draw is a banner, not a defeat")


func test_a_draw_shows_no_overlay_on_a_couch() -> void:
	await _build(SeatPolicy.Seating.COUCH)

	await _end_run(null)

	assert_false(_overlay_shown())


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
