extends GutTest

## [LobbyRoster] is the lobby's DOMAIN half (#1002): the participant list, the
## pick memory that survives a rebuild, colour / core / camp allocation, the
## seat-policy vetoes and the [RunConfig] START hands up. Every assertion here
## runs against a bare `RefCounted` — no [LobbyScreen], no row, no tree. The
## rows and the screen's own behaviour are `test/unit/ui/test_lobby_screen.gd`;
## the networked seat/mode wiring is `test_lobby_versus_roster.gd`.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _PALETTE := preload("res://ui/theme/player_palette.tres")
const _XP := preload("res://stats_system/defs/xp.tres")
const _WISDOM := preload("res://stats_system/defs/wisdom.tres")
const _NINJA := preload("res://entity/core/ninja_core.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")
const _SERPENT := preload("res://entity/core/serpent_core.tres")
const _POLICY_HOTSEAT := preload("res://ui/frontmatter/policies/lobby_policy_hotseat.tres")
const _POLICY_VERSUS := preload("res://ui/frontmatter/policies/lobby_policy_versus.tres")
const _POLICY_SINGLE := preload("res://ui/frontmatter/policies/lobby_policy_single.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

## #741: the roster seeds seat 1 from [member GameSettings.player_name] —
## isolated exactly like `test_settings.gd`, so a run here never reads or
## clobbers the developer's real `user://settings.cfg`.
const _SETTINGS_PATH := "user://settings.cfg"
var _had_previous_settings := false
var _settings_backup: PackedByteArray


func before_each() -> void:
	_had_previous_settings = FileAccess.file_exists(_SETTINGS_PATH)
	if _had_previous_settings:
		_settings_backup = FileAccess.get_file_as_bytes(_SETTINGS_PATH)
	Settings.current = GameSettings.new()


func after_each() -> void:
	if _had_previous_settings:
		var f := FileAccess.open(_SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_settings_backup)
		f.close()
	elif FileAccess.file_exists(_SETTINGS_PATH):
		DirAccess.remove_absolute(_SETTINGS_PATH)
	Settings.current = GameSettings.new()


func _humans(participants: Array[Participant]) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in participants:
		if p.kind != Participant.Kind.AI:
			out.append(p)
	return out


func _make_ai(id: int) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = Participant.Kind.AI
	return p


func _make_human(id: int) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = Participant.Kind.HUMAN
	return p


# --- roster shape per mode ---------------------------------------------------

func test_hot_seat_run_config_has_two_allied_local_humans() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.COOP_HOTSEAT)
	var run_config := roster.to_run_config()

	assert_eq(run_config.mode, RunConfig.Mode.COOP_HOTSEAT,
			"two humans on one camp is coop, however many AI join them")
	var humans := _humans(run_config.participants)
	assert_eq(humans.size(), 2)
	for p in humans:
		assert_eq(p.kind, Participant.Kind.HUMAN)
		assert_eq(p.camp, _CAMP_1)


func test_single_player_yields_one_participant_in_single_mode() -> void:
	var run_config := LobbyRoster.new(RunConfig.Mode.SINGLE).to_run_config()

	assert_eq(run_config.mode, RunConfig.Mode.SINGLE)
	var humans := _humans(run_config.participants)
	assert_eq(humans.size(), 1)
	assert_eq(humans[0].kind, Participant.Kind.HUMAN)
	assert_eq(humans[0].camp, _PLAYER_FACTION)


func test_an_offline_roster_seats_the_default_ai_count_and_a_client_none() -> void:
	assert_eq(LobbyRoster.new(RunConfig.Mode.SINGLE).ai_opponent_count(),
			LobbyRoster.DEFAULT_AI_OPPONENTS)
	var client := LobbyRoster.new(RunConfig.Mode.SINGLE, NetworkConfig.join("127.0.0.1", 0))
	assert_eq(client.ai_opponent_count(), 0,
			"a client's roster is a placeholder the host's broadcast replaces")


func test_seed_parsing_numeric_string_becomes_int() -> void:
	assert_eq(LobbyRoster.parse_seed("12345"), 12345)
	assert_eq(LobbyRoster.new(RunConfig.Mode.SINGLE).to_run_config(12345).seed, 12345)


func test_seed_parsing_empty_or_non_numeric_becomes_zero() -> void:
	assert_eq(LobbyRoster.parse_seed(""), 0, "empty text randomises")
	assert_eq(LobbyRoster.parse_seed("not-a-number"), 0, "non-numeric text randomises")


