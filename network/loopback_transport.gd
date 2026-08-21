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


## Two transports facing each other, already "linked".
static func pair() -> Array[LoopbackTransport]:
	var host := LoopbackTransport.new()
	var client := LoopbackTransport.new()
	host.peer = client
	client.peer = host
	host.role = Role.HOST
	client.role = Role.CLIENT
	return [host, client]


func start_host(_port: int) -> Error:
	role = Role.HOST
	_announce("loopback: host")
	return OK


func start_client(_address: String, _port: int) -> Error:
	role = Role.CLIENT
	_announce("loopback: client")
	return OK


func stop() -> void:
	peer = null
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
