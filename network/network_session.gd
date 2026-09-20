class_name NetworkSession
extends Node
## The network ROLE of one level, lifted out of [GameRoot] (#1004): which side
## of the wire this machine is on, bringing the socket up, a joining client's
## wait for the authority's world, and the peer events a live level hears.
##
## Composed into `game_root.tscn` as a child, taking its deps as `@export`
## NodePaths. It owns the LIFECYCLE and EMITS; the root keeps presentation
## (toasts, the run-end overlay, camera, controllers, fog) by subscribing to the
## signals below — the session never reaches into the HUD or the camera.
##
## Single-player is this same node with no role to adopt: [method is_client]
## and [method is_host] answer false, [method join_or_host] returns at once,
## and nothing here opens a socket. Nothing in it needs a scene tree beyond
## `get_tree().process_frame` inside the join wait, so a test may `new()` it
## and set the exports by hand.

## The authority's world has landed — on the join path once, and again on
## every mid-run repair (#521/#560/#561). The root re-derives what depends on
## the world (controllers, seat vision) on each.
signal world_ready(reason: String)
## Mirror-side: the host says this seat is the AI's now (#755).
signal seat_handover(participant_id: int)
## Host-side only: a peer on the socket went away mid-run. The root decides
## what happens to the seats it held.
signal peer_left(peer_id: int)
## Client-side: this machine learned its own peer id from the socket — the
## root restates whatever registry copies were taken before it was known.
signal local_peer_resolved(peer_id: int)
## This machine's link is gone — the host quit, the socket dropped — and no
## world is coming. The applier's parked intent is already abandoned.
signal link_lost(reason: String)
## The host turned this peer away, and said why. The hang-up follows one
## message later as [signal link_lost]; the reason here is the one to show.
signal refused(reason: String)

@export var transport: NetworkTransport
@export var command_link: CommandLink
@export var command_applier: CommandApplier

## How long a joining client waits for the authority's world before asking for
## it again ([method CommandLink.renew_join_pull], 2026-09-06). Three seconds is
## well past a LAN round trip and well short of a human deciding the screen is
## dead. Overridable so a test can watch the renewal without waiting it out.
const JOIN_PULL_RETRY_SEC := 3.0
var join_pull_retry_sec: float = JOIN_PULL_RETRY_SEC

## Set by [method _on_resync_applied]: the authority's world has landed at least
## once, so [method join_world] may stop waiting.
var _join_world_arrived: bool = false
## Set by [method _on_link_lost] / [method _on_refused_by_host]: this machine's
## link is gone and no world is coming. What ends [method join_world] the
## OTHER way.
var _link_ended: bool = false


## Hooks the link's inbound events. The node sits after `CommandLink` in
## `game_root.tscn`, so the link is up (its own `_ready` done) by the time this
## runs, and both are ready before the root's `_ready` adopts the role.
func _ready() -> void:
	if command_link == null:
		return
	command_link.resync_applied.connect(_on_resync_applied)
	# The host turning this peer away with a reason (a join it did not seat,
	# a build it does not match). It arrives a message BEFORE the drop that
	# follows it, and it is the sentence a human needs to read.
	command_link.link_refused.connect(_on_refused_by_host)
	# #755, mirror-side: the host telling us a dropped peer's seat is the
	# AI's now.
	command_link.seat_handover_received.connect(_on_seat_handover)
	# Rung 3's protocol trace, hooked HERE rather than beside the verdict line
	# at the tail of the root's `_ready` — by then the resync has already been
	# pushed (host) or applied (client) and the interesting lines are gone. It is
	# what makes acceptance 3 comparable ACROSS the two logs: the host's
	# `⟳ RESYNC pushed — … (fp N)` and the client's `⟳ resync applied — … (fp N)`
	# sample the SAME world, whereas the two FIRST TURN lines are each taken at
	# their own machine's turn start and so straddle whatever the turn start
	# itself moves (regen, mana). See [method GameRoot._announce_first_turn_for_rung_3].
	#
	# Printed on EVERY online run since 2026-09-06, not only under the rung-3
	# flag: it goes to stdout and so to `user://logs/godot.log`, which is the
	# only thing a LAN playtest on somebody else's machine can hand back.
	var trace_role := HarnessFlags.value(HarnessFlags.LOBBY)
	if trace_role.is_empty():
		trace_role = online_role_name()
	if not trace_role.is_empty():
		command_link.logged.connect(
				func(line: String) -> void: print("[%s] %s" % [trace_role, line]))


