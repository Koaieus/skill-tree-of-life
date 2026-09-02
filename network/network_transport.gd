@tool
class_name NetworkTransport
extends Node

## The seam every networked byte crosses (`docs/domain/multiplayer-sync-model.md`).
##
## Deliberately dumb: it moves [Dictionary] payloads between peers and knows
## nothing about commands, entities or authority. That split is what makes the
## transport choice "close to free and reversible" the doc claims — swapping
## [EnetTransport] for a WebSocket or WebRTC one touches nothing above this
## class.
##
## [b]Payloads are plain dictionaries of primitives[/b], because that is what
## [method Command.to_dict] already produces and what every Godot transport can
## encode without a custom serializer.
##
## [b]This is wave 0 of the harness, not the sync layer.[/b] There is no
## host-authority validation here and no intent channel upward — see
## [CommandLink] for exactly what is and is not wired, and why (#463 owns the
## rest).

## Who this peer is on the link. Set by [method start_host] / [method start_client].
enum Role {
	OFFLINE,  ## No link.
	HOST,     ## Decides; broadcasts confirmed commands down.
	CLIENT,   ## Applies what it is told.
}

## A payload arrived from the other side. Never emitted for our own [method send].
signal message_received(payload: Dictionary)

## Human-readable link state, for the harness log. Not a state machine — read
## [method is_linked] for a decision, this is for a person to read.
signal link_changed(status: String)

## A peer arrived, and this is WHICH one (#554). Distinct from [signal
## link_changed] on purpose: that one is prose for a log, this one carries the
## single datum nothing above the seam can obtain for itself.
##
## [b]The transport is where a peer id lives.[/b] Godot's peer ids come off
## [member Node.multiplayer], and reaching for that from a lobby or a level
## would put transport knowledge above the seam — the one thing this class
## exists to prevent. Host-side this fires once per joining peer; client-side it
## fires for the server (id 1) when the dial completes.
signal peer_joined(peer_id: int)

## A peer went away. Since #716 the LOBBY derives state from this: a seat whose
## peer dropped goes back to waiting ([method LobbyScreen._on_link_peer_left]).
## In a RUN nothing does, and that is still deliberate — the sync model's answer
## to an in-run disconnect is "a desync is a restart" (#554 NOTES).
signal peer_left(peer_id: int)

## This machine's link went away without it asking (#716): a failed dial, a host
## that went away, a host that dropped us. Distinct from [signal link_changed],
## which is prose for a log, and from [signal peer_left], which is about somebody
## ELSE — this one says the local end is offline now.
##
## [b]Emitted AFTER the transport is already OFFLINE[/b], so a listener that
## repaints a lobby reads the state it is being told about rather than the one
## that is about to be true.
signal link_lost(reason: String)

## The id Godot's high-level multiplayer always gives the server. Named here
## rather than typed as a literal at each site that stamps the host's own
## participant.
const HOST_PEER_ID := 1

var role: Role = Role.OFFLINE


## Listen on [param port]. Returns an [enum Error]; [constant OK] means the
## socket is open, not that anybody has connected yet.
func start_host(_port: int) -> Error:
	return ERR_UNAVAILABLE


## Dial [param address]:[param port]. [constant OK] means the attempt started —
## success arrives later as [signal link_changed].
func start_client(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


## Tear the link down. Idempotent.
func stop() -> void:
	role = Role.OFFLINE


## Ship [param payload] to the other side. Silently drops when not linked — a
## transport is not the place to decide that an unsent message is an error.
func send(_payload: Dictionary) -> void:
	pass


## Ship [param payload] to ONE peer (#716). Same silent-drop contract as
## [method send]; the default is a no-op for the same reason.
##
## [b]Why the seam needs it at all.[/b] The build-stamp gate now runs host-side,
## per joining peer, before a seat is offered — and the refusal has to reach that
## peer alone. A broadcast refusal would print on every client that is already
## seated and happily linked.
func send_to(_peer_id: int, _payload: Dictionary) -> void:
	pass


## Disconnect ONE peer, leaving the link up for everybody else (#716). Host-side;
## a client has nothing to drop but its own link, which is [method stop].
func drop_peer(_peer_id: int) -> void:
	pass


## The VERIFIED id of whoever sent the payload currently being delivered — the
## transport's own answer, not one the sender wrote into the dictionary. `0`
## when unknown (no link, or a payload injected straight at [signal
## message_received] by a fixture).
##
## [b]Anything that acts ON a peer must key off this[/b], because a claimed id is
## a claim: the build gate disconnects the peer it refuses, and taking the id
## from the payload would let one client name another and have it dropped. Read
## it inside a [signal message_received] handler and nowhere else — it describes
## the message in flight and the next arrival overwrites it.
func last_sender_id() -> int:
	return 0


## True when a peer is actually on the other end (not merely listening).
func is_linked() -> bool:
	return false


## This machine's own id on the link — the value [member GameSession.local_peer_id]
## takes, and what [method SeatPolicy.from_roster] compares each
## [member Participant.peer_id] against. [constant HOST_PEER_ID] on a host,
## whatever the server minted on a client, and `0` offline — which is exactly the
## [member Participant.peer_id] a lobby-authored offline seat carries, so an
## offline run stays a couch by construction.
func local_peer_id() -> int:
	return 0


## For subclasses: announce and log in one call.
func _announce(status: String) -> void:
	link_changed.emit(status)