func test_to_participant_roster_carries_every_seat() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.COOP_HOTSEAT)
	var wire := roster.to_participant_roster()
	assert_eq(wire.all().size(), roster.participants.size())
	assert_eq(wire.by_id(1), roster.participants[0])


# --- #616: the roster owns hero colour ---------------------------------------

func test_player_palette_offers_sixteen_colours() -> void:
	assert_eq(_PALETTE.size(), 16,
			"#616/2026-09-02 restyle: 8 canonical brights + 8 secondary, still headroom over a 6-slot roster")


func test_player_palette_excludes_pure_white() -> void:
	# LOAD-BEARING, not tidiness. `Participant.color` defaults to Color.WHITE
	# and carries no separate "unset" flag, so ProcgenPlaySandbox's
	# resolve_spawn_color reads pure white as "this participant chose nothing"
	# — and so does [LobbyRoster.Pick].
	assert_false(_PALETTE.has_color(Color.WHITE),
			"pure white is the 'no colour chosen' sentinel")


func test_player_palette_excludes_the_reserved_golds() -> void:
	# `.claude/rules/ui-palette.md`: gold means reward, never identity.
	assert_false(_PALETTE.has_color(_XP.tint_color), "xp gold is reserved")
	assert_false(_PALETTE.has_color(_WISDOM.tint_color), "WIS gold is reserved")


func test_every_slot_of_a_full_roster_gets_a_distinct_colour() -> void:
	var parts := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 4)
	assert_eq(parts.size(), 6, "two humans plus four AI opponents")
	var seen: Array[Color] = []
	for p in parts:
		assert_false(seen.has(p.color),
				"%s reuses a colour already taken" % p.display_name)
		assert_true(_PALETTE.has_color(p.color), "and it came from the palette")
		seen.append(p.color)


static func _oklab(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	var l := 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
	var m := 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
	var s := 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
	var l_ := pow(maxf(l, 0.0), 1.0 / 3.0)
	var m_ := pow(maxf(m, 0.0), 1.0 / 3.0)
	var s_ := pow(maxf(s, 0.0), 1.0 / 3.0)
	return Vector3(
			0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
			1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
			0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


static func _delta_e_ok(a: Color, b: Color) -> float:
	return (_oklab(a) - _oklab(b)).length()


func _assert_pairwise_separated(swatches: Array[Color], minimum: float, label: String) -> void:
	for i in swatches.size():
		for j in range(i + 1, swatches.size()):
			var d := _delta_e_ok(swatches[i], swatches[j])
			assert_gte(d, minimum,
					"%s: slot %d vs %d only %.4f apart in OKLab" % [label, i, j, d])


func test_a_three_slot_rosters_default_colours_are_pairwise_separated() -> void:
	var swatches: Array[Color] = []
	for p in LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 1):
		swatches.append(p.color)
	_assert_pairwise_separated(swatches, 0.14, "3-slot roster")


func test_a_six_slot_rosters_default_colours_are_pairwise_separated() -> void:
	var swatches: Array[Color] = []
	for p in LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 4):
		swatches.append(p.color)
	_assert_pairwise_separated(swatches, 0.14, "6-slot roster")


func test_default_for_still_wraps_past_the_palette_size() -> void:
	for i in _PALETTE.size():
		assert_eq(_PALETTE.default_for(i), _PALETTE.default_for(i + _PALETTE.size()),
				"the wrap contract holds under the plain array walk too")


func test_a_pick_moves_the_colour_and_frees_the_old_one() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.COOP_HOTSEAT)
	var mine: Participant = roster.participants[0]
	var before := mine.color
	var free_color: Color = _PALETTE.colors[_PALETTE.size() - 1]
	assert_ne(before, free_color, "picking something nobody holds")

	assert_true(roster.pick_color(mine, free_color))

	assert_eq(mine.color, free_color)
	var others := LobbyRoster.taken_colors(roster.participants, mine.id)
	assert_false(others.has(free_color))
	assert_false(others.has(before), "the colour it vacated is offerable again")


func test_a_pick_of_a_taken_colour_is_refused() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.COOP_HOTSEAT)
	var mine: Participant = roster.participants[0]
	var theirs: Color = roster.participants[1].color
	var before := mine.color

	assert_false(roster.pick_color(mine, theirs))
	assert_eq(mine.color, before, "two slots never share a colour")


