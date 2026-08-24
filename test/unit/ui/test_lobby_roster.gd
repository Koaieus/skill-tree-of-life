extends GutTest

## #456 LAN milestone scaffolding — [LobbyScreen] builds its participant rows
## and [RunConfig] from a configured mode instead of one hardcoded "Player 1"
## row. Covers the two OFFLINE shapes (single-player, 2-human hot-seat) and
## confirms the lobby's output is actually consumable by the level seam
## ([method GameRoot.apply_roster]), same style as test_game_root_roster.gd.
##
## The networked shapes, the derived mode and the seat wiring are #554's
## `test/unit/session/test_lobby_versus_roster.gd`. Since #554 every lobby also
## authors AI opponents, so the human participants are filtered for here rather
## than being the whole list.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")


func _make_lobby(mode: RunConfig.Mode) -> LobbyScreen:
	var lobby := LobbyScreen.new()
	lobby.configure(mode)
	add_child_autofree(lobby)
	return lobby


func _humans(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind != Participant.Kind.AI:
			out.append(p)
	return out


func test_multiplayer_lobby_run_config_has_two_allied_local_humans() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var run_config: RunConfig = lobby.build_run_config()

	assert_eq(run_config.mode, RunConfig.Mode.COOP_HOTSEAT,
			"two humans on one camp is coop, however many AI join them")
	var humans := _humans(run_config.participants)
	assert_eq(humans.size(), 2)
	for p in humans:
		assert_eq(p.kind, Participant.Kind.LOCAL_HUMAN)
		assert_eq(p.camp, _CAMP_1)


func test_multiplayer_participants_are_allied_and_human_controlled_via_apply_roster() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var run_config: RunConfig = lobby.build_run_config()

	var roster := ParticipantRoster.new()
	for p in run_config.participants:
		roster.add(p)

	var e1: Entity = autofree(Entity.new())
	var e2: Entity = autofree(Entity.new())
	var humans := _humans(run_config.participants)
	var p1: Participant = humans[0]
	var p2: Participant = humans[1]
	var entities_by_id := {p1.id: e1, p2.id: e2}

	GameRoot.apply_roster(entities_by_id, roster)

	assert_true(e1.is_human_controlled)
	assert_true(e2.is_human_controlled)
	assert_eq(e1.attitude_to(e2), Entity.Attitude.ALLIED,
			"lobby-scaffolded hot-seat humans must read allied")
	assert_eq(e2.attitude_to(e1), Entity.Attitude.ALLIED)


func test_single_player_lobby_yields_one_participant_in_single_mode() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	var run_config: RunConfig = lobby.build_run_config()

	assert_eq(run_config.mode, RunConfig.Mode.SINGLE)
	var humans := _humans(run_config.participants)
	assert_eq(humans.size(), 1)
	assert_eq(humans[0].kind, Participant.Kind.LOCAL_HUMAN)
	assert_eq(humans[0].camp, _PLAYER_FACTION)


func test_seed_parsing_numeric_string_becomes_int() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	lobby._seed_edit.text = "12345"

	assert_eq(lobby.build_run_config().seed, 12345)


func test_seed_parsing_empty_or_non_numeric_becomes_zero() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)

	lobby._seed_edit.text = ""
	assert_eq(lobby.build_run_config().seed, 0, "empty text randomises")

	lobby._seed_edit.text = "not-a-number"
	assert_eq(lobby.build_run_config().seed, 0, "non-numeric text randomises")
