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
## which is still `Needs design`. So the client here is a spectator with a real
## applier, which is exactly enough to prove the shape.
##
## [b]Every verb [CommandApplier] handles mirrors[/b] — allocate / deallocate /
## deallocate_set / mass_allocate / stake / extract / move_core / end_turn /
## toggle_temp_upgrade, launch_attack since #511 (which rides down with an
## [AttackRecord] the client replays rather than re-resolving), and loot since
## #522 (a [LootRoundCommand] per round of a relic's claim, carrying what was
## granted BY VALUE — same two-states-one-type shape as the attack). `end_turn`
## only became true here on 2026-08-22, and loot was the last hold-out: the
## HUD's End Turn button called [method TurnManager.end_turn] directly until
## then, and nothing raised a loot command at all, so both were verbs that never
## became commands.
##
## [b]The lesson those three share:[/b] this class mirrors whatever the applier
## handles, so a verb missing from the wire is almost always a missing
## submission site, not a transport gap. Check who raises the command first.
##
## [b]What is still one-directional:[/b] the link itself. There is no intent
## channel upward, so a client remains a spectator with a real applier — see
## the wave-0 note above. [PickLootCommand] is the one verb built for that
## direction and is therefore dormant, not unrouted: the applier answers it for
## real (through [method CommandApplier._answer_loot_pick], deliberately NOT
## through its queue — see there), nothing can send it yet. It is also the one
## command that must never be broadcast back down; bypassing the queue means it
## never confirms, so that falls out rather than needing a guard here.
##
## [b]#529's determinism probe hangs off the mirror path here[/b], as three
## optional calls into [DeterminismProbe] and no logic of its own. It measures
## whether this peer could have DERIVED what it was sent, which is the input to
## the choice between confirm-down and lockstep — it never changes what is
## applied, and it is off unless a harness turns it on.
##
## See `docs/domain/multiplayer-harness.md` and
## `docs/domain/determinism-probe.md`.

## Wire envelope keys. The command's own dictionary is nested rather than merged
## so the codec keeps owning its whole namespace.
const KEY_KIND := "kind"
const KEY_COMMAND := "cmd"
const KEY_FINGERPRINT := "fp"
const KEY_SUMMARY := "summary"
const KEY_SNAPSHOT := "snapshot"
const KEY_CONFIG := "config"
const KEY_ROSTER := "roster"

const KIND_HELLO := "hello"
const KIND_COMMAND := "command"
## #527's join-handshake payload: an encoded [GraphSnapshot]. Additive and
## opt-in — sent only by [method send_graph_snapshot], never by [method send_hello]
## — so existing hello/fingerprint flows (and their tests) are untouched by a
## client that never calls it.
const KIND_SNAPSHOT := "snapshot"
## #528's join-handshake payload: [RunConfig] + [ParticipantRoster], both by
## value. Same additive shape as [constant KIND_SNAPSHOT] — sent only by
## [method send_run_setup].
const KIND_SETUP := "setup"

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

## #529's measurement, optional and OFF unless a harness enables it. A null
## probe, or a disabled one, costs one branch per received command — the hooks
## below are three calls and no logic, because the question "could a peer have
## derived this?" is a whole subject and belongs in its own file, not smeared
## across the verb path #463's other children are also editing.
@export var probe: DeterminismProbe

## Setting this is also what tells the applier whether it DECIDES or is told.
## Single writer, so no scene has to carry a second role flag and the two can
## never disagree — see [member CommandApplier.is_authority] for the one thing
## that reads it.
var mode: Mode = Mode.OFF:
	set(value):
		mode = value
		if command_applier != null:
			command_applier.is_authority = value != Mode.MIRROR

## True while a RECEIVED command is being submitted, so a client that is also
## broadcasting cannot echo it back. Wave 0 never sets both, but the guard is
## one line and its absence is an infinite loop.
var _applying_remote: bool = false

## Monotonic receive counter, so a handler resuming from an await can tell
## whether a newer command has since superseded its view of the world. Not a
## wire field — the host never sees it.
var _recv_seq: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# The export resolves after the setter may already have run (a level scene
	# can set `mode` before this node is ready), so re-apply it here.
	if command_applier != null:
		command_applier.is_authority = mode != Mode.MIRROR
	if transport != null:
		transport.message_received.connect(_on_message_received)
		transport.link_changed.connect(func(status: String) -> void: logged.emit(status))
	if command_applier != null:
		command_applier.command_confirmed.connect(_on_command_confirmed)


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


## Send the whole graph to a freshly-connected peer (#527) — host-side, opt-in.
## Not called from [method send_hello]: existing hello/fingerprint-only flows
## (the multiplayer harness's rung 1, #532) must keep working for a client
## that never wants a graph transferred to it. The receiving side handles
## [constant KIND_SNAPSHOT] in [method _on_message_received] regardless of
## `mode` — decoding a snapshot is not a mirrored command, so it isn't gated
## behind `Mode.MIRROR` the way [method _on_remote_command] is.
func send_graph_snapshot() -> void:
	if transport == null or mode != Mode.BROADCAST or graph == null:
		return
	transport.send({KEY_KIND: KIND_SNAPSHOT, KEY_SNAPSHOT: GraphSnapshot.encode(graph)})
	logged.emit("→ graph snapshot (%s)" % WorldFingerprint.describe(graph))


