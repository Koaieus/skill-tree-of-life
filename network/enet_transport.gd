@tool
class_name EnetTransport
extends NetworkTransport

## The LAN transport — a facade over the [Wire] singleton, which owns the socket
## and the RPC (#713).
##
## ENet is the pick because it ships with Godot and is zero-config on a LAN, not
## because it is the only option; the seam above exists so that stays true
## (`docs/domain/multiplayer-sync-model.md`, "Transport").
##
## [b]This node holds no peer.[/b] Before #713 it owned an [ENetMultiplayerPeer]
## and carried the repo's only `@rpc`, which pinned the wire to a node path
## underneath [GameRoot] — so two machines could not talk until both were already
## inside a level. Everything socket-shaped moved to `/root/Wire`, a path that
## outlives a scene change; what stays here is the [NetworkTransport] seam the
## game actually talks to.
##
## [b]So a level may ADOPT a link it did not open.[/b] [method start_host] and
## [method start_client] bring the socket up only when there isn't one; when the
## lobby already opened it, they bind to it and replay the peers that arrived
## before this node existed. That is what makes "the host clicks START and
## everyone transitions over an already-established connection" possible without
## a reconnect — and note that [method Wire.start_host] begins with a `stop()`,
## so a level that blindly re-started would tear down the very link it was handed.
##
## [b]Why the mount survives at all.[/b] The seam stays per-level and swappable:
## [LoopbackTransport] is still the mounted default, `test_link_mount.gd` still
## asserts exactly one transport child, and the two-worlds-in-one-process
## fixtures still give each [GameRoot] a transport of its own. A single
## process-wide transport could not serve two worlds; a single process-wide
## SOCKET always did, because `multiplayer_peer` is per-[SceneTree].

## Whether this node is currently bound to [Wire]'s signals. Bind is idempotent
## and unbind runs on [method _exit_tree], so a freed level stops re-emitting
## while the socket itself keeps running.
var _bound: bool = false


func _exit_tree() -> void:
	_unbind()


func start_host(port: int) -> Error:
	if Wire.is_open():
		return _adopt_live_link(Role.HOST)
	_bind()
	var err := Wire.start_host(port)
	role = Wire.role
	return err


func start_client(address: String, port: int) -> Error:
	if Wire.is_open():
		return _adopt_live_link(Role.CLIENT)
	_bind()
	var err := Wire.start_client(address, port)
	role = Wire.role
	return err


func stop() -> void:
	_unbind()
	Wire.stop()
	super()


func send(payload: Dictionary) -> void:
	Wire.send(payload)


func is_linked() -> bool:
	return Wire.is_linked()


func local_peer_id() -> int:
	return Wire.local_peer_id()


## Bind to a socket somebody else opened — the lobby, before this level existed.
##
## [b]The peers are replayed.[/b] A peer that connected while the menu was up
## fired [signal Wire.peer_joined] at a moment this node could not have been
## listening, and every host-side consequence of a join (stamping a roster seat,
## shipping the run setup) hangs off that signal. Replaying it here is what makes
## a level that adopts a link indistinguishable from one that opened its own.
## Emitted AFTER [signal NetworkTransport.link_changed], for the same ordering
## reason [method Wire._on_peer_connected] documents: a listener may send, and
## sending is gated on [method is_linked].
func _adopt_live_link(expected: Role) -> Error:
	if Wire.role != expected:
		_announce("adopt: REFUSED — the live link is %s, this level wants %s"
				% [Wire.role, expected])
		return ERR_UNAVAILABLE
	_bind()
	role = Wire.role
	_announce("adopted the live link (%d peer(s))" % Wire.peers().size())
	for id in Wire.peers():
		peer_joined.emit(id)
	return OK


func _bind() -> void:
	if _bound:
		return
	_bound = true
	Wire.message_received.connect(_on_wire_message)
	Wire.link_changed.connect(_on_wire_status)
	Wire.peer_joined.connect(_on_wire_peer_joined)
	Wire.peer_left.connect(_on_wire_peer_left)


func _unbind() -> void:
	if not _bound:
		return
	_bound = false
	Wire.message_received.disconnect(_on_wire_message)
	Wire.link_changed.disconnect(_on_wire_status)
	Wire.peer_joined.disconnect(_on_wire_peer_joined)
	Wire.peer_left.disconnect(_on_wire_peer_left)


func _on_wire_message(payload: Dictionary) -> void:
	message_received.emit(payload)


## Also the point where a link that closed itself (a failed dial, a host that
## went away) is reflected back into this node's own [member role] — [Wire] can
## drop to [constant NetworkTransport.Role.OFFLINE] without anybody calling
## [method stop] here.
func _on_wire_status(status: String) -> void:
	role = Wire.role
	_announce(status)


func _on_wire_peer_joined(id: int) -> void:
	peer_joined.emit(id)


func _on_wire_peer_left(id: int) -> void:
	peer_left.emit(id)
