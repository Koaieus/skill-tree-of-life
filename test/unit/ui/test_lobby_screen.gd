extends GutTest

## [LobbyScreen] as a VIEW over [LobbyRoster] (#1002): the rows, the pickers,
## the run-section ladders and the status copy. Every domain rule (roster
## shape, colour separation, rebuild survival, preset templating, vetoes) is
## `test/unit/session/test_lobby_roster.gd`, against the roster alone.
##
## The networked shapes, the derived mode and the seat wiring are #554's
## `test/unit/session/test_lobby_versus_roster.gd`. Since #554 every lobby also
## authors AI opponents, so the human participants are filtered for here rather
## than being the whole list.

const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")

## #741: every test in this file may touch [member GameSettings.player_name]
## through the roster it builds or a row it commits — isolated exactly like
## `test_settings.gd`, so a run here never reads or clobbers the developer's
## real `user://settings.cfg`.
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


# --- #616: the lobby owns hero colour --------------------------------------

const _PALETTE := preload("res://ui/theme/player_palette.tres")
const _ROW_SCENE := preload("res://ui/frontmatter/panels/participant_row.tscn")


func test_picking_a_colour_disables_it_in_another_slots_dropdown() -> void:
	var parts := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 1)
	var mine: Participant = parts[0]
	var theirs: Participant = parts[1]

	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(mine, 0)
	row.set_color_choices(_PALETTE, LobbyRoster.taken_colors(parts, mine.id))

	var pick: OptionButton = row.get_node("%ColorPick")
	assert_eq(pick.item_count, _PALETTE.size(), "every palette colour is listed")
	var mine_index := _PALETTE.colors.find(mine.color)
	var theirs_index := _PALETTE.colors.find(theirs.color)
	assert_eq(pick.selected, mine_index, "my own colour is the selected item")
	assert_false(pick.is_item_disabled(mine_index), "and stays selectable")
	assert_true(pick.is_item_disabled(theirs_index),
			"#616 D6: a colour another slot holds is greyed out here")


# --- 2026-09-02: default colours walk a hand-curated array, no runtime stride ---

## OKLab dE (Euclidean distance in OKLab) — the same Björn Ottosson formulas
## the palette's own docstring cites, and the same yardstick the issue's dE
## table was measured with. No runtime code needs this conversion (the
## implementation only needs `gcd`), so it lives here, local to the test that
## states the acceptance criteria in these units — not a second copy of
## anything `default_for` does. Not gameplay code, so
## `.claude/rules/multiplayer-sync.md`'s ban on transcendentals in
## gameplay/stat formulas doesn't apply: this `pow()` never leaves this test
## file.
# --- #618: the slot picks a core class, the sigil rides along --------------

const _NINJA := preload("res://entity/core/ninja_core.tres")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")


func _row_for(p: Participant) -> ParticipantRow:
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child_autofree(row)
	row.configure(p, 0)
	row.set_core_choices(CoreClass.pickable_for(LobbyRoster.slot_bit_for(p.kind)))
	return row


func test_the_row_renders_the_sigil_of_the_selected_class() -> void:
	var parts := LobbyRoster.build_participants(RunConfig.Mode.SINGLE, null, 0)
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


func test_every_core_is_offered_to_both_slot_kinds() -> void:
	# #840: any core is pickable by any slot — the old asymmetry (enemy core
	# AI-only, Balanced player-only) is gone. Every authored core now carries
	# `pickable_in = 3`, so both pickers offer the identical roster.
	var parts := LobbyRoster.build_participants(RunConfig.Mode.SINGLE, null, 1)
	var human_row := _row_for(parts[0])
	var ai_row := _row_for(parts[1])

	var offered := func(row: ParticipantRow) -> Array:
		var pick: OptionButton = row.get_node("%CorePick")
		var out: Array = []
		for i in pick.item_count:
			out.append(pick.get_item_metadata(i))
		return out

	assert_true(offered.call(human_row).has(_BASIC_ENEMY), "opt-in WIS core reaches human slots too")
	assert_true(offered.call(ai_row).has(_BALANCED), "AI can mirror the player exactly")
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


