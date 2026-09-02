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
## #716: what the sender CLAIMS its own peer id is, on a client's announce.
##
## [b]It is never the authority.[/b] [method _gate_peer] acts on
## [method NetworkTransport.last_sender_id], the id the transport itself vouches
## for; this key exists only so a disagreement between the two can be seen and
## named. Trusting it would let one client announce its neighbour's id and have
## a seated, innocent peer disconnected — which is not the "one LAN, one room"
## trust model [constant LobbyScreen.PICK_PEER] rides on, but a client trivially
## acting on another client's behalf.
const KEY_PEER := "peer"

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
## #561's repair envelope: the WHOLE world, entities and graph together, in one
## message. Sent only by [method send_resync], applied only under
## [constant Mode.MIRROR].
##
## [b]One envelope rather than the two separate sends the join uses[/b], and
## that is the point: [method EntitySnapshot.resolve_graph_refs] has to run
## AFTER the nodes exist, which the join gets by parking the entity bytes until
## a graph arrives. A repair cannot rely on that — it decodes into a graph that
## is ALREADY populated, so the park would drain against the pre-repair nodes
## and never re-run against the new ones. Carrying both halves together makes
## the dependency order (#521 D5) local to one handler instead of a property of
## arrival timing. It is the same three calls in the same order; nothing here
## is a second decode path.
const KIND_RESYNC := "resync"
## #561: "our worlds disagree — send me yours." The only thing a client emits
## on a desync verdict, because only the authority may send state (#521 D4).
const KIND_RESYNC_REQUEST := "resync_request"
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
## [constant Mode.MIRROR], received only under [constant Mode.BROADCAST] — the
## same inversion [constant KIND_INTENT] draws for the world, at the roster's
## scope: a pick is an INTENT, and the host's [constant KIND_LOBBY] answer is the
## confirmation.
const KIND_LOBBY_PICK := "lobby_pick"

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
signal peer_cleared(peer_id: int)

## #716, host-side: this peer's build does not match ours and it has been
## disconnected. The listener is up, every other peer is untouched, and nothing
## on this end latched — refusing the PEER is not refusing the socket.
signal peer_refused(peer_id: int, reason: String)

## #646: a [LootPickOffer] arrived — a REMOTE collector's peer owes a pick.
## [method LootSystem._on_loot_offer_received] is the one consumer (#564): the
## mirror-side adapter that rebuilds the offer into the same [LootPickRequest] /
## [SpellLootRequest] the host's own claim flow raises, on the same `Events`
## bus. The signal exists so that adapter has a single source rather than
## reaching into [method _on_message_received] itself.
signal loot_offer_received(offer: LootPickOffer)

## #714, client-side: the host's authoritative lobby roster arrived. Decoded
## here and re-emitted, never applied here — this class owns the envelope, and
## [LobbyScreen] owns what a roster means to a lobby.
signal lobby_roster_received(roster: ParticipantRoster)

## #714, host-side: a client asked for a change to one seat. The payload is left
## as a raw [Dictionary] on purpose — validating it against the roster (may this
## peer edit that seat, is that colour taken) is the LOBBY's rule set, and this
## class must not become a second place that decides.
signal lobby_pick_received(pick: Dictionary)

@export var transport: NetworkTransport
@export var command_applier: CommandApplier
@export var graph: Graph
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
		transport.peer_joined.connect(_on_transport_peer_joined)
	if command_applier != null:
		command_applier.command_confirmed.connect(_on_command_confirmed)
		command_applier.intent_submitted.connect(_on_intent_submitted)
		command_applier.command_applied.connect(_on_command_applied)
	if loot_pick_registry != null:
		loot_pick_registry.offer_parked.connect(_on_offer_parked)


## Who this peer is for [method CommandApplier._mint_intent_id]'s high half. It
## has one job: make sure no two peers ever mint the same
## [member Command.intent_id].
##
## [b]It asks the transport, never [member Node.multiplayer].[/b] A peer id is
## the one datum [signal NetworkTransport.peer_joined] exists to carry across
## the seam, and reaching past it for [method MultiplayerAPI.get_unique_id]
## would put transport knowledge above the seam — plus it cannot tell an
## [OfflineMultiplayerPeer]'s `1` from a real host's.
##
## Only `0` — not linked yet — falls back to the role, because [member mode] is
## set before a level calls `_open_link()` and the applier needs *some* distinct
## half from the first command. It stops being a guess the moment
## [signal NetworkTransport.peer_joined] re-stamps it below.
func _local_peer_id() -> int:
	var assigned := transport.local_peer_id() if transport != null else 0
	if assigned != 0:
		return assigned
	return 2 if mode == Mode.MIRROR else 1


