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

## This machine's own link went away without it asking (#716) — a dial that
## failed or that nobody answered (#752), a host that quit, a host that dropped
## us. Emitted AFTER [method stop] has run, so [member role] already reads
## OFFLINE.
signal link_lost(reason: String)

## How long a dial may go unanswered before this machine gives up on it (#752).
##
## [b]Why ENet's own `connection_failed` is not enough.[/b] It does fire — see
## [method _on_connection_failed] — but only once ENet has exhausted its
## connect retries, which is on the order of 15–30 seconds, and on a LAN the
## common failures (a wrong IP, a host not up yet, a firewall eating UDP) all
## look identical to "still trying" until then. `create_client` itself returns
## [constant OK] the instant the socket exists. So without this, a joiner who
## typed the wrong address sat on a "dialling…" caption with nothing telling
## it to stop waiting. Eight seconds is well past any LAN round trip and well
## short of a human giving up on the screen.
const DIAL_TIMEOUT_SEC := 8.0

## Overridable so a test can watch the watchdog fire without spending eight
## real seconds on it. Production never writes it.
var dial_timeout_sec: float = DIAL_TIMEOUT_SEC

## Mirrors [enum NetworkTransport.Role] by value. Declared here rather than
## imported so this singleton does not depend on the seam that wraps it — the
## dependency runs the other way.
var role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE

## Peers currently connected to us. Host-side this can be many; client-side it is
## only ever the server.
var _peers: PackedInt32Array = PackedInt32Array()

var _peer: ENetMultiplayerPeer

## Armed by [method start_client], disarmed by the server answering or by
## [method stop]; fires [method _on_dial_watchdog_timeout]. A [Timer] child
## rather than a [SceneTreeTimer] because a dial that is abandoned early (the
## player backs out, or re-dials) needs it CANCELLED, not merely ignored.
var _dial_watchdog: Timer
## What the live dial is aimed at, for the watchdog's message. `""` when
## nothing is dialling.
var _dial_endpoint: String = ""

## The last line [signal link_changed] carried. A lobby that mounts AFTER a dial
## already failed has no signal left to catch — `create_client` errors
## synchronously on an unreachable or malformed address, before any screen could
## be listening — so the last announcement is the only thing left to show
## (#716 item 4).
var last_status: String = ""

## Who sent the payload currently being delivered, straight off the [MultiplayerAPI]
## — the id ENet itself vouches for, not one a sender wrote into a dictionary.
## `0` outside a delivery.
##
## [b]Read it during a [signal message_received] handler and nowhere else.[/b] It
## is a property of the message in flight; the next arrival overwrites it.
var last_sender_id: int = 0

## The ONE facade currently re-emitting this singleton's signals, by
## `get_instance_id()` — see [method claim_binder]. `0` when nobody holds it.
##
## An id, not the reference, because a freed [Object] compares equal to `null`
## (`.claude/rules/gdscript-pitfalls.md`): a latch holding the freed lobby
## transport would read back as "nothing bound" only by accident, and would read
## back as "still bound" the rest of the time.
var _binder_id: int = 0


func _ready() -> void:
	_dial_watchdog = Timer.new()
	_dial_watchdog.name = "DialWatchdog"
	_dial_watchdog.one_shot = true
	# A dial happens from the menu, but nothing about a paused tree should be
	# able to turn "no answer" back into "silent forever".
	_dial_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	_dial_watchdog.timeout.connect(_on_dial_watchdog_timeout)
	add_child(_dial_watchdog)


## Take exclusive hold of this singleton's signals, and refuse if somebody else
## already has it (#715).
##
## [b]Why exclusivity is a rule and not a convention.[/b] Since #714 there are
## two places that mount a [NetworkTransport] facade over this one socket — the
## lobby and the level — and the level ADOPTS the link the lobby opened rather
## than opening its own. If the lobby's facade is still bound when the level's
## binds, BOTH re-emit [signal message_received] and every packet is handled
## twice: a command applied twice, a resync decoded twice, a roster adopted
## twice. Nothing errors; the world simply drifts. So the second binder is
## refused loudly here rather than left to the accident of which scene Godot
## frees first.
##
## Idempotent for the current holder: re-claiming what you already hold succeeds.
func claim_binder(who: Object) -> bool:
	if who == null:
		return false
	var id := who.get_instance_id()
	if _binder_id == id:
		return true
	if _binder_id != 0 and is_instance_id_valid(_binder_id):
		# A warning and a refusing RETURN VALUE, not `push_error`: the caller
		# ([method EnetTransport._bind]) answers `ERR_ALREADY_IN_USE` and its own
		# callers act on that, which is the same shape
		# [method EnetTransport._adopt_live_link] already uses for its refusal.
		push_warning(
			"Wire: %s tried to bind while %s already holds the wire — refused. "
			% [who, instance_from_id(_binder_id)]
			+ "Two bound facades double-handle every packet; release the first "
			+ "one (LobbyScreen.release_link) before mounting the second.")
		return false
	_binder_id = id
	return true


## Hand the wire back. A no-op for anybody who is not the current holder, so a
## facade tearing down after it was refused cannot evict the one that won.
func release_binder(who: Object) -> void:
	if who != null and _binder_id == who.get_instance_id():
		_binder_id = 0