# --- #840: any core is pickable by any slot, and the AI default stops cheating --

## Sum of `ADD_BASE`-style flat `value`s a core grants to `stat_id`, ignoring
## formula-driven entries (neither core under test has one on wisdom) — this
## is deliberately a property of the modifiers array, not the resource's
## identity, so the assert survives the owner re-authoring which core is the
## AI default (#840 comment, 2026-09-10 correction).
func test_balanced_core_is_pickable_by_ai_slots() -> void:
	assert_true(CoreClass.pickable_for(CoreClass.PICKABLE_AI).has(_BALANCED),
			"an AI slot can be a literal mirror of the player")


func test_basic_enemy_core_is_pickable_by_player_slots() -> void:
	assert_true(CoreClass.pickable_for(CoreClass.PICKABLE_PLAYER).has(_BASIC_ENEMY),
			"a human who wants the WIS head start can opt into it")


# --- #841: a preset row templates AI cores, and per-row overrides stick ------
#
# `LobbyRoster.resolve_templated` is the resolution rule, exercised directly
# against hand-built participants — no scene needed for the seven acceptance
# bullets. `_SERPENT` mirrors the owner's own worked example on the issue.

const _SERPENT := preload("res://entity/core/serpent_core.tres")


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


func test_reset_affordance_shows_only_when_the_row_is_overridden() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	lobby.set_ai_opponents(1)
	var ai: Participant = lobby.participants()[1]
	assert_eq(ai.kind, Participant.Kind.AI, "premise: index 1 is the sole AI slot")

	var row: ParticipantRow = lobby._rows_container.get_child(1)
	assert_false(row.get_node("%CoreReset").visible, "not overridden yet")

	lobby._on_core_class_picked(_NINJA, ai)
	lobby._refresh_rows()
	row = lobby._rows_container.get_child(1)
	assert_true(row.get_node("%CoreReset").visible, "an explicit pick shows the reset control")

	row.get_node("%CoreReset").pressed.emit()

	row = lobby._rows_container.get_child(1)
	assert_false(row.get_node("%CoreReset").visible, "reset cleared the override, so it hides again")
	assert_eq(ai.core_class, _BALANCED, "and the seat falls back to the kind default with no preset armed")


func test_setting_the_preset_templates_every_live_ai_row() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	lobby.set_ai_opponents(2)

	lobby._ai_preset_row.core_changed.emit(_SERPENT)

	for p in lobby.participants():
		if p.kind == Participant.Kind.AI:
			assert_eq(p.core_class, _SERPENT)


func test_raising_ai_count_after_preset_armed_seats_new_ai_on_it() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	lobby.set_ai_opponents(1)
	lobby._ai_preset_row.core_changed.emit(_SERPENT)

	lobby.set_ai_opponents(3)

	for p in lobby.participants():
		if p.kind == Participant.Kind.AI:
			assert_eq(p.core_class, _SERPENT, "a newly seated AI takes the live preset")


func test_a_client_lobby_offers_no_ai_preset_row() -> void:
	# Owner, 2026-09-10: gate it the same as the AI-count row beside it — a
	# client authors no AI slots at all, so it has nothing to template.
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.join("10.0.0.4", 7777))
	add_child_autofree(lobby)

	assert_null(lobby._ai_preset_row)


# --- #741: a slot types its own name, the roster carries it ------------------

func test_the_row_paints_the_participants_name_and_locks_with_the_seat() -> void:
	var parts := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 0)
	var row := _row_for(parts[0])

	var edit: LineEdit = row.get_node("%Name")
	assert_eq(edit.text, "Player 1", "configure paints the roster's name")
	assert_true(edit.editable, "a local human seat's name is this machine's to type")

	row.set_editable(false)
	assert_false(edit.editable, "a locked seat cannot be retyped")