# --- Predicates ------------------------------------------------------------

## Is this process the one that decides, rather than one that is told? The same
## question [CommandApplier.is_authority] answers, asked from the level: a
## missing link is an offline run, which is its own authority, and so is a link
## left in `Mode.OFF`. Only a MIRROR is told.
func is_authority() -> bool:
	return command_link == null or command_link.mode != CommandLink.Mode.MIRROR


## #463: does this machine ADOPT its run, or DECIDE it?
##
## The one question the join path turns on, asked in one place. A client's
## lobby settings are a wish, not a run: `GameSession.apply_received` replaces
## its [RunConfig] and its whole [ParticipantRoster] with the host's, so
## everything this machine builds must wait for that message. Offline play and
## the host both answer false and take the untouched pre-#463 path.
##
## [b]Read from [member GameSession.network], never from the link's mode[/b] —
## the two are different sources on purpose. `scenes/dev/mp_procgen_sandbox.gd`
## drives its own link off the command line and sets `mode` by hand without
## ever populating the session's network config; a mode-based answer would
## drop its client into a pull-and-wait it never asked for.
func is_client() -> bool:
	var net: NetworkConfig = GameSession.network
	return (net != null and net.is_online()
			and net.role == NetworkTransport.Role.CLIENT)


## The menu made this machine the host. False offline, false for a level that
## drives its own link by hand (see [method is_client]).
func is_host() -> bool:
	var net: NetworkConfig = GameSession.network
	return (net != null and net.is_online()
			and net.role == NetworkTransport.Role.HOST)


## What the wire trace is prefixed with on an online run that was not launched
## through the rung-3 flag: the role the menu set. `""` offline, so an offline
## level prints nothing.
static func online_role_name() -> String:
	var net: NetworkConfig = GameSession.network
	if net == null or not net.is_online():
		return ""
	return "host" if net.role == NetworkTransport.Role.HOST else "client"


# --- Lifecycle -------------------------------------------------------------

## Half one of bringing the wire up (#531): tell the link which side of it we
## are on. [member CommandLink.mode] is the single writer of
## [member CommandApplier.is_authority], so this one assignment is also what
## decides whether this machine DECIDES or is TOLD.
##
## Called by the root FIRST in its `_ready`, before `_setup_level` spawns an
## actor that could act: a CLIENT that learns it is not the authority only
## after its first AI turn has decided and submitted locally has already
## diverged — the exact trap `scenes/dev/mp_dev_sandbox.gd` documents at length
## in its own `_ready`. The socket itself opens later, in [method open_link].
##
## [b]A no-op unless the menu set a role[/b], which is what keeps offline play
## unchanged and what lets `scenes/dev/mp_dev_sandbox.gd` keep driving its own
## link off the command line — the harness never populates
## [member GameSession.network], so nothing here touches the authority flag it
## set by hand a moment earlier.
func adopt_role() -> void:
	if command_link == null:
		return
	var net: NetworkConfig = GameSession.network
	if net == null or not net.is_online():
		return
	command_link.mode = (CommandLink.Mode.BROADCAST
			if net.role == NetworkTransport.Role.HOST
			else CommandLink.Mode.MIRROR)


## Half two: open the socket on whatever transport this level mounted.
##
## [b]The session never picks the transport CLASS.[/b] It brings up the node it
## was handed in the role it was handed, and a level authored for real play
## swaps that node's script for [EnetTransport] — `scenes/level.tscn` does, the
## same way the harness does. Asking a [LoopbackTransport] to host is therefore
## not an error here; it announces itself and links to nobody, which is exactly
## what a level that never meant to be networked should do.
func open_link() -> void:
	if command_link == null or transport == null:
		return
	var net: NetworkConfig = GameSession.network
	if net == null or not net.is_online():
		return
	# #554: both roles want the joining peer's id — the host to stamp its roster,
	# the client to learn its own. Connected before the socket opens so no
	# connection can beat the listener.
	transport.peer_joined.connect(_on_peer_joined)
	# And the two ways a link ENDS, which until now only the lobby listened to
	# (#716 surfaced them there; the level never picked them up).
	transport.peer_left.connect(_on_peer_left)
	transport.link_lost.connect(_on_link_lost)
	match net.role:
		NetworkTransport.Role.HOST:
			# The hello is what produces the in-sync / DIVERGED verdict, and it
			# has to wait for a peer — `start_host` only opens a socket.
			transport.link_changed.connect(_greet_if_linked)
			transport.start_host(net.port)
		NetworkTransport.Role.CLIENT:
			transport.start_client(net.address, net.port)


