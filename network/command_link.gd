@tool
class_name CommandLink
extends Node

## Bridges one [CommandApplier] to one [NetworkTransport]: the host broadcasts
## the commands it confirmed, every client applies them through its own applier.
##
## [b]Since #548 the link runs BOTH ways.[/b] Host-authoritative intent-up /
## confirmed-command-down (owner call, 2026-08-24): a client's
## [method CommandApplier.submit] does not queue — it emits the command upward
## as a [constant KIND_INTENT], the host puts it through the same
## `_validate -> confirm -> apply` a local command takes, and the confirm comes
## back down as an ordinary [constant KIND_COMMAND] the client applies through
## [method CommandApplier.apply_remote]. There is no local pre-application and
## no prediction (#548 decision 5).
##
## [b]A refusal has its own leg[/b] ([constant KIND_REFUSAL]), because a command
## the host's gate rejects never confirms and so never crosses down — and a
## client waiting on a confirmation that will never arrive is the failure mode
## this feature most needs to not ship. There is deliberately NO timeout, retry
## or heartbeat for a confirm that is simply lost (#548 decision 4): ENet's
## reliable-ordered channel is the guarantee, and a desync on a one-room LAN is
## a restart.
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
## [PickLootCommand] is the one verb built for the upward direction and now
## travels it, but it is still the exception on both ends: the applier answers
## it through [method CommandApplier._answer_loot_pick], deliberately NOT
## through its queue, so it never confirms and therefore can never be broadcast
## back down — that falls out rather than needing a guard here. For the same
## reason it opens no awaiting window and is not watched for refusal; see
## [method _on_intent].
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
## #560's join-handshake payload: an encoded [EntitySnapshot].
const KEY_ENTITIES := "entities"
## #548: which intent a [constant KIND_REFUSAL] is about — the id the CLIENT
## minted, echoed back so it can match.
const KEY_INTENT_ID := "intent"
## #548: why the authority refused, as a [StringName] code.
const KEY_REASON := "reason"
## #546: which code the sender is running. Rides the hello, never a [Command] —
## see [method send_hello].
const KEY_BUILD := "build"

## Keys inside [constant KEY_BUILD]. Only [constant BUILD_SHA] is COMPARED; the
## other two exist so the refusal message can name what the peer was on.
const BUILD_SHA := "sha"
const BUILD_BRANCH := "branch"
const BUILD_WORKTREE := "worktree"

const KIND_HELLO := "hello"
const KIND_COMMAND := "command"
## #546: "I am hanging up, and here is the build you failed to match." Sent by
## whichever side detects the mismatch, so BOTH ends print it.
const KIND_REFUSED := "refused"
## #527's join-handshake payload: an encoded [GraphSnapshot]. Additive and
## opt-in — sent only by [method send_graph_snapshot], never by [method send_hello]
## — so existing hello/fingerprint flows (and their tests) are untouched by a
## client that never calls it.
const KIND_SNAPSHOT := "snapshot"
## #528's join-handshake payload: [RunConfig] + [ParticipantRoster], both by
## value. Same additive shape as [constant KIND_SNAPSHOT] — sent only by
## [method send_run_setup].
const KIND_SETUP := "setup"
## #560's join-handshake payload: an encoded [EntitySnapshot] — the ENTITY half
## of what [constant KIND_SNAPSHOT] does for the graph. Same additive, opt-in
## shape: sent only by [method send_entity_snapshot].
const KIND_ENTITIES := "entities"
## #548's upward leg: a client's INTENT, not yet a command. Sent only under
## [constant Mode.MIRROR], received only under [constant Mode.BROADCAST] — the
## exact inverse of [constant KIND_COMMAND], which is why it is its own kind
## rather than a [constant KIND_COMMAND] with the mode gate inverted.
const KIND_INTENT := "intent"
## #548's refusal leg: the authority's gate said no. Sent only under
## [constant Mode.BROADCAST], received only under [constant Mode.MIRROR].
##
## A dedicated kind rather than an echoed command with a `refused` flag:
## [method CommandApplier.confirm] documents that a refused command "changed
## nothing and must not cross the wire", and an echo would force both the
## fingerprint compare and [DeterminismProbe] to special-case the one path that
## is the only cross-process diagnostic there is.
const KIND_REFUSAL := "refusal"

