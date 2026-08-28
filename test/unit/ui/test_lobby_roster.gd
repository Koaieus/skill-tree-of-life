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


# --- #639: default colours stride the palette instead of walking it -------

## OKLab dE (Euclidean distance in OKLab) — the same Björn Ottosson formulas
## the palette's own docstring cites, and the same yardstick the issue's dE
## table was measured with. No runtime code needs this conversion (the
## implementation only needs `gcd`), so it lives here, local to the test that
## states the acceptance criteria in these units — not a second copy of
## anything `default_for` does. Not gameplay code, so
## `.claude/rules/multiplayer-sync.md`'s ban on transcendentals in
## gameplay/stat formulas doesn't apply: this `pow()` never leaves this test
## file.
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
	# The reported symptom: the first 3 slots landed within 31 degrees of hue.
	var swatches: Array[Color] = []
	for i in 3:
		swatches.append(_PALETTE.default_for(i))
	_assert_pairwise_separated(swatches, 0.14, "3-slot roster")


func test_a_six_slot_rosters_default_colours_are_pairwise_separated() -> void:
	# 2 humans + 4 AI — the widest roster the lobby can author (#616).
	var swatches: Array[Color] = []
	for i in 6:
		swatches.append(_PALETTE.default_for(i))
	_assert_pairwise_separated(swatches, 0.14, "6-slot roster")


func test_the_shipped_stride_is_coprime_with_the_shipped_palette_size() -> void:
	assert_eq(PlayerPalette.gcd(PlayerPalette.DEFAULT_STRIDE, _PALETTE.size()), 1,
			"#639: this is what lets the stride cycle every colour before repeating")
	assert_eq(PlayerPalette.effective_stride(_PALETTE.size()), PlayerPalette.DEFAULT_STRIDE)


func test_a_non_coprime_palette_size_falls_back_to_the_old_walk() -> void:
	# 34 = 2 * 17 shares a factor with the stride — the exact trap the issue
	# calls out: gcd(17, 34) is 17, not 1.
	assert_eq(PlayerPalette.gcd(PlayerPalette.DEFAULT_STRIDE, 34), 17,
			"premise: 34 is NOT coprime with the shipped stride")
	assert_eq(PlayerPalette.effective_stride(34), 1,
			"falls back to the old walk rather than collapsing onto gcd(17,34)=17 colours")

	var oversized := PlayerPalette.new()
	oversized.colors = []
	for i in 34:
		oversized.colors.append(Color(float(i) / 34.0, 0.5, 0.5))

	var seen: Array[Color] = []
	for i in 34:
		var c := oversized.default_for(i)
		assert_true(oversized.colors.has(c), "still a real palette entry, not a crash")
		assert_false(seen.has(c),
				"stride-1 fallback: no repeat before size() picks, same as today")
		seen.append(c)


func test_default_for_still_wraps_past_the_palette_size() -> void:
	for i in _PALETTE.size():
		assert_eq(_PALETTE.default_for(i), _PALETTE.default_for(i + _PALETTE.size()),
				"#639: the wrap contract holds under the strided walk too")


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


# --- #643 / #642 acceptance 5-6: the per-RUN section ------------------------
#
# The knobs a run is tuned with at the LAN, and the reason they exist, in the
# owner's words (2026-08-27): "so that i don't have to recompile + redistribute
# the game mid-lan if we want to tune runs". Every assertion below is ultimately
# about that sentence — a picker that does not reach the generated graph is
# worth nothing here.

const _MAP_SIZE_OPTIONS := preload("res://ui/frontmatter/lobby_options/map_size_options.tres")
const _BLOCKER_OPTIONS := preload("res://ui/frontmatter/lobby_options/blocker_options.tres")
const _FIRST_LEVEL_SCENARIO := preload("res://session/scenarios/first_level.tres")