## The link came up, so the transport now knows an id the role could only guess.
##
## [b]A CLIENT also ANNOUNCES here (#716).[/b] The build-stamp gate used to ride
## the host's hello, which a lobby only sends once a level exists — so a joiner
## on the wrong commit was already seated by the time anybody compared. Now the
## first thing a client puts on the wire is its own stamp, the instant its dial
## completes, and the host answers by clearing or refusing it. The hello itself
## is unchanged and still goes the other way: this is an ADDITIONAL, upward leg,
## not a move of the existing one.
func _on_transport_peer_joined(_peer_id: int) -> void:
	if command_applier != null:
		command_applier.local_peer_id = _local_peer_id()
	if mode == Mode.MIRROR:
		announce_self()


## Client-side: "here I am, and this is the code I am running." Its own send
## rather than a branch inside [method send_hello], which is host-only and
## carries a world.
func announce_self() -> void:
	if transport == null or mode != Mode.MIRROR:
		return
	transport.send({
		KEY_KIND: KIND_HELLO,
		KEY_BUILD: build_stamp,
		KEY_PEER: transport.local_peer_id(),
	})
	logged.emit("↑ hello (%s)" % describe_build(build_stamp))


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


## #561's backstop. Push the WHOLE world to every client, as a repair —
## host-side, and the only thing that ever sends state on a desync verdict.
##
## Both halves ride one [constant KIND_RESYNC] envelope in the dependency order
## #521 D5 settled and #560 established: entities decode first (pass 1 needs no
## [SkillNode]), the graph next (its `owner_id` resolves through
## [method Graph.get_by_entity_id]), and the entity->node references last. See
## [constant KIND_RESYNC] for why it is one message rather than two.
##
## [b]It has no presentation semantics and must never acquire any[/b] (#521 D1).
## No [Command] is submitted, so nothing this peer draws off
## [signal CommandApplier.command_confirmed] — #525's camera director included —
## fires. Nobody animates a repair.
func send_resync(reason: String, is_join_world: bool = false) -> void:
	if transport == null or mode != Mode.BROADCAST or graph == null:
		return
	transport.send({
		KEY_KIND: KIND_RESYNC,
		KEY_ENTITIES: EntitySnapshot.encode(graph),
		KEY_SNAPSHOT: GraphSnapshot.encode(graph),
		KEY_SUMMARY: reason,
		KEY_JOIN: is_join_world,
	})
	logged.emit("⟳ RESYNC pushed — %s (%s)" % [reason, WorldFingerprint.describe(graph)])
	resync_sent.emit(reason)


## Client-side half of #521 D4: ask, do not reconstruct.
##
## Latched until the next boundary agrees. A verdict fires per applied command,
## so an unrepairable divergence would otherwise beg for a full world snapshot
## on every command for the rest of the run — turning a diagnostic into a flood
## and hiding the very log line the verdict exists to print.
func request_resync(reason: String, is_join_world: bool = false) -> void:
	if transport == null or mode != Mode.MIRROR:
		return
	if _awaiting_resync:
		return
	_awaiting_resync = true
	transport.send({
		KEY_KIND: KIND_RESYNC_REQUEST,
		KEY_SUMMARY: reason,
		KEY_JOIN: is_join_world,
	})
	logged.emit("↑ resync requested — %s" % reason)


## Latched between asking for a repair and the next agreeing boundary. See
## [method request_resync].
var _awaiting_resync: bool = false