# --- #618 / #841: cores, defaults and the AI preset --------------------------

func _summed_stat_contribution(core: CoreClass, stat_id: StringName) -> float:
	var total := 0.0
	for m in core.modifiers:
		if m.stat_id == stat_id:
			total += m.value
	return total


func _resolve_cores(parts: Array[Participant], picked_cores: Dictionary, preset_core: CoreClass) -> void:
	var picks := {}
	for id in picked_cores:
		var pick := LobbyRoster.Pick.new()
		pick.core = picked_cores[id]
		picks[id] = pick
	var preset := LobbyRoster.Pick.new()
	preset.core = preset_core
	LobbyRoster.resolve_templated(parts, picks, preset)


func test_slot_bit_maps_kind_to_pickable_flag() -> void:
	assert_eq(LobbyRoster.slot_bit_for(Participant.Kind.HUMAN), CoreClass.PICKABLE_PLAYER)
	assert_eq(LobbyRoster.slot_bit_for(Participant.Kind.AI), CoreClass.PICKABLE_AI)


func test_default_cores_give_ai_and_human_the_same_wisdom_head_start() -> void:
	var parts: Array[Participant] = [_make_human(1), _make_ai(2)]

	LobbyRoster.assign_default_cores(parts)

	var human_wisdom := _summed_stat_contribution(parts[0].core_class, &"wisdom")
	var ai_wisdom := _summed_stat_contribution(parts[1].core_class, &"wisdom")
	assert_lte(ai_wisdom, human_wisdom,
			"the AI default must not out-WIS the human default")


func test_human_slot_still_defaults_to_balanced_core() -> void:
	var parts: Array[Participant] = [_make_human(1)]
	LobbyRoster.assign_default_cores(parts)
	assert_eq(parts[0].core_class, _BALANCED, "regression guard — green today")


func test_core_preset_templates_every_ai_with_no_pick() -> void:
	var parts: Array[Participant] = [_make_human(1), _make_ai(2), _make_ai(3)]

	_resolve_cores(parts, {}, _SERPENT)

	assert_eq(parts[0].core_class, _BALANCED, "the human is never templated")
	assert_eq(parts[1].core_class, _SERPENT)
	assert_eq(parts[2].core_class, _SERPENT)


func test_core_preset_covers_a_newly_seated_ai_id() -> void:
	var parts: Array[Participant] = [_make_ai(2)]
	var picked := {}
	_resolve_cores(parts, picked, _SERPENT)

	parts.append(_make_ai(3))
	_resolve_cores(parts, picked, _SERPENT)

	assert_eq(parts[1].core_class, _SERPENT, "a seat added after arming follows the preset")


func test_one_ai_given_a_pick_only_that_one_changes() -> void:
	var parts: Array[Participant] = [_make_ai(2), _make_ai(3)]
	var picked := {2: _NINJA}

	_resolve_cores(parts, picked, _SERPENT)

	assert_eq(parts[0].core_class, _NINJA, "the pick wins over the preset")
	assert_eq(parts[1].core_class, _SERPENT, "the un-picked seat follows the preset")


func test_preset_change_moves_every_ai_except_the_overridden_one() -> void:
	var parts: Array[Participant] = [_make_ai(2), _make_ai(3)]
	var picked := {2: _NINJA}

	_resolve_cores(parts, picked, _SERPENT)
	_resolve_cores(parts, picked, _BALANCED)

	assert_eq(parts[0].core_class, _NINJA)
	assert_eq(parts[1].core_class, _BALANCED)


func test_clearing_the_pick_resumes_following_the_preset() -> void:
	var parts: Array[Participant] = [_make_ai(2)]
	var picked := {2: _NINJA}

	_resolve_cores(parts, picked, _SERPENT)
	assert_eq(parts[0].core_class, _NINJA)
	picked.erase(2)
	_resolve_cores(parts, picked, _SERPENT)

	assert_eq(parts[0].core_class, _SERPENT)


func test_sentinel_preset_behaves_exactly_as_assign_default_cores() -> void:
	var via_preset: Array[Participant] = [_make_human(1), _make_ai(2), _make_ai(3)]
	_resolve_cores(via_preset, {}, null)

	var via_default: Array[Participant] = [_make_human(1), _make_ai(2), _make_ai(3)]
	LobbyRoster.assign_default_cores(via_default)

	for i in via_preset.size():
		assert_eq(via_preset[i].core_class, via_default[i].core_class,
				"no preset armed changes nothing")