## A policy that unlocks the whole run section AND names a Scenario, so
## `resolved_preset()` has a preset to merge onto. Built here rather than
## preloaded because #597 fork 3 (where a lobby's Scenario comes from) is still
## open — the shipped `.tres` deliberately leave `scenario` null, so a test that
## wants the end-to-end path has to supply one.
func _run_policy() -> LobbyPolicy:
	var policy := LobbyPolicy.new()
	policy.scenario = _FIRST_LEVEL_SCENARIO
	policy.map_size_options = _MAP_SIZE_OPTIONS
	policy.blocker_options = _BLOCKER_OPTIONS
	policy.budget_overridable = true
	return policy


func _run_section_lobby(policy: LobbyPolicy) -> LobbyScreen:
	return _policied_lobby(RunConfig.Mode.SINGLE, policy)


## #643 acceptance 2, the characterization half — matching the camp half's
## `test_a_null_policy_reproduces_todays_lobby_exactly` exactly in shape. A null
## policy renders NO run section at all, not an empty one.
func test_a_null_policy_renders_no_run_section_at_all() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)

	assert_null(lobby._run_section, "no policy, no run section")
	assert_null(lobby.find_child("RunSection", true, false),
			"and nothing named like one is in the tree either")

	var cfg := lobby.build_run_config()
	assert_eq(cfg.overrides.size(), 0, "and START writes no override")
	assert_null(cfg.scenario, "master's behaviour: a lobby run carries no Scenario")


## #643 acceptance 2, the gating half. A policy that unlocks nothing is not the
## same object as a null one, and must still render nothing.
func test_a_policy_that_unlocks_nothing_renders_no_run_section() -> void:
	var policy := LobbyPolicy.new()
	assert_false(policy.offers_run_section(), "premise: a bare policy unlocks nothing")
	assert_null(_run_section_lobby(policy)._run_section)


## #643 acceptance 2, the positive half — a fully-unlocked policy renders all
## three controls.
func test_an_unlocking_policy_renders_all_three_run_controls() -> void:
	var lobby := _run_section_lobby(_run_policy())

	assert_not_null(lobby._run_section, "the section exists")
	assert_not_null(lobby._map_size_row)
	assert_not_null(lobby._blocker_row)
	assert_not_null(lobby._budget_row)
	assert_true(lobby._map_size_row.visible)
	assert_true(lobby._blocker_row.visible)


## #643 acceptance 2, per-knob. Unlocking budget alone must not conjure the
## ladders — this is what lets #558 and #638 add controls that a route can
## unlock independently.
func test_each_knob_is_gated_independently() -> void:
	var policy := LobbyPolicy.new()
	policy.budget_overridable = true
	var lobby := _run_section_lobby(policy)

	assert_not_null(lobby._budget_row, "budget was unlocked")
	assert_null(lobby._map_size_row, "map size was not")
	assert_null(lobby._blocker_row, "nor blockers")


## #642 acceptance 6: order IS information. `DirAccess.get_files_at` would have
## returned `l, m, s, xl, xs, xxl`; the authored array is a ladder, and this is
## the assertion that keeps it one.
func test_the_map_size_ladder_is_authored_in_ascending_order() -> void:
	var labels: Array[String] = []
	var sizes: Array[int] = []
	for o in _MAP_SIZE_OPTIONS.choices():
		labels.append(o.label)
		assert_eq(o.patches.size(), 1, "'%s' patches exactly node_count" % o.label)
		assert_eq(o.patches[0].target, "topology:node_count")
		sizes.append(int(o.patches[0].value))

	assert_eq(labels, ["XS", "S", "M", "L", "XL", "XXL"] as Array[String],
			"the ladder reads as a sequence, not as an alphabetised directory")
	for i in range(1, sizes.size()):
		assert_gt(sizes[i], sizes[i - 1],
				"%s is a bigger map than %s" % [labels[i], labels[i - 1]])


