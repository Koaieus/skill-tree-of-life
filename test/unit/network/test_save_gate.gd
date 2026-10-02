extends GutTest

## [SaveGate] — offline only, pressable whenever offline, and a request made
## while the applier is not quiescent is held and taken at the next quiescent
## boundary. The open loot round is the held case: it is the one wait on a
## human, and the applier's own open/close notifications drive it.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _TEST_SLOT := "user://test_save_gate.bin"

var _gate: SaveGate
var _applier: CommandApplier
var _graph: Graph


func before_each() -> void:
	GameSession.start(RunConfig.new())
	var level := Node.new()
	level.scene_file_path = "res://scenes/level.tscn"
	add_child_autofree(level)
	_graph = _GRAPH_SCENE.instantiate()
	level.add_child(_graph)
	_graph.owner = level
	_applier = CommandApplier.new()
	level.add_child(_applier)
	_gate = SaveGate.new()
	_gate.command_applier = _applier
	_gate.graph = _graph
	_gate.slot_path = _TEST_SLOT
	level.add_child(_gate)
	await get_tree().process_frame


func after_each() -> void:
	for path in [_TEST_SLOT, _TEST_SLOT + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameSession.end()


func test_online_run_cannot_save() -> void:
	var net := NetworkConfig.new()
	net.role = NetworkConfig.Role.HOST
	GameSession.network = net
	assert_false(_gate.can_save())
	assert_ne(_gate.blocked_reason(), "")
	assert_false(_gate.request_save())
	assert_false(FileAccess.file_exists(_TEST_SLOT))


func test_offline_quiescent_saves_at_once() -> void:
	# No seat condition: the holder (local, AI, anyone) is irrelevant offline.
	assert_true(_gate.can_save())
	assert_eq(_gate.blocked_reason(), "")
	assert_true(_gate.request_save())
	assert_false(_gate.is_save_held)
	var loaded := SaveFile.read_slot(_TEST_SLOT)
	assert_eq(loaded.load_result, SaveFile.LoadResult.OK)
	assert_eq(loaded.world.to_bytes(), WorldImage.capture(_graph).to_bytes())


func test_open_loot_round_holds_the_save_until_it_closes() -> void:
	_applier.notify_loot_round_opened()
	assert_true(_gate.can_save(), "SAVE stays pressable offline")
	assert_eq(_gate.blocked_reason(), SaveGate.REASON_LOOT)
	assert_true(_gate.request_save())
	assert_true(_gate.is_save_held)
	assert_false(FileAccess.file_exists(_TEST_SLOT), "nothing written mid-pick")
	_applier.notify_loot_round_closed()
	assert_false(_gate.is_save_held)
	var loaded := SaveFile.read_slot(_TEST_SLOT)
	assert_eq(loaded.load_result, SaveFile.LoadResult.OK)
	assert_eq(loaded.world.to_bytes(), WorldImage.capture(_graph).to_bytes())