func test_enter_commits_the_trimmed_name_and_the_field_agrees() -> void:
	var parts := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 0)
	var row := _row_for(parts[0])
	var heard: Array[String] = []
	row.name_committed.connect(func(text: String): heard.append(text))

	var edit: LineEdit = row.get_node("%Name")
	edit.text = "  Bob  "
	edit.text_submitted.emit("  Bob  ")

	assert_eq(heard, ["Bob"], "the row asks with the trimmed name — it never writes")
	assert_eq(parts[0].display_name, "Player 1", "and the participant is untouched by the row")
	assert_eq(edit.text, "Bob", "the field shows exactly what it committed")


func test_an_empty_commit_is_refused_and_the_field_falls_back() -> void:
	var parts := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 0)
	var row := _row_for(parts[0])
	var heard: Array[String] = []
	row.name_committed.connect(func(text: String): heard.append(text))

	var edit: LineEdit = row.get_node("%Name")
	edit.text = "   "
	edit.text_submitted.emit("   ")

	assert_eq(heard.size(), 0, "an empty name is not expressable")
	assert_eq(edit.text, "Player 1", "the field falls back to what the roster holds")


func test_a_teardown_focus_loss_is_not_a_commit() -> void:
	# `_refresh_rows` frees every row on each roster change, and removing a
	# FOCUSED field fires `focus_exited` too. Mid-edit text must not become a
	# pick just because a broadcast landed — the teardown guard is what keeps
	# the commit a decision.
	var parts := LobbyRoster.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 0)
	var row: ParticipantRow = _ROW_SCENE.instantiate()
	add_child(row)
	row.configure(parts[0], 0)
	row.set_core_choices(CoreClass.pickable_for(LobbyRoster.slot_bit_for(parts[0].kind)))
	var heard: Array[String] = []
	row.name_committed.connect(func(text: String): heard.append(text))
	var edit: LineEdit = row.get_node("%Name")
	edit.text = "Bob"
	edit.grab_focus()
	assert_true(edit.has_focus())

	# queue_free FIRST — is_queued_for_deletion() is the only reliable read
	# during remove_child's own exit-tree cascade (see participant_row.gd's
	# _commit_name guard and LobbyScreen._refresh_rows).
	row.queue_free()
	remove_child(row)

	assert_eq(heard.size(), 0, "focus lost to a teardown, not to a decision")


func test_a_committed_name_writes_the_roster_and_survives_a_rebuild() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var mine: Participant = lobby.participants()[0]

	lobby._on_name_picked("  Bob  ", mine)

	assert_eq(mine.display_name, "Bob", "the writer trims what the row already trimmed")
	assert_eq(lobby.build_run_config().participants[0].display_name, "Bob",
			"START hands the name to the run")

	# An AI-count change rebuilds the roster from scratch — the name must
	# survive it exactly like a colour pick does.
	lobby._ai_count_row.value = 2.0
	assert_eq(lobby.participants()[0].display_name, "Bob",
			"the typed name survived the roster rebuild")
	assert_eq(lobby.participants().size(), 4, "sanity: the rebuild actually happened")


func test_an_empty_or_unchanged_name_pick_writes_nothing() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var mine: Participant = lobby.participants()[0]

	lobby._on_name_picked("   ", mine)
	assert_eq(mine.display_name, "Player 1", "empty is refused")
	lobby._on_name_picked("Player 1", mine)
	assert_eq(lobby.participants()[0].display_name, "Player 1", "unchanged is a no-op")


# --- #741: a saved default name seeds a fresh lobby --------------------------

func test_committing_a_name_saves_it_as_the_default() -> void:
	var lobby := _make_lobby(RunConfig.Mode.SINGLE)
	var mine: Participant = lobby.participants()[0]

	lobby._on_row_name_committed("Bramh", mine)

	assert_eq(Settings.current.player_name, "Bramh",
			"a solo lobby's one human is unambiguously the machine's own identity")


