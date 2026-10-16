extends RefCounted
## A level's wire composed the way `scenes/game_root.tscn` mounts it — a
## [NetworkLink] core with a [WorldSyncChannel] and a [CommandChannel] on it —
## for tests that drive two peers over a [LoopbackTransport] pair. Preload it;
## it has no `class_name` on purpose.
##
## Exports are set before `add_child` (a channel's `_ready`/`_on_attached` is
## what connects its applier), the role after, so the role reaches the applier
## through [method LinkChannel._on_identity_changed] exactly as in a level.


## Compose and mount under [param test]; returns the core. [param extra] are
## further channels (a [LootOfferChannel], a [LobbyChannel]) registered after
## the two a level always has.
static func compose(test: GutTest, transport: NetworkTransport, applier: CommandApplier,
		role: NetworkConfig.Role, graph: Graph = null, turn_manager: TurnManager = null,
		probe: DeterminismProbe = null, extra: Array[LinkChannel] = []) -> NetworkLink:
	var world := WorldSyncChannel.new()
	world.name = "WorldSyncChannel"
	world.graph = graph
	world.turn_manager = turn_manager
	world.command_applier = applier
	world.probe = probe
	var command := CommandChannel.new()
	command.name = "CommandChannel"
	command.command_applier = applier
	command.probe = probe
	var core := NetworkLink.new()
	core.name = "NetworkLink"
	core.transport = transport
	var channels: Array[LinkChannel] = [world, command]
	channels.append_array(extra)
	core.channels = channels
	test.add_child_autofree(core)
	for channel in channels:
		test.add_child_autofree(channel)
	core.role = role
	return core


## The world channel on [param core].
static func world(core: NetworkLink) -> WorldSyncChannel:
	return core.channel_for(WorldSyncChannel.KIND_RESYNC) as WorldSyncChannel


## The command channel on [param core].
static func command(core: NetworkLink) -> CommandChannel:
	return core.channel_for(CommandChannel.KIND_COMMAND) as CommandChannel
