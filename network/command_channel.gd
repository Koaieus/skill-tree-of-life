class_name CommandChannel
extends LinkChannel
## Bridges one [CommandApplier] to a [NetworkLink]: the host broadcasts the
## commands it confirmed, every client applies them through its own applier.
##
## [b]It runs BOTH ways.[/b] Host-authoritative intent-up / confirmed-command-down
## (owner call, 2026-08-24): a client's [method CommandApplier.submit] does not
## queue — it emits the command upward as a [constant KIND_INTENT], the host puts
## it through the same `_validate -> confirm -> apply` a local command takes, and
## the confirm comes back down as an ordinary [constant KIND_COMMAND] the client
## applies through [method CommandApplier.apply_remote]. There is no local
## pre-application and no prediction.
##
## [b]A refusal has its own leg[/b] ([constant KIND_REFUSAL]), because a command
## the host's gate rejects never confirms and so never crosses down — and a
## client waiting on a confirmation that will never arrive is the failure mode
## this feature most needs to not ship. There is deliberately NO timeout, retry
## or heartbeat for a confirm that is simply lost: ENet's reliable-ordered
## channel is the guarantee, and a desync on a one-room LAN is a restart.
##
## [b]Every verb [CommandApplier] handles mirrors[/b] — launch_attack rides down
## with an [AttackRecord] the client replays rather than re-resolving, loot as a
## [LootRoundCommand] per round carrying what was granted BY VALUE. This class
## mirrors whatever the applier handles, so a verb missing from the wire is
## almost always a missing submission site, not a transport gap. Check who
## raises the command first.
##
## [PickLootCommand] is the one verb built for the upward direction, and the
## exception on both ends: the applier answers it through
## [method PickLootCommandHandler.apply], NOT through its queue, so it never
## confirms and can never be broadcast back down. For the same reason it opens
## no awaiting window and is not watched for refusal; see [method _on_intent].
##
## [b]The determinism probe hangs off the mirror path here[/b] as two optional
## calls into [DeterminismProbe] and no logic of its own; the per-command
## compare is [WorldSyncChannel]'s. It never changes what is applied, and it is
## off unless a harness turns it on.
##
## This channel is also the one that tells the applier whether it DECIDES or is
## told: the core's [member NetworkLink.role] reaches it through
## [method _on_identity_changed], so the core holds no applier.
##
## See `docs/domain/multiplayer-harness.md` and
## `docs/domain/determinism-probe.md`.

## Wire envelope keys. The command's own dictionary is nested rather than merged
## so the codec keeps owning its whole namespace.
const KEY_COMMAND := "cmd"
const KEY_FINGERPRINT := "fp"
## Which intent a [constant KIND_REFUSAL] is about — the id the CLIENT minted,
## echoed back so it can match.
const KEY_INTENT_ID := "intent"
## Why the authority refused, as a [StringName] code.
const KEY_REASON := "reason"

## Host → every client: a command the host confirmed.
const KIND_COMMAND := "command"
## The upward leg: a client's INTENT, not yet a command. Sent only under
## [constant NetworkConfig.Role.CLIENT], received only under
## [constant NetworkConfig.Role.HOST] — the exact inverse of
## [constant KIND_COMMAND], which is why it is its own kind rather than a
## [constant KIND_COMMAND] with the role gate inverted.
const KIND_INTENT := "intent"
## The refusal leg: the authority's gate said no. Sent only under
## [constant NetworkConfig.Role.HOST], received only under
## [constant NetworkConfig.Role.CLIENT].
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

@export var command_applier: CommandApplier
## Optional and OFF unless a harness enables it. A null probe, or a disabled
## one, costs one branch per received command.
@export var probe: DeterminismProbe

## True while a RECEIVED command is being applied, so a client that is also
## broadcasting cannot echo it back. The guard is one line and its absence is an
## infinite loop.
var _applying_remote: bool = false

## Host-side. Watches every intent this channel accepted, so a validate-fail can
## be reported back to the peer that is waiting on it. Erased on the way out
## either way — a confirmed command reports itself down the ordinary
## [constant KIND_COMMAND] leg and needs no second message.
##
## Keyed by [member Command.intent_id] rather than holding the command, because
## the applier hands the same object back and the id is the only thing the
## client can match on.
var _remote_intents: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_connect_applier()


func _on_attached() -> void:
	_connect_applier()


func _connect_applier() -> void:
	if command_applier == null or command_applier.command_confirmed.is_connected(_on_command_confirmed):
		return
	command_applier.command_confirmed.connect(_on_command_confirmed)
	command_applier.intent_submitted.connect(_on_intent_submitted)
	command_applier.command_applied.connect(_on_command_applied)
	command_applier.command_stamped.connect(_on_command_stamped)