func test_hot_seats_second_slot_never_overwrites_the_saved_default() -> void:
	Settings.current.player_name = "Bramh"
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var guest: Participant = lobby.participants()[1]

	lobby._on_row_name_committed("Guest", guest)

	assert_eq(guest.display_name, "Guest", "the roster itself is still written")
	assert_eq(Settings.current.player_name, "Bramh",
			"but a guest typing their own name must not overwrite the operator's saved default")


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
	assert_eq(LobbyRoster.resolve_mode(parts), RunConfig.Mode.COOP_HOTSEAT,
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
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL]:
		var item := tree.get_item(id)
		assert_eq(item.panel, MenuGraph.PANEL_LOBBY, "'%s' opens a lobby" % id)
		assert_not_null(item.route.lobby_policy, "'%s' names a policy" % id)
	# The two networked leaves reach their lobby through a config panel — JOIN
	# through #531's address one, HOST through #582's port one — so neither
	# names PANEL_LOBBY, and both must still agree with each other about what
	# that lobby is.
	for id in [MenuGraph.ID_HOST, MenuGraph.ID_JOIN]:
		var item := tree.get_item(id)
		assert_ne(item.panel, MenuGraph.PANEL_LOBBY, "'%s' types digits first" % id)
		assert_not_null(item.route.lobby_policy, "'%s' names a policy" % id)
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
		assert_eq(o.patches[0].target, "preset:topology:node_count")
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
			if patch.target == "preset:blockers:blocker_per_small":
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
	assert_eq(lobby._map_size_row.get_value(), _MAP_SIZE_OPTIONS.default_index,
			"the widget shows the ladder's authored default, not a real pick")

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
	assert_eq(resolved.blockers.blocker_per_small, 15, "Heavy's rung, re-pitched in #777")
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


# --- #597 fork 3, settled: the Scenario is authored per ROUTE, on the policy --

const _COOP_VERSUS_SCENARIO := preload("res://session/scenarios/coop_versus.tres")


## Generates from [param lobby]'s run config and returns the graph's nodes.
## Goes through `build_run_config().resolved_preset()` — the real START path —
## rather than assembling a preset, which is what makes these end-to-end.
func _generate_from(lobby: LobbyScreen, run_seed: int) -> Array:
	var resolved := lobby.build_run_config().resolved_preset()
	assert_not_null(resolved, "the route's policy names a Scenario to merge onto")
	resolved.seed = run_seed
	var graph_scene: PackedScene = load("res://graph/graph.tscn")
	var graph: Graph = autofree(graph_scene.instantiate()) as Graph
	add_child(graph)
	await get_tree().process_frame
	var result: Dictionary = await GraphProcgen.generate(resolved, graph)
	return result.nodes


func _total_modifiers(nodes: Array) -> int:
	var total := 0
	for n in nodes:
		total += n.modifiers.size()
	return total


## The mapping, pinned. `lobby_policy_hotseat` is the `ID_LOCAL` route under
## MULTIPLAYER — couch coop, the "Coop" in "Coop / Versus" — not a single-player
## variant, so it takes the coop preset. Two things make that the substantive
## answer rather than a naming coincidence: `coop_versus`'s `starting_points`
## authors a `CampAnnulusStarters` placement and `first_level`'s authors NONE
## (#558's central finding), and `test_coop_versus_preset.gd` documents its
## budget gradient as the deliberate MIRROR of `first_level`'s so that multi-camp
## rim spawns work inwards. A multi-camp lobby on `first_level` would get neither.
func test_each_shipped_policy_names_the_scenario_its_lobby_shape_needs() -> void:
	assert_eq(_POLICY_SINGLE.scenario, _FIRST_LEVEL_SCENARIO,
			"one human, no camps -> the first level")
	assert_eq(_POLICY_HOTSEAT.scenario, _COOP_VERSUS_SCENARIO,
			"couch coop is a multi-camp shape -> the coop preset")
	assert_eq(_POLICY_VERSUS.scenario, _COOP_VERSUS_SCENARIO)

	for policy in [_POLICY_SINGLE, _POLICY_HOTSEAT, _POLICY_VERSUS]:
		assert_not_null(policy.scenario.preset,
				"'%s' names a Scenario carrying a preset" % policy.scenario.resource_name)

	# Only the multi-camp presets carry camp-relative starter placement, which is
	# the reason the hotseat mapping is what it is. `first_level.tres` authors a
	# real placement too since #742 (CenterCoreStarters, single-spawn-ring), just
	# not a camp-relative one — see `test_only_routes_with_a_starter_placement_offer_the_arrangement`.
	assert_true(_COOP_VERSUS_SCENARIO.preset.starting.starter_placement is CampAnnulusStarters)
	assert_true(_FIRST_LEVEL_SCENARIO.preset.starting.starter_placement is CenterCoreStarters,
			"#742: first_level authors CenterCoreStarters, not CampAnnulusStarters")


