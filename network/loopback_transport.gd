@tool
class_name LoopbackTransport
extends NetworkTransport

## An in-process [NetworkTransport] pair — no socket, no OS process.
##
## [b]It does not echo to itself.[/b] A self-echo would re-apply every command
## the sender already applied, which is the one failure mode a loopback must not
## have. Instead two instances are wired to each other via [method pair]: what
## one sends, the other receives.
##
## This exists so the seam is testable headlessly (`test/unit/network/`). It is
## NOT the single-player / hot-seat path the sync model describes — that path
## needs the intent-up channel (#463), and wave 0 has none.

## The other end. Null until [method pair] (or a direct assignment) wires it.
var peer: LoopbackTransport

## What this end calls itself, so [signal NetworkTransport.peer_joined] and
## [method NetworkTransport.local_peer_id] mean something headlessly. [method
## pair] mints the same two ids ENet would: the host is [constant
## NetworkTransport.HOST_PEER_ID], the client is the next one up.
var my_peer_id: int = 0


## Two transports facing each other, already "linked".
## The id a paired loopback client answers to. ENet would mint something
## larger and random; the exact number is irrelevant, that it DIFFERS from the
## host's is the whole point of a headless versus fixture.
const _CLIENT_PEER_ID := 2


static func pair() -> Array[LoopbackTransport]:
	var host := LoopbackTransport.new()
	var client := LoopbackTransport.new()
	host.peer = client
	client.peer = host
	host.role = Role.HOST
	client.role = Role.CLIENT
	host.my_peer_id = HOST_PEER_ID
	client.my_peer_id = _CLIENT_PEER_ID
	# No `peer_joined` here: these two objects were minted on the line above, so
	# nothing can be connected yet and the emit would land on nobody. A test that
	# wants the join event connects first and then calls [method announce_joined].
	return [host, client]


## Replay the join both ends already have, for a listener that could not have
## been connected when [method pair] ran. Loopback-only — the real transports
## emit this off an actual socket event.
func announce_joined() -> void:
	if peer == null:
		return
	peer_joined.emit(peer.my_peer_id)


func start_host(_port: int) -> Error:
	role = Role.HOST
	my_peer_id = HOST_PEER_ID
	_announce("loopback: host")
	return OK


func start_client(_address: String, _port: int) -> Error:
	role = Role.CLIENT
	my_peer_id = _CLIENT_PEER_ID
	_announce("loopback: client")
	return OK


func stop() -> void:
	peer = null
	my_peer_id = 0
	super()
	_announce("loopback: closed")


func send(payload: Dictionary) -> void:
	if peer == null:
		return
	# Duplicated deep: the receiver must not be handed a dictionary the sender
	# can still mutate. A real socket copies by definition; a loopback that
	# skips this hides aliasing bugs until the day ENet is switched on.
	peer.message_received.emit(payload.duplicate(true))


func is_linked() -> bool:
	return peer != null


func local_peer_id() -> int:
	return my_peer_id