## #715: consumed by the FIRST [constant KEY_JOIN]-flagged resync to arrive.
## Never reset — a peer joins once per level, and a level that re-joins is a new
## [CommandLink]. Read at [method _on_resync]'s guard, which is where the reason
## it exists is written down.
var _join_world_arrived: bool = false


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
var defer_until_resync: bool = false


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
##
## [b]Passed[/b]
## [constant KIND_SETUP], [constant KIND_SNAPSHOT], [constant KIND_ENTITIES],
## [constant KIND_RESYNC]: these are HOW the client gets a world at all. Gating
## them deadlocks the join.
## [constant KIND_HELLO], [constant KIND_REFUSED]: link-level handshake and
## diagnostics; they touch no world state.
## [constant KIND_INTENT], [constant KIND_RESYNC_REQUEST]: host-only handlers
## ([code]mode != Mode.BROADCAST[/code] early-return), and this latch is only
## ever set on a MIRROR peer — gating them would be unreachable code, so the
## decision is recorded here rather than as a guard that can never fire.
## [constant KIND_REFUSAL]: the answer to an intent this peer raised, and a
## joining client has raised none — but it mutates nothing and a swallowed
## refusal would strand a waiting submitter forever, which is exactly the
## failure #548 refused to ship.
const DEFERRED_KINDS: Array[String] = [KIND_COMMAND, KIND_LOOT_OFFER]


## #561 receive side, host-only. A client asking is treated exactly as the
## host's own verdict would be — one push, same payload.
func _on_resync_request(payload: Dictionary) -> void:
	if mode != Mode.BROADCAST:
		return
	var reason := String(payload.get(KEY_SUMMARY, "peer asked"))
	logged.emit("↓ resync requested by peer — %s" % reason)
	# The join flag rides the request through, so the answer is recognisable as
	# the join's world on the way back down (#715). See [constant KEY_JOIN].
	send_resync(reason, bool(payload.get(KEY_JOIN, false)))


## #561 receive side, client-only — a host must never apply a repair, which is
## what the [constant Mode.MIRROR] gate here says out loud.
##
## The three calls below are [method EntitySnapshot.decode] ->
## [method GraphSnapshot.decode] -> [method EntitySnapshot.resolve_graph_refs],
## the join's own order with no parking step, because both halves arrived
## together. Every one of them reconciles rather than rebuilds (#561 D6), so
## the graph this decodes into being POPULATED is the ordinary case, not the
## dangerous one: an entity's [method Entity.initialize] signal wiring, its
## [Stat] instances and every [EffectInstance] handle survive, and a world that
## never actually drifted comes out untouched.
func _on_resync(payload: Dictionary) -> void:
	if mode != Mode.MIRROR or graph == null:
		return
	var entity_bytes: PackedByteArray = payload.get(KEY_ENTITIES, PackedByteArray())
	var graph_bytes: PackedByteArray = payload.get(KEY_SNAPSHOT, PackedByteArray())
	var reason := String(payload.get(KEY_SUMMARY, ""))
	if graph_bytes.is_empty():
		# `GraphSnapshot._unpack` reads a 4-byte size header off the front, so
		# an empty payload is not a no-op there — it is a decode error.
		logged.emit("← resync with no graph half, dropped")
		return
	var is_join_world := bool(payload.get(KEY_JOIN, false))
	if is_join_world and _join_world_arrived:
		# The join race's loser (#715). Both legs — the host's push and the
		# answer to this peer's pull — carry a WHOLE world, and one of them is
		# redundant by construction. Dropping the second is not merely an
		# optimisation: applying it would re-run the decode against a graph the
		# first leg populated, re-emit [signal resync_applied] (whose GameRoot
		# handler re-derives seat vision and controllers) and re-enter
		# [member entity_spawner] for every materialised blocker.
		#
		# Safe because the transport is ONE ordered reliable channel: everything
		# the host sent between the two encodes has already been received and —
		# the first leg having cleared [member defer_until_resync] — applied. So
		# this peer's world is ALREADY the world this payload describes, in the
		# parts a fingerprint folds and the parts it does not (tags, effects).
		#
		# Scoped to the flag, never to "a world is present": a mid-run repair
		# (#521/#560/#561) carries no join flag and must always apply, including
		# the case where it repairs state the fingerprint fold cannot see —
		# which is why this is a flag and not a fingerprint compare.
		logged.emit("← join world already applied, dropped — %s" % reason)
		return
	EntitySnapshot.decode(entity_bytes, graph, entity_spawner)
	GraphSnapshot.decode(graph_bytes, graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, graph, entity_spawner)
	# LAST, and it is a fourth step rather than part of the graph half: HP is a
	# POOL and a pool clamps to a cap the owner's board decides, so it can only be
	# restored once that board is whole — which pass 2 above is what finishes.
	# See [method GraphSnapshot.restore_hp].
	GraphSnapshot.restore_hp(graph_bytes, graph)
	# Cleared here, not on the next verdict: the repair has landed, and the very
	# next compare is the one that says whether it worked.
	_awaiting_resync = false
	# #667: and the world this peer was missing is now the host's, so the drop
	# window is over. Same line for the same reason — the repair HAS landed.
	defer_until_resync = false
	if is_join_world:
		_join_world_arrived = true
	logged.emit("⟳ resync applied — %s (%s)" % [reason, WorldFingerprint.describe(graph)])
	resync_applied.emit(reason)


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


