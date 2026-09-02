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
##
## [b]Since #716 a host end may face SEVERAL clients[/b] ([method attach]), which
## is what makes "one joiner is refused and the other client is untouched"
## statable without a socket. A client end still holds exactly one link, its
## host, because that is all a client ever has.

## Every end this one talks to. A client holds one (its host); a host holds one
## per client.
var links: Array[LoopbackTransport] = []

## The other end, for the overwhelmingly common one-to-one fixture. A VIEW of
## [member links] rather than a second field: two stored answers to the same
## question is exactly the parallel state that goes on to disagree, and every
## fixture written before #716 addresses its pair through this name.
var peer: LoopbackTransport:
	get:
		return null if links.is_empty() else links[0]
	set(value):
		var next: Array[LoopbackTransport] = []
		if value != null:
			next.append(value)
		links = next

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


## A further client facing [param host], appended to its links (#716). The
## multi-client shape a real host has and [method pair] cannot express: two
## joiners, one listener, so refusing one can be shown to leave the other alone.
## [param client_id] is the id the "server" minted for it and must differ from
## every other end's.
static func attach(host: LoopbackTransport, client_id: int) -> LoopbackTransport:
	var client := LoopbackTransport.new()
	client.role = Role.CLIENT
	client.my_peer_id = client_id
	client.peer = host
	host.links.append(client)
	return client


## Replay the join both ends already have, for a listener that could not have
## been connected when [method pair] ran. Loopback-only — the real transports
## emit this off an actual socket event.
##
## [b]On a CLIENT end this is now the announce half of the build gate.[/b] Since
## #716 [method CommandLink._on_transport_peer_joined] sends a hello upward under
## [constant NetworkTransport.Role.CLIENT], so a fixture calling this on a client
## drives the very handshake a real dial does — which is the point.
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
	links = []
	my_peer_id = 0
	super()
	_announce("loopback: closed")


func send(payload: Dictionary) -> void:
	for link in links:
		# Duplicated deep, per recipient: the receiver must not be handed a
		# dictionary the sender — or a sibling recipient — can still mutate. A
		# real socket copies by definition; a loopback that skips this hides
		# aliasing bugs until the day ENet is switched on.
		link.message_received.emit(payload.duplicate(true))


func send_to(peer_id: int, payload: Dictionary) -> void:
	for link in links:
		if link.my_peer_id == peer_id:
			link.message_received.emit(payload.duplicate(true))
			return


## Drop one client, exactly as a host's socket would: the victim finds its own
## link gone, OFFLINE, and is told why — [signal NetworkTransport.link_lost] on
## the end that was dropped, [signal NetworkTransport.peer_left] on the end that
## did the dropping. Everybody else is untouched, which is the whole of #716
## item 1.
func drop_peer(peer_id: int) -> void:
	for i in links.size():
		var victim := links[i]
		if victim.my_peer_id != peer_id:
			continue
		links.remove_at(i)
		victim.links = []
		victim.role = Role.OFFLINE
		victim._announce("loopback: dropped by host")
		victim.link_lost.emit("dropped by host")
		peer_left.emit(peer_id)
		return


func is_linked() -> bool:
	return not links.is_empty()


func local_peer_id() -> int:
	return my_peer_id