## Is anything currently bound? What a test asserts on, and what makes the
## exclusivity rule observable rather than only enforced.
func has_binder() -> bool:
	return _binder_id != 0 and is_instance_id_valid(_binder_id)


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
## success arrives later as [signal link_changed], and a dial nobody answers
## within [member dial_timeout_sec] ends in [signal link_lost] (#752).
func start_client(address: String, port: int) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_announce("client: FAILED to dial %s:%d (%s)" % [address, port, error_string(err)])
		return err
	_adopt(peer, NetworkTransport.Role.CLIENT)
	_dial_endpoint = "%s:%d" % [address, port]
	_dial_watchdog.start(dial_timeout_sec)
	_announce("client: dialling %s…" % _dial_endpoint)
	return OK


## Tear the link down and hand the [SceneTree] back the peer it started with.
## Idempotent.
##
## [b]It restores an [OfflineMultiplayerPeer]; it does not null the slot.[/b]
## Godot installs one by default, and that is the state every headless test and
## every offline run boots into. Nulling the slot leaves the whole process in a
## state it never boots into, and the damage lands nowhere near here: in GUT it
## surfaced as `Condition "multiplayer_peer.is_null()" is true` on ~30 unrelated tests
## that merely ran after a link was closed.
## Nothing open means nothing to close, and that early return is what makes this
## safe to call from every leave path (#716 item 2): [method GameSession.end]
## and the lobby back-out both call it unconditionally, and neither should
## reinstall an [OfflineMultiplayerPeer] over a process that never had a socket.
func stop() -> void:
	if not is_open():
		return
	_disarm_dial_watchdog()
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


## Ship [param payload] to ONE peer (#716). Gated on that peer still being on our
## books: `rpc_id` at an id ENet no longer knows is an engine error, not a
## silent drop, and the whole point of this call site is a peer that is about to
## be disconnected.
func send_to(peer_id: int, payload: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	_receive.rpc_id(peer_id, payload)


## Disconnect ONE peer and keep listening (#716 item 1). Host-only — a client's
## only peer is the server, and hanging that up is [method stop].
##
## [b]The book is updated here rather than left to ENet.[/b]
## `disconnect_peer` schedules the drop; `peer_disconnected` arrives a poll or
## more later, and every caller wants "that peer is gone" to be true the instant
## it asked. [method _on_peer_disconnected] is idempotent for exactly this
## reason, so ENet's own later notification is a no-op rather than a second
## [signal peer_left].
func drop_peer(peer_id: int) -> void:
	if role != NetworkTransport.Role.HOST:
		return
	if _peer != null:
		_peer.disconnect_peer(peer_id)
	var idx := _peers.find(peer_id)
	if idx == -1:
		return
	_peers.remove_at(idx)
	_announce("peer %d dropped" % peer_id)
	peer_left.emit(peer_id)


## The port this machine is actually bound to, or `0` when it is not hosting.
## Asked for by a caller that wants to re-open the very endpoint it just held —
## which is the only way to state #716 acceptance 3 when the port was ephemeral.
func port() -> int:
	if _peer == null or role != NetworkTransport.Role.HOST:
		return 0
	return _peer.host.get_local_port()


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


## Idempotent: an id [method drop_peer] already took off the books produces
## nothing here, so ENet's own `peer_disconnected` for a peer this machine hung
## up cannot fire [signal peer_left] a second time — and a lobby seat cannot be
## returned to "waiting" twice, once per notification.
func _on_peer_disconnected(id: int) -> void:
	var idx := _peers.find(id)
	if idx == -1:
		return
	_peers.remove_at(idx)
	_announce("peer %d disconnected" % id)
	peer_left.emit(id)


## Client-side, the server's arrival also comes through `peer_connected`; this
## is the moment this machine learns its OWN id, which is what a lobby needs to
## stamp its seat before any level exists.
func _on_connected_to_server() -> void:
	_disarm_dial_watchdog()
	_announce("client: connected (my id %d)" % multiplayer.get_unique_id())
	peer_joined.emit(NetworkTransport.HOST_PEER_ID)


## [b]`stop()` comes FIRST, and that order is the whole fix (#716 item 4).[/b]
## [method EnetTransport._on_wire_status] copies [member role] out of this
## singleton on every announcement, so announcing before the teardown handed the
## facade the role it was ABOUT to stop being — CLIENT — and nothing above the
## seam ever learned the link had died. Announce the state that is already true.
func _on_connection_failed() -> void:
	_lost("could not reach the host")


func _on_server_disconnected() -> void:
	_lost("the host went away")


## The dial outlived [member dial_timeout_sec] with nobody on the line (#752).
## Guarded rather than trusted: a [Timer] that fired on the same frame the
## server answered, or one whose dial was already torn down another way, must
## not report a loss over a link that is fine.
func _on_dial_watchdog_timeout() -> void:
	if role != NetworkTransport.Role.CLIENT or is_linked():
		return
	_lost("no answer from %s" % _dial_endpoint)


func _disarm_dial_watchdog() -> void:
	_dial_endpoint = ""
	if _dial_watchdog != null:
		_dial_watchdog.stop()


func _lost(reason: String) -> void:
	stop()
	_announce("client: %s" % reason)
	link_lost.emit(reason)


func _announce(status: String) -> void:
	last_status = status
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
	# Captured BEFORE the emit: a handler that sends (the build gate's reject
	# does) re-enters the [MultiplayerAPI], and this is the only moment the
	# sender of THIS message is knowable.
	last_sender_id = multiplayer.get_remote_sender_id() if multiplayer != null else 0
	message_received.emit(payload)