## #714 send side, host-only: the whole authoritative lobby roster. Unlike
## [method send_run_setup] this carries no [RunConfig], so nothing about it can
## open a run — see [constant KIND_LOBBY].
##
## Not gated on [member graph]: a lobby has no world, which is the entire point
## of the kind.
func send_lobby_roster(roster: ParticipantRoster) -> void:
	if transport == null or mode != Mode.BROADCAST or roster == null:
		return
	transport.send({KEY_KIND: KIND_LOBBY, KEY_ROSTER: roster.to_dict()})
	logged.emit("→ lobby roster (%d participants)" % roster.all().size())


## #714 send side, client-only: one seat's changed fields. [param pick] is built
## by the lobby (see [method LobbyScreen.encode_pick]) and crosses verbatim.
func send_lobby_pick(pick: Dictionary) -> void:
	if transport == null or mode != Mode.MIRROR or pick.is_empty():
		return
	transport.send({KEY_KIND: KIND_LOBBY_PICK, KEY_PICK: pick})
	logged.emit("↑ lobby pick for seat %d" % int(pick.get("id", 0)))


## #714 receive side, client-only. The host's answer REPLACES what this peer
## shows — there is no merge and no prediction (#548 D5 at the roster's scope),
## which is what makes a refused pick converge rather than linger.
func _on_lobby_roster(payload: Dictionary) -> void:
	if mode != Mode.MIRROR:
		return
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	lobby_roster_received.emit(roster)
	logged.emit("← lobby roster (%d participants)" % roster.all().size())


## #714 receive side, host-only.
func _on_lobby_pick(payload: Dictionary) -> void:
	if mode != Mode.BROADCAST:
		return
	var pick: Dictionary = payload.get(KEY_PICK, {})
	if pick.is_empty():
		logged.emit("↑ empty lobby pick, dropped")
		return
	lobby_pick_received.emit(pick)
	logged.emit("↑ lobby pick for seat %d" % int(pick.get("id", 0)))


## #646 send side. [method LootPickRegistry.park] only ever parks a REMOTE
## claim ([SkillDustAddon]'s `_await_pick`), so every [signal
## LootPickRegistry.offer_parked] this connects to is, by construction, a pick
## that owes a downward offer. Host-only and NOT gated on [member graph] —
## unlike every other `send_*` here, this message names no node, only stat
## candidates (BY VALUE) or spell ids.
func _on_offer_parked(request: Variant) -> void:
	send_loot_offer(_offer_for(request))


func _offer_for(request: Variant) -> LootPickOffer:
	if request is SpellLootRequest:
		return LootPickOffer.for_spell_request(request as SpellLootRequest)
	return LootPickOffer.for_stat_request(request as LootPickRequest)


## Send [param offer] to every connected peer. Mutates nothing and carries no
## [Command] — see [constant KIND_LOOT_OFFER].
func send_loot_offer(offer: LootPickOffer) -> void:
	if transport == null or mode != Mode.BROADCAST or offer == null:
		return
	transport.send({KEY_KIND: KIND_LOOT_OFFER, KEY_OFFER: offer.to_dict()})
	logged.emit("→ loot offer (request %d, collector %d)" %
			[offer.request_id, offer.collector_id])


