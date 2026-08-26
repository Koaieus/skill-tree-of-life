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


# --- #618: the slot picks a core class, the sigil rides along --------------

const _NINJA := preload("res://entity/core/ninja_core.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")


func _row_for(p: Participant) -> ParticipantRow:
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(p, 0)
	row.set_core_choices(CoreClass.pickable_for(LobbyScreen.slot_bit_for(p.kind)))
	return row


func test_the_row_renders_the_sigil_of_the_selected_class() -> void:
	var parts := LobbyScreen.build_participants(RunConfig.Mode.SINGLE, null, 0)
	var human: Participant = parts[0]
	var row := _row_for(human)

	var glyph: SigilGlyph = row.get_node("%Sigil")
	assert_eq(glyph.sigil, _BALANCED.sigil, "the default class's own sigil")

	var pick: OptionButton = row.get_node("%CorePick")
	var ninja_index := -1
	for i in pick.item_count:
		if pick.get_item_metadata(i) == _NINJA:
			ninja_index = i
	assert_gte(ninja_index, 0, "ninja is offered in a human slot")

	pick.item_selected.emit(ninja_index)
	assert_eq(glyph.sigil, _NINJA.sigil, "picking a class repaints the sigil")


func test_the_row_renders_a_class_that_has_no_sigil() -> void:
	# #618 D4, revisited: every authored CoreClass now carries a sigil, so the
	# empty-glyph fallback is exercised with a synthetic CoreClass rather than
	# a real preset — the row must show an empty glyph rather than misbehave.
	var no_sigil_core := CoreClass.new()
	no_sigil_core.display_name = "No Sigil"

	var ai := Participant.new()
	ai.id = 9
	ai.kind = Participant.Kind.AI
	ai.core_class = no_sigil_core
	assert_null(no_sigil_core.sigil, "premise: this core carries no glyph")

	var row := _row_for(ai)
	assert_null(row.get_node("%Sigil").sigil, "and the row is fine with that")
	assert_eq(row.get_node("%Seat").text, "AI")


func test_a_human_slot_is_never_offered_the_enemy_core() -> void:
	var parts := LobbyScreen.build_participants(RunConfig.Mode.SINGLE, null, 1)
	var human_row := _row_for(parts[0])
	var ai_row := _row_for(parts[1])

	var offered := func(row: ParticipantRow) -> Array:
		var pick: OptionButton = row.get_node("%CorePick")
		var out: Array = []
		for i in pick.item_count:
			out.append(pick.get_item_metadata(i))
		return out

	assert_false(offered.call(human_row).has(_BASIC_ENEMY), "AI-only core")
	assert_false(offered.call(ai_row).has(_BALANCED), "player-only core")
	assert_true(offered.call(human_row).has(_NINJA), "shared cores reach both")
	assert_true(offered.call(ai_row).has(_NINJA))


func test_picking_a_class_writes_it_onto_the_roster() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	var human: Participant = lobby.participants()[0]
	assert_eq(human.core_class, _BALANCED, "seated on the default first")

	lobby._on_core_class_picked(_NINJA, human)

	assert_eq(human.core_class, _NINJA)
	assert_eq(lobby.build_run_config().participants[0].core_class, _NINJA,
			"and START hands the pick to the level")

# --- #615: a LobbyPolicy on the route decides who may pick a camp ------------

const _CAMP_2 := preload("res://entity/factions/camp_2.tres")
const _POLICY_SINGLE := preload("res://ui/frontmatter/policies/lobby_policy_single.tres")
const _POLICY_HOTSEAT := preload("res://ui/frontmatter/policies/lobby_policy_hotseat.tres")
const _POLICY_VERSUS := preload("res://ui/frontmatter/policies/lobby_policy_versus.tres")


func _policied_lobby(
	mode: RunConfig.Mode, policy: LobbyPolicy, network: NetworkConfig = null
) -> LobbyScreen:
	var lobby := LobbyScreen.new()
	lobby.configure(mode, network, policy)
	add_child_autofree(lobby)
	return lobby