## #642 acceptance 6 for the blocker ladder, and the trap it is really guarding:
## `blocker_per_small` is a DENOMINATOR (`floor(node_count / blocker_per_size)`),
## so MORE blockers means a SMALLER number. An ascending ladder here would ship a
## "Heavy" option that produced the fewest blockers on the map.
func test_the_blocker_ladder_descends_because_the_field_is_a_denominator() -> void:
	var choices := _BLOCKER_OPTIONS.choices()
	var labels: Array[String] = []
	for o in choices:
		labels.append(o.label)
	assert_eq(labels, ["None", "Few", "Regular", "Lots", "Heavy"] as Array[String])

	# "None" is the 0-disables-the-tier case and sits outside the ordering.
	for patch in choices[0].patches:
		assert_eq(int(patch.value), 0, "None disables every tier")

	var prev := -1
	for i in range(1, choices.size()):
		var small := 0
		for patch in choices[i].patches:
			if patch.target == "blockers:blocker_per_small":
				small = int(patch.value)
		assert_true(small > 0, "%s places blockers" % labels[i])
		if prev != -1:
			assert_lt(small, prev,
					"%s is DENSER than %s, so its denominator is smaller"
					% [labels[i], labels[i - 1]])
		prev = small


## #643 acceptance 5, and the reason the brief calls it out: this asserts the
## override list is EMPTY, never that a value happens to match the authored one.
## A silent no-op and a correct pass-through are indistinguishable by value.
func test_an_untouched_control_writes_no_override_at_all() -> void:
	var lobby := _run_section_lobby(_run_policy())
	var cfg := lobby.build_run_config()

	assert_eq(cfg.overrides.size(), 0,
			"nothing was picked, so nothing is overridden")
	assert_eq(lobby._map_size_row.get_value(), -1,
			"and the widget itself is in the no-pick state")

	# The authored preset is what a run with no picks generates from.
	var resolved := cfg.resolved_preset()
	assert_not_null(resolved)
	assert_eq(resolved.topology.node_count,
			_FIRST_LEVEL_SCENARIO.preset.topology.node_count,
			"the Scenario's authored preset, unchanged")


## #643 acceptance 4 — THE control that must work. Raw spinners reaching
## `BudgetPolicy.base_min` / `base_max`, asserted on the merged preset rather
## than on the widget.
func test_the_budget_spinners_reach_budget_policy_on_the_generated_preset() -> void:
	var lobby := _run_section_lobby(_run_policy())
	var authored := _FIRST_LEVEL_SCENARIO.preset.content.budget_policy
	assert_eq(lobby._budget_row.get_min_value(), authored.base_min,
			"the row opens on the preset's own authored budget")
	assert_eq(lobby._budget_row.get_max_value(), authored.base_max)

	lobby._budget_row._min_spin.value = 11
	lobby._budget_row._max_spin.value = 40

	var cfg := lobby.build_run_config()
	var resolved := cfg.resolved_preset()
	assert_eq(resolved.content.budget_policy.base_min, 11, "go HAM, min")
	assert_eq(resolved.content.budget_policy.base_max, 40, "go HAM, max")

	# #642's module-mutation trap, from the consumer's side: the merge must have
	# written to a private copy, never to the shared cached module every other
	# run in this process loads.
	assert_eq(authored.base_min, _FIRST_LEVEL_SCENARIO.preset.content.budget_policy.base_min,
			"the authored .tres is untouched")
	assert_ne(resolved.content.budget_policy, authored,
			"and the merge produced its own BudgetPolicy object")