## #646 receive side. Decodes and re-emits — see [signal loot_offer_received]
## for why this does not itself open a picker.
func _on_loot_offer(payload: Dictionary) -> void:
	if mode != Mode.MIRROR:
		return
	var offer := LootPickOffer.from_dict(payload.get(KEY_OFFER, {}))
	loot_offer_received.emit(offer)
	logged.emit("← loot offer (request %d, collector %d)" %
			[offer.request_id, offer.collector_id])


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
	var kind := String(payload.get(KEY_KIND, ""))
	# #667: same reasoning for the placement — the pre-world window is a
	# property of the LINK, not of one handler, so the decision about every kind
	# is readable in one place. See [constant DEFERRED_KINDS].
	if defer_until_resync and DEFERRED_KINDS.has(kind):
		logged.emit("← %s dropped — no world yet, waiting on resync" % kind)
		return
	match kind:
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
		KIND_RESYNC:
			_on_resync(payload)
		KIND_RESYNC_REQUEST:
			_on_resync_request(payload)
		KIND_INTENT:
			_on_intent(payload)
		KIND_REFUSAL:
			_on_refusal(payload)
		KIND_LOOT_OFFER:
			_on_loot_offer(payload)
		KIND_LOBBY:
			_on_lobby_roster(payload)
		KIND_LOBBY_PICK:
			_on_lobby_pick(payload)
		_:
			logged.emit("ignored payload with unknown kind %s" % payload.get(KEY_KIND))