func test_a_pick_equal_to_the_preset_still_resolves_independently() -> void:
	var ai := _make_ai(2)
	var parts: Array[Participant] = [ai]
	var picked := {2: _BASIC_ENEMY}

	_resolve_cores(parts, picked, _BASIC_ENEMY)
	assert_eq(ai.core_class, _BASIC_ENEMY, "premise: the pick and the preset coincide")

	_resolve_cores(parts, picked, _NINJA)

	assert_eq(ai.core_class, _BASIC_ENEMY,
			"tracked as its own state — it does not follow the preset's move")


func test_setting_the_preset_templates_every_live_ai_seat() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	roster.set_preset_core(_SERPENT)
	for p in roster.participants:
		if p.kind == Participant.Kind.AI:
			assert_eq(p.core_class, _SERPENT)
		else:
			assert_eq(p.core_class, _BALANCED, "the human is never templated")


func test_a_seat_with_an_explicit_core_reads_as_overridden_until_reset() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	var ai: Participant = roster.participants[1]
	assert_false(roster.is_core_overridden(ai))

	roster.pick_core(ai, _BALANCED)
	assert_true(roster.is_core_overridden(ai),
			"a pick equal to the default is still an override — provenance, not value")

	roster.set_preset_core(_SERPENT)
	assert_eq(ai.core_class, _BALANCED, "the override does not follow the preset")
	roster.reset_core(ai)
	assert_false(roster.is_core_overridden(ai))
	assert_eq(ai.core_class, _SERPENT, "cleared, it follows the preset again")


func test_the_resolve_walks_the_declared_field_list_and_nothing_else() -> void:
	# #1083: one rule over every templated field. Appending an entry (here
	# `camp` for #884, `ai_tier` for #1086) plus a nullable Pick field is the
	# whole change.
	assert_eq(LobbyRoster.TEMPLATED_FIELDS,
			{&"core": &"core_class", &"camp": &"camp", &"ai_tier": &"ai_tier"})
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	for dead in [&"_resolve_cores", &"_picked_cores", &"apply_core_preset"]:
		assert_false(roster.has_method(dead), "no per-field resolve: %s" % dead)

	var human := _make_human(1)
	human.camp = _PLAYER_FACTION
	var ai := _make_ai(2)
	var picked_ai := _make_ai(3)
	var parts: Array[Participant] = [human, ai, picked_ai]
	var preset := LobbyRoster.Pick.new()
	preset.core = _SERPENT
	preset.camp = _CAMP_2
	var pick := LobbyRoster.Pick.new()
	pick.camp = _CAMP_1
	var human_default := LobbyRoster.Pick.new()
	human_default.camp = _PLAYER_FACTION
	LobbyRoster.resolve_templated(parts, {3: pick}, preset, {1: human_default})

	assert_eq(ai.camp, _CAMP_2, "an appended field is templated by the preset")
	assert_eq(picked_ai.camp, _CAMP_1, "and a pick on it wins")
	assert_eq(picked_ai.core_class, _SERPENT, "per field: the camp pick leaves core on the preset")
	assert_eq(human.camp, _PLAYER_FACTION, "the human keeps its default")


# --- rebuild survival: an AI-count change never loses a pick -----------------

func test_shrink_then_grow_ai_count_keeps_the_core_override() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	roster.set_ai_opponents(5)
	var target: Participant = roster.participants[roster.participants.size() - 1]
	assert_eq(target.kind, Participant.Kind.AI, "premise: the last slot is an AI")
	roster.pick_core(target, _NINJA)
	var target_id := target.id

	roster.set_ai_opponents(4)
	assert_null(roster.by_id(target_id), "premise: the seat was dropped")
	roster.set_ai_opponents(5)

	var reseated := roster.by_id(target_id)
	assert_not_null(reseated, "the id that was dropped comes back on the regrow")
	assert_eq(reseated.core_class, _NINJA, "and its override rides along")


func test_a_camp_pick_survives_an_ai_count_change() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(0), _POLICY_HOTSEAT)
	var ai: Participant = roster.participants[2]
	assert_eq(ai.kind, Participant.Kind.AI, "premise: the third slot is an AI")

	assert_true(roster.pick_camp(ai, _CAMP_2))
	roster.set_ai_opponents(3)

	assert_eq(roster.participants[2].camp, _CAMP_2, "the pick survived")
	assert_eq(roster.to_run_config().participants[2].camp, _CAMP_2,
			"and START hands it to the level")