## Every route the shipped menu offers reaches a preset. The companion to
## `test_every_lobby_route_carries_a_policy` — a policy with no scenario would
## render the whole run section inert, and nothing else would fail.
func test_every_lobby_route_reaches_a_generable_preset() -> void:
	var tree := MenuGraph.build()
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN]:
		var policy: LobbyPolicy = tree.get_item(id).route.lobby_policy
		assert_not_null(policy.scenario, "'%s' names a Scenario" % id)
		assert_not_null(policy.scenario.preset, "'%s' reaches a preset" % id)
		assert_true(policy.offers_run_section(), "'%s' offers the run section" % id)


## #643 acceptance 2, re-asserted now that the shipped policies carry scenarios:
## a NULL policy must still yield a null scenario and behave exactly as master.
## This is the property the whole feature is allowed to exist behind.
func test_a_null_policy_still_yields_no_scenario_and_no_overrides() -> void:
	var lobby := _make_lobby(RunConfig.Mode.COOP_HOTSEAT)
	var cfg := lobby.build_run_config()

	assert_null(cfg.scenario, "master's behaviour: no policy, no Scenario")
	assert_eq(cfg.overrides.size(), 0)
	assert_null(cfg.resolved_preset(),
			"so the level falls back to its own `preset` export, as on master")
	assert_true(lobby.can_start())


## **The LAN requirement, asserted against SHIPPED DATA.** No test-fixture
## policy and no test-fixture scenario: this drives the real `New Game` route's
## authored `LobbyPolicy` and asserts that turning the budget spinners up changes
## how many modifiers procgen actually puts on the map.
##
## Two runs at the SAME seed, differing only in the budget pick, compared by
## total modifier count. A comparison rather than an absolute threshold because
## the rolled range is scaled by `archetype_multiplier` and `budget_field`
## before it lands — but it is MONOTONIC in `base_min`/`base_max`, so "more
## budget yields more modifiers" holds whatever those scalars are.
func test_a_budget_pick_on_the_shipped_route_reaches_the_generated_map() -> void:
	var route_policy: LobbyPolicy = MenuGraph.build().get_item(
			MenuGraph.ID_NEW_GAME).route.lobby_policy
	assert_eq(route_policy, _POLICY_SINGLE, "premise: this is the shipped route's policy")

	# XS on both runs, purely to keep the comparison cheap — it is itself a
	# second shipped-ladder pick reaching procgen.
	var baseline := _run_section_lobby(route_policy)
	baseline._on_option_picked(0, LobbyScreen.KNOB_MAP_SIZE)
	var baseline_nodes := await _generate_from(baseline, 20260828)

	var ham := _run_section_lobby(route_policy)
	ham._on_option_picked(0, LobbyScreen.KNOB_MAP_SIZE)
	ham._budget_row._min_spin.value = 18
	ham._budget_row._max_spin.value = 30
	var ham_nodes := await _generate_from(ham, 20260828)

	assert_eq(ham_nodes.size(), baseline_nodes.size(),
			"same seed and same map size, so the topology is identical")
	assert_gt(_total_modifiers(ham_nodes), _total_modifiers(baseline_nodes),
			"'do the normal stuff but increase budgets, lets go HAM' reached the map")


