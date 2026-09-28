class_name NetworkLink
extends Node
## The core of a wire: the state that gates EVERY kind, and the table that hands
## each payload to the [LinkChannel] owning its kind.
##
## What lives here is exactly what no single protocol may decide alone — the
## [member role], the build-stamp handshake ([constant KIND_HELLO] /
## [constant KIND_REFUSED]), the refused latch, and the pre-world latch. What a
## kind MEANS lives on its channel. Two links on one process (a lobby's and a
## level's) are two cores with their own channel tables; a kind is owned by at
## most one channel per core.
##
## Why the build gate rides the hello, why a refused client latches and a
## refused host does not, and why a peer is named by the transport and never by
## its own claim: see the method docs below — each is a bug that shipped once.

const KEY_KIND := "kind"
const KEY_SUMMARY := "summary"
const KEY_BUILD := "build"
const KEY_PEER := "peer"
const KEY_JOIN_PREFS := "join_prefs"

const BUILD_SHA := "sha"
const BUILD_BRANCH := "branch"
const BUILD_WORKTREE := "worktree"

## Link establishment. Upward it is a joiner announcing its build; downward it
## is the host's world announcement, whose world half a channel reads off
## [signal hello_accepted].
const KIND_HELLO := "hello"
## "I compared our builds and am hanging up." Diagnostics only — touches no world.
const KIND_REFUSED := "refused"

signal logged(line: String)
## This machine's own link was refused — by its own comparison or by the peer's.
signal link_refused(reason: String)
## Host-side: a joiner's build matched. Whether it gets a seat is the caller's.
signal peer_cleared(peer_id: int, join_prefs: Dictionary)
## Host-side: one joiner was turned away; the listener stays up.
signal peer_refused(peer_id: int, reason: String)
## Client-side: the host's hello passed the build gate. The world half of the
## hello (fingerprint compare) is a channel's, not the core's.
signal hello_accepted(payload: Dictionary)

@export var transport: NetworkTransport
## The channels this core dispatches to. Registered in [method _ready]; a
## channel may also [method register] itself later.
@export var channels: Array[LinkChannel] = []

## Setting this tells every channel ([method LinkChannel._on_identity_changed]);
## [CommandChannel] is how the applier learns whether it DECIDES or is told —
## single writer, so the two can never disagree. See
## [member CommandApplier.is_authority].
var role: NetworkConfig.Role = NetworkConfig.Role.OFFLINE:
	set(value):
		role = value
		_apply_role()

## What this peer announces and compares an incoming stamp against. Filled from
## [BuildInfo] in [method _ready]; a test sets it after `add_child` to stage a
## mismatch without needing two checkouts.
var build_stamp: Dictionary = {}

## A joining CLIENT's preferred name, carried in its own hello rather than
## waited on as a lobby pick. Empty means "not offering one"; what the string
## means is the lobby's business.
var join_display_name: String = ""

## The pre-world latch. A joining CLIENT opens its socket before it has a world
## and spends seconds generating one; a channel whose kinds mutate a world
## ([method LinkChannel.is_deferred]) has them DROPPED — not buffered — while
## this is set. Dropping is lossless because the transport is one ordered
## channel: the resync that clears this latch already contains everything sent
## before it. Defaults off, so hosts and offline links are untouched.
var defer_until_world: bool = false

## Latched once a build mismatch hung the link up; every payload is dropped
## from here on.
##
## [b]A separate flag and NOT `role = OFFLINE`[/b]: the role setter writes
## `is_authority = role != CLIENT`, so parking a refused CLIENT at OFFLINE would
## hand it authority. A refused link must go quiet, not become an authority.
var _refused: bool = false

var _owner_of: Dictionary = {}  # kind -> LinkChannel


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if build_stamp.is_empty():
		build_stamp = local_build_stamp()
	# The export resolves after the setter may already have run.
	_apply_role()
	for channel in channels:
		if channel != null:
			register(channel)
	if transport != null:
		transport.message_received.connect(_on_message_received)
		transport.link_changed.connect(func(status: String) -> void: logged.emit(status))
		transport.peer_joined.connect(_on_transport_peer_joined)


## Put [param channel] in the dispatch table. Idempotent; a kind another
## channel already owns is an authoring error, reported and left with its owner.
func register(channel: LinkChannel) -> void:
	if not channels.has(channel):
		channels.append(channel)
	for kind in channel.kinds():
		var owner: LinkChannel = _owner_of.get(kind)
		if owner != null and owner != channel:
			push_error("NetworkLink: kind %s already owned by %s" % [kind, owner.name])
			continue
		_owner_of[kind] = channel
	if channel.link != self:
		channel.link = self
		channel._on_attached()
		channel._on_identity_changed()