func test_picking_the_camp_a_seat_already_holds_still_records_the_pick() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	var ai: Participant = roster.participants[1]
	assert_eq(ai.kind, Participant.Kind.AI, "premise: the second slot is an AI")

	assert_true(roster.pick_camp(ai, ai.camp),
			"a value-coincident pick is still a pick — provenance, not value")
	assert_eq(roster._pick_of(ai.id).camp, ai.camp, "and it is recorded")


func test_a_colour_and_a_name_pick_survive_an_ai_count_change() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.COOP_HOTSEAT)
	var mine: Participant = roster.participants[0]
	var free_color: Color = _PALETTE.colors[_PALETTE.size() - 1]
	roster.pick_color(mine, free_color)
	roster.pick_name(mine, "  Bramh  ")

	roster.set_ai_opponents(2)

	var rebuilt := roster.by_id(mine.id)
	assert_eq(rebuilt.color, free_color)
	assert_eq(rebuilt.display_name, "Bramh")


func test_a_rebuild_emits_changed_once() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	watch_signals(roster)
	roster.set_ai_opponents(2)
	assert_signal_emit_count(roster, "changed", 1)


# --- names -------------------------------------------------------------------

func test_normalize_name_trims_and_caps() -> void:
	assert_eq(LobbyRoster.normalize_name("  Bob  "), "Bob")
	assert_eq(LobbyRoster.normalize_name("   "), "")
	var long_name := "x".repeat(LobbyRoster.MAX_NAME_LENGTH + 10)
	assert_eq(LobbyRoster.normalize_name(long_name).length(), LobbyRoster.MAX_NAME_LENGTH,
			"a remote pick meets the same cap the field's max_length enforces locally")


func test_an_empty_or_unchanged_name_pick_writes_nothing() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE)
	var mine: Participant = roster.participants[0]
	assert_false(roster.pick_name(mine, "   "))
	assert_eq(mine.display_name, "Player 1")
	assert_false(roster.pick_name(mine, "Player 1"), "unchanged is not a write")


func test_a_fresh_offline_roster_seeds_the_saved_default_name() -> void:
	Settings.current.player_name = "Bramh"

	var single := LobbyRoster.build_participants(RunConfig.Mode.SINGLE, null, 0)
	assert_eq(single[0].display_name, "Bramh", "single-player's one human is unambiguously me")

	var hotseat := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 0)
	assert_eq(hotseat[0].display_name, "Bramh", "hot-seat's first slot is still me")
	assert_eq(hotseat[1].display_name, "Player 2",
			"the second slot is a guest on this machine — no saved identity to seed it with")


func test_no_saved_name_falls_back_to_the_authored_default() -> void:
	assert_eq(Settings.current.player_name, "", "sanity: nothing saved yet")
	var parts := LobbyRoster.build_participants(RunConfig.Mode.SINGLE, null, 0)
	assert_eq(parts[0].display_name, "Player 1")


func test_hosting_seeds_the_saved_name_but_joining_does_not() -> void:
	Settings.current.player_name = "Bramh"

	var hosting := LobbyRoster.build_participants(
			RunConfig.Mode.SINGLE, NetworkConfig.host(0), 0)
	assert_eq(hosting[0].display_name, "Bramh", "the host's own seat is never thrown away")

	var joining := LobbyRoster.build_participants(
			RunConfig.Mode.SINGLE, NetworkConfig.join("127.0.0.1", 0), 0)
	assert_eq(joining[0].display_name, "Player 1",
			"the client's placeholder roster is not worth seeding")


# --- seat-policy vetoes and START ----------------------------------------------

func test_may_edit_is_the_one_locality_rule() -> void:
	var mine := _make_human(1)
	mine.peer_id = 7
	var theirs := _make_human(2)
	theirs.peer_id = 8
	var ai := _make_ai(3)
	assert_true(LobbyRoster.may_edit(mine, 7, false))
	assert_false(LobbyRoster.may_edit(theirs, 7, true))
	assert_true(LobbyRoster.may_edit(ai, 7, true), "an AI seat belongs to the roster's author")
	assert_false(LobbyRoster.may_edit(ai, 7, false), "and a client does not author it")
	assert_false(LobbyRoster.may_edit(null, 7, true))


