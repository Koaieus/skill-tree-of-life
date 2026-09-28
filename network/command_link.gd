@tool
class_name CommandLink
extends LinkChannel

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
## it through [method PickLootCommandHandler.apply], deliberately NOT
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
## #646: a [LootPickOffer]'s wire form. Its own key, not [constant KEY_COMMAND]
## — an offer is explicitly NOT a [Command], and this class's convention is one
## key per concept even where several nest a plain [Dictionary].
const KEY_OFFER := "offer"
## #546: which code the sender is running. Rides the hello, never a [Command] —
## see [method send_hello].
const KEY_BUILD := "build"
## #714: one lobby seat's changed fields, on the way UP. Its own key rather than
## [constant KEY_ROSTER] because it is emphatically not a roster — a client never
## sends one, it sends the single row it touched and lets the host answer with
## the whole thing.
const KEY_PICK := "pick"
## #755: which seat a [constant KIND_SEAT_HANDOVER] is about — a [member
## Participant.id], never a `peer_id`. The peer whose id it was is by definition
## gone, and every mirror already resolves a seat by participant id
## ([method SeatHandover.entity_for_participant]); a mirror has no view of a
## sibling's peer id at all.
const KEY_PARTICIPANT := "participant"
## #716: what the sender CLAIMS its own peer id is, on a client's announce.
##
## [b]It is never the authority.[/b] [method NetworkLink._gate_peer] acts on
## [method NetworkTransport.last_sender_id], the id the transport itself vouches
## for; this key exists only so a disagreement between the two can be seen and
## named. Trusting it would let one client announce its neighbour's id and have
## a seated, innocent peer disconnected — which is not the "one LAN, one room"
## trust model [constant LobbyScreen.PICK_PEER] rides on, but a client trivially
## acting on another client's behalf.
const KEY_PEER := "peer"
## #741: what a joining client would LIKE its seat to carry, rides the hello
## alongside identity — optional, and never trusted further than any other
## lobby pick. A bare dict rather than one key each, so a later addition (a
## preferred colour, say) is one more entry here rather than one more const.
const KEY_JOIN_PREFS := "join_prefs"