## #463/#715: how a joining client gets a world at all. It does not generate one
## — it asks the authority for the serialized one, through the [constant
## CommandLink.KIND_RESYNC] envelope #561 already ships: entities, graph, then
## the entity->node pass, in one message.
##
## [b]#715 made this the ONLY way a client gets a map, and that closed a
## window.[/b] Until then the client generated from the host's seed and pulled on
## top, because generating from a seed is not the same as playing the host's map
## (`procgen/` leans on transcendentals whose last bit is not portable across two
## platforms' libm, #547). So there was a period where the link was up and a
## WRONG world was present. There is no longer: the client builds nothing, and
## `#689`/`#706`'s `pow()` in the seeded draw leaves the LAN critical path with
## it, because nothing on this machine re-derives the map.
##
## [b]A pull, not a push, and that is the whole ordering answer.[/b] A push
## races the level's own construction — over a loopback it lands INSIDE
## `_on_run_setup`, before the level has spawned anything at all. Asking once
## the level is built has no such window, and needs no upward "I am ready"
## message: [method CommandLink.request_resync] IS that message.
##
## [b]The reply's internal order is load-bearing, and it serves BOTH shapes.[/b]
## [method CommandLink._on_resync] decodes entities, decodes the graph, THEN
## resolves the entity->node refs. On the join path the graph is EMPTY, which is
## the #533 harness's old odd case and is now the primary one. On a mid-run
## repair (#521/#560/#561) it is POPULATED, and the order is what stops
## [method EntitySnapshot.resolve_graph_refs] resolving every `core_location`
## against nodes [method GraphSnapshot.decode] is about to delete. One order,
## both shapes — which is the reason this is a resync pull and not the two
## pushed snapshots `scenes/dev/mp_procgen_sandbox.gd` sends in the opposite
## order. Anyone "fixing" this to match the harness's order will reintroduce the
## bug; `test_graph_snapshot.gd` pins both shapes.
func pull_host_world() -> void:
	if command_link == null or not is_client():
		return
	command_link.request_resync("join: adopting the host's world", true)


## Wait for the authority's world, or for the link to end — whichever comes
## first. `true` when a world landed. Polled per frame rather than awaited on a
## signal because there are two signals to wait on, and because the renewal
## below needs a clock: every [member join_pull_retry_sec] without a world, the
## pull is sent again ([method CommandLink.renew_join_pull]).
func join_world() -> bool:
	var last_pull := Time.get_ticks_msec()
	while not _join_world_arrived and not _link_ended:
		if not is_inside_tree():
			return false
		await get_tree().process_frame
		if _join_world_arrived or _link_ended or command_link == null:
			break
		var now := Time.get_ticks_msec()
		if now - last_pull >= int(join_pull_retry_sec * 1000.0):
			last_pull = now
			command_link.renew_join_pull("join: still no world, asking again")
	return _join_world_arrived


