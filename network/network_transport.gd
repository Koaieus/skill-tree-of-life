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

## A peer went away. Emitted for symmetry and for a log; the sync model's
## answer to a disconnect is still "a desync is a restart" (#554 NOTES), so
## nothing derives run state from this yet.
signal peer_left(peer_id: int)

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


## True when a peer is actually on the other end (not merely listening).
func is_linked() -> bool:
	return false


## This machine's own id on the link — the value [member GameSession.local_peer_id]
## takes, and what [method SeatPolicy.from_roster] compares each
## [member Participant.peer_id] against. [constant HOST_PEER_ID] on a host,
## whatever the server minted on a client, and `0` offline — which is exactly the
## value a lobby-authored LOCAL_HUMAN carries, so an offline run stays a couch by
## construction.
func local_peer_id() -> int:
	return 0


## For subclasses: announce and log in one call.
func _announce(status: String) -> void:
	link_changed.emit(status)
