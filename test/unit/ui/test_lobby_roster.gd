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
		assert_eq(p.kind, Participant.Kind.HUMAN)
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
	assert_eq(humans[0].kind, Participant.Kind.HUMAN)
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


# --- #616: the lobby owns hero colour --------------------------------------

const _PALETTE := preload("res://ui/theme/player_palette.tres")
const _XP := preload("res://stats_system/defs/xp.tres")
const _WISDOM := preload("res://stats_system/defs/wisdom.tres")
const _ROW_SCENE := preload("res://ui/frontmatter/panels/participant_row.tscn")


func test_player_palette_offers_at_least_twenty_colours() -> void:
	assert_gte(_PALETTE.size(), 20,
			"#616 D5: ~20 colours, enough that a 6-slot roster never wraps")


func test_player_palette_excludes_pure_white() -> void:
	# LOAD-BEARING, not tidiness. `Participant.color` defaults to Color.WHITE
	# and carries no separate "unset" flag, so #563's
	# ProcgenPlaySandbox.resolve_spawn_color reads pure white as the sentinel
	# for "this participant chose nothing" and falls back to the level's
	# player_color / enemy_colors exports. A slot that could pick pure white
	# would silently spawn in the level default instead of the player's choice.
	assert_false(_PALETTE.has_color(Color.WHITE),
			"pure white is resolve_spawn_color's 'no colour chosen' sentinel")


func test_player_palette_excludes_the_reserved_golds() -> void:
	# `.claude/rules/ui-palette.md`: gold means reward, never identity.
	assert_false(_PALETTE.has_color(_XP.tint_color), "xp gold is reserved")
	assert_false(_PALETTE.has_color(_WISDOM.tint_color), "WIS gold is reserved")


func test_every_slot_of_a_full_roster_gets_a_distinct_colour() -> void:
	# 2 humans + 4 AI is the widest roster the lobby can author.
	var parts := LobbyScreen.build_participants(
			RunConfig.Mode.COOP_HOTSEAT, null, 4)
	assert_eq(parts.size(), 6, "two humans plus four AI opponents")
	var seen: Array[Color] = []
	for p in parts:
		assert_false(seen.has(p.color),
				"%s reuses a colour already taken" % p.display_name)
		assert_true(_PALETTE.has_color(p.color), "and it came from the palette")
		seen.append(p.color)


func test_picking_a_colour_disables_it_in_another_slots_dropdown() -> void:
	var parts := LobbyScreen.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 1)
	var mine: Participant = parts[0]
	var theirs: Participant = parts[1]

	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(mine, 0)
	row.set_color_choices(_PALETTE, LobbyScreen.taken_colors(parts, mine.id))

	var pick: OptionButton = row.get_node("%ColorPick")
	assert_eq(pick.item_count, _PALETTE.size(), "every palette colour is listed")
	var mine_index := _PALETTE.colors.find(mine.color)
	var theirs_index := _PALETTE.colors.find(theirs.color)
	assert_eq(pick.selected, mine_index, "my own colour is the selected item")
	assert_false(pick.is_item_disabled(mine_index), "and stays selectable")
	assert_true(pick.is_item_disabled(theirs_index),
			"#616 D6: a colour another slot holds is greyed out here")


func test_a_pick_moves_the_colour_and_frees_the_old_one() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var parts := lobby.participants()
	var mine: Participant = parts[0]
	var before := mine.color
	var free_color: Color = _PALETTE.colors[_PALETTE.size() - 1]
	assert_ne(before, free_color, "picking something nobody holds")

	lobby._on_color_picked(free_color, mine)

	assert_eq(mine.color, free_color, "the lobby wrote the roster, not the row")
	assert_false(LobbyScreen.taken_colors(parts, mine.id).has(free_color))
	var others := LobbyScreen.taken_colors(parts, mine.id)
	assert_false(others.has(before), "the colour it vacated is offerable again")