## #527 receive side. Decodes straight into [member graph]. The join flow (a
## lobby, #531) still hands this link an empty graph, but that is now a
## convention rather than a requirement: since #561 [method GraphSnapshot.decode]
## RECONCILES, so decoding into a populated graph is well-defined — it is what
## the resync backstop does on every repair.
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
	EntitySnapshot.decode(bytes, graph, entity_spawner)
	_pending_entities = bytes
	if not graph.get_skill_nodes().is_empty():
		_drain_pending_entities()
	logged.emit("← entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


func _drain_pending_entities() -> void:
	if _pending_entities.is_empty() or graph == null:
		return
	var bytes := _pending_entities
	_pending_entities = PackedByteArray()
	EntitySnapshot.resolve_graph_refs(bytes, graph, entity_spawner)


## An entity snapshot whose pass 2 is still waiting on a graph. Cleared the
## moment it is drained, so a later graph snapshot cannot re-run it.
var _pending_entities: PackedByteArray = PackedByteArray()


## How an arriving snapshot builds an [Entity] this peer does not have (#715).
##
## Set by [GameRoot] to [method GameRoot.spawn_snapshot_entity]; left unset a
## missing row is skipped with a warning, exactly as before. It is a [Callable]
## and not a subclass hook because the knowledge is the LEVEL's — what a blocker
## is, which board its tier carries — and this class deliberately knows only
## about rows. See [method EntitySnapshot._materialize] for why a joining client
## needs it at all: since #715 it runs no procgen, so the entities procgen would
## have spawned (one per removable blocker) arrive only here.
var entity_spawner: Callable = Callable()


## #546's build gate, run before anything in the hello is believed.
##
## [b]An ABSENT stamp is a mismatch, not a pass.[/b] That is the whole incident:
## the peer that corrupted #534's sweep was a `dc5ef29`-era orphan — code from
## before this check existed, which sends a hello with no build key at all. If
## "no stamp" read as agreement, this fix would sail straight past the one run
## it was written for. Present-but-empty is different and DOES compare equal —
## though that case is now rare on purpose: an exported build has no
## `res://.git`, so it used to announce an empty sha and two DIFFERENT builds
## compared equal all the way into a desync. `mise run build` writes a build
## stamp that [BuildInfo] falls back to, so a build knows its sha too and this
## gate fires between builds, not just between checkouts.
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


## #716, host-side: the gate a joining peer clears before it is offered
## anything. Same comparison as [method _accept_build] — absent is a mismatch,
## present-but-empty is a match, only the sha counts — reached through the one
## place that decides it.
##
## [b]It emits rather than acts.[/b] Whether a cleared peer gets a lobby seat, a
## run setup, or nothing at all is not this class's call; what is this class's
## call is that no peer is heard from before the comparison ran.
##
## [b]The peer acted on is the one the TRANSPORT names[/b]
## ([method NetworkTransport.last_sender_id]), never the one the payload claims.
## The two exist because a claim can be wrong: a client announcing its
## neighbour's id would otherwise have that neighbour — already cleared, already
## seated — disconnected on its say-so. A disagreement is itself a refusal, and
## of the sender: there is no legitimate way to produce one, and a client that
## cannot name itself correctly has nothing to contribute to a roster.
##
## Falling back to the claimed id when the transport answers `0` keeps a fixture
## that emits [signal NetworkTransport.message_received] by hand — and any
## transport with no id of its own — on the path it was on.
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
	peer_cleared.emit(peer_id)


## Hang up on ONE peer and keep listening (#716 item 1, acceptance 1).
##
## [b]No latch and no [method NetworkTransport.stop].[/b] Both are what
## [method _refuse] does, and both are wrong for a host: the listener the socket
## holds belongs to every other peer on it, and a latch would make this machine
## deaf to the client whose checkout the operator is about to fix. What the host
## loses by staying up is nothing — a refused peer is no longer connected, so it
## has no way to say anything else.
##
## The reject goes out BEFORE the disconnect, same reason [method _refuse]
## documents: a message aimed at a peer that is already gone is dropped, and then
## the refused end has nothing on screen to explain itself with.
func _refuse_peer(peer_id: int, reason: String, theirs: Dictionary) -> void:
	_log_refusal(reason, theirs)
	if transport != null:
		transport.send_to(peer_id, {
			KEY_KIND: KIND_REFUSED, KEY_BUILD: build_stamp, KEY_SUMMARY: reason,
		})
		transport.drop_peer(peer_id)
	peer_refused.emit(peer_id, reason)


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
##
## [b]A CLIENT told this does latch, since #716.[/b] Everything above is about a
## HOST, and stays true for one. A client, though, has just been disconnected by
## the peer that sent this — [method _refuse_peer] drops it — so there is no
## socket left to be deaf on, and going quiet is what stops it acting on
## anything still in flight. The one behaviour that must not change either way is
## [method NetworkTransport.stop] on a host, which is why the latch is the only
## line under the mode check.
##
## The reason travels (#716 item 4): the lobby shows it, so "Refused" alone —
## which is all this used to emit — would put a screen in front of a human that
## says a build mismatch happened without saying which build.
func _on_refused_by_peer(payload: Dictionary) -> void:
	var summary := String(payload.get(KEY_SUMMARY, "build mismatch"))
	_log_refusal(summary, payload.get(KEY_BUILD, {}))
	if mode == Mode.MIRROR:
		_refused = true
	link_refused.emit("refused by peer — %s" % summary)


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


## A hello means two different things depending on which end reads it (#716), so
## it dispatches on [member mode] rather than growing a second kind:
##
## - under [constant Mode.BROADCAST] it is a JOINER announcing itself, and the
##   answer is [method _gate_peer] — clear that peer or hang up on that peer;
## - under [constant Mode.MIRROR] it is the host's world announcement, unchanged
##   since #546, and a mismatch hangs up this machine's own link.
##
## The asymmetry is the point. A client owns nothing but its own link, so
## [method _refuse] closing it is correct; a host owns the listener every OTHER
## peer is on, so it must never take that route.
func _on_hello(payload: Dictionary) -> void:
	if mode == Mode.BROADCAST:
		_gate_peer(payload)
		return
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
		# The repair landed and the next boundary agreed, so the client may ask
		# again if it ever drifts a second time.
		_awaiting_resync = false
		return true
	logged.emit("  ✗ DIVERGED %s — mine %d, host %d" % [when, local, remote])
	_heal_desync("%s (mine %d, host %d)" % [when, local, remote])
	return false


## #521 D3, both halves. The shout above is not optional and is not replaced by
## the repair: a silent auto-heal would retire the "the client's number crept
## wrong" bug class from the LOGS rather than from the code, which is exactly
## what the #529/#532 harness ladder exists to prevent. `sync_checked` has
## already fired by the time this runs, so a rung asserting on it still sees
## the failure.
##
## [b]Only the authority sends state (#521 D4).[/b] A client that detects
## disagreement asks; it never reconstructs, because a peer repairing itself
## from its own wrong world is not a repair.
func _heal_desync(reason: String) -> void:
	match mode:
		Mode.BROADCAST:
			send_resync(reason)
		Mode.MIRROR:
			request_resync(reason)
		_:
			pass
