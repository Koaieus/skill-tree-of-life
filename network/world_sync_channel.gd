class_name WorldSyncChannel
extends LinkChannel
## STUB — filled in by the next commit.

const KIND_SNAPSHOT := "snapshot"
const KIND_SETUP := "setup"
const KIND_ENTITIES := "entities"
const KIND_RESYNC := "resync"
const KIND_RESYNC_REQUEST := "resync_request"

signal sync_checked(agrees: bool, local: int, remote: int)
signal resync_sent(reason: String)
signal resync_applied(reason: String)

@export var graph: Graph
@export var turn_manager: TurnManager
@export var command_applier: CommandApplier
@export var probe: DeterminismProbe


func kinds() -> Array[String]:
	return []