## #715: this resync (or the request that asked for it) is the JOIN's first
## world, not a mid-run repair. Set on both legs of the join race — the host's
## push in [code]GameRoot._on_peer_joined[/code] and the client's pull in
## [code]GameRoot.pull_host_world[/code] — so the client can apply the first one
## to arrive and drop the loser. A repair never carries it.
const KEY_JOIN := "join"

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
## shim: the world kinds are [WorldSyncChannel]'s; aliased for the callers
## that still name them here.
const KIND_SNAPSHOT := WorldSyncChannel.KIND_SNAPSHOT
const KIND_SETUP := WorldSyncChannel.KIND_SETUP
const KIND_ENTITIES := WorldSyncChannel.KIND_ENTITIES
const KIND_RESYNC := WorldSyncChannel.KIND_RESYNC
const KIND_RESYNC_REQUEST := WorldSyncChannel.KIND_RESYNC_REQUEST
## #548's upward leg: a client's INTENT, not yet a command. Sent only under
## [constant NetworkConfig.Role.CLIENT], received only under [constant NetworkConfig.Role.HOST] — the
## exact inverse of [constant KIND_COMMAND], which is why it is its own kind
## rather than a [constant KIND_COMMAND] with the mode gate inverted.
const KIND_INTENT := "intent"
## #548's refusal leg: the authority's gate said no. Sent only under
## [constant NetworkConfig.Role.HOST], received only under [constant NetworkConfig.Role.CLIENT].
##
## A dedicated kind rather than an echoed command with a `refused` flag:
## [method CommandApplier.confirm] documents that a refused command "changed
## nothing and must not cross the wire", and an echo would force both the
## fingerprint compare and [DeterminismProbe] to special-case the one path that
## is the only cross-process diagnostic there is.
const KIND_REFUSAL := "refusal"
## #646's downward offer — "show this collector a pick screen, here is the
## draw" ([LootPickOffer]). NOT a [Command]: it mutates nothing on arrival, so
## it never touches [CommandApplier] at all, unlike every kind above it. Same
## additive, opt-in shape as [constant KIND_SNAPSHOT] — sent only by
## [method send_loot_offer], which [method _ready] wires to
## [signal LootPickRegistry.offer_parked].
const KIND_LOOT_OFFER := "loot_offer"
## #714's downward leg: the host's WHOLE authoritative [ParticipantRoster] while
## the menu is still up, after every accepted change, join or drop.
##
## [b]Why not [constant KIND_SETUP].[/b] That envelope carries a [RunConfig] too
## and its receiver hands both to [method GameSession.apply_received], which
## asserts the seed is already resolved and OPENS a run by emitting
## [signal GameSession.run_started]. A lobby's seed is still the `0` sentinel
## until START and a lobby must not open a run, so relaxing that gate to reuse
## the envelope would trade a load-bearing assertion for one saved constant.
## This kind carries [constant KEY_ROSTER] and nothing else, touches
## [GameSession] not at all, and is decoded straight back into a lobby view.
##
## Whole-roster rather than a delta, deliberately: it is a handful of rows, and a
## delta protocol would buy an ordering problem a lobby does not have.
const KIND_LOBBY := "lobby"
## #714's upward leg: "I picked X for my seat." Carries the sender's `peer_id`,
## the target [member Participant.id] and only the fields that changed, in
## [method Participant.to_dict]'s encoding. Sent only under
## [constant NetworkConfig.Role.CLIENT], received only under [constant NetworkConfig.Role.HOST] — the
## same inversion [constant KIND_INTENT] draws for the world, at the roster's
## scope: a pick is an INTENT, and the host's [constant KIND_LOBBY] answer is the
## confirmation.
const KIND_LOBBY_PICK := "lobby_pick"
## #755's downward leg: "the human on this seat is gone; the AI has it now."
## Sent by the host from [method SeatHandover.hand_seat_to_ai] when a seated peer
## drops mid-run.
##
## [b]Not a [Command].[/b] Same shape as [constant KIND_LOOT_OFFER]: it never
## touches [CommandApplier], because there is nothing to validate and nothing
## that may refuse it — the peer is already gone, and a gate with no gate behind
## it is only a way for the mirrors to disagree with the host. It also mutates
## no world state that [WorldFingerprint] or [EntitySnapshot] carry
## ([member Entity.is_human_controlled] is in neither), so it cannot desync a
## compare.
##
## [b]Why it has to cross at all[/b], rather than staying the host-local banner
## it was until #755: [method SeatPolicy.vision_group] keys on
## [member Entity.is_human_controlled], so a coop ally on a THIRD machine kept
## seeing through a hero that had become an AI — AI never shares vision, and the
## host had already stopped. That fog divergence is the argument; the banner
## every peer now gets is the smaller half.
const KIND_SEAT_HANDOVER := "seat_handover"

## The one refusal code today — [method CommandApplier._validate] answers a
## bool, so there is nothing finer to report yet. A [StringName], never a UI
## string: rendering a reason is a HUD question, not a wire one.
const REASON_REFUSED := &"refused"

## A line worth showing a human (both roles). The harness prints these; nothing
## depends on their text.
signal logged(line: String)

## The client's comparison against the host's fingerprint — since #540 a
## PRE-apply one on both sides (the host stamps the world it is about to mutate,
## the client checks the world it is about to mutate). [param agrees] false means
## the two worlds have diverged, as of one command ago.
signal sync_checked(agrees: bool, local: int, remote: int)

## #561: this peer, as the authority, pushed a full repair. [param reason] is
## the verdict that caused it. A green run never emits this — which is the
## assertion that keeps the "shout" half of #521 D3 honest.
signal resync_sent(reason: String)

## #561: this peer, as a client, had a repair applied to it. Emitted AFTER the
## world is whole again. Deliberately not [signal CommandApplier.command_confirmed]
## — #525's camera director pans on that one, and nobody pans for a repair.
signal resync_applied(reason: String)

## #546: the link was hung up because the peers are not running the same code.
## Terminal — nothing reconnects, by design.
signal link_refused(reason: String)

