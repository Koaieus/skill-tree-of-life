extends GutTest

## #563 — a rival human must NOT render in the local player's colour.
##
## The owner's call, 2026-08-26, verbatim:
##
##   "The roster is authoritative for hero colour. `Participant.color` is real
##   run shape, it crosses the wire, and every peer draws every hero in the
##   colour its lobby slot chose."
##
## That reverses #563's own opening Note (colour as per-machine presentation
## owned by [SeatPolicy]). See `docs/domain/seat-policy.md` § "One axis".
##
## [b]What this file tests, and why not a full level boot.[/b] The decision under
## test is `ProcgenPlaySandbox.resolve_spawn_color`, which is the ONLY thing the
## spawn loop consults for colour — the loop passes its result straight to
## [method GameRoot.spawn_entity] on all three arms. Booting the real level
## instead would drag in a full [GraphProcgen] run (seconds, and a shared
## [GameSession]) to re-derive the same four-line answer, so the assertions here
## drive the production function directly rather than mirroring its logic.

const _SANDBOX := preload("res://scenes/procgen_play_sandbox.gd")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _NPC := preload("res://entity/factions/npc.tres")

## The scene exports as authored, i.e. what the fallback arm would hand back.
const _PLAYER_FALLBACK := Color(0.4, 0.8, 1.0)
const _ENEMY_FALLBACK: Array[Color] = [Color(0.95, 0.4, 0.4), Color(1.0, 0.6, 0.2)]


func _human(id: int, camp: Faction, color: Color, peer_id: int = 0) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = Participant.Kind.HUMAN
	p.camp = camp
	p.color = color
	p.peer_id = peer_id
	return p


func _ai(id: int, color: Color = Color.WHITE) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = Participant.Kind.AI
	p.camp = _NPC
	p.color = color
	return p


func _resolve(p: Participant, enemy_index: int = 0) -> Color:
	return _SANDBOX.resolve_spawn_color(
			p, _PLAYER_FALLBACK, _ENEMY_FALLBACK, enemy_index)


# --- Acceptance 1: two humans, two distinct roster colours -----------------

## THE regression this issue opened on. Before #563 the `else` arm of the spawn
## loop handed `player_color` to any human who was not this machine's, so both
## heroes in a versus run came out the same blue and territory stopped being
## readable at a glance.
func test_two_humans_in_a_versus_roster_take_their_own_roster_colours() -> void:
	var mine := Color(0.2, 0.9, 0.3)
	var theirs := Color(0.9, 0.2, 0.4)
	var local := _human(1, _CAMP_1, mine, 0)
	var rival := _human(2, _CAMP_2, theirs, 4711)  # a human at ANOTHER machine

	var local_color := _resolve(local)
	var rival_color := _resolve(rival)

	assert_eq(local_color, mine, "the local hero draws in its own slot's colour")
	assert_eq(rival_color, theirs, "the rival draws in ITS slot's colour")
	assert_ne(local_color, rival_color,
			"#563: two humans must not share one colour")
	assert_ne(rival_color, _PLAYER_FALLBACK,
			"#563: the rival must not fall back to the local player's colour")


## The same roster read from the OTHER machine. Colour is run shape, so the
## answer must not move when `local_peer_id` does — `resolve_spawn_color` takes
## no peer id at all, which is what makes that true by construction.
func test_hero_colour_does_not_depend_on_which_machine_asks() -> void:
	var rival := _human(2, _CAMP_2, Color(0.9, 0.2, 0.4), 4711)
	assert_eq(_resolve(rival), Color(0.9, 0.2, 0.4),
			"every peer draws every hero in the colour its lobby slot chose")


## D1 — AI is on the same path, not a second policy.
func test_an_ai_with_a_roster_colour_takes_it_over_the_enemy_pool() -> void:
	var ai := _ai(3, Color(0.1, 0.2, 0.3))
	assert_eq(_resolve(ai), Color(0.1, 0.2, 0.3))
	assert_false(_ENEMY_FALLBACK.has(_resolve(ai)),
			"a roster colour beats the enemy_colors pool")


## The colour must survive the wire, or peers disagree about what they draw.
## Already true on master (`participant.gd:58` / `:69`); pinned here because
## #563 is what made it load-bearing.
func test_a_roster_colour_survives_the_wire() -> void:
	var rival := _human(2, _CAMP_2, Color(0.9, 0.2, 0.4), 4711)
	var decoded := Participant.from_dict(rival.to_dict())
	assert_eq(_resolve(decoded), _resolve(rival))


# --- Acceptance 2: no colour in the roster → the exports still apply -------

## D2 — `player_color` / `enemy_colors` are fallbacks, NOT dead code. A sandbox
## launched from an authored `RunConfig` has no lobby to have picked a colour,
## and must still render distinguishable heroes.
func test_a_colourless_human_falls_back_to_the_player_export() -> void:
	var p := _human(1, _CAMP_1, Color.WHITE)
	assert_eq(_resolve(p), _PLAYER_FALLBACK)


func test_colourless_ai_cycle_through_the_enemy_export_pool() -> void:
	assert_eq(_resolve(_ai(2), 0), _ENEMY_FALLBACK[0])
	assert_eq(_resolve(_ai(3), 1), _ENEMY_FALLBACK[1])
	assert_eq(_resolve(_ai(4), 2), _ENEMY_FALLBACK[0], "the pool wraps")


## The fallback is per-participant, not per-roster: a roster that is half
## authored and half lobby-picked resolves each row on its own terms.
func test_the_fallback_is_decided_per_participant() -> void:
	var picked := _human(1, _CAMP_1, Color(0.2, 0.9, 0.3))
	var unpicked := _human(2, _CAMP_2, Color.WHITE)
	assert_eq(_resolve(picked), Color(0.2, 0.9, 0.3))
	assert_eq(_resolve(unpicked), _PLAYER_FALLBACK)


## Degenerate scene authoring must not crash the spawn loop.
func test_an_empty_enemy_pool_still_yields_a_colour() -> void:
	var empty: Array[Color] = []
	assert_eq(_SANDBOX.resolve_spawn_color(_ai(2), _PLAYER_FALLBACK, empty, 0),
			Color.RED, "no pool to draw from, but a spawn still needs a colour")