func _camp_picks(lobby: LobbyScreen) -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	for row in lobby._rows_container.get_children():
		out.append(row.get_node("%Camp") as OptionButton)
	return out


## #615 acceptance 3, the characterization half: without a policy the lobby is
## byte-for-byte what it was before this issue — no camp control on any row, and
## START refused by nothing. This is the assertion that lets a route be authored
## with a null policy.
func test_a_null_policy_reproduces_todays_lobby_exactly() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)

	for pick in _camp_picks(lobby):
		assert_false(pick.visible, "no policy, no camp control")
		assert_eq(pick.item_count, 0, "and nothing was ever put in it")

	assert_true(lobby.can_start(), "nothing blocks START without a policy")
	assert_eq(lobby.start_blocked_reason(), "")
	var cfg := lobby.build_run_config()
	assert_eq(cfg.mode, RunConfig.Mode.COOP_HOTSEAT)
	var humans := _humans(cfg.participants)
	assert_eq(humans.size(), 2)
	assert_eq(humans[0].camp, _CAMP_1)
	assert_eq(humans[1].camp, _CAMP_1, "the pre-#615 hot-seat roster, unchanged")


## #615 acceptance 1. The control is SHOWN and disabled rather than absent, so
## the rule is visible; and D6's invariant holds by construction — both humans
## are still on `camp_1`, so `resolve_mode` still answers coop.
func test_a_hot_seat_policy_locks_the_camp_on_both_human_rows() -> void:
	var lobby := _policied_lobby(RunConfig.Mode.COOP_HOTSEAT, _POLICY_HOTSEAT)
	var parts := lobby.participants()

	var humans := _humans(parts)
	assert_eq(humans.size(), 2, "premise: a hot-seat lobby seats two humans")
	for i in humans.size():
		var pick: OptionButton = lobby._rows_container.get_child(i).get_node("%Camp")
		assert_true(pick.visible, "the rule is shown, not hidden")
		assert_true(pick.disabled, "a hot-seat human may not change camp")

	assert_false(_POLICY_HOTSEAT.may_pick_camp(Participant.Kind.HUMAN))
	assert_true(_POLICY_HOTSEAT.may_pick_camp(Participant.Kind.AI),
			"locking the players together does not lock the opponents")
	assert_eq(LobbyScreen.resolve_mode(parts), RunConfig.Mode.COOP_HOTSEAT,
			"#615 D6: the mode is still derived, and still coop")
	assert_true(lobby.can_start())


## #615 acceptance 2. A versus lobby whose humans all share a camp has no
## opposing side — `resolve_mode` would quietly answer COOP_HOTSEAT — so the
## policy refuses START rather than letting a coop run out of a versus route.
func test_a_versus_policy_refuses_a_start_where_every_human_shares_a_camp() -> void:
	var lobby := _policied_lobby(
			RunConfig.Mode.COOP_HOTSEAT, _POLICY_VERSUS, NetworkConfig.host())
	var humans := _humans(lobby.participants())
	assert_eq(humans[0].camp, _CAMP_1)
	assert_eq(humans[1].camp, _CAMP_2, "premise: a host lobby seats two camps")
	assert_true(lobby.can_start(), "two camps is a legal versus start")

	lobby._on_camp_picked(_CAMP_1, humans[1])

	assert_false(lobby.can_start(), "one camp between them is not versus")
	assert_ne(lobby.start_blocked_reason(), "", "and it says why")
	assert_true(lobby._start_button.disabled, "the button follows the veto")

	var fired: Array[int] = []
	lobby.start_pressed.connect(func(_cfg: RunConfig): fired.append(1))
	lobby._start_button.pressed.emit()
	assert_eq(fired.size(), 0, "pressing it anyway starts nothing")

	lobby._on_camp_picked(_CAMP_2, humans[1])
	assert_true(lobby.can_start(), "and moving back off it lifts the veto")