## The other half of the requirement: with NO pick, the shipped route generates
## exactly the map it did before this feature existed. Acceptance 5, end to end.
func test_the_shipped_route_with_no_pick_generates_the_authored_preset() -> void:
	var lobby := _run_section_lobby(_POLICY_SINGLE)
	var cfg := lobby.build_run_config()

	assert_eq(cfg.overrides.size(), 0, "nothing picked, nothing overridden")
	var resolved := cfg.resolved_preset()
	var authored := _FIRST_LEVEL_SCENARIO.preset
	assert_eq(resolved.topology.node_count, authored.topology.node_count)
	assert_eq(resolved.content.budget_policy.base_min,
			authored.content.budget_policy.base_min)
	assert_eq(resolved.content.budget_policy.base_max,
			authored.content.budget_policy.base_max)


## **For #558, updated for #742.** After the hotseat remap, `first_level.tres`
## is reachable from exactly one shipped lobby route: `New Game`, the
## single-player one. Every camp-offering route lands on `coop_versus`, which
## authors a `CampAnnulusStarters` placement — `New Game` authors a REAL
## placement too since #742 (`CenterCoreStarters`), just not a camp-relative
## one, so it is the ONE route whose placement is not a `CampAnnulusStarters`.
##
## That matters to #558 in both directions. Its arrangement control WILL be
## observable on every route that offers camps (its own central complaint about
## itself, discharged). And on `New Game` the arrangement leaf still has
## nothing to patch (`CenterCoreStarters` carries no `arrangement` field) — so a
## mispaired override there is still the silent no-op #642 acceptance 8 exists
## to catch, not a bug in the control.
##
## If a later change points a camp-offering route back at `CenterCoreStarters`,
## or gives `New Game` a `CampAnnulusStarters`, this test fails and that
## paragraph needs rewriting — which is the point of asserting it.
func test_only_the_single_player_route_reaches_the_non_camp_relative_preset() -> void:
	var tree := MenuGraph.build()
	var without_camp_placement: Array[StringName] = []
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN]:
		var policy: LobbyPolicy = tree.get_item(id).route.lobby_policy
		if not (policy.scenario.preset.starting.starter_placement is CampAnnulusStarters):
			without_camp_placement.append(id)

	assert_eq(without_camp_placement, [MenuGraph.ID_NEW_GAME] as Array[StringName],
			"only New Game reaches a preset with no CampAnnulusStarters")
	assert_true(tree.get_item(MenuGraph.ID_NEW_GAME).route.lobby_policy.camps.is_empty(),
			"and that route offers no camps, so nothing there wants camp-relative placement")


# ── #558 — the starter-arrangement ladder ──────────────────────────────────
#
# Owner call 2026-08-24 (#516 decision 5): the arrangement is HOST-chosen and
# is run shape a peer must reproduce, so it rides the roster/RunConfig half and
# never SeatPolicy. D3 makes it a MODULE override rather than a bespoke field —
# one more instance of the ladder map size and blockers already use.

const _ARRANGEMENT_OPTIONS := preload(
		"res://ui/frontmatter/lobby_options/arrangement_options.tres")


## The ladder-direction trap #643 found on the blocker denominators, applied
## here: `arrangement` is an ENUM, so "ordered correctly" means each option's
## value IS the constant its label names. An off-by-one would ship a dropdown
## whose "Random" produced grouped camps, and every other test would stay green.
func test_the_arrangement_ladder_maps_each_label_to_its_own_enum_value() -> void:
	var choices := _ARRANGEMENT_OPTIONS.choices()
	var labels: Array[String] = []
	for o in choices:
		labels.append(o.label)
	assert_eq(labels, ["Grouped", "Alternating", "Random"] as Array[String],
			"D5: GROUPED is the default and leads the ladder")

	var expected := [
		CampAnnulusStarters.Arrangement.GROUPED,
		CampAnnulusStarters.Arrangement.ALTERNATING,
		CampAnnulusStarters.Arrangement.RANDOM,
	]
	for i in choices.size():
		assert_eq(choices[i].patches.size(), 1,
				"'%s' patches exactly the arrangement" % labels[i])
		assert_eq(choices[i].patches[0].target, "preset:starting:starter_placement:arrangement",
				"D3: a module override, not a bespoke RunConfig field")
		assert_eq(int(choices[i].patches[0].value), expected[i],
				"'%s' must carry its own enum value" % labels[i])


