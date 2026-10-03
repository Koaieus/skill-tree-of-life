extends GutTest

## The pause menu's SAVE and LOAD, and the one load path both LOAD buttons
## share ([SavedRun]). SAVE asks the level's [SaveGate]; LOAD reads the slot the
## gate writes. The press of LOAD itself is not driven — it ends in
## [method SceneDirector.goto] — so [method PauseMenu.load_saved], the half
## before the route, is what is asserted, by the session it leaves behind.

const _PAUSE_MENU := preload("res://ui/pause_menu.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _TEST_SLOT := "user://test_pause_menu_save_load.bin"
const _SAVED_SEED := 98765

var _menu: PauseMenu
var _gate: SaveGate


func before_each() -> void:
	_clear_slot()
	var cfg := RunConfig.new()
	cfg.seed = 1234
	GameSession.start(cfg)
	var level := Node.new()
	level.scene_file_path = "res://scenes/level.tscn"
	add_child_autofree(level)
	var graph: Graph = _GRAPH_SCENE.instantiate()
	level.add_child(graph)
	graph.owner = level
	var applier := CommandApplier.new()
	level.add_child(applier)
	_gate = SaveGate.new()
	_gate.command_applier = applier
	_gate.graph = graph
	_gate.slot_path = _TEST_SLOT
	level.add_child(_gate)
	_menu = _PAUSE_MENU.instantiate()
	_menu.save_gate = _gate
	add_child_autofree(_menu)
	await get_tree().process_frame


func after_each() -> void:
	get_tree().paused = false
	_clear_slot()
	GameSession.network = null
	GameSession.end()


func _clear_slot() -> void:
	for path in [_TEST_SLOT, _TEST_SLOT + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _go_online() -> void:
	var net := NetworkConfig.new()
	net.role = NetworkConfig.Role.HOST
	GameSession.network = net


func _button(name: String) -> Button:
	return _menu.find_child(name, true, false)


func _write_valid_slot() -> void:
	var cfg := RunConfig.new()
	cfg.seed = _SAVED_SEED
	var p := Participant.new()
	p.id = 3
	p.camp = _CAMP_1
	cfg.participants = [p] as Array[Participant]
	var save := SaveFile.new()
	save.level_scene_path = "res://scenes/level.tscn"
	save.config = cfg.to_dict()
	save.roster = ParticipantRoster.of(cfg.participants).to_dict()
	save.world = WorldImage.new(PackedByteArray([1, 2, 3]), PackedByteArray([4, 5, 6, 7]))
	assert_eq(save.write_slot(_TEST_SLOT), OK, "sanity: the fixture slot was written")


# --- SAVE --------------------------------------------------------------------

func test_save_is_disabled_in_an_online_run_with_the_gates_reason() -> void:
	_go_online()
	_menu.active = true
	assert_true(_button("SaveButton").disabled, "no saving in an online run")
	assert_eq(_button("SaveButton").tooltip_text, _gate.blocked_reason())
	assert_ne(_button("SaveButton").tooltip_text, "")


func test_save_is_enabled_at_a_quiescent_local_turn_and_writes_the_slot() -> void:
	_menu.active = true
	assert_false(_button("SaveButton").disabled, "offline + quiescent: SAVE is live")
	_button("SaveButton").pressed.emit()
	assert_true(FileAccess.file_exists(_TEST_SLOT), "SAVE wrote the gate's slot")
	assert_true(_menu.find_child("SaveStatus", true, false).visible, "SAVE gives feedback")


# --- LOAD --------------------------------------------------------------------

func test_load_is_disabled_with_no_slot() -> void:
	_menu.active = true
	assert_true(_button("LoadButton").disabled, "nothing to load")


func test_load_is_enabled_with_a_slot() -> void:
	_write_valid_slot()
	_menu.active = true
	assert_false(_button("LoadButton").disabled)


func test_load_is_disabled_in_an_online_run() -> void:
	_write_valid_slot()
	_go_online()
	_menu.active = true
	assert_true(_button("LoadButton").disabled, "no loading in an online run")


func test_load_with_a_valid_slot_opens_the_saved_run() -> void:
	_write_valid_slot()
	var save := _menu.load_saved()
	assert_eq(save.load_result, SaveFile.LoadResult.OK)
	assert_eq(GameSession.config.seed, _SAVED_SEED, "the saved run is now the session's")
	assert_eq(GameSession.world_source, GameSession.WorldSource.ARRIVES)
	assert_not_null(GameSession.pending_world, "the world is parked for the level")


func test_a_corrupt_slot_is_refused_out_loud_and_leaves_the_run_alone() -> void:
	var file := FileAccess.open(_TEST_SLOT, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3, 4]))
	file.close()
	var save := _menu.load_saved()
	assert_eq(save.load_result, SaveFile.LoadResult.CORRUPT)
	assert_eq(GameSession.config.seed, 1234, "the running run is untouched")
	var status: Label = _menu.find_child("SaveStatus", true, false)
	assert_true(status.visible, "a failed load is never a silent no-op")
	assert_eq(status.text, SavedRun.describe(SaveFile.LoadResult.CORRUPT))


func test_every_refusal_has_a_line_to_show() -> void:
	for result in [SaveFile.LoadResult.MISSING, SaveFile.LoadResult.CORRUPT,
			SaveFile.LoadResult.VERSION_MISMATCH]:
		assert_ne(SavedRun.describe(result), "", "LoadResult %d says why" % result)


# --- FRONTMATTER LOAD GAME ---------------------------------------------------

const _LOAD_PANEL := preload("res://ui/frontmatter/panels/load_panel.tscn")


func _load_panel() -> LoadPanel:
	var panel: LoadPanel = _LOAD_PANEL.instantiate()
	panel.slot_path = _TEST_SLOT
	add_child_autofree(panel)
	return panel


func test_the_frontmatter_leaf_is_selectable() -> void:
	assert_false(MenuGraph.build().get_item(MenuGraph.ID_LOAD_GAME).disabled)


func test_the_load_panel_offers_nothing_without_a_slot() -> void:
	var panel := _load_panel()
	assert_true((panel.find_child("LoadButton", true, false) as Button).disabled)
	assert_eq((panel.find_child("Status", true, false) as Label).text,
			SavedRun.describe(SaveFile.LoadResult.MISSING))


func test_the_load_panel_refuses_a_corrupt_slot_out_loud() -> void:
	var file := FileAccess.open(_TEST_SLOT, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3, 4]))
	file.close()
	var panel := _load_panel()
	var button: Button = panel.find_child("LoadButton", true, false)
	assert_false(button.disabled, "a slot exists, so the press may say why it fails")
	button.pressed.emit()
	assert_eq((panel.find_child("Status", true, false) as Label).text,
			SavedRun.describe(SaveFile.LoadResult.CORRUPT))
	assert_eq(GameSession.config.seed, 1234, "the session is untouched")