## Send the run's shape to a freshly-connected peer (#528) — host-side,
## opt-in, same additive shape as [method send_graph_snapshot]. [param config]
## and [param roster] cross BY VALUE ([method RunConfig.to_dict] /
## [method ParticipantRoster.to_dict]); the receiving peer decodes and hands
## both to [method GameSession.apply_received], which does NOT re-resolve the
## seed — it already is the host's resolved value.
func send_run_setup(config: RunConfig, roster: ParticipantRoster) -> void:
	if transport == null or mode != Mode.BROADCAST or config == null:
		return
	transport.send({
		KEY_KIND: KIND_SETUP,
		KEY_CONFIG: config.to_dict(),
		KEY_ROSTER: (roster.to_dict() if roster != null else {"participants": []}),
	})
	logged.emit("→ run setup (seed %d, %d participants)" %
			[config.seed, roster.all().size() if roster != null else 0])


## Mirrors off [signal CommandApplier.command_confirmed], NOT `command_applied`:
## the two are the same instant for every verb that has nothing to await after
## its mutation, and for an attack the difference is the host's whole animation
## tail (see that signal's note). A refused command never confirms, so the
## "changed nothing, mirror nothing" rule is now the applier's to enforce.
func _on_command_confirmed(command: Command) -> void:
	if mode != Mode.BROADCAST or transport == null:
		return
	if _applying_remote:
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
		KIND_SNAPSHOT:
			_on_graph_snapshot(payload)
		KIND_SETUP:
			_on_run_setup(payload)
		_:
			logged.emit("ignored payload with unknown kind %s" % payload.get(KEY_KIND))


## #527 receive side. Decodes straight into [member graph] — the caller (a
## lobby / join flow, #531) is responsible for handing this link an EMPTY
## graph before the host sends, same as [method GraphSnapshot.decode]'s own
## contract; decoding twice into an already-populated graph is not this
## method's job to make safe.
func _on_graph_snapshot(payload: Dictionary) -> void:
	var bytes: PackedByteArray = payload.get(KEY_SNAPSHOT, PackedByteArray())
	if graph == null or bytes.is_empty():
		return
	GraphSnapshot.decode(bytes, graph)
	logged.emit("← graph snapshot (%s)" % WorldFingerprint.describe(graph))


## #528 receive side. Decodes [RunConfig] + [ParticipantRoster] and hands both
## to [method GameSession.apply_received] — the seed is NOT re-resolved here,
## it rides the wire as the host's already-resolved value.
func _on_run_setup(payload: Dictionary) -> void:
	var config := RunConfig.from_dict(payload.get(KEY_CONFIG, {}))
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	GameSession.apply_received(config, roster)
	logged.emit("← run setup (seed %d, %d participants)" % [config.seed, roster.all().size()])


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
	_recv_seq += 1
	var seq := _recv_seq
	# BEFORE the mutation, deliberately: the host resolved this command against
	# the PRE-command world, so a probe that ran after `submit` would compare
	# its own re-resolution against the wrong state and report divergence that
	# is really just ordering. Mutates nothing — see [DeterminismProbe].
	# The settled flag is read HERE and passed down, not asked for later: by the
	# time the probe could ask, `submit` has already started a drain and the
	# answer is always "busy".
	if probe != null:
		probe.observe_before_apply(command,
				not command_applier.is_applying and command_applier.pending_count() == 0)
	_applying_remote = true
	command_applier.submit(command)
	# `submit` may await (move_core beats, end_turn's initiative tick), so the
	# flag is cleared when the queue actually empties, not on the next line.
	if command_applier.is_applying:
		await command_applier.applying_changed
	_applying_remote = false
	logged.emit("← %s" % command.type_tag())
	# Only the NEWEST handler, and only once the queue is empty, may compare.
	# Two async commands in flight (move_core's per-hop beats, end_turn's
	# initiative tick) resume from the SAME `applying_changed` and both then see
	# the post-both-commands world — so the earlier one would compare it against
	# its own older fingerprint and report a divergence that never happened. A
	# spurious ✗ poisons the only diagnostic this harness has, which is worth
	# more than a tick per command.
	# Both early returns below are commands that are never compared at all —
	# counted, not dropped, or the probe's denominator would silently be a lie
	# ("0 diverged of 412" while only 280 were ever looked at).
	if command_applier.is_applying or command_applier.pending_count() > 0:
		if probe != null:
			probe.observe_skipped(command)
		return
	if seq != _recv_seq:
		if probe != null:
			probe.observe_skipped(command)
		return
	var agrees := _report_sync(WorldFingerprint.compute(graph),
			int(payload.get(KEY_FINGERPRINT, 0)), "after %s" % command.type_tag())
	if probe != null:
		probe.observe_world(command, agrees)


## Returns the verdict as well as announcing it, so #529's probe can attribute
## it to the command that produced it without re-deriving the comparison.
func _report_sync(local: int, remote: int, when: String) -> bool:
	var agrees := local == remote
	sync_checked.emit(agrees, local, remote)
	if agrees:
		logged.emit("  ✓ in sync %s (fp %d)" % [when, local])
	else:
		logged.emit("  ✗ DIVERGED %s — mine %d, host %d" % [when, local, remote])
	return agrees