func test_may_edit_remotely_is_own_seat_only() -> void:
	var seat := _make_human(2)
	seat.peer_id = 4
	assert_false(LobbyRoster.may_edit_remotely(seat, 0))
	assert_false(LobbyRoster.may_edit_remotely(null, 4))
	assert_true(LobbyRoster.may_edit_remotely(seat, 4))
	assert_false(LobbyRoster.may_edit_remotely(seat, 5))
	assert_false(LobbyRoster.may_edit_remotely(_make_ai(3), 4), "no peer edits an AI seat")


func test_a_versus_roster_refuses_a_start_where_every_human_shares_a_camp() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.host(0), _POLICY_VERSUS)
	assert_true(roster.can_start(), "authored on two camps, START is open")

	roster.pick_camp(roster.participants[1], _CAMP_1)

	assert_false(roster.can_start())
	assert_false(roster.start_blocked_reason().is_empty(), "and it says why")


func test_a_connecting_peer_blocks_start_until_cleared_or_gone() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.host(0), _POLICY_VERSUS)
	roster.add_remote(9)
	assert_false(roster.can_start(), "#736: a socket mid-handshake is not a seat")

	roster.remove_remote(9)
	assert_true(roster.can_start())

	roster.add_remote(9)
	assert_true(roster.clear_remote(9, {"display_name": "  Guest  "}))
	assert_true(roster.can_start())
	assert_eq(roster.participants[1].peer_id, 9, "the pending seat was stamped")
	assert_eq(roster.participants[1].display_name, "Guest", "with the name the joiner offered")


func test_a_leaving_peer_frees_its_seat_back_to_pending() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.host(0), _POLICY_VERSUS)
	roster.clear_remote(9)
	assert_false(roster.has_pending_remote())

	assert_true(roster.remove_remote(9))
	assert_true(roster.has_pending_remote())
	assert_false(roster.remove_remote(9), "nothing left to free")


func test_a_rebuild_keeps_a_seated_peer_in_its_seat() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.host(0), _POLICY_VERSUS)
	roster.clear_remote(9)

	roster.set_ai_opponents(1)

	assert_eq(roster.participants[1].peer_id, 9,
			"the AI-count slider must not un-seat a friend who already joined")


func test_a_remote_pick_lands_only_on_the_askers_own_seat() -> void:
	var roster := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.host(0), _POLICY_VERSUS)
	roster.clear_remote(9)
	var theirs := roster.participants[1]
	var mine := roster.participants[0]
	var free_color: Color = _PALETTE.colors[_PALETTE.size() - 1]

	assert_true(roster.apply_remote_pick(
			LobbyRoster.encode_pick(theirs, 9, {"color": free_color, "display_name": "Guest"})))
	assert_eq(theirs.color, free_color)
	assert_eq(theirs.display_name, "Guest")

	var before := mine.color
	assert_false(roster.apply_remote_pick(
			LobbyRoster.encode_pick(mine, 9, {"color": _PALETTE.colors[0]})))
	assert_eq(mine.color, before, "somebody else's seat is refused")


func test_encode_pick_carries_resources_by_path() -> void:
	var pick := LobbyRoster.encode_pick(_make_human(2), 9, {"core_class": _NINJA, "color": Color.RED})
	assert_eq(pick[LobbyRoster.PICK_ID], 2)
	assert_eq(pick[LobbyRoster.PICK_PEER], 9)
	assert_eq(pick["core_class"], _NINJA.resource_path)
	assert_eq(pick["color"], Color.RED)


func test_adopting_a_broadcast_replaces_the_placeholder_roster() -> void:
	var client := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.join("127.0.0.1", 0))
	var host := LobbyRoster.new(RunConfig.Mode.VERSUS, NetworkConfig.host(0), _POLICY_VERSUS)
	host.set_ai_opponents(3)

	client.adopt(host.to_participant_roster())

	assert_eq(client.participants.size(), host.participants.size())
	assert_eq(client.participants[4].display_name, host.participants[4].display_name)


# --- #884: single-player camps — the Siege by default, split on request -------

func _sp_roster(ai_count: int = 3) -> LobbyRoster:
	var roster := LobbyRoster.new(RunConfig.Mode.SINGLE, null, _POLICY_SINGLE)
	roster.set_ai_opponents(ai_count)
	return roster