## The row is offered through the SAME seam as the other two, and is gated
## independently — a policy unlocking only the arrangement gets only that row.
func test_the_arrangement_knob_is_gated_independently() -> void:
	var policy := LobbyPolicy.new()
	policy.arrangement_options = _ARRANGEMENT_OPTIONS
	var lobby := _run_section_lobby(policy)

	assert_not_null(lobby._run_section, "an arrangement ladder alone opens the section")
	assert_not_null(lobby._arrangement_row, "arrangement was unlocked")
	assert_true(lobby._arrangement_row.visible)
	assert_null(lobby._map_size_row, "map size was not")
	assert_null(lobby._blocker_row, "nor blockers")


## #558 acceptance 3's lobby half: a pick becomes exactly one leaf override,
## and an untouched control writes none at all.
func test_a_picked_arrangement_becomes_one_leaf_override() -> void:
	var policy := LobbyPolicy.new()
	policy.scenario = _COOP_VERSUS_SCENARIO
	policy.arrangement_options = _ARRANGEMENT_OPTIONS
	var lobby := _run_section_lobby(policy)

	assert_eq(lobby.build_run_config().overrides.size(), 0,
			"untouched: no override, not an override that happens to match")

	lobby._on_option_picked(
			CampAnnulusStarters.Arrangement.ALTERNATING, LobbyScreen.KNOB_ARRANGEMENT)
	var overrides := lobby.build_run_config().overrides
	assert_eq(overrides.size(), 1)
	assert_eq(overrides[0].target, "preset:starting:starter_placement:arrangement")
	assert_eq(int(overrides[0].value), CampAnnulusStarters.Arrangement.ALTERNATING)


## Only the routes whose Scenario actually carries a `CampAnnulusStarters` offer
## the control — the companion to
## `test_only_the_single_player_route_reaches_the_non_camp_relative_preset`. New
## Game reaches `first_level`, which authors a `CenterCoreStarters` (#742) — a
## real placement, just not a camp-relative one — so an arrangement ladder
## there would still be the silent no-op #642 acceptance 8 catches.
func test_only_routes_with_a_starter_placement_offer_the_arrangement() -> void:
	var tree := MenuGraph.build()
	for id in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN]:
		var policy: LobbyPolicy = tree.get_item(id).route.lobby_policy
		var has_camp_placement := policy.scenario.preset.starting.starter_placement is CampAnnulusStarters
		assert_eq(policy.arrangement_options != null, has_camp_placement,
				"'%s': the arrangement is offered iff there is a CampAnnulusStarters to patch" % id)


# --- what a host reads out loud (#582 acceptance 3) ---------------------------

## The caption's label, wherever it ended up in the column.
func _caption_of(lobby: LobbyScreen) -> String:
	for child in lobby.content.get_children():
		var label := child as Label
		if label != null:
			return label.text
	return ""


func test_a_hosting_lobby_says_where_a_joiner_should_dial() -> void:
	# Nothing discovers a host: LAN broadcast was evaluated and dropped (#463),
	# so "one room, one number" means a human reads the number to another human.
	# This is where that number is said.
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.host(7777))
	add_child_autofree(lobby)

	var caption := _caption_of(lobby)
	assert_string_contains(caption, "7777", "the port a joiner types")
	assert_string_contains(caption, NetworkConfig.local_advertised_address(),
			"and the address it goes with")


func test_a_joining_lobby_is_told_nothing_about_its_own_addresses() -> void:
	# It already knows what it dialled, and its own local address is at best
	# noise and at worst the wrong number (#582 D6).
	var lobby := LobbyScreen.new()
	lobby.configure(RunConfig.Mode.COOP_HOTSEAT, NetworkConfig.join("10.0.0.4", 7777))
	add_child_autofree(lobby)

	assert_eq(_caption_of(lobby), NetworkConfig.join("10.0.0.4", 7777).describe())


func test_an_offline_lobby_says_nothing_about_the_wire_at_all() -> void:
	assert_eq(_caption_of(_make_lobby(RunConfig.Mode.SINGLE)), "")