## #716, host-side: this peer announced itself and its build matches ours. THE
## gate a joiner clears before anything is offered to it — [LobbyScreen] seats a
## peer on this signal rather than on [signal NetworkTransport.peer_joined],
## which is what makes "a refused peer never appears in anyone's roster" a
## property of the wiring rather than of a check somebody has to remember.
## [param join_prefs] is the cleared peer's [constant KEY_JOIN_PREFS], verbatim
## and unvalidated — whatever [LobbyScreen] does with a "display_name" inside
## it goes through the same writer a local pick does (#741); this class only
## forwards what arrived.
signal peer_cleared(peer_id: int, join_prefs: Dictionary)

## #716, host-side: this peer's build does not match ours and it has been
## disconnected. The listener is up, every other peer is untouched, and nothing
## on this end latched — refusing the PEER is not refusing the socket.
signal peer_refused(peer_id: int, reason: String)

## #755, client-side: the host handed a dropped peer's seat to the AI. Carries
## the [member Participant.id], decoded no further here — what a handover MEANS
## to a level ([method SeatHandover._on_seat_handover]) is the level's, same split
## as [signal LobbyChannel.lobby_roster_received].
signal seat_handover_received(participant_id: int)

@export var transport: NetworkTransport
@export var command_applier: CommandApplier:
	set(value):
		command_applier = value
		if link != null:
			link.command_applier = value
@export var graph: Graph:
	set(value):
		graph = value
		_forward_to_world(&"graph", value)

## The level's clock. Only ever WRITTEN through
## [method EntitySnapshot.restore_turn_cursor], and only on a mirror: who holds
## the turn is a host decision that a repaired peer receives rather than
## reproduces (#756). Wired by `game_root.tscn`.
@export var turn_manager: TurnManager:
	set(value):
		turn_manager = value
		_forward_to_world(&"turn_manager", value)
## #646: the outstanding-pick book, ONLY consulted here for
## [signal LootPickRegistry.offer_parked] — the trigger for
## [method send_loot_offer]. Null is supported (no registry wired, e.g. every
## existing [CommandLink] test): the offer leg simply never sends, same as
## every other additive/opt-in kind on this class.
@export var loot_pick_registry: LootPickRegistry

## #529's measurement, optional and OFF unless a harness enables it. A null
## probe, or a disabled one, costs one branch per received command — the hooks
## below are three calls and no logic, because the question "could a peer have
## derived this?" is a whole subject and belongs in its own file, not smeared
## across the verb path #463's other children are also editing.
@export var probe: DeterminismProbe:
	set(value):
		probe = value
		_forward_to_world(&"probe", value)

## shim: the role, build stamp, join name and refused latch live on the core
## ([NetworkLink]) now; these forward so callers not yet re-pointed keep working.
## A value written before a core is attached is parked in [member _early] and
## handed over on attach.
var role: NetworkConfig.Role:
	get:
		return link.role if link != null else _early.get("role", NetworkConfig.Role.OFFLINE)
	set(value):
		_forward("role", "role", value)

var build_stamp: Dictionary:
	get:
		return link.build_stamp if link != null else _early.get("stamp", {})
	set(value):
		_forward("stamp", "build_stamp", value)

var join_display_name: String:
	get:
		return link.join_display_name if link != null else _early.get("name", "")
	set(value):
		_forward("name", "join_display_name", value)

var _refused: bool:
	get:
		return link._refused if link != null else false

var _early: Dictionary = {}

## True while a RECEIVED command is being submitted, so a client that is also
## broadcasting cannot echo it back. Wave 0 never sets both, but the guard is
## one line and its absence is an infinite loop.
var _applying_remote: bool = false


func _forward(early_key: String, core_property: String, value: Variant) -> void:
	if link != null:
		link.set(core_property, value)
	else:
		_early[early_key] = value


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# A level mounts a [NetworkLink] beside this node and lists it as a channel
	# there; a bare `CommandLink.new()` (tests, the outcome playground) composes
	# its own so it keeps working as the one node it always was.
	# The private core gets a private [WorldSyncChannel] too, fed this node's
	# world exports, since the world kinds are no longer this channel's.
	if link == null:
		var world := WorldSyncChannel.new()
		world.name = "WorldSyncChannel"
		world.graph = graph
		world.turn_manager = turn_manager
		world.command_applier = command_applier
		world.probe = probe
		add_child(world)
		var core := NetworkLink.new()
		core.name = "NetworkLink"
		core.transport = transport
		core.command_applier = command_applier
		core.channels = [world, self] as Array[LinkChannel]
		add_child(core)
	_wire_world_shims()
	if command_applier != null:
		command_applier.command_confirmed.connect(_on_command_confirmed)
		command_applier.intent_submitted.connect(_on_intent_submitted)
		command_applier.command_applied.connect(_on_command_applied)
		command_applier.command_stamped.connect(_on_command_stamped)
	if loot_pick_registry != null:
		loot_pick_registry.offer_parked.connect(_on_offer_parked)