## The single writer of [member CommandApplier.is_authority]: whatever the
## core's role says, so the two can never disagree. A refused CLIENT keeps its
## role (see [member NetworkLink._refused]) and so never becomes an authority.
func _on_identity_changed() -> void:
	if command_applier == null or link == null:
		return
	command_applier.is_authority = link.role != NetworkConfig.Role.CLIENT
	command_applier.local_peer_id = link.local_peer_id()


func kinds() -> Array[String]:
	return [KIND_COMMAND, KIND_INTENT, KIND_REFUSAL]


## Only [constant KIND_COMMAND] waits for a world — which of this channel's
## kinds [member NetworkLink.defer_until_world] swallows, and as important,
## which it must NOT:
##
## [b]Dropped[/b]
## [constant KIND_COMMAND]: the whole point. A world mutation against a
## half-built graph, superseded wholesale by the resync.
##
## [b]Passed[/b]
## [constant KIND_INTENT]: a host-only handler, and the latch is only ever set
## on a CLIENT peer — gating it would be unreachable, so the decision is
## recorded here rather than as a guard that can never fire.
## [constant KIND_REFUSAL]: the answer to an intent this peer raised, and a
## joining client has raised none — but it mutates nothing and a swallowed
## refusal would strand a waiting submitter forever, which is exactly the
## failure the refusal leg exists to prevent.
func is_deferred(kind: String) -> bool:
	return kind == KIND_COMMAND


func receive(kind: String, payload: Dictionary) -> void:
	match kind:
		KIND_COMMAND:
			_on_remote_command(payload)
		KIND_INTENT:
			_on_intent(payload)
		KIND_REFUSAL:
			_on_refusal(payload)


func _role() -> NetworkConfig.Role:
	return link.role if link != null else NetworkConfig.Role.OFFLINE


## Mirrors off [signal CommandApplier.command_confirmed], NOT `command_applied`:
## a refused command never confirms, and a confirm fires BEFORE the mutation for
## every deterministic verb — which is what stops every peer being one mutation
## window behind the authority.
##
## [b]The fingerprint is READ here, never computed here.[/b]
## [method CommandApplier._drain] stamped [member Command.pre_fingerprint] the
## instant this command left the queue, which is the PRE-mutation world; the
## receiving peer compares against its own pre-state at its own stamp point.
func _on_command_confirmed(command: Command) -> void:
	if _applying_remote or link == null:
		return
	if link.send({
		NetworkLink.KEY_KIND: KIND_COMMAND,
		KEY_COMMAND: command.to_dict(),
		KEY_FINGERPRINT: command.pre_fingerprint,
	}, NetworkConfig.Role.HOST):
		_log("→ %s (pre-fp %d)" % [command.type_tag(), command.pre_fingerprint])


## The upward leg. Mirrors off [signal CommandApplier.intent_submitted], which
## only a peer that does NOT decide ever emits — so the `CLIENT` gate is
## belt-and-braces, and the honest statement of which direction this travels.
##
## No fingerprint rides up: the client's world is not the one being mutated
## from, and the authority's own pre-state is what the downward
## [constant KIND_COMMAND] compares against.
func _on_intent_submitted(command: Command) -> void:
	if link == null:
		return
	if link.send({NetworkLink.KEY_KIND: KIND_INTENT, KEY_COMMAND: command.to_dict()},
			NetworkConfig.Role.CLIENT):
		_log("↑ %s (intent %d)" % [command.type_tag(), command.intent_id])


## Receive side, host-only. A received intent enters the SAME queue as a local
## one — [method CommandApplier.submit], `_validate -> confirm -> apply` — and
## the confirm broadcasts to everyone, the originator included.
##
## [b]`_applying_remote` is deliberately NOT set here.[/b] That flag stops a
## mirrored command echoing back; an intent is the opposite case — the whole
## point is that the host's confirm goes out to every peer.
##
## The client's [member Command.intent_id] is preserved verbatim through
## `submit`'s mint-if-absent; nothing here re-stamps it.
func _on_intent(payload: Dictionary) -> void:
	if _role() != NetworkConfig.Role.HOST or command_applier == null:
		return
	var command := CommandCodec.from_dict(payload.get(KEY_COMMAND, {}))
	if command == null:
		_log("↑ undecodable intent, dropped")
		return
	if command.intent_id == 0:
		_log("↑ %s with no intent id, dropped" % command.type_tag())
		return
	# [PickLootCommand] bypasses the queue ([method CommandApplier.submit]) and
	# so never reports through `command_applied`. It also never opens the
	# client's awaiting window, so there is nothing to refuse and nothing to
	# leak — watching it would strand an entry here forever.
	if not (command is PickLootCommand):
		_remote_intents[command.intent_id] = true
	_log("↑ %s (intent %d)" % [command.type_tag(), command.intent_id])
	command_applier.submit(command)