## The channel that owns [param kind], or null.
func channel_for(kind: String) -> LinkChannel:
	return _owner_of.get(kind)


## Put [param payload] on the wire to every peer. [param only_as] is the role
## this send is legal under (`-1`: any) — a host-only or client-only kind says
## so here rather than repeating the guard in every channel. Returns whether it
## was sent.
func send(payload: Dictionary, only_as: int = -1) -> bool:
	if transport == null or (only_as != -1 and role != only_as):
		return false
	transport.send(payload)
	return true


## As [method send], addressed to one peer.
func send_to(peer_id: int, payload: Dictionary, only_as: int = -1) -> bool:
	if transport == null or (only_as != -1 and role != only_as):
		return false
	transport.send_to(peer_id, payload)
	return true


func _apply_role() -> void:
	for channel in channels:
		if channel != null and channel.link == self:
			channel._on_identity_changed()


## Who this peer is, for the applier's intent-id high half. Asks the transport,
## never [member Node.multiplayer]; only `0` (not linked yet) falls back to the
## role, and [signal NetworkTransport.peer_joined] re-stamps it.
func local_peer_id() -> int:
	var assigned := transport.local_peer_id() if transport != null else 0
	if assigned != 0:
		return assigned
	return 2 if role == NetworkConfig.Role.CLIENT else 1


## The link came up, so the transport now knows an id the role could only
## guess — and a CLIENT announces its build the instant its dial completes, so
## a joiner on the wrong commit is refused before anybody seats it.
func _on_transport_peer_joined(_peer_id: int) -> void:
	_apply_role()
	if role == NetworkConfig.Role.CLIENT:
		announce_self()


## Client-side: "here I am, and this is the code I am running."
func announce_self() -> void:
	if transport == null or role != NetworkConfig.Role.CLIENT:
		return
	var payload := {
		KEY_KIND: KIND_HELLO,
		KEY_BUILD: build_stamp,
		KEY_PEER: transport.local_peer_id(),
	}
	if not join_display_name.is_empty():
		payload[KEY_JOIN_PREFS] = {"display_name": join_display_name}
	transport.send(payload)
	logged.emit("↑ hello (%s)" % describe_build(build_stamp))


## Host-side: "this is the code I am running", plus whatever a channel wants
## the joiner to read off [signal hello_accepted]. The channel composes
## [param extras] and hands them in — the core never names a channel.
## [WorldSyncChannel.send_hello] is the one caller that adds any.
func send_hello(extras: Dictionary = {}) -> void:
	if transport == null or role != NetworkConfig.Role.HOST:
		return
	var payload := extras.duplicate()
	payload[KEY_KIND] = KIND_HELLO
	payload[KEY_BUILD] = build_stamp
	transport.send(payload)


## The one dispatch: refused gate → handshake kinds → owner lookup → pre-world
## gate → [method LinkChannel.receive]. Every gate is a property of the LINK,
## so the decision about every kind is readable here.
func _on_message_received(payload: Dictionary) -> void:
	if _refused:
		return
	var kind := String(payload.get(KEY_KIND, ""))
	match kind:
		KIND_HELLO:
			_on_hello(payload)
			return
		KIND_REFUSED:
			_on_refused_by_peer(payload)
			return
	var channel: LinkChannel = _owner_of.get(kind)
	if channel == null:
		logged.emit("ignored payload with unknown kind %s" % payload.get(KEY_KIND))
		return
	if defer_until_world and channel.is_deferred(kind):
		logged.emit("← %s dropped — no world yet, waiting on resync" % kind)
		return
	channel.receive(kind, payload)


## A hello means two things depending on which end reads it:
## - under HOST it is a JOINER announcing itself → [method _gate_peer] clears or
##   refuses that one peer;
## - otherwise it is the host's world announcement: a build mismatch hangs up
##   this machine's own link, a match is handed on as [signal hello_accepted].
## A client owns nothing but its own link, so closing it is correct; a host
## owns the listener every other peer is on, so it never takes that route.
func _on_hello(payload: Dictionary) -> void:
	if role == NetworkConfig.Role.HOST:
		_gate_peer(payload)
		return
	if not _accept_build(payload):
		return
	hello_accepted.emit(payload)


