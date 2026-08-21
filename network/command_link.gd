@tool
class_name CommandLink
extends Node

## Bridges one [CommandApplier] to one [NetworkTransport]: the host broadcasts
## the commands it confirmed, every client applies them through its own applier.
##
## [b]This is a mirror, not the sync layer.[/b] Wave 0 is deliberately
## one-directional — host down to client, no intent channel upward. The reason
## is not laziness: routing a client's own input upward means the client must
## STOP applying locally and wait to be told, which is surgery on
## [PlayerInputController]'s submit path and on [BattleSystem]. That is #463,
## and `docs/FOCUS.md` gates it behind #511 and #512. So the client here is a
## spectator with a real applier, which is exactly enough to prove the shape.
##
## [b]What actually mirrors today:[/b] every verb [CommandApplier] handles —
## allocate / deallocate / deallocate_set / mass_allocate / stake / extract /
## move_core / end_turn / toggle_temp_upgrade. [b]What does not:[/b] attacks
## (still called straight into [BattleSystem] — #511) and loot rolls (#509's
## [PickLootCommand] is not routed). A client will therefore diverge the moment
## somebody swings, and the fingerprint below is how you SEE that happen instead
## of guessing.
##
## See `docs/domain/multiplayer-harness.md`.

## Wire envelope keys. The command's own dictionary is nested rather than merged
## so the codec keeps owning its whole namespace.
const KEY_KIND := "kind"
const KEY_COMMAND := "cmd"
const KEY_FINGERPRINT := "fp"
const KEY_SUMMARY := "summary"

const KIND_HELLO := "hello"
const KIND_COMMAND := "command"

enum Mode {
	OFF,        ## Wired but idle.
	BROADCAST,  ## Host: publish every confirmed command.
	MIRROR,     ## Client: apply everything received.
}

## A line worth showing a human (both roles). The harness prints these; nothing
## depends on their text.
signal logged(line: String)

## The client's post-apply comparison against the host's fingerprint.
## [param agrees] false means the two worlds have diverged — see the class note
## for the two known-unmirrored paths that cause it legitimately today.
signal sync_checked(agrees: bool, local: int, remote: int)

@export var transport: NetworkTransport
@export var command_applier: CommandApplier
@export var graph: Graph

var mode: Mode = Mode.OFF

## True while a RECEIVED command is being submitted, so a client that is also
## broadcasting cannot echo it back. Wave 0 never sets both, but the guard is
## one line and its absence is an infinite loop.
var _applying_remote: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if transport != null:
		transport.message_received.connect(_on_message_received)
		transport.link_changed.connect(func(status: String) -> void: logged.emit(status))
	if command_applier != null:
		command_applier.command_applied.connect(_on_command_applied)


## Announce our world to a freshly-connected peer. Host-side; the client's reply
## is a log line, not a handshake — nothing here negotiates.
func send_hello() -> void:
	if transport == null or mode != Mode.BROADCAST:
		return
	transport.send({
		KEY_KIND: KIND_HELLO,
		KEY_FINGERPRINT: WorldFingerprint.compute(graph),
		KEY_SUMMARY: WorldFingerprint.describe(graph),
	})


func _on_command_applied(command: Command, success: bool) -> void:
	if mode != Mode.BROADCAST or transport == null:
		return
	# A refused command changed nothing, so there is nothing to mirror. The
	# client's own gates would refuse it too, but re-deriving that on a peer is
	# precisely what host authority exists to avoid.
	if not success or _applying_remote:
		return
	transport.send({
		KEY_KIND: KIND_COMMAND,
		KEY_COMMAND: command.to_dict(),
		KEY_FINGERPRINT: WorldFingerprint.compute(graph),
	})
	logged.emit("→ %s (fp %d)" % [command.type_tag(), WorldFingerprint.compute(graph)])


func _on_message_received(payload: Dictionary) -> void:
	match String(payload.get(KEY_KIND, "")):
		KIND_HELLO:
			_on_hello(payload)
		KIND_COMMAND:
			_on_remote_command(payload)
		_:
			logged.emit("ignored payload with unknown kind %s" % payload.get(KEY_KIND))


## The link-up check. A mismatch HERE — before a single command has crossed —
## means the two graphs disagree about node identity, which in a hand-authored
## scene almost always means unminted `stable_id`s. That is the failure this
## harness is built to make loud.
func _on_hello(payload: Dictionary) -> void:
	var remote := int(payload.get(KEY_FINGERPRINT, 0))
	var local := WorldFingerprint.compute(graph)
	logged.emit("host world: %s" % payload.get(KEY_SUMMARY, "?"))
	logged.emit("mine:       %s" % WorldFingerprint.describe(graph))
	_report_sync(local, remote, "at link-up")


func _on_remote_command(payload: Dictionary) -> void:
	if mode != Mode.MIRROR or command_applier == null:
		return
	var command := CommandCodec.from_dict(payload.get(KEY_COMMAND, {}))
	if command == null:
		logged.emit("← undecodable payload, dropped")
		return
	_applying_remote = true
	command_applier.submit(command)
	# `submit` may await (move_core beats, end_turn's initiative tick), so the
	# flag is cleared when the queue actually empties, not on the next line.
	if command_applier.is_applying:
		await command_applier.applying_changed
	_applying_remote = false
	logged.emit("← %s" % command.type_tag())
	_report_sync(WorldFingerprint.compute(graph), int(payload.get(KEY_FINGERPRINT, 0)), \
			"after %s" % command.type_tag())


func _report_sync(local: int, remote: int, when: String) -> void:
	var agrees := local == remote
	sync_checked.emit(agrees, local, remote)
	if agrees:
		logged.emit("  ✓ in sync %s (fp %d)" % [when, local])
	else:
		logged.emit("  ✗ DIVERGED %s — mine %d, host %d" % [when, local, remote])
