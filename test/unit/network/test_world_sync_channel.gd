extends GutTest
## The fingerprint check lives on [WorldSyncChannel], not on the command
## protocol: a link that mounts ONLY the world channel still notices a
## divergence reported through [signal CommandApplier.command_stamped] and asks
## the host for its world.

var _upward: Array[Dictionary] = []
var _verdicts: Array = []
var _applier: CommandApplier
var _sync: WorldSyncChannel


func before_each() -> void:
	_upward = []
	_verdicts = []
	var pair := LoopbackTransport.pair()
	add_child_autofree(pair[0])
	add_child_autofree(pair[1])
	(pair[0] as NetworkTransport).message_received.connect(
			func(p: Dictionary) -> void: _upward.append(p))

	_applier = CommandApplier.new()
	add_child_autofree(_applier)

	var core := NetworkLink.new()
	core.transport = pair[1]
	_sync = WorldSyncChannel.new()
	_sync.command_applier = _applier
	core.channels = [_sync] as Array[LinkChannel]
	add_child_autofree(core)
	add_child_autofree(_sync)
	core.role = NetworkConfig.Role.CLIENT
	_sync.sync_checked.connect(
			func(a: bool, l: int, r: int) -> void: _verdicts.append([a, l, r]))


func test_no_command_channel_is_mounted() -> void:
	for node in get_children():
		assert_false(node is CommandChannel, "the pin is void if a CommandChannel rides along")


func test_a_stamped_divergence_is_healed_without_a_command_channel() -> void:
	var command := AllocateCommand.new(1, 1)
	command.pre_fingerprint = 11
	command.host_fingerprint = 22
	_applier.command_stamped.emit(command)
	await get_tree().process_frame

	assert_eq(_verdicts, [[false, 11, 22]], "the stamped compare ran on the world channel")
	var kinds: Array[String] = []
	for p in _upward:
		kinds.append(String(p.get(NetworkLink.KEY_KIND, "")))
	assert_eq(kinds.count(WorldSyncChannel.KIND_RESYNC_REQUEST), 1,
			"and the heal asked the host for its world: %s" % [kinds])


func test_an_agreeing_stamp_asks_for_nothing() -> void:
	var command := AllocateCommand.new(1, 1)
	command.pre_fingerprint = 7
	command.host_fingerprint = 7
	_applier.command_stamped.emit(command)
	await get_tree().process_frame

	assert_eq(_verdicts, [[true, 7, 7]])
	assert_true(_upward.is_empty(), "nothing crosses for a world in sync: %s" % [_upward])