func _ais(roster: LobbyRoster) -> Array[Participant]:
	var out: Array[Participant] = []
	for p in roster.participants:
		if p.kind == Participant.Kind.AI:
			out.append(p)
	return out


func test_the_sp_policy_offers_the_six_camp_pool_to_ai_seats_only() -> void:
	var pool := _POLICY_SINGLE.camp_choices()
	assert_eq(pool.size(), LobbyPolicy.MAX_CAMPS, "npc, player, camp_1..4")
	assert_eq(pool[0], _NPC_FACTION, "the bloc heads the pool")
	assert_true(pool.has(_PLAYER_FACTION), "the Warband: an AI may join the player")
	assert_true(_POLICY_SINGLE.may_pick_camp(Participant.Kind.AI))
	assert_false(_POLICY_SINGLE.may_pick_camp(Participant.Kind.HUMAN),
			"the human stays on player.tres")


func test_an_untouched_sp_roster_is_the_siege() -> void:
	var roster := _sp_roster()
	assert_eq(roster.participants[0].camp, _PLAYER_FACTION)
	for ai in _ais(roster):
		assert_eq(ai.camp, _NPC_FACTION, "every AI on the one enemy bloc")
		assert_false(roster.is_camp_overridden(ai))


func test_a_camp_preset_moves_every_unpicked_ai_but_never_the_human() -> void:
	var roster := _sp_roster()
	roster.set_preset_camp(_CAMP_2)
	for ai in _ais(roster):
		assert_eq(ai.camp, _CAMP_2)
	assert_eq(roster.participants[0].camp, _PLAYER_FACTION, "the human is never templated")

	roster.set_preset_camp(null)
	for ai in _ais(roster):
		assert_eq(ai.camp, _NPC_FACTION, "the sentinel disarms back to the bloc")


func test_a_warband_pick_survives_preset_and_ai_count_changes() -> void:
	var roster := _sp_roster()
	var ally: Participant = _ais(roster)[0]
	var ally_id := ally.id
	assert_true(roster.pick_camp(ally, _PLAYER_FACTION))

	roster.set_preset_camp(_CAMP_2)
	assert_eq(roster.by_id(ally_id).camp, _PLAYER_FACTION, "the pick does not follow the preset")
	roster.set_ai_opponents(4)
	assert_eq(roster.by_id(ally_id).camp, _PLAYER_FACTION, "nor does a rebuild drop it")
	assert_eq(_ais(roster)[3].camp, _CAMP_2, "a newly seated AI follows the preset")


func test_reset_camp_resumes_the_preset() -> void:
	var roster := _sp_roster()
	var ai: Participant = _ais(roster)[1]
	roster.pick_camp(ai, _CAMP_1)
	roster.set_preset_camp(_CAMP_2)
	assert_true(roster.is_camp_overridden(ai))

	assert_true(roster.reset_camp(ai))
	assert_false(roster.is_camp_overridden(ai))
	assert_eq(ai.camp, _CAMP_2)
	assert_false(roster.reset_camp(ai), "nothing left to reset")


func test_picking_the_held_camp_reads_overridden() -> void:
	var roster := _sp_roster()
	var ai: Participant = _ais(roster)[0]
	roster.pick_camp(ai, _NPC_FACTION)
	assert_true(roster.is_camp_overridden(ai), "provenance, not value coincidence")
	roster.set_preset_camp(_CAMP_2)
	assert_eq(ai.camp, _NPC_FACTION, "so it stays put when the preset moves")


func test_an_sp_warband_spawns_allied_to_the_human_and_a_camp_ai_hostile() -> void:
	var roster := _sp_roster(2)
	var ais := _ais(roster)
	roster.pick_camp(ais[0], _CAMP_1)
	roster.pick_camp(ais[1], _PLAYER_FACTION)
	var human_ent: Entity = autofree(Entity.new())
	var raider: Entity = autofree(Entity.new())
	var ally: Entity = autofree(Entity.new())

	GameRoot.apply_roster(
			{roster.participants[0].id: human_ent, ais[0].id: raider, ais[1].id: ally},
			roster.to_participant_roster())

	assert_eq(raider.faction, _CAMP_1)
	assert_eq(ally.faction, _PLAYER_FACTION)
	assert_eq(human_ent.attitude_to(ally), Entity.Attitude.ALLIED, "the Warband is an ally")
	assert_eq(human_ent.attitude_to(raider), Entity.Attitude.HOSTILE)
	assert_eq(raider.attitude_to(ally), Entity.Attitude.HOSTILE)