## shim: re-emit the world channel's signals here and hand it what callers
## still set on this node, until those callers re-point to the channel. Runs
## from [method _ready], by which point the core has registered every channel.
func _wire_world_shims() -> void:
	var world := world_sync()
	if world == null or world.resync_applied.is_connected(resync_applied.emit):
		return
	world.sync_checked.connect(sync_checked.emit)
	world.resync_sent.connect(resync_sent.emit)
	world.resync_applied.connect(resync_applied.emit)
	if world.probe == null:
		world.probe = probe
	if _early.has("spawner"):
		world.entity_spawner = _early["spawner"]
		_early.erase("spawner")


## shim: a world export written on this node after [method _ready] (tests set
## [member graph] late) reaches the world channel it now feeds. [member probe]
## is also this channel's own, for the skipped/before-apply observations.
func _forward_to_world(property: StringName, value: Variant) -> void:
	var world := world_sync()
	if world != null:
		world.set(property, value)


func _on_attached() -> void:
	if transport == null:
		transport = link.transport
	if link.command_applier == null and command_applier != null:
		link.command_applier = command_applier
	var early := _early
	_early = {}
	for pair in [["role", "role"], ["stamp", "build_stamp"], ["name", "join_display_name"],
			["defer", "defer_until_world"]]:
		if early.has(pair[0]):
			link.set(pair[1], early[pair[0]])
	link.logged.connect(logged.emit)
	link.link_refused.connect(link_refused.emit)
	link.peer_cleared.connect(peer_cleared.emit)
	link.peer_refused.connect(peer_refused.emit)


## Every line this channel traces goes through the core's [signal
## NetworkLink.logged], which [signal logged] re-emits — one stream either way.
func _log(line: String) -> void:
	if link != null:
		link.logged.emit(line)
	else:
		logged.emit(line)


## shim: see [method NetworkLink.announce_self].
func announce_self() -> void:
	link.announce_self()



## The world channel on this link — [WorldSyncChannel] owns snapshot, setup,
## entities and resync. Null only before the link is composed.
func world_sync() -> WorldSyncChannel:
	return link.channel_for(KIND_RESYNC) as WorldSyncChannel if link != null else null


## shim: [method WorldSyncChannel.send_hello] — the hello's world half is the
## world channel's. Every method below forwards the same way until its callers
## re-point.
func send_hello() -> void:
	var w := world_sync()
	if w != null:
		w.send_hello()


func send_graph_snapshot() -> void:
	var w := world_sync()
	if w != null:
		w.send_graph_snapshot()


func send_entity_snapshot() -> void:
	var w := world_sync()
	if w != null:
		w.send_entity_snapshot()


func send_resync(reason: String, is_join_world: bool = false) -> void:
	var w := world_sync()
	if w != null:
		w.send_resync(reason, is_join_world)


func request_resync(reason: String, is_join_world: bool = false) -> void:
	var w := world_sync()
	if w != null:
		w.request_resync(reason, is_join_world)


func renew_join_pull(reason: String) -> void:
	var w := world_sync()
	if w != null:
		w.renew_join_pull(reason)



## #667's drop-until-resync latch. A joining CLIENT opens its socket BEFORE it
## has a world ([code]GameRoot._ready[/code]'s client branch, which exists so a
## [constant KIND_SETUP] cannot be missed), and then spends seconds generating
## one. Everything that arrives in that window would otherwise apply against a
## half-built graph — and a kill that lands there reaches [VictorySystem], whose
## `outcome` latch has no reset and ejects the player to the meta-shell on a
## verdict the host never reached.
##
## [b]Drop, do not buffer.[/b] The transport is ONE `@rpc` on ONE channel
## ([code]EnetTransport._receive[/code], `reliable`, channel 0 — the sole
## production `@rpc` in the repo) and kind is a dictionary FIELD, not a channel.
## So the host encodes the resync at the moment the request arrives, everything
## it applied before that is already INSIDE the resync, and everything after is
## sent after and lands on top. Dropping here is provably lossless; replaying a
## buffer would double-apply.
##
## Set by GameRoot before [code]_open_link()[/code] on the client path and
## cleared in [method _on_resync]. Defaults OFF, so every host, offline sandbox
## and existing harness is untouched.
var defer_until_resync: bool:
	get:
		return link.defer_until_world if link != null else _early.get("defer", false)
	set(value):
		_forward("defer", "defer_until_world", value)