## The one refusal code today — [method CommandApplier._validate] answers a
## bool, so there is nothing finer to report yet. A [StringName], never a UI
## string: rendering a reason is a HUD question, not a wire one.
const REASON_REFUSED := &"refused"

enum Mode {
	OFF,        ## Wired but idle.
	BROADCAST,  ## Host: publish every confirmed command.
	MIRROR,     ## Client: apply everything received.
}

## A line worth showing a human (both roles). The harness prints these; nothing
## depends on their text.
signal logged(line: String)

## The client's comparison against the host's fingerprint — since #540 a
## PRE-apply one on both sides (the host stamps the world it is about to mutate,
## the client checks the world it is about to mutate). [param agrees] false means
## the two worlds have diverged, as of one command ago.
signal sync_checked(agrees: bool, local: int, remote: int)

## #546: the link was hung up because the peers are not running the same code.
## Terminal — nothing reconnects, by design.
signal link_refused(reason: String)

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
			command_applier.local_peer_id = _local_peer_id()

## True while a RECEIVED command is being submitted, so a client that is also
## broadcasting cannot echo it back. Wave 0 never sets both, but the guard is
## one line and its absence is an infinite loop.
var _applying_remote: bool = false

## #546. What this peer announces at link-up, and what it compares an incoming
## hello against. Filled from [BuildInfo] in [method _ready]; a test sets it
## after `add_child` to stage a mismatch without needing two checkouts.
var build_stamp: Dictionary = {}

## Latched once a build mismatch hung the link up. Every payload is dropped
## from here on.
##
## [b]This is a separate flag and NOT `mode = Mode.OFF`[/b], which is the
## tempting one-liner and is a trap: the `mode` setter writes
## `command_applier.is_authority = value != Mode.MIRROR`, so parking a refused
## CLIENT at OFF would hand it authority — and a client with authority is
## exactly the silent-divergence hole `mp_dev_sandbox._ready` documents (Blue's
## [AIController] starts deciding locally). A refused link must go quiet, not
## become an authority.
var _refused: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		# Deliberately BEFORE the build stamp is read: [BuildInfo] resolves in
		# its own `_ready`, and this `@tool` script runs during the editor's
		# import pass, when reaching into that autoload is not safe. Nothing in
		# the editor links anyway.
		return
	if build_stamp.is_empty():
		build_stamp = local_build_stamp()
	# The export resolves after the setter may already have run (a level scene
	# can set `mode` before this node is ready), so re-apply it here.
	if command_applier != null:
		command_applier.is_authority = mode != Mode.MIRROR
		command_applier.local_peer_id = _local_peer_id()
	if transport != null:
		transport.message_received.connect(_on_message_received)
		transport.link_changed.connect(func(status: String) -> void: logged.emit(status))
	if command_applier != null:
		command_applier.command_confirmed.connect(_on_command_confirmed)
		command_applier.intent_submitted.connect(_on_intent_submitted)
		command_applier.command_applied.connect(_on_command_applied)


## Who this peer is for [method CommandApplier._mint_intent_id]'s high half. It
## has one job: make sure no two peers ever mint the same
## [member Command.intent_id].
##
## [b]An id of 1 is not evidence of anything.[/b] It is what ENet hands the
## HOST, and equally what [method MultiplayerAPI.get_unique_id] returns under
## the [OfflineMultiplayerPeer] Godot installs by default — which every headless
## test and every [LoopbackTransport] pair runs under. So a non-1 id is
## believed (only a real ENet client is ever assigned one, and with three peers
## in the room it is the only thing that keeps two clients apart), and 1 falls
## back to the role, which is all a two-peer loopback needs.
func _local_peer_id() -> int:
	var assigned := multiplayer.get_unique_id() if multiplayer != null else 1
	if assigned != 1:
		return assigned
	return 2 if mode == Mode.MIRROR else 1