## Absent stamp is a MISMATCH (a pre-check orphan build sends none and must not
## sail through); present-but-empty compares equal. Only the sha counts —
## branch and worktree ride along for the message.
func _accept_build(payload: Dictionary) -> bool:
	if not payload.has(KEY_BUILD):
		_refuse("the peer sent no build stamp — it predates this check", {})
		return false
	var theirs: Dictionary = payload.get(KEY_BUILD, {})
	if String(theirs.get(BUILD_SHA, "")) == String(build_stamp.get(BUILD_SHA, "")):
		return true
	_refuse("build mismatch", theirs)
	return false


## Hang up, loudly, on both ends. The reject goes out BEFORE
## [method NetworkTransport.stop] — a stopped transport drops the send, and the
## other end would print nothing.
func _refuse(reason: String, theirs: Dictionary) -> void:
	if _refused:
		return
	_refused = true
	_log_refusal(reason, theirs)
	if transport != null:
		transport.send({KEY_KIND: KIND_REFUSED, KEY_BUILD: build_stamp, KEY_SUMMARY: reason})
		transport.stop()
	link_refused.emit(reason)


## Host-side gate a joiner clears before it is offered anything. It EMITS rather
## than acts: whether a cleared peer gets a seat is not this class's call.
##
## The peer acted on is the one the TRANSPORT names
## ([method NetworkTransport.last_sender_id]), never the payload's claim — a
## client naming its neighbour would otherwise get that neighbour dropped. A
## disagreement refuses the sender. `0` from the transport falls back to the
## claim, so a fixture emitting [signal NetworkTransport.message_received] by
## hand stays on its path.
func _gate_peer(payload: Dictionary) -> void:
	var claimed := int(payload.get(KEY_PEER, 0))
	var verified := transport.last_sender_id() if transport != null else 0
	var peer_id := verified if verified != 0 else claimed
	if verified != 0 and claimed != 0 and claimed != verified:
		_refuse_peer(peer_id, "announced as peer %d but sent from peer %d"
				% [claimed, verified], payload.get(KEY_BUILD, {}))
		return
	if not payload.has(KEY_BUILD):
		_refuse_peer(peer_id, "the peer sent no build stamp — it predates this check", {})
		return
	var theirs: Dictionary = payload.get(KEY_BUILD, {})
	if String(theirs.get(BUILD_SHA, "")) != String(build_stamp.get(BUILD_SHA, "")):
		_refuse_peer(peer_id, "build mismatch", theirs)
		return
	logged.emit("↑ peer %d cleared (%s)" % [peer_id, describe_build(theirs)])
	peer_cleared.emit(peer_id, payload.get(KEY_JOIN_PREFS, {}))


## Hang up on ONE peer and keep listening. No latch and no stop — both belong to
## [method _refuse] and both would deafen a host to every other peer, and to the
## client whose checkout the operator is about to fix.
func _refuse_peer(peer_id: int, reason: String, theirs: Dictionary) -> void:
	_log_refusal(reason, theirs)
	if transport != null:
		transport.send_to(peer_id, {
			KEY_KIND: KIND_REFUSED, KEY_BUILD: build_stamp, KEY_SUMMARY: reason,
		})
		transport.drop_peer(peer_id)
	peer_refused.emit(peer_id, reason)


## The one public way onto [method _refuse_peer], for a caller that already
## knows a peer must go (the in-run join gate) and has no stamp to compare.
func refuse_peer(peer_id: int, reason: String) -> void:
	_refuse_peer(peer_id, reason, {})


## The other end did the comparing, so this side reports it. A HOST neither
## latches nor stops — stopping closes the listener every other peer is on, and
## latching makes it deaf to the fixed client. A CLIENT latches: the host has
## just dropped it, so going quiet is what stops it acting on anything in
## flight.
func _on_refused_by_peer(payload: Dictionary) -> void:
	var summary := String(payload.get(KEY_SUMMARY, "build mismatch"))
	_log_refusal(summary, payload.get(KEY_BUILD, {}))
	if role == NetworkConfig.Role.CLIENT:
		_refused = true
	link_refused.emit("refused by peer — %s" % summary)


func _log_refusal(reason: String, theirs: Dictionary) -> void:
	logged.emit("link REFUSED — %s" % reason)
	logged.emit("  peer:   %s" % describe_build(theirs))
	logged.emit("  mine:   %s" % describe_build(build_stamp))
	logged.emit("The peers are not running the same code.")


## This peer's stamp, straight off the [BuildInfo] autoload.
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