## The kinds [member defer_until_resync] swallows, and — as important — the ones
## it must NOT.
##
## [b]Dropped[/b]
## [constant KIND_COMMAND]: the whole point. A world mutation against a
## half-built graph, superseded wholesale by the resync.
## [constant KIND_LOOT_OFFER]: not a [Command], but it parks state. It resolves
## `collector_id` through the applier's graph (null, mid-generation), binds a
## [signal Entity.died] handler on an entity the resync is about to reconcile,
## and parks [code]LootSystem._pending_mirror_request[/code]. It also cannot be
## FOR this peer — an offer follows its collector's own claim, and a peer still
## joining has taken no action to claim from. The whole window is pre-HUD too,
## so nothing is listening on `Events.loot_pick_requested` to answer it; letting
## it through buys a forfeit against the wrong world, not an answer.
## [constant KIND_SEAT_HANDOVER]: it names a seat by [member Participant.id]
## and a peer mid-join has no entities to resolve one against. Nothing is lost
## by dropping it — the [constant KIND_SETUP] this peer is joining on carries
## the host's roster as it stands NOW, seat already AI, so the join applies the
## same flip by the shorter route. Its banner is dropped with it, correctly: it
## announces something that happened before this peer was in the room.
##
## [b]Passed[/b]
## [constant KIND_SETUP], [constant KIND_SNAPSHOT], [constant KIND_ENTITIES],
## [constant KIND_RESYNC]: these are HOW the client gets a world at all. Gating
## them deadlocks the join.
## [constant KIND_HELLO], [constant KIND_REFUSED]: link-level handshake and
## diagnostics; they touch no world state.
## [constant KIND_INTENT], [constant KIND_RESYNC_REQUEST]: host-only handlers
## ([code]role != NetworkConfig.Role.HOST[/code] early-return), and this latch is only
## ever set on a CLIENT peer — gating them would be unreachable code, so the
## decision is recorded here rather than as a guard that can never fire.
## [constant KIND_REFUSAL]: the answer to an intent this peer raised, and a
## joining client has raised none — but it mutates nothing and a swallowed
## refusal would strand a waiting submitter forever, which is exactly the
## failure #548 refused to ship.
const DEFERRED_KINDS: Array[String] = [KIND_COMMAND, KIND_LOOT_OFFER, KIND_SEAT_HANDOVER]




## shim: see [method WorldSyncChannel.send_run_setup].
func send_run_setup(config: RunConfig, roster: ParticipantRoster) -> void:
	var w := world_sync()
	if w != null:
		w.send_run_setup(config, roster)


## shim: the lobby protocol is [LobbyChannel]'s; this sender stays only for a
## lifecycle test that needs any host broadcast. Removed when that test re-points.
func send_lobby_roster(roster: ParticipantRoster) -> void:
	if transport == null or role != NetworkConfig.Role.HOST or roster == null:
		return
	transport.send({KEY_KIND: KIND_LOBBY, KEY_ROSTER: roster.to_dict()})



## #646 send side. [method LootPickRegistry.park] only ever parks a REMOTE
## claim ([LootRoundCommandHandler]'s `_await_pick`), so every [signal
## LootPickRegistry.offer_parked] this connects to is, by construction, a pick
## that owes a downward offer — ADDRESSED to [method LootPickRegistry.peer_for]'s
## answer: nobody but the picker needs to know until the pick lands as a
## [LootRoundCommand]. Host-only and NOT gated on [member graph] — unlike every
## other `send_*` here, this message names no node, only stat candidates (BY
## VALUE) or spell ids.
func _on_offer_parked(request: Variant) -> void:
	var peer_id := loot_pick_registry.peer_for(request.collector)
	if peer_id == 0:
		_log("✗ loot offer: no peer seats the collector")
		return
	send_loot_offer(_offer_for(request), peer_id)