## The whole join-or-host step, called by the root once its world is built —
## after `_setup_level` and the HUD compose, before the run is armed. `true`
## when there is a world to play on: at once for offline and host, and for a
## client once the authority's world has landed; `false` when a client's link
## ended first (refused, or the host went away), in which case the root
## presents that and stops.
##
## EVERY role opens here (#715), and the reason the host and offline always
## did is finally the reason on the joining side too: opening after
## `_setup_level` means a command arriving the instant the link comes up finds
## a world to apply to. Split from [method adopt_role] because the role has to
## be known far earlier than the socket may open.
##
## [b]#667's drop latch stays, and its window is what changed.[/b] It used to
## span the client's whole procgen — seconds, with a socket up and no world.
## It now spans the ONE round trip between adopting the link and the resync
## landing: this peer's world is empty until the pull answers, and a
## `KIND_COMMAND` that arrives meanwhile would apply against nothing.
## Narrower, not gone — the latch is still what makes the window safe rather
## than merely short, because `apply_remote` enqueues and drains AT ONCE
## against whatever world is there. If the command's ids do not resolve,
## `CommandApplier._validate` warns and DROPS it. If they DO resolve, nothing
## warns at all and it lands on whatever node happens to carry that
## `stable_id`. Silence here is not evidence that nothing went wrong.
##
## Either way it is survivable for exactly one reason: [method pull_host_world]
## asks the authority for its whole world, and the reply carries the
## authority's whole state, superseding both shapes above — what this peer
## missed and what it misapplied alike. Ordering makes it airtight rather than
## probable — `Wire._receive` is an `@rpc(..., "reliable")`, so it is ordered
## as well as delivered: the host encodes the resync when the request arrives,
## and anything it applies after that is sent after the envelope and lands on
## top of it. Nothing this window swallowed can outlive the pull.
##
## So the gate is not a buffer, it is the repair — and the pull must stay
## immediately after the link is up. Moving it later (behind a fade, an await,
## a turn start) reopens the hole this comment is about.
##
## And then WAIT for the answer, on the joining side only (#715). Before this,
## a client had a world of its own — the wrong one, but a populated one — so
## everything after could run against it and the pull repaired it a moment
## later. It no longer has one: its graph is empty until the resync lands, and
## arming [VictorySystem], starting a turn or lifting the curtain over nothing
## is not "a bit early", it is a level with no map. This wait IS what the
## client's loading bar has been covering since `_setup_level` — the host's
## generate and ship, rather than this machine's own procgen.
##
## Unbounded for the world, and bounded by the LINK (2026-09-06). It used to be
## a bare `await resync_applied`, with [SceneDirector]'s 30s reveal timeout as
## the only way out — and a link that died meanwhile (the host refusing this
## peer, the host quitting) presented its overlay UNDER the curtain: the
## run-end overlay is a layer-100 canvas and [SceneTransition] sits at 101, so
## the joiner looked at a black screen with a bar at 0% for the rest of the
## timeout. Now the wait ends the moment the link does, and the curtain lifts
## on the overlay that says why. While it waits, it re-asks for the world
## every [member join_pull_retry_sec] rather than trusting one ask.
func join_or_host() -> bool:
	var joining := is_client() and command_link != null
	if joining:
		command_link.defer_until_resync = true
	open_link()
	pull_host_world()
	if joining:
		return await join_world()
	return true


# --- Peer events -----------------------------------------------------------

## Host-side: announce our world to each peer as it arrives. `link_changed`
## fires for disconnects too, hence the [method NetworkTransport.is_linked]
## gate rather than greeting on every status line.
func _greet_if_linked(_status: String) -> void:
	if transport != null and transport.is_linked() and command_link != null:
		command_link.send_hello()


## #554: a peer arrived. On the lobby path everything about that has ALREADY
## happened — the socket was opened by the menu (#714), the joiner's seat was
## stamped there, and its id reached [GameSession] there too. What survives here
## is the belt-and-braces restatement of both facts for a peer that arrives while
## a level is up, and the replayed join [method EnetTransport._adopt_live_link]
## fires for a peer that was already on the socket when this level adopted it.
##
## [b]It no longer sends the run's shape, and that is #715's core subtraction.[/b]
## This was `run_setup`'s only sender, and it fired off a
## [signal NetworkTransport.peer_joined] that a PRE-ESTABLISHED link never fires
## again — so a level that adopted the lobby's socket would sit waiting for a
## message nobody would ever send. START broadcasts it from the lobby instead,
## once, over the live link ([method LobbyScreen._on_run_started]).
##
## [b]#733: the other half is refusing a peer that was never in the lobby at
## all.[/b] Everything above describes a peer [LobbyScreen] already seated —
## the replay, or the belt-and-braces restatement. A fresh dial mid-run has no
## seat in [member GameSession.roster], because "joining only happens to the
## lobby before the host presses START" (owner call, #733) — there is no
## drop-in mid-game. That peer is refused, with a reason a human reads on its
## screen, before [method LobbyScreen.stamp_pending_remote] or the world push
## below ever run.
func _on_peer_joined(peer_id: int) -> void:
	var net: NetworkConfig = GameSession.network
	if net == null:
		return
	if net.role == NetworkTransport.Role.CLIENT:
		GameSession.local_peer_id = transport.local_peer_id()
		# The root restates BOTH of its registry copies on this (#668): its
		# `_ready` pushed a snapshot of `GameSession.roster` and
		# `.local_peer_id`, and this branch exists precisely for the case where
		# those were not yet known then.
		local_peer_resolved.emit(GameSession.local_peer_id)
		return
	var seated := false
	if GameSession.roster != null:
		for p in GameSession.roster.all():
			if p.peer_id == peer_id:
				seated = true
				break
	if not seated:
		if command_link != null:
			command_link.refuse_peer(peer_id,
					"the run has already started — there is no drop-in mid-game")
		return
	LobbyScreen.stamp_pending_remote(GameSession.roster, peer_id)
	# And ship this peer the world (#715). Host-side this line runs at the tail of
	# the root's `_ready`, so the world is COMPLETE — [method open_link] is the
	# last thing before it, and [method EnetTransport._adopt_live_link] replays
	# the join for a peer that was already on the socket, which on the lobby
	# path is every peer.
	#
	# [b]Why a push as well as the client's pull.[/b] They race, and neither wins
	# alone. A client's level is up in milliseconds (it generates nothing) while
	# the host spends 5-10 seconds on procgen — so `request_resync` arrives while
	# the host's level has not yet adopted the link, `Wire` emits it to nobody,
	# and it is silently dropped. Conversely this push lands on nothing if the
	# client's level is the slower one.
	#
	# [b]And when BOTH legs land, the world is applied ONCE.[/b] Both are flagged
	# [constant CommandLink.KEY_JOIN] (the flag rides the request through
	# `_on_resync_request`, so the answer carries it too) and the client's
	# `_join_world_arrived` latch drops the loser outright rather than decoding a
	# whole world it already holds. `_awaiting_resync` stops it asking twice.
	# `CommandLink._on_resync`'s guard is where that is argued, including why it
	# keys off the flag rather than off a fingerprint compare — a mid-run repair
	# (#521/#560/#561) must still apply even when the fold agrees.
	#
	# The old warning against pushing from here does not survive #715: it said a
	# graph snapshot would "decode into a graph that is about to be generated
	# over", and the joining peer no longer generates anything.
	if command_link != null:
		command_link.send_resync(
				"join: the peer is on the link and has no world", true)