## Host-side refusal routing. A client's command that fails
## [method CommandApplier._validate] produces `command_applied(cmd, false)` here
## and nothing else — no confirm, so nothing crosses the wire — and the client
## would wait forever. This is the message that closes it.
##
## Only ever for a REFUSED intent. A successful one already went down as a
## [constant KIND_COMMAND], which is what closes the client's gate.
func _on_command_applied(command: Command, success: bool) -> void:
	if _role() != NetworkConfig.Role.HOST or command == null:
		return
	if not _remote_intents.has(command.intent_id):
		return
	_remote_intents.erase(command.intent_id)
	if success:
		return
	if link.send({
		NetworkLink.KEY_KIND: KIND_REFUSAL,
		KEY_INTENT_ID: command.intent_id,
		KEY_REASON: String(REASON_REFUSED),
	}, NetworkConfig.Role.HOST):
		_log("→ refused %s (intent %d)" % [command.type_tag(), command.intent_id])


## Receive side, client-only. Closes the awaiting window and reports the
## refusal through [signal CommandApplier.command_applied], which
## [PlayerInputController] already renders — no new feedback path, and
## emphatically no [signal CommandApplier.command_confirmed] (the camera
## director pans on that one).
func _on_refusal(payload: Dictionary) -> void:
	if _role() != NetworkConfig.Role.CLIENT or command_applier == null:
		return
	var intent_id := int(payload.get(KEY_INTENT_ID, 0))
	command_applier.refuse_intent(intent_id,
			StringName(payload.get(KEY_REASON, String(REASON_REFUSED))))
	_log("← refused (intent %d)" % intent_id)


func _on_remote_command(payload: Dictionary) -> void:
	if _role() != NetworkConfig.Role.CLIENT or command_applier == null:
		return
	var command := CommandCodec.from_dict(payload.get(KEY_COMMAND, {}))
	if command == null:
		_log("← undecodable payload, dropped")
		return
	# ── Compared BEFORE the mutation, on both sides ───────────────────────────
	# The host stamped its fingerprint when this command left ITS queue, so what
	# rides the wire is "the world I was about to apply this to"; the honest
	# comparison is the same question asked here. Pre-state versus pre-state.
	#
	# `settled` still gates it: a non-empty local queue means this peer is
	# somewhere INSIDE an earlier command, so its world is not at any command's
	# boundary and a comparison would report a divergence that never happened.
	# A spurious ✗ poisons the only diagnostic this harness has.
	#
	# The cost, accepted: divergence detection lags one command, and a run's
	# FINAL command is never compared at all. The host's stamp travels ON the
	# command, so the compare happens at this peer's own stamp point inside
	# [method CommandApplier._drain] ([method WorldSyncChannel._on_command_stamped]).
	command.host_fingerprint = int(payload.get(KEY_FINGERPRINT, 0))
	# The same flag the probe needs, read once — by the time the probe could ask
	# for itself, `apply_remote` has started a drain and the answer is always
	# "busy". The RESOLVE/LAND re-derivation happens here, on arrival, because
	# it must run before this peer applies.
	if probe != null:
		probe.observe_before_apply(command,
				not command_applier.is_applying and command_applier.pending_count() == 0)
	_applying_remote = true
	# [method CommandApplier.apply_remote], NOT `submit` — `submit` is the
	# INTENT door, and on this CLIENT peer it would send the host's own
	# confirmed command straight back up. `apply_remote` is the same queue and
	# the same full `_validate -> confirm -> apply`, so
	# [signal CommandApplier.command_confirmed] still fires here.
	command_applier.apply_remote(command)
	# Applying may await (move_core beats, end_turn's initiative tick), so the
	# flag is cleared when the queue actually empties, not on the next line.
	if command_applier.is_applying:
		await command_applier.applying_changed
	_applying_remote = false
	_log("← %s" % command.type_tag())


## The unstamped half of the per-command check: a received command whose
## envelope carried no host stamp is COUNTED, not dropped, or the probe's
## denominator would lie ("0 diverged of 412" while 280 were looked at). The
## compare itself is [method WorldSyncChannel._on_command_stamped]'s; this half
## needs [member _applying_remote], which is ours.
func _on_command_stamped(command: Command) -> void:
	if _role() != NetworkConfig.Role.CLIENT or command == null or command.host_fingerprint != 0:
		return
	if probe != null and _applying_remote:
		probe.observe_skipped(command)


func _log(line: String) -> void:
	if link != null:
		link.logged.emit(line)