func _offer_for(request: Variant) -> LootPickOffer:
	if request is SpellLootRequest:
		return LootPickOffer.for_spell_request(request as SpellLootRequest)
	return LootPickOffer.for_stat_request(request as LootPickRequest)


## Send [param offer] to [param peer_id] alone. Mutates nothing and carries no
## [Command] — see [constant KIND_LOOT_OFFER].
func send_loot_offer(offer: LootPickOffer, peer_id: int) -> void:
	if transport == null or role != NetworkConfig.Role.HOST or offer == null:
		return
	transport.send_to(peer_id, {KEY_KIND: KIND_LOOT_OFFER, KEY_OFFER: offer.to_dict()})
	_log("→ loot offer (request %d, collector %d) to peer %d" %
			[offer.request_id, offer.collector_id, peer_id])


## #646 receive side. Decodes and hands to [method
## LootPickRegistry.receive_offer], which gates ownership and emits the signal
## [LootSystem] opens its picker on — the link itself opens nothing.
func _on_loot_offer(payload: Dictionary) -> void:
	if role != NetworkConfig.Role.CLIENT:
		return
	var offer := LootPickOffer.from_dict(payload.get(KEY_OFFER, {}))
	if loot_pick_registry != null:
		loot_pick_registry.receive_offer(offer)
	_log("← loot offer (request %d, collector %d)" %
			[offer.request_id, offer.collector_id])


## #755 send side, host-only. Broadcast rather than addressed: every mirror
## needs the flip, and the one peer that does not — the one that left — is not
## on the link to receive it.
func send_seat_handover(participant_id: int) -> void:
	if transport == null or role != NetworkConfig.Role.HOST or participant_id == 0:
		return
	transport.send({KEY_KIND: KIND_SEAT_HANDOVER, KEY_PARTICIPANT: participant_id})
	_log("→ seat %d handed to the AI" % participant_id)


## #755 receive side. Decodes and re-emits — see [signal seat_handover_received].
func _on_seat_handover(payload: Dictionary) -> void:
	if role != NetworkConfig.Role.CLIENT:
		return
	var participant_id := int(payload.get(KEY_PARTICIPANT, 0))
	if participant_id == 0:
		return
	seat_handover_received.emit(participant_id)
	_log("← seat %d handed to the AI" % participant_id)


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
	if role != NetworkConfig.Role.HOST or transport == null:
		return
	if _applying_remote:
		return
	transport.send({
		KEY_KIND: KIND_COMMAND,
		KEY_COMMAND: command.to_dict(),
		KEY_FINGERPRINT: command.pre_fingerprint,
	})
	_log("→ %s (pre-fp %d)" % [command.type_tag(), command.pre_fingerprint])


## #548's upward leg. Mirrors off [signal CommandApplier.intent_submitted],
## which only a peer that does NOT decide ever emits — so the `CLIENT` gate here
## is belt-and-braces, and the honest statement of which direction this travels.
##
## No fingerprint rides up: the client's world is not the one being mutated
## from, and the authority's own pre-state is what the downward
## [constant KIND_COMMAND] compares against.
func _on_intent_submitted(command: Command) -> void:
	if role != NetworkConfig.Role.CLIENT or transport == null:
		return
	transport.send({KEY_KIND: KIND_INTENT, KEY_COMMAND: command.to_dict()})
	_log("↑ %s (intent %d)" % [command.type_tag(), command.intent_id])


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
	if role != NetworkConfig.Role.HOST or command_applier == null:
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


## Host-side refusal routing (#548). A client's command that fails
## [method CommandApplier._validate] produces `command_applied(cmd, false)` here
## and nothing else — no confirm, so nothing crosses the wire — and the client
## would wait forever. This is the message that closes it.
##
## Only ever for a REFUSED intent. A successful one already went down as a
## [constant KIND_COMMAND], which is what closes the client's gate.
func _on_command_applied(command: Command, success: bool) -> void:
	if role != NetworkConfig.Role.HOST or transport == null or command == null:
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
	_log("→ refused %s (intent %d)" % [command.type_tag(), command.intent_id])


