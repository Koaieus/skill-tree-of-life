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
## [b]It is never the authority.[/b] [method _gate_peer] acts on
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
## [constant NetworkConfig.Role.CLIENT].
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
## as [signal lobby_roster_received].
signal seat_handover_received(participant_id: int)

@export var transport: NetworkTransport
@export var command_applier: CommandApplier:
	set(value):
		command_applier = value
		if link != null:
			link.command_applier = value
@export var graph: Graph

## The level's clock. Only ever WRITTEN through
## [method EntitySnapshot.restore_turn_cursor], and only on a mirror: who holds
## the turn is a host decision that a repaired peer receives rather than
## reproduces (#756). Wired by `game_root.tscn`.
@export var turn_manager: TurnManager
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
	if link == null:
		var core := NetworkLink.new()
		core.name = "NetworkLink"
		core.transport = transport
		core.command_applier = command_applier
		core.channels = [self] as Array[LinkChannel]
		add_child(core)
	if command_applier != null:
		command_applier.command_confirmed.connect(_on_command_confirmed)
		command_applier.intent_submitted.connect(_on_intent_submitted)
		command_applier.command_applied.connect(_on_command_applied)
		command_applier.command_stamped.connect(_on_command_stamped)
	if loot_pick_registry != null:
		loot_pick_registry.offer_parked.connect(_on_offer_parked)


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
	link.hello_accepted.connect(_on_hello_accepted)


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
	if transport == null or role != NetworkConfig.Role.HOST:
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
## `role` — decoding a snapshot is not a mirrored command, so it isn't gated
## behind `NetworkConfig.Role.CLIENT` the way [method _on_remote_command] is.
func send_graph_snapshot() -> void:
	if transport == null or role != NetworkConfig.Role.HOST or graph == null:
		return
	transport.send({KEY_KIND: KIND_SNAPSHOT, KEY_SNAPSHOT: GraphSnapshot.encode(graph)})
	_log("→ graph snapshot (%s)" % WorldFingerprint.describe(graph))


