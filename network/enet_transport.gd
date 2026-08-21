@tool
class_name EnetTransport
extends NetworkTransport

## [NetworkTransport] over [ENetMultiplayerPeer] — the LAN default.
##
## ENet is the pick because it ships with Godot and is zero-config on a LAN, not
## because it is the only option; the seam above exists so that stays true
## (`docs/domain/multiplayer-sync-model.md`, "Transport").
##
## [b]Payloads ride one RPC.[/b] Godot's high-level multiplayer resolves an RPC
## by NODE PATH, so both peers must run a scene where this node sits at the same
## path — which is exactly what the harness does (both processes open the same
## `.tscn`). If you ever mount this transport at a different path per role, the
## RPC silently goes nowhere.
##
## [b]It claims the SceneTree's [MultiplayerAPI].[/b] `multiplayer_peer` is a
## per-SceneTree property, so one process holds one link. That is not a
## limitation to design around — two worlds in one process would also share the
## [Events] autoload, which is why the harness launches two OS processes instead
## (see `docs/domain/multiplayer-harness.md`).

## Peers currently connected to us. Host-side this can be many; client-side it
## is only ever the server (id 1).
var _peers: PackedInt32Array = PackedInt32Array()

var _peer: ENetMultiplayerPeer


func start_host(port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		_announce("host: FAILED to listen on %d (%s)" % [port, error_string(err)])
		return err
	_adopt(peer, Role.HOST)
	_announce("host: listening on port %d" % port)
	return OK


func start_client(address: String, port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_announce("client: FAILED to dial %s:%d (%s)" % [address, port, error_string(err)])
		return err
	_adopt(peer, Role.CLIENT)
	_announce("client: dialling %s:%d…" % [address, port])
	return OK


func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_peers = PackedInt32Array()
	super()


func send(payload: Dictionary) -> void:
	if not is_linked():
		return
	_receive.rpc(payload)


func is_linked() -> bool:
	return not _peers.is_empty()


func _adopt(peer: ENetMultiplayerPeer, as_role: Role) -> void:
	_peer = peer
	role = as_role
	multiplayer.multiplayer_peer = peer
	_wire_multiplayer_signals()


## Connected once per link, and only if not already connected — [method stop]
## drops the peer but leaves this node's connections in place.
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


func _on_peer_disconnected(id: int) -> void:
	var idx := _peers.find(id)
	if idx != -1:
		_peers.remove_at(idx)
	_announce("peer %d disconnected" % id)


func _on_connected_to_server() -> void:
	_announce("client: connected (my id %d)" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	_announce("client: connection FAILED")
	stop()


func _on_server_disconnected() -> void:
	_announce("client: host went away")
	stop()


## The wire's only entry point. `call_remote` so a send never re-enters the
## sender — the host has already applied what it is broadcasting.
@rpc("any_peer", "call_remote", "reliable")
func _receive(payload: Dictionary) -> void:
	message_received.emit(payload)