# --- #1086: the AI tier — one knob in the preset row, one override per AI row --

func test_an_untouched_roster_seats_every_ai_on_the_default_tier() -> void:
	var roster := _sp_roster()
	for ai in _ais(roster):
		assert_eq(ai.ai_tier, AIController.DEFAULT_TIER)
		assert_false(roster.is_tier_overridden(ai))


func test_a_tier_preset_templates_every_unpicked_ai_but_never_the_human() -> void:
	var roster := _sp_roster()
	roster.set_preset_tier(AIController.Tier.WARLORD)
	for ai in _ais(roster):
		assert_eq(ai.ai_tier, AIController.Tier.WARLORD)
	assert_eq(roster.participants[0].ai_tier, AIController.DEFAULT_TIER,
			"the human is never templated")

	roster.set_preset_tier(null)
	for ai in _ais(roster):
		assert_eq(ai.ai_tier, AIController.DEFAULT_TIER, "the sentinel disarms to the default")


func test_a_tier_pick_survives_preset_and_ai_count_changes() -> void:
	var roster := _sp_roster()
	var picked: Participant = _ais(roster)[0]
	var picked_id := picked.id
	assert_true(roster.pick_tier(picked, AIController.Tier.BRAWLER))

	roster.set_preset_tier(AIController.Tier.WARLORD)
	assert_eq(roster.by_id(picked_id).ai_tier, AIController.Tier.BRAWLER,
			"the pick does not follow the preset")
	roster.set_ai_opponents(4)
	assert_eq(roster.by_id(picked_id).ai_tier, AIController.Tier.BRAWLER,
			"nor does a rebuild drop it")
	assert_eq(_ais(roster)[3].ai_tier, AIController.Tier.WARLORD,
			"a newly seated AI follows the preset")


func test_reset_tier_resumes_the_preset() -> void:
	var roster := _sp_roster()
	var ai: Participant = _ais(roster)[1]
	roster.pick_tier(ai, AIController.Tier.BRAWLER)
	roster.set_preset_tier(AIController.Tier.WARLORD)
	assert_true(roster.is_tier_overridden(ai))

	assert_true(roster.reset_tier(ai))
	assert_false(roster.is_tier_overridden(ai))
	assert_eq(ai.ai_tier, AIController.Tier.WARLORD)
	assert_false(roster.reset_tier(ai), "nothing left to reset")


func test_a_tier_pick_equal_to_the_preset_still_reads_overridden() -> void:
	var roster := _sp_roster()
	var ai: Participant = _ais(roster)[0]
	roster.set_preset_tier(AIController.Tier.WARLORD)
	roster.pick_tier(ai, AIController.Tier.WARLORD)
	assert_true(roster.is_tier_overridden(ai), "provenance, not value coincidence")
	roster.set_preset_tier(AIController.Tier.FIGHTER)
	assert_eq(ai.ai_tier, AIController.Tier.WARLORD, "so it stays put when the preset moves")


## A hand-built seat has no recorded default: an unarmed tier must still land
## on the kind default, never on a null the AI factory would read as BRAWLER.
func test_a_hand_built_seat_with_no_default_resolves_to_the_default_tier() -> void:
	var ai := _make_ai(7)
	ai.ai_tier = AIController.Tier.BRAWLER
	var human := _make_human(1)
	var parts: Array[Participant] = [human, ai]
	LobbyRoster.resolve_templated(parts, {}, LobbyRoster.Pick.new())
	assert_eq(ai.ai_tier, AIController.DEFAULT_TIER)
	assert_eq(human.ai_tier, AIController.DEFAULT_TIER)


func test_a_tier_pick_crosses_the_wire_as_an_int_through_the_pick_writers() -> void:
	var roster := _sp_roster()
	var ai: Participant = _ais(roster)[0]
	var encoded := LobbyRoster.encode_pick(ai, 1, {"ai_tier": AIController.Tier.BRAWLER})
	assert_eq(encoded["ai_tier"], AIController.Tier.BRAWLER)
	assert_false(roster.apply_remote_pick(encoded),
			"an AI seat is never a peer's to edit, tier included")
	assert_eq(ai.ai_tier, AIController.DEFAULT_TIER)