## #615 acceptance 3, the authoring half: every route that opens a lobby names a
## policy, on the ROUTE (D2) rather than in a mode table.
func test_every_lobby_route_carries_a_policy() -> void:
	var tree := MenuGraph.build()
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL, MenuGraph.ID_HOST]:
		var item := tree.get_item(id)
		assert_eq(item.panel, MenuGraph.PANEL_LOBBY, "'%s' opens a lobby" % id)
		assert_not_null(item.route.lobby_policy, "'%s' names a policy" % id)
	# JOIN reaches the same lobby through #531's address screen, so it must agree
	# with HOST about what that lobby is.
	assert_eq(tree.get_item(MenuGraph.ID_JOIN).route.lobby_policy,
			tree.get_item(MenuGraph.ID_HOST).route.lobby_policy,
			"both ends of one link show the same lobby")
	assert_null(tree.get_item(MenuGraph.ID_OPTIONS).route,
			"and a leaf that opens no lobby carries no route to hang one on")


## #615 acceptance 4 / D5. The bound has zero headroom: the picker may never
## offer more camps than `entity/factions/` actually holds.
func test_the_camp_picker_never_offers_more_camps_than_exist() -> void:
	var on_disk := 0
	for file in DirAccess.get_files_at("res://entity/factions"):
		if file.begins_with("camp_") and file.ends_with(".tres"):
			on_disk += 1
	assert_eq(on_disk, LobbyPolicy.MAX_CAMPS,
			"D5: camp_1..camp_6, and the bound is that number")

	var policies: Array[LobbyPolicy] = [_POLICY_SINGLE, _POLICY_HOTSEAT, _POLICY_VERSUS]
	for policy in policies:
		var choices := policy.camp_choices()
		assert_lte(choices.size(), on_disk, "no policy offers a camp that isn't there")
		var seen: Array[Faction] = []
		for camp in choices:
			assert_false(seen.has(camp), "and none is offered twice")
			seen.append(camp)

	# The ceiling is enforced by the policy, not merely by what was authored.
	var greedy := LobbyPolicy.new()
	greedy.camps = _POLICY_VERSUS.camps.duplicate()
	greedy.max_distinct_camps = 99
	assert_lte(greedy.camp_choices().size(), LobbyPolicy.MAX_CAMPS,
			"max_distinct_camps is clamped to MAX_CAMPS")


func test_a_single_player_policy_shows_no_camp_control_at_all() -> void:
	# The solo human is on `player.tres` and every AI shares `npc.tres`; there is
	# no camp choice to make, so the column stays out of the row entirely.
	var lobby := _policied_lobby(RunConfig.Mode.SINGLE, _POLICY_SINGLE)
	assert_true(_POLICY_SINGLE.camp_choices().is_empty())
	assert_false(_POLICY_SINGLE.may_pick_camp(Participant.Kind.HUMAN))
	for pick in _camp_picks(lobby):
		assert_false(pick.visible)
	assert_true(lobby.can_start())


func test_a_camp_pick_survives_an_ai_count_change() -> void:
	# Same rebuild-survival contract as #616's colours: changing the AI count
	# rebuilds the roster from scratch, and a pick must not silently revert.
	var lobby := _policied_lobby(
			RunConfig.Mode.COOP_HOTSEAT, _POLICY_HOTSEAT, NetworkConfig.host())
	var ai: Participant = lobby.participants()[2]
	assert_eq(ai.kind, Participant.Kind.AI, "premise: the third slot is an AI")

	lobby._on_camp_picked(_CAMP_2, ai)
	lobby._ai_count_row.value = 3

	assert_eq(lobby.participants()[2].camp, _CAMP_2, "the pick survived")
	assert_eq(lobby.build_run_config().participants[2].camp, _CAMP_2,
			"and START hands it to the level")