## Send every entity's accumulated state to a freshly-connected peer (#560) —
## host-side, opt-in, the sibling of [method send_graph_snapshot]. The peer
## DECORATES the entities its roster (#528) already spawned; nothing here
## spawns or mints an id. Send order does not matter: the receive side runs
## [method EntitySnapshot.decode] on arrival and defers the entity->node pass
## until a graph exists (see [method _on_entity_snapshot]).
func send_entity_snapshot() -> void:
	if transport == null or role != NetworkConfig.Role.HOST or graph == null:
		return
	transport.send({KEY_KIND: KIND_ENTITIES, KEY_ENTITIES: EntitySnapshot.encode(graph)})
	_log("→ entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


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
	if transport == null or role != NetworkConfig.Role.HOST or graph == null:
		return
	transport.send({
		KEY_KIND: KIND_RESYNC,
		KEY_ENTITIES: EntitySnapshot.encode(graph),
		KEY_SNAPSHOT: GraphSnapshot.encode(graph),
		KEY_SUMMARY: reason,
		KEY_JOIN: is_join_world,
	})
	_log("⟳ RESYNC pushed — %s (%s)" % [reason, WorldFingerprint.describe(graph)])
	resync_sent.emit(reason)


## Client-side half of #521 D4: ask, do not reconstruct.
##
## Latched until the next boundary agrees. A verdict fires per applied command,
## so an unrepairable divergence would otherwise beg for a full world snapshot
## on every command for the rest of the run — turning a diagnostic into a flood
## and hiding the very log line the verdict exists to print.
func request_resync(reason: String, is_join_world: bool = false) -> void:
	if transport == null or role != NetworkConfig.Role.CLIENT:
		return
	if _awaiting_resync:
		return
	_awaiting_resync = true
	transport.send({
		KEY_KIND: KIND_RESYNC_REQUEST,
		KEY_SUMMARY: reason,
		KEY_JOIN: is_join_world,
	})
	_log("↑ resync requested — %s" % reason)


## The join's pull, asked AGAIN (2026-09-06). [method request_resync] latches
## on [member _awaiting_resync] so a mid-run verdict cannot flood the host, but
## a joining client with NO world has nothing to flood and nothing to lose: the
## host answers each ask with a whole world (~40 KB on the shipped preset) and
## [member _join_world_arrived] drops every answer after the first. So a peer
## that has been waiting a while asks once more rather than trusting that its
## first ask, or the host's push, survived whatever happened on the wire — the
## one window a LAN exposes and loopback never did. A no-op once a join world
## has landed.
func renew_join_pull(reason: String) -> void:
	if _join_world_arrived:
		return
	_awaiting_resync = false
	request_resync(reason, true)


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


## #561 receive side, host-only. A client asking is treated exactly as the
## host's own verdict would be — one push, same payload.
func _on_resync_request(payload: Dictionary) -> void:
	if role != NetworkConfig.Role.HOST:
		return
	var reason := String(payload.get(KEY_SUMMARY, "peer asked"))
	_log("↓ resync requested by peer — %s" % reason)
	# The join flag rides the request through, so the answer is recognisable as
	# the join's world on the way back down (#715). See [constant KEY_JOIN].
	send_resync(reason, bool(payload.get(KEY_JOIN, false)))


## #561 receive side, client-only — a host must never apply a repair, which is
## what the [constant NetworkConfig.Role.CLIENT] gate here says out loud.
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
	if role != NetworkConfig.Role.CLIENT or graph == null:
		return
	var entity_bytes: PackedByteArray = payload.get(KEY_ENTITIES, PackedByteArray())
	var graph_bytes: PackedByteArray = payload.get(KEY_SNAPSHOT, PackedByteArray())
	var reason := String(payload.get(KEY_SUMMARY, ""))
	if graph_bytes.is_empty():
		# `GraphSnapshot._unpack` reads a 4-byte size header off the front, so
		# an empty payload is not a no-op there — it is a decode error.
		_log("← resync with no graph half, dropped")
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
		_log("← join world already applied, dropped — %s" % reason)
		return
	EntitySnapshot.decode(entity_bytes, graph, entity_spawner)
	GraphSnapshot.decode(graph_bytes, graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, graph, entity_spawner)
	# LAST, and it is a fourth step rather than part of the graph half: HP is a
	# POOL and a pool clamps to a cap the owner's board decides, so it can only be
	# restored once that board is whole — which pass 2 above is what finishes.
	# See [method GraphSnapshot.restore_hp].
	GraphSnapshot.restore_hp(graph_bytes, graph)
	# FIFTH, and after the HP for the same reason the HP is after pass 2: the
	# cursor's [signal TurnManager.turn_started] reaches the HUD, and a banner
	# raised over a half-restored world is the same class of bug one step later.
	EntitySnapshot.restore_turn_cursor(entity_bytes, graph, turn_manager)
	# Cleared here, not on the next verdict: the repair has landed, and the very
	# next compare is the one that says whether it worked.
	_awaiting_resync = false
	# #667: and the world this peer was missing is now the host's, so the drop
	# window is over. Same line for the same reason — the repair HAS landed.
	link.defer_until_world = false
	if is_join_world:
		_join_world_arrived = true
	_log("⟳ resync applied — %s (%s)" % [reason, WorldFingerprint.describe(graph)])
	resync_applied.emit(reason)


## Send the run's shape to a freshly-connected peer (#528) — host-side,
## opt-in, same additive shape as [method send_graph_snapshot]. [param config]
## and [param roster] cross BY VALUE ([method RunConfig.to_dict] /
## [method ParticipantRoster.to_dict]); the receiving peer decodes and hands
## both to [method GameSession.apply_received], which does NOT re-resolve the
## seed — it already is the host's resolved value.
func send_run_setup(config: RunConfig, roster: ParticipantRoster) -> void:
	if transport == null or role != NetworkConfig.Role.HOST or config == null:
		return
	transport.send({
		KEY_KIND: KIND_SETUP,
		KEY_CONFIG: config.to_dict(),
		KEY_ROSTER: (roster.to_dict() if roster != null else {"participants": []}),
	})
	_log("→ run setup (seed %d, %d participants)" %
			[config.seed, roster.all().size() if roster != null else 0])


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
	return [KIND_COMMAND, KIND_SNAPSHOT, KIND_SETUP, KIND_ENTITIES, KIND_RESYNC, KIND_RESYNC_REQUEST, KIND_INTENT, KIND_REFUSAL, KIND_LOOT_OFFER, KIND_SEAT_HANDOVER]


## Only [constant DEFERRED_KINDS] wait for a world; the rest are how one arrives.
func is_deferred(kind: String) -> bool:
	return DEFERRED_KINDS.has(kind)


func receive(kind: String, payload: Dictionary) -> void:
	match kind:
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
		KIND_SEAT_HANDOVER:
			_on_seat_handover(payload)


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
	_log("← graph snapshot (%s)" % WorldFingerprint.describe(graph))


## #528 receive side. Decodes [RunConfig] + [ParticipantRoster] and hands both
## to [method GameSession.apply_received] — the seed is NOT re-resolved here,
## it rides the wire as the host's already-resolved value.
func _on_run_setup(payload: Dictionary) -> void:
	var config := RunConfig.from_dict(payload.get(KEY_CONFIG, {}))
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	GameSession.apply_received(config, roster)
	_log("← run setup (seed %d, %d participants)" % [config.seed, roster.all().size()])


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
	_log("← entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


func _drain_pending_entities() -> void:
	if _pending_entities.is_empty() or graph == null:
		return
	var bytes := _pending_entities
	_pending_entities = PackedByteArray()
	EntitySnapshot.resolve_graph_refs(bytes, graph, entity_spawner)
	EntitySnapshot.restore_turn_cursor(bytes, graph, turn_manager)


## An entity snapshot whose pass 2 is still waiting on a graph. Cleared the
## moment it is drained, so a later graph snapshot cannot re-run it.
var _pending_entities: PackedByteArray = PackedByteArray()


## How an arriving snapshot builds an [Entity] this peer does not have (#715).
##
## Set by [GameRoot] to [method EntityFactory.spawn_snapshot_entity]; left unset a
## missing row is skipped with a warning, exactly as before. It is a [Callable]
## and not a subclass hook because the knowledge is the LEVEL's — what a blocker
## is, which board its tier carries — and this class deliberately knows only
## about rows. See [method EntitySnapshot._materialize] for why a joining client
## needs it at all: since #715 it runs no procgen, so the entities procgen would
## have spawned (one per removable blocker) arrive only here.
var entity_spawner: Callable = Callable()


## The core cleared the host's hello (build gate — [method NetworkLink._on_hello]);
## its WORLD half is this channel's until the world-sync channel takes it.
func _on_hello_accepted(payload: Dictionary) -> void:
	var remote := int(payload.get(KEY_FINGERPRINT, 0))
	var local := WorldFingerprint.compute(graph)
	_log("host world: %s" % payload.get(KEY_SUMMARY, "?"))
	_log("mine:       %s" % WorldFingerprint.describe(graph))
	_report_sync(local, remote, "at link-up")


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


## The divergence check, at the mirror's own [member Command.pre_fingerprint]
## stamp (#756) — pre-state against pre-state, for EVERY command.
##
## [b]What moved, and why.[/b] This used to run in
## [method _on_remote_command], on arrival, behind a `settled` guard: a command
## that landed while the applier was mid-drain was compared against a world
## sitting at no command's boundary, so it had to be skipped instead. Under
## autoplay — and under any burst, which is what a real turn of an AI looks
## like — nine commands in a row would arrive inside one drain and exactly one
## of them was ever looked at. The count was honest (they were tallied
## `skipped`) and useless: "the mirror diverged 3 times" could not say which
## command diverged first, which is the only question a sync bug is debugged by.
##
## Here there is no such thing as an unsettled world. [method
## CommandApplier._drain] pops one command, stamps the world it is about to
## apply it to, and emits — the exact counterpart of the moment the host
## stamped. Nothing is skipped, and the first `✗` names the first command that
## actually disagreed.
##
## [b]CLIENT only.[/b] The authority's stamp IS the reference; comparing it
## against itself would be a tautology, and every command it drains carries
## [member Command.host_fingerprint] 0 anyway.
func _on_command_stamped(command: Command) -> void:
	if role != NetworkConfig.Role.CLIENT or command == null:
		return
	if command.host_fingerprint == 0:
		# A received command whose envelope carried no stamp — nothing to
		# compare against. Counted, not dropped, or the probe's denominator
		# would silently be a lie ("0 diverged of 412" while only 280 were ever
		# looked at).
		if probe != null and _applying_remote:
			probe.observe_skipped(command)
		return
	var agrees := _report_sync(command.pre_fingerprint, command.host_fingerprint,
			"before %s" % command.type_tag())
	if probe != null:
		probe.observe_world(command, agrees)


## Returns the verdict as well as announcing it, so #529's probe can attribute
## it to the command that produced it without re-deriving the comparison.
func _report_sync(local: int, remote: int, when: String) -> bool:
	var agrees := local == remote
	sync_checked.emit(agrees, local, remote)
	if agrees:
		_log("  ✓ in sync %s (fp %d)" % [when, local])
		# The repair landed and the next boundary agreed, so the client may ask
		# again if it ever drifts a second time.
		_awaiting_resync = false
		return true
	_log("  ✗ DIVERGED %s — mine %d, host %d" % [when, local, remote])
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
	match role:
		NetworkConfig.Role.HOST:
			send_resync(reason)
		NetworkConfig.Role.CLIENT:
			request_resync(reason)
		_:
			pass