## #643 acceptance 1, END TO END ON THE GENERATED GRAPH — the brief is explicit
## that asserting on the widget does not count. A picked map size must change
## how many nodes procgen actually emits.
func test_a_picked_map_size_reaches_the_generated_graph() -> void:
	var lobby := _run_section_lobby(_run_policy())
	# Index 0 is XS (100 nodes); the authored preset is 800.
	lobby._on_option_picked(0, LobbyScreen.KNOB_MAP_SIZE)

	var cfg := lobby.build_run_config()
	var resolved := cfg.resolved_preset()
	assert_eq(resolved.topology.node_count, 100, "the pick reached the preset")

	# The shipped `graph.tscn`, not `Graph.new()` — generation reaches
	# `entities_container` and other children the scene supplies, and a
	# code-composed Graph has none of them (`.claude/rules/scene-composition.md`,
	# and every procgen test in `test/unit/procgen/` does it this way).
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	resolved.seed = 1234
	var result: Dictionary = await GraphProcgen.generate(resolved, graph)

	var nodes: Array = result.nodes
	assert_gt(nodes.size(), 0, "procgen produced a graph")
	assert_lt(nodes.size(), 400,
			"an XS map is nowhere near the authored 800-node first level")


## #643 acceptance 3. The roster rebuilds on EVERY slot change; a run-level pick
## is not a roster fact and must not be collateral damage.
func test_a_run_level_pick_survives_a_roster_rebuild() -> void:
	var policy := _run_policy()
	policy.camps = [_CAMP_1, _CAMP_2]
	policy.ai_camps_pickable = true
	var lobby := _policied_lobby(RunConfig.Mode.COOP_HOTSEAT, policy, NetworkConfig.host())

	lobby._on_option_picked(0, LobbyScreen.KNOB_MAP_SIZE)
	lobby._budget_row._min_spin.value = 9

	lobby._ai_count_row.value = 3

	var cfg := lobby.build_run_config()
	assert_eq(cfg.participants.size(), 5, "premise: the roster really did rebuild")
	var resolved := cfg.resolved_preset()
	assert_eq(resolved.topology.node_count, 100, "the map-size pick survived")
	assert_eq(resolved.content.budget_policy.base_min, 9, "and so did the budget")


## Two picks into DIFFERENT modules must compose, not discard each other — the
## localize-once-per-module contract `ScenarioOverride._localize_module` keeps,
## exercised from the lobby rather than from a hand-built override list.
func test_picks_across_two_modules_compose() -> void:
	var lobby := _run_section_lobby(_run_policy())
	lobby._on_option_picked(0, LobbyScreen.KNOB_MAP_SIZE)   # XS
	lobby._on_option_picked(4, LobbyScreen.KNOB_BLOCKERS)   # Heavy
	lobby._budget_row._max_spin.value = 33

	var resolved := lobby.build_run_config().resolved_preset()
	assert_eq(resolved.topology.node_count, 100)
	assert_eq(resolved.blockers.blocker_per_small, 5)
	assert_eq(resolved.content.budget_policy.base_max, 33)


## The section is a SHARED surface (#558 adds a starter-arrangement control,
## #638 a victory-condition one). This is the seam they land on, asserted so a
## later wave finds it rather than re-deriving how this screen builds a column.
func test_the_run_section_accepts_an_appended_row() -> void:
	var lobby := _run_section_lobby(_run_policy())
	var before := lobby._run_section.get_child_count()
	var extra := Label.new()

	lobby.add_run_row(extra)

	assert_eq(lobby._run_section.get_child_count(), before + 1)
	assert_eq(extra.get_parent(), lobby._run_section)


## Raising min past max drags max with it. `BudgetPolicy` rolls
## `lerp(base_min, base_max, randf())`, which does not error on an inverted
## range — it quietly rolls downward.
func test_raising_the_budget_minimum_pushes_the_maximum_up() -> void:
	var lobby := _run_section_lobby(_run_policy())
	lobby._budget_row._min_spin.value = 99

	assert_eq(lobby._budget_row.get_max_value(), 99, "max followed min up")
	var resolved := lobby.build_run_config().resolved_preset()
	assert_lte(resolved.content.budget_policy.base_min,
			resolved.content.budget_policy.base_max,
			"the merged policy never carries an inverted range")