func test_a_locked_slot_still_shows_the_camp_it_actually_holds() -> void:
	# An AI sits on `npc.tres`, which is not in any policy's pool. The dropdown
	# must show that rather than lie by selecting the pool's first entry.
	var ai := Participant.new()
	ai.id = 9
	ai.kind = Participant.Kind.AI
	ai.camp = preload("res://entity/factions/npc.tres")
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(ai, 0)
	row.set_camp_choices(_POLICY_VERSUS.camp_choices(), false)

	var pick: OptionButton = row.get_node("%Camp")
	assert_true(pick.visible)
	assert_true(pick.disabled)
	assert_eq(pick.get_item_metadata(pick.selected), ai.camp,
			"the shown camp is the one the slot is on")

# --- #617: a faction carries an emblem, and the row shows it -----------------

## #617 acceptance 1. Every camp on disk is authored with a mark that actually
## resolves — an unset one is not an error at load, it is an empty box at the
## far left of a lobby row, which nothing else would catch.
func test_every_faction_is_authored_with_an_emblem_that_loads() -> void:
	var seen := 0
	for file in DirAccess.get_files_at("res://entity/factions"):
		if not file.ends_with(".tres"):
			continue
		seen += 1
		var faction: Faction = load("res://entity/factions/%s" % file)
		assert_not_null(faction, "%s is a Faction" % file)
		assert_not_null(faction.emblem, "%s names an emblem" % file)
		assert_gt(faction.emblem.get_width(), 0, "%s's emblem is a real texture" % file)
	assert_eq(seen, 9, "camp_1..6 plus player, npc and blocker")


## #617 D1: the emblem identifies the CAMP, so no two camps may share one — six
## slots showing the same silhouette would be worse than none.
func test_no_two_factions_share_an_emblem() -> void:
	var seen: Array[Texture2D] = []
	for file in DirAccess.get_files_at("res://entity/factions"):
		if not file.ends_with(".tres"):
			continue
		var faction: Faction = load("res://entity/factions/%s" % file)
		assert_false(seen.has(faction.emblem), "%s's emblem is its own" % file)
		seen.append(faction.emblem)


## #617 acceptance 2.
func test_the_row_renders_the_emblem_of_the_slots_faction() -> void:
	var p := Participant.new()
	p.id = 1
	p.camp = _CAMP_1
	p.color = Color.CYAN
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(p, 0)

	var mark: TextureRect = row.get_node("%Emblem")
	assert_eq(mark.texture, _CAMP_1.emblem, "camp_1's own mark")
	assert_eq(mark.modulate, _CAMP_1.color,
			"tinted by the CAMP, not the hero — the swatch answers that question")
	assert_ne(mark.modulate, p.color)


func test_the_row_survives_a_slot_with_no_camp() -> void:
	# A Participant is constructible without one, and an empty box of the same
	# size is the correct answer — same contract the sigil keeps for a core
	# class that carries no glyph.
	var p := Participant.new()
	p.id = 1
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(p, 0)
	assert_null(row.get_node("%Emblem").texture)


## #617 D4 meets #615: the emblem is display, and the camp dropdown is what
## moves it. Picking a camp must repaint the mark in the same gesture.
func test_picking_a_camp_repaints_the_emblem() -> void:
	var p := Participant.new()
	p.id = 1
	p.camp = _CAMP_1
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(p, 0)
	row.set_camp_choices(_POLICY_VERSUS.camp_choices(), true)

	var pick: OptionButton = row.get_node("%Camp")
	var camp_2_index := -1
	for i in pick.item_count:
		if pick.get_item_metadata(i) == _CAMP_2:
			camp_2_index = i
	assert_gte(camp_2_index, 0, "camp_2 is offered")

	pick.item_selected.emit(camp_2_index)
	assert_eq(row.get_node("%Emblem").texture, _CAMP_2.emblem)