## Announce our world to a freshly-connected peer. Host-side; the client's reply
## is a log line, not a handshake — with one exception, below.
##
## [b]The hello carries this peer's build stamp (#546), and a mismatch REFUSES
## the link.[/b] That is the one thing here that negotiates, and it rides the
## hello rather than a message of its own precisely so it cannot be forgotten:
## the hello IS link establishment, so there is no way to bring a link up
## without the check running. It is emphatically NOT a [Command] and must never
## enter [method Command.to_dict] — a fixture at `test/fixtures/outcome/` is a
## serialized command dict, and a per-checkout sha inside one would re-capture
## every fixture on every commit.
func send_hello() -> void:
	if transport == null or mode != Mode.BROADCAST:
		return
	transport.send({
		KEY_KIND: KIND_HELLO,
		KEY_BUILD: build_stamp,
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


## Send every entity's accumulated state to a freshly-connected peer (#560) —
## host-side, opt-in, the sibling of [method send_graph_snapshot]. The peer
## DECORATES the entities its roster (#528) already spawned; nothing here
## spawns or mints an id. Send order does not matter: the receive side runs
## [method EntitySnapshot.decode] on arrival and defers the entity->node pass
## until a graph exists (see [method _on_entity_snapshot]).
func send_entity_snapshot() -> void:
	if transport == null or mode != Mode.BROADCAST or graph == null:
		return
	transport.send({KEY_KIND: KIND_ENTITIES, KEY_ENTITIES: EntitySnapshot.encode(graph)})
	logged.emit("→ entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


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
## a refused command never confirms, and since #540 a confirm fires BEFORE the
## mutation for every deterministic verb — which is the whole point, because it
## is what stops every peer being one mutation window behind the authority.
##
## [b]The fingerprint is READ here, never computed here (#540 decision 4).[/b]
## [method CommandApplier._drain] stamped [member Command.pre_fingerprint] the
## instant this command left the queue, which is the PRE-mutation world. Once the
## authority confirms before it applies, there is no post-mutation world to
## sample at this point — recomputing here would ship the world as it stood
## before the command either way, but only by accident for some verbs and not
## others. Stamping at submit makes it true uniformly, and the receiving peer
## compares against its own pre-state in [method _on_remote_command].
##
## This also fixes a plain waste: the fingerprint used to be computed twice per
## send, once for the payload and once for the log line.
func _on_command_confirmed(command: Command) -> void:
	if mode != Mode.BROADCAST or transport == null:
		return
	if _applying_remote:
		return
	transport.send({
		KEY_KIND: KIND_COMMAND,
		KEY_COMMAND: command.to_dict(),
		KEY_FINGERPRINT: command.pre_fingerprint,
	})
	logged.emit("→ %s (pre-fp %d)" % [command.type_tag(), command.pre_fingerprint])


## #548's upward leg. Mirrors off [signal CommandApplier.intent_submitted],
## which only a peer that does NOT decide ever emits — so the `MIRROR` gate here
## is belt-and-braces, and the honest statement of which direction this travels.
##
## No fingerprint rides up: the client's world is not the one being mutated
## from, and the authority's own pre-state is what the downward
## [constant KIND_COMMAND] compares against.
func _on_intent_submitted(command: Command) -> void:
	if mode != Mode.MIRROR or transport == null:
		return
	transport.send({KEY_KIND: KIND_INTENT, KEY_COMMAND: command.to_dict()})
	logged.emit("↑ %s (intent %d)" % [command.type_tag(), command.intent_id])


## Host-side. Watches every intent this link accepted, so a validate-fail can be
## reported back to the peer that is waiting on it. Erased on the way out either
## way — a confirmed command reports itself down the ordinary
## [constant KIND_COMMAND] leg and needs no second message.
##
## Keyed by [member Command.intent_id] rather than holding the command, because
## the applier hands the same object back and the id is the only thing the
## client can match on.
var _remote_intents: Dictionary = {}


## #548 receive side, host-only. A received intent enters the SAME queue as a
## local one — [method CommandApplier.submit], `_validate -> confirm -> apply`
## — and the confirm broadcasts to everyone, the originator included.
##
## [b]`_applying_remote` is deliberately NOT set here.[/b] That flag stops a
## mirrored command echoing back; an intent is the opposite case — the whole
## point is that the host's confirm goes out to every peer.
##
## The client's [member Command.intent_id] is preserved verbatim through
## `submit`'s mint-if-absent; nothing here re-stamps it.
func _on_intent(payload: Dictionary) -> void:
	if mode != Mode.BROADCAST or command_applier == null:
		return
	var command := CommandCodec.from_dict(payload.get(KEY_COMMAND, {}))
	if command == null:
		logged.emit("↑ undecodable intent, dropped")
		return
	if command.intent_id == 0:
		logged.emit("↑ %s with no intent id, dropped" % command.type_tag())
		return
	# [PickLootCommand] bypasses the queue ([method CommandApplier.submit]) and
	# so never reports through `command_applied`. It also never opens the
	# client's awaiting window, so there is nothing to refuse and nothing to
	# leak — watching it would strand an entry here forever.
	if not (command is PickLootCommand):
		_remote_intents[command.intent_id] = true
	logged.emit("↑ %s (intent %d)" % [command.type_tag(), command.intent_id])
	command_applier.submit(command)


## Host-side refusal routing (#548). A client's command that fails
## [method CommandApplier._validate] produces `command_applied(cmd, false)` here
## and nothing else — no confirm, so nothing crosses the wire — and the client
## would wait forever. This is the message that closes it.
##
## Only ever for a REFUSED intent. A successful one already went down as a
## [constant KIND_COMMAND], which is what closes the client's gate.
func _on_command_applied(command: Command, success: bool) -> void:
	if mode != Mode.BROADCAST or transport == null or command == null:
		return
	if not _remote_intents.has(command.intent_id):
		return
	_remote_intents.erase(command.intent_id)
	if success:
		return
	transport.send({
		KEY_KIND: KIND_REFUSAL,
		KEY_INTENT_ID: command.intent_id,
		KEY_REASON: String(REASON_REFUSED),
	})
	logged.emit("→ refused %s (intent %d)" % [command.type_tag(), command.intent_id])


## #548 receive side, client-only. Closes the awaiting window and reports the
## refusal through [signal CommandApplier.command_applied], which
## [PlayerInputController] already renders — no new feedback path, and
## emphatically no [signal CommandApplier.command_confirmed] (#525's camera
## director pans on that one).
func _on_refusal(payload: Dictionary) -> void:
	if mode != Mode.MIRROR or command_applier == null:
		return
	var intent_id := int(payload.get(KEY_INTENT_ID, 0))
	command_applier.refuse_intent(intent_id,
			StringName(payload.get(KEY_REASON, String(REASON_REFUSED))))
	logged.emit("← refused (intent %d)" % intent_id)


func _on_message_received(payload: Dictionary) -> void:
	# One gate for every kind, rather than one per handler: a refused link is
	# refused for commands, snapshots and run setup alike (#546).
	if _refused:
		return
	match String(payload.get(KEY_KIND, "")):
		KIND_HELLO:
			_on_hello(payload)
		KIND_REFUSED:
			_on_refused_by_peer(payload)
		KIND_COMMAND:
			_on_remote_command(payload)
		KIND_SNAPSHOT:
			_on_graph_snapshot(payload)
		KIND_SETUP:
			_on_run_setup(payload)
		KIND_ENTITIES:
			_on_entity_snapshot(payload)
		KIND_INTENT:
			_on_intent(payload)
		KIND_REFUSAL:
			_on_refusal(payload)
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
	# #560 pass 2: an entity snapshot that landed first parked its bytes here
	# because `core_location` and node-sourced effects need nodes to resolve
	# against. Now they exist.
	_drain_pending_entities()
	logged.emit("← graph snapshot (%s)" % WorldFingerprint.describe(graph))


## #528 receive side. Decodes [RunConfig] + [ParticipantRoster] and hands both
## to [method GameSession.apply_received] — the seed is NOT re-resolved here,
## it rides the wire as the host's already-resolved value.
func _on_run_setup(payload: Dictionary) -> void:
	var config := RunConfig.from_dict(payload.get(KEY_CONFIG, {}))
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	GameSession.apply_received(config, roster)
	logged.emit("← run setup (seed %d, %d participants)" % [config.seed, roster.all().size()])


## #560 receive side. [method EntitySnapshot.decode] is pass 1 — identity,
## entity-wide effects, and the whole stat board, none of which needs a
## [SkillNode]. Pass 2 (`core_location`, node-sourced effects) needs the graph,
## so it runs immediately if one has already arrived and is otherwise parked
## for [method _on_graph_snapshot] to drain. Both passes are idempotent, so
## neither ordering loses anything.
func _on_entity_snapshot(payload: Dictionary) -> void:
	var bytes: PackedByteArray = payload.get(KEY_ENTITIES, PackedByteArray())
	if graph == null or bytes.is_empty():
		return
	EntitySnapshot.decode(bytes, graph)
	_pending_entities = bytes
	if not graph.get_skill_nodes().is_empty():
		_drain_pending_entities()
	logged.emit("← entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


func _drain_pending_entities() -> void:
	if _pending_entities.is_empty() or graph == null:
		return
	var bytes := _pending_entities
	_pending_entities = PackedByteArray()
	EntitySnapshot.resolve_graph_refs(bytes, graph)


## An entity snapshot whose pass 2 is still waiting on a graph. Cleared the
## moment it is drained, so a later graph snapshot cannot re-run it.
var _pending_entities: PackedByteArray = PackedByteArray()


## #546's build gate, run before anything in the hello is believed.
##
## [b]An ABSENT stamp is a mismatch, not a pass.[/b] That is the whole incident:
## the peer that corrupted #534's sweep was a `dc5ef29`-era orphan — code from
## before this check existed, which sends a hello with no build key at all. If
## "no stamp" read as agreement, this fix would sail straight past the one run
## it was written for. Present-but-empty is different and DOES compare equal: an
## exported build has no `res://.git` and so no sha (see [BuildInfo]), and two
## shipped builds have nothing to disagree about here.
##
## [b]Only the sha is compared.[/b] Bare sha is the strictest key and the right
## one for a LAN where everyone pulls the same commit; it also refuses when one
## side has an unrelated uncommitted edit, which is a loud, instantly
## diagnosable false positive — the exact opposite of the silent failure this
## exists to kill. Branch and worktree ride along for the message only.
func _accept_build(payload: Dictionary) -> bool:
	if not payload.has(KEY_BUILD):
		_refuse("the peer sent no build stamp — it predates this check", {})
		return false
	var theirs: Dictionary = payload.get(KEY_BUILD, {})
	if String(theirs.get(BUILD_SHA, "")) == String(build_stamp.get(BUILD_SHA, "")):
		return true
	_refuse("build mismatch", theirs)
	return false


## Hang up, loudly, on both ends. The reject payload goes out BEFORE
## [method NetworkTransport.stop] — a transport silently drops a send once it is
## no longer linked, so the order here is what makes the other end print
## anything at all.
func _refuse(reason: String, theirs: Dictionary) -> void:
	if _refused:
		return
	_refused = true
	_log_refusal(reason, theirs)
	if transport != null:
		transport.send({KEY_KIND: KIND_REFUSED, KEY_BUILD: build_stamp, KEY_SUMMARY: reason})
		transport.stop()
	link_refused.emit(reason)


## The other end did the comparing, so this side only reports it.
##
## [b]It deliberately neither latches nor stops.[/b] Both are one line and both
## are wrong here. The refusing peer has already hung up its own side, so the
## socket goes down on its own and a send drops by itself — while stopping HERE
## closes a host's listening socket, and latching makes it deaf forever. That
## breaks the exact workflow this feature exists to serve: the operator reads
## the mismatch, fixes the client's checkout, relaunches the CLIENT — and would
## find a host that can no longer be reached, with nothing on screen saying to
## relaunch it too. On a LAN with several clients it is worse: one stale peer's
## refusal would disconnect everybody.
##
## Nothing is lost by staying open. This side is [constant Mode.BROADCAST], and
## [method _on_remote_command] requires [constant Mode.MIRROR], so a stale peer
## still cannot make it apply anything. The latch belongs on the side that
## REFUSED, where [method _refuse] sets it.
func _on_refused_by_peer(payload: Dictionary) -> void:
	_log_refusal(String(payload.get(KEY_SUMMARY, "build mismatch")),
			payload.get(KEY_BUILD, {}))
	link_refused.emit("refused by peer")


func _log_refusal(reason: String, theirs: Dictionary) -> void:
	logged.emit("link REFUSED — %s" % reason)
	logged.emit("  peer:   %s" % describe_build(theirs))
	logged.emit("  mine:   %s" % describe_build(build_stamp))
	logged.emit("The peers are not running the same code.")


## This peer's stamp, straight off the [BuildInfo] autoload — which reads
## `res://.git` once at startup, with no `git` subprocess.
static func local_build_stamp() -> Dictionary:
	return {
		BUILD_SHA: BuildInfo.short_sha,
		BUILD_BRANCH: BuildInfo.branch,
		BUILD_WORKTREE: BuildInfo.worktree,
	}


## e.g. `4174f36 (master)`, or `54cfcd7 (master @ issue-546-…)` in a worktree.
static func describe_build(stamp: Dictionary) -> String:
	var sha := String(stamp.get(BUILD_SHA, ""))
	if sha.is_empty():
		return "unknown — no build stamp"
	var branch := String(stamp.get(BUILD_BRANCH, ""))
	var worktree := String(stamp.get(BUILD_WORKTREE, ""))
	var where := branch if branch != "" else "detached"
	if worktree != "":
		where += " @ " + worktree
	return "%s (%s)" % [sha, where]


## The link-up check. A mismatch HERE — before a single command has crossed —
## means the two graphs disagree about node identity, which in a hand-authored
## scene almost always means unminted `stable_id`s. That is the failure this
## harness is built to make loud.
func _on_hello(payload: Dictionary) -> void:
	if not _accept_build(payload):
		return
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
	# ── Compared BEFORE the mutation, on both sides (#540 decision 4) ─────────
	# The host stamped its fingerprint when this command left ITS queue, so what
	# rides the wire is "the world I was about to apply this to". The honest
	# comparison against that is the same question asked here: "the world I am
	# about to apply this to". Pre-state versus pre-state.
	#
	# `settled` still gates it, and for the reason the old post-apply compare
	# needed it too: a non-empty local queue means this peer is somewhere INSIDE
	# an earlier command, so its world is not at any command's boundary and a
	# comparison would report a divergence that never happened. A spurious ✗
	# poisons the only diagnostic this harness has.
	#
	# What DOES go away is the far larger source of skips — a compare that had to
	# survive its own `await`, and so lost to any command that arrived meanwhile
	# (the `_recv_seq` supersede check this replaces). Nothing awaits before the
	# compare now.
	#
	# The cost, accepted and stated in the issue: divergence detection lags one
	# command, and a run's FINAL command is never compared at all.
	var settled := not command_applier.is_applying and command_applier.pending_count() == 0
	# The same flag the probe needs, read once — by the time the probe could ask
	# for itself, `submit` has started a drain and the answer is always "busy".
	if probe != null:
		probe.observe_before_apply(command, settled)
	if settled:
		var agrees := _report_sync(WorldFingerprint.compute(graph),
				int(payload.get(KEY_FINGERPRINT, 0)), "before %s" % command.type_tag())
		if probe != null:
			probe.observe_world(command, agrees)
	elif probe != null:
		# Counted, not dropped, or the probe's denominator would silently be a
		# lie ("0 diverged of 412" while only 280 were ever looked at).
		probe.observe_skipped(command)
	_applying_remote = true
	# [method CommandApplier.apply_remote], NOT `submit` — since #548 `submit`
	# is the INTENT door, and on this MIRROR peer it would send the host's own
	# confirmed command straight back up. `apply_remote` is the same queue and
	# the same full `_validate -> confirm -> apply`, so
	# [signal CommandApplier.command_confirmed] still fires here, on the peer
	# that applies.
	command_applier.apply_remote(command)
	# `submit` may await (move_core beats, end_turn's initiative tick), so the
	# flag is cleared when the queue actually empties, not on the next line.
	if command_applier.is_applying:
		await command_applier.applying_changed
	_applying_remote = false
	logged.emit("← %s" % command.type_tag())


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