## #548 receive side, client-only. Closes the awaiting window and reports the
## refusal through [signal CommandApplier.command_applied], which
## [PlayerInputController] already renders — no new feedback path, and
## emphatically no [signal CommandApplier.command_confirmed] (#525's camera
## director pans on that one).
func _on_refusal(payload: Dictionary) -> void:
	if role != NetworkConfig.Role.CLIENT or command_applier == null:
		return
	var intent_id := int(payload.get(KEY_INTENT_ID, 0))
	command_applier.refuse_intent(intent_id,
			StringName(payload.get(KEY_REASON, String(REASON_REFUSED))))
	_log("← refused (intent %d)" % intent_id)


## Every kind this link still carries until the world-sync, loot-offer and
## command channels split it (the core owns hello/refused; the lobby its own).
func kinds() -> Array[String]:
	return [KIND_COMMAND, KIND_INTENT, KIND_REFUSAL, KIND_LOOT_OFFER, KIND_SEAT_HANDOVER]


## Only [constant DEFERRED_KINDS] wait for a world; the rest are how one arrives.
func is_deferred(kind: String) -> bool:
	return DEFERRED_KINDS.has(kind)


func receive(kind: String, payload: Dictionary) -> void:
	match kind:
		KIND_COMMAND:
			_on_remote_command(payload)
		KIND_INTENT:
			_on_intent(payload)
		KIND_REFUSAL:
			_on_refusal(payload)
		KIND_LOOT_OFFER:
			_on_loot_offer(payload)
		KIND_SEAT_HANDOVER:
			_on_seat_handover(payload)


## shim: the world's legs are [WorldSyncChannel]'s; forwarded until the callers
## (GameRoot, the out-of-fence tests) re-point. Early writes are held until the
## channel is found.
var entity_spawner: Callable:
	get:
		var w := world_sync()
		return w.entity_spawner if w != null else _early.get("spawner", Callable())
	set(value):
		var w := world_sync()
		if w != null:
			w.entity_spawner = value
		else:
			_early["spawner"] = value



## shim: the build stamp moved to [NetworkLink]; removed when the callers re-point.
static func local_build_stamp() -> Dictionary:
	return NetworkLink.local_build_stamp()


## shim: see [method NetworkLink.describe_build].
static func describe_build(stamp: Dictionary) -> String:
	return NetworkLink.describe_build(stamp)


## shim: see [method NetworkLink.refuse_peer].
func refuse_peer(peer_id: int, reason: String) -> void:
	link.refuse_peer(peer_id, reason)



func _on_remote_command(payload: Dictionary) -> void:
	if role != NetworkConfig.Role.CLIENT or command_applier == null:
		return
	var command := CommandCodec.from_dict(payload.get(KEY_COMMAND, {}))
	if command == null:
		_log("← undecodable payload, dropped")
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
	# The host's stamp travels ON the command from here (#756), so the compare
	# can happen where it belongs — at this peer's own stamp point inside
	# [method CommandApplier._drain], see [method _on_command_stamped].
	command.host_fingerprint = int(payload.get(KEY_FINGERPRINT, 0))
	# The same flag the probe needs, read once — by the time the probe could ask
	# for itself, `submit` has started a drain and the answer is always "busy".
	# It no longer gates anything: the RESOLVE/LAND re-derivation still happens
	# here, on arrival, because it must run before this peer applies, and
	# `settled` is the honest annotation of what world it read.
	if probe != null:
		probe.observe_before_apply(command,
				not command_applier.is_applying and command_applier.pending_count() == 0)
	_applying_remote = true
	# [method CommandApplier.apply_remote], NOT `submit` — since #548 `submit`
	# is the INTENT door, and on this CLIENT peer it would send the host's own
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
	_log("← %s" % command.type_tag())


## The unstamped half of the per-command check: a received command whose
## envelope carried no host stamp is COUNTED, not dropped, or the probe's
## denominator would lie ("0 diverged of 412" while 280 were looked at). The
## compare itself is [method WorldSyncChannel._on_command_stamped]'s — it needs
## no command channel; this half needs [member _applying_remote], which is ours.
func _on_command_stamped(command: Command) -> void:
	if role != NetworkConfig.Role.CLIENT or command == null or command.host_fingerprint != 0:
		return
	if probe != null and _applying_remote:
		probe.observe_skipped(command)
