extends Node

## The socket, and the one RPC the whole game rides on — at a path that outlives
## every scene (#713).
##
## [b]Why an autoload.[/b] Godot resolves an RPC by NODE PATH, and until #713 the
## only `@rpc` in the repo sat on the transport mounted under [GameRoot]
## (`docs/domain/multiplayer-harness.md`, "The mount, and why a level may only
## SWAP it"). That made the wire unable to exist before a level did: two machines
## could not talk until both were already in one, which is why the lobby was
## local on every machine and why a joining client used to generate a world
## nobody was playing. `/root/Wire` is the same fixed-path argument #531 made,
## taken one step further — a path that is identical on every peer AND survives
## [method SceneDirector.goto].
##
## [b]The peer was always tree-scoped.[/b] `multiplayer.multiplayer_peer` is a
## property of the [SceneTree]'s [MultiplayerAPI], not of any node, so an open
## socket already survived a scene change. What died with the freed [GameRoot]
## was the RPC target, the signal connections, and the peer list — this class is
## those three things, kept somewhere that does not get freed.
##
## [b]It is not the transport seam.[/b] [NetworkTransport] is still what the game
## talks to, still mounted per-level, still swappable for [LoopbackTransport]
## headlessly. [EnetTransport] is now a facade over this singleton (it holds no
## peer of its own), so the seam's shape — and every two-worlds-in-one-process
## test fixture that depends on a per-root transport — is unchanged.
##
## One process holds one link. That was already true (`multiplayer_peer` is
## per-SceneTree) and is now stated by the structure rather than by a comment.

## A payload arrived from another peer. Never emitted for our own [method send].
signal message_received(payload: Dictionary)

## Human-readable link state, for a log or a lobby caption. Not a state machine —
## read [method is_linked] for a decision.
signal link_changed(status: String)

## A peer arrived, and this is WHICH one. Host-side this fires once per joining
## peer; client-side it fires for the server when the dial completes.
signal peer_joined(peer_id: int)

## A peer went away.
signal peer_left(peer_id: int)

## Mirrors [enum NetworkTransport.Role] by value. Declared here rather than
## imported so this singleton does not depend on the seam that wraps it — the
## dependency runs the other way.
var role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE

## Peers currently connected to us. Host-side this can be many; client-side it is
## only ever the server.
var _peers: PackedInt32Array = PackedInt32Array()

var _peer: ENetMultiplayerPeer


## Listen on [param port]. [constant OK] means the socket is open, not that
## anybody has connected yet.
func start_host(port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		_announce("host: FAILED to listen on %d (%s)" % [port, error_string(err)])
		return err
	_adopt(peer, NetworkTransport.Role.HOST)
	_announce("host: listening on port %d" % port)
	return OK


## Dial [param address]:[param port]. [constant OK] means the attempt started —
## success arrives later as [signal link_changed].
func start_client(address: String, port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_announce("client: FAILED to dial %s:%d (%s)" % [address, port, error_string(err)])
		return err
	_adopt(peer, NetworkTransport.Role.CLIENT)
	_announce("client: dialling %s:%d…" % [address, port])
	return OK


## Tear the link down and hand the [SceneTree] back the peer it started with.
## Idempotent.
##
## [b]It restores an [OfflineMultiplayerPeer]; it does not null the slot.[/b]
## Godot installs one by default, and that is what makes
## `multiplayer.get_unique_id()` answer `1` for a game with no network rather
## than raising — `CommandLink._local_peer_id` calls it unguarded, by design, on
## every single command. Nulling the slot leaves the whole process in a state it
## never boots into, and the damage lands nowhere near here: in GUT it surfaced
## as `Condition "multiplayer_peer.is_null()" is true` on ~30 unrelated tests
## that merely ran after a link was closed.
func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peers = PackedInt32Array()
	role = NetworkTransport.Role.OFFLINE


## Ship [param payload] to every connected peer. Silently drops when not linked.
func send(payload: Dictionary) -> void:
	if not is_linked():
		return
	_receive.rpc(payload)


## True when a peer is actually on the other end, not merely listening.
func is_linked() -> bool:
	return not _peers.is_empty()


## True when a socket exists at all — a host that nobody has joined yet answers
## true here and false to [method is_linked]. What a lobby asks to decide whether
## a second Host click would rebind a port it already holds.
func is_open() -> bool:
	return role != NetworkTransport.Role.OFFLINE


## This machine's own id on the link. [constant NetworkTransport.HOST_PEER_ID] on
## a host, whatever the server minted on a client, and `0` with no socket.
## [OfflineMultiplayerPeer] answers `1` — the same id ENet gives a host — so it
## is ruled out explicitly rather than by a null check. A peer that is not on a
## link is `0`, which is the [member Participant.peer_id] a lobby-authored
## offline seat carries, so an offline run stays a couch by construction.
func local_peer_id() -> int:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return 0
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()


## Everyone currently on the other end. A copy — a caller iterating this while a
## peer drops must not have the array mutated underneath it.
func peers() -> PackedInt32Array:
	return _peers.duplicate()


func _adopt(peer: ENetMultiplayerPeer, as_role: NetworkTransport.Role) -> void:
	_peer = peer
	role = as_role
	multiplayer.multiplayer_peer = peer
	_wire_multiplayer_signals()


## Connected once, and only if not already connected — [method stop] drops the
## peer but leaves this singleton's connections in place.
func _wire_multiplayer_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	if not _peers.has(id):
		_peers.append(id)
	_announce("peer %d connected" % id)
	# Announce FIRST, then hand the id up: a listener on `peer_joined` may send
	# (the host's run setup does), and `send` is gated on [method is_linked],
	# which only just became true on the line above.
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	var idx := _peers.find(id)
	if idx != -1:
		_peers.remove_at(idx)
	_announce("peer %d disconnected" % id)
	peer_left.emit(id)


## Client-side, the server's arrival also comes through `peer_connected`; this
## is the moment this machine learns its OWN id, which is what a lobby needs to
## stamp its seat before any level exists.
func _on_connected_to_server() -> void:
	_announce("client: connected (my id %d)" % multiplayer.get_unique_id())
	peer_joined.emit(NetworkTransport.HOST_PEER_ID)


func _on_connection_failed() -> void:
	_announce("client: connection FAILED")
	stop()


func _on_server_disconnected() -> void:
	_announce("client: host went away")
	stop()


func _announce(status: String) -> void:
	link_changed.emit(status)


## The wire's only entry point, and the repo's only production `@rpc`.
## `call_remote` so a send never re-enters the sender — the host has already
## applied what it is broadcasting.
##
## [b]Its path is `/root/Wire` on every peer, in every scene.[/b] That is the
## whole reason this singleton exists; moving this function anywhere else
## re-couples the wire to whatever scene is loaded.
@rpc("any_peer", "call_remote", "reliable")
func _receive(payload: Dictionary) -> void:
	message_received.emit(payload)