## This machine's link is gone — the host quit, the socket dropped — and it is
## not coming back: there is no drop-in mid-game (#733, owner call), so there
## is no rejoin either. Two things have to happen, and before this neither did:
##
## 1. The intent parked in [CommandApplier] waiting for a confirm that will
##    never arrive is abandoned. Otherwise `is_awaiting_confirmation` stays true
##    for the rest of the run and [method PlayerInputController.can_player_act]
##    gates every click closed — a silent hang.
## 2. The player is told — the root's half, off [signal link_lost]: the run-end
##    overlay, whose main-menu button is the same way out a finished run takes.
##
## A host whose own socket dies lands here too and is treated the same: its
## remote seats are all gone at once, and there is nobody left to play on for.
func _on_link_lost(reason: String) -> void:
	_link_ended = true
	if command_applier != null:
		command_applier.abandon_pending_intent(&"link_lost")
	link_lost.emit(reason)


## The host turned this peer away, and said why. The hang-up follows one
## message later and lands in [method _on_link_lost]. Reachable on the lobby
## route when the host's level finds no seat carrying this peer's id
## ([method _on_peer_joined]'s "no drop-in mid-game" refusal).
func _on_refused_by_host(reason: String) -> void:
	_link_ended = true
	if command_applier != null:
		command_applier.abandon_pending_intent(&"link_refused")
	refused.emit(reason)


## Host-side: a seated peer left mid-run. The run goes on for everyone still
## here — the alternative is the turn loop parked forever on a hero whose human
## will never end its turn, which every other player experiences as a hang with
## no explanation. The root hands its hero to the AI
## ([method GameRoot.hand_seat_to_ai]) off [signal peer_left]: the host is the
## authority, so the AI's turns cross the wire as ordinary confirmed commands
## and every mirror watches the hero keep playing.
##
## A client never acts on THIS signal: its host leaving is
## [method _on_link_lost], and a sibling client leaving is the host's to detect.
## It does hear about the outcome — the host broadcasts the handover and every
## mirror applies its shared half (#755, [signal seat_handover]).
func _on_peer_left(peer_id: int) -> void:
	var net: NetworkConfig = GameSession.network
	if net == null or net.role != NetworkTransport.Role.HOST:
		return
	peer_left.emit(peer_id)


## Mirror-side entry for a seat handover, off
## [signal CommandLink.seat_handover_received] (#755).
func _on_seat_handover(participant_id: int) -> void:
	seat_handover.emit(participant_id)


## The authority's world has landed (#715): the join wait may end, and the
## root re-derives what hangs off the world.
func _on_resync_applied(reason: String) -> void:
	_join_world_arrived = true
	world_ready.emit(reason)
