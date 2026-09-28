class_name WorldSyncChannel
extends LinkChannel
## How a world ARRIVES on a peer, and how a drifted one is put back: the
## snapshot / entities / setup legs, the whole-world resync and its request, and
## the fingerprint check whose only effect is a resync. Rides a [NetworkLink]
## beside the command channel and owns nothing of it — the stamped compare reads
## [signal CommandApplier.command_stamped], so it runs with no command channel
## mounted at all.
##
## [member LinkChannel.deferred_until_world] stays false: these kinds are HOW a
## world arrives, so the pre-world latch must never drop them. A landed resync
## is what clears [member NetworkLink.defer_until_world].
##
## The backstop's contract (client asks once, host pushes, a second drift waits
## for the next agreeing boundary; a join world applies once) is in
## `docs/domain/multiplayer-sync-model.md`.

const KEY_FINGERPRINT := "fp"
const KEY_SUMMARY := NetworkLink.KEY_SUMMARY
const KEY_SNAPSHOT := "snapshot"
const KEY_ENTITIES := "entities"
const KEY_CONFIG := "config"
const KEY_ROSTER := "roster"
## Marks a resync (and the request that asked for it) as the JOIN's world, so
## the second of the join's two whole-world legs is recognised and dropped.
const KEY_JOIN := "join"

## Host → client: the graph half of a world, applied in place.
const KIND_SNAPSHOT := "snapshot"
## Host → client: the resolved config + roster, opening the run on a joiner.
const KIND_SETUP := "setup"
## Host → client: the entity half of a world. Parks its graph refs until the
## nodes they resolve against exist.
const KIND_ENTITIES := "entities"
## Host → client: the WHOLE world in one ordered message — the repair, and the
## join's world.
const KIND_RESYNC := "resync"
## Client → host: "send me your world". The client never reconstructs state.
const KIND_RESYNC_REQUEST := "resync_request"

## One fingerprint comparison — at link-up or at a command's stamp point.
signal sync_checked(agrees: bool, local: int, remote: int)
## Host-side: a whole world was pushed.
signal resync_sent(reason: String)
## Client-side: a whole world landed.
signal resync_applied(reason: String)

@export var graph: Graph
@export var turn_manager: TurnManager
## Its [signal CommandApplier.command_stamped] is the check's input. Falls back
## to the core's applier when left unset.
@export var command_applier: CommandApplier
## Receives [method DeterminismProbe.observe_world] for every compared stamp.
@export var probe: DeterminismProbe

## Materialises an entity a snapshot names but this peer lacks. Set by
## [GameRoot]; empty in tests that never materialise one.
var entity_spawner: Callable = Callable()

## An entity snapshot that arrived before the graph it points into.
var _pending_entities: PackedByteArray = PackedByteArray()
## A request is in flight; cleared when a resync lands or a boundary agrees, so
## a drifting client asks once rather than once per command.
var _awaiting_resync: bool = false
## The join's world has landed; every later join-flagged world is the race's
## loser and is dropped. Never set by a mid-run repair.
var _join_world_arrived: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_connect_applier()


func _on_attached() -> void:
	link.hello_accepted.connect(_on_hello_accepted)
	_connect_applier()


func _connect_applier() -> void:
	if command_applier == null and link != null:
		command_applier = link.command_applier
	if command_applier != null and not command_applier.command_stamped.is_connected(_on_command_stamped):
		command_applier.command_stamped.connect(_on_command_stamped)


func kinds() -> Array[String]:
	return [KIND_SNAPSHOT, KIND_SETUP, KIND_ENTITIES, KIND_RESYNC, KIND_RESYNC_REQUEST]


func receive(kind: String, payload: Dictionary) -> void:
	match kind:
		KIND_SNAPSHOT:
			_on_graph_snapshot(payload)
		KIND_SETUP:
			_on_run_setup(payload)
		KIND_ENTITIES:
			_on_entity_snapshot(payload)
		KIND_RESYNC:
			_on_resync(payload)
		KIND_RESYNC_REQUEST:
			_on_resync_request(payload)


func _role() -> NetworkConfig.Role:
	return link.role if link != null else NetworkConfig.Role.OFFLINE


func _log(line: String) -> void:
	if link != null:
		link.logged.emit(line)


# ── send side ─────────────────────────────────────────────────────────────────

## Host-side: the build stamp plus this world's fingerprint and summary, which
## the joiner compares at link-up. Tolerates a null graph (a lobby-less build
## check has none).
func send_hello() -> void:
	if link == null:
		return
	link.send_hello({
		KEY_FINGERPRINT: WorldFingerprint.compute(graph),
		KEY_SUMMARY: WorldFingerprint.describe(graph),
	})


func send_graph_snapshot() -> void:
	if graph == null or link == null:
		return
	if link.send({NetworkLink.KEY_KIND: KIND_SNAPSHOT, KEY_SNAPSHOT: GraphSnapshot.encode(graph)},
			NetworkConfig.Role.HOST):
		_log("→ graph snapshot (%s)" % WorldFingerprint.describe(graph))


func send_entity_snapshot() -> void:
	if graph == null or link == null:
		return
	if link.send({NetworkLink.KEY_KIND: KIND_ENTITIES, KEY_ENTITIES: EntitySnapshot.encode(graph)},
			NetworkConfig.Role.HOST):
		_log("→ entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


func send_run_setup(config: RunConfig, roster: ParticipantRoster) -> void:
	if config == null or link == null:
		return
	if link.send({
		NetworkLink.KEY_KIND: KIND_SETUP,
		KEY_CONFIG: config.to_dict(),
		KEY_ROSTER: (roster.to_dict() if roster != null else {"participants": []}),
	}, NetworkConfig.Role.HOST):
		_log("→ run setup (seed %d, %d participants)" %
				[config.seed, roster.all().size() if roster != null else 0])


## Host-side: the whole world, entities first — see [method _on_resync] for the
## order it is applied in.
func send_resync(reason: String, is_join_world: bool = false) -> void:
	if graph == null or link == null:
		return
	if not link.send({
		NetworkLink.KEY_KIND: KIND_RESYNC,
		KEY_ENTITIES: EntitySnapshot.encode(graph),
		KEY_SNAPSHOT: GraphSnapshot.encode(graph),
		KEY_SUMMARY: reason,
		KEY_JOIN: is_join_world,
	}, NetworkConfig.Role.HOST):
		return
	_log("⟳ RESYNC pushed — %s (%s)" % [reason, WorldFingerprint.describe(graph)])
	resync_sent.emit(reason)


## Client-side: ask the host for its world. Latched on [member _awaiting_resync]
## so a mid-run verdict cannot flood the host.
func request_resync(reason: String, is_join_world: bool = false) -> void:
	if _awaiting_resync or link == null:
		return
	if not link.send({
		NetworkLink.KEY_KIND: KIND_RESYNC_REQUEST,
		KEY_SUMMARY: reason,
		KEY_JOIN: is_join_world,
	}, NetworkConfig.Role.CLIENT):
		return
	_awaiting_resync = true
	_log("↑ resync requested — %s" % reason)


## The join's pull, asked AGAIN: the latch would swallow a second ask, and a
## lost first answer must not strand the joiner. A no-op once the join world
## has landed.
func renew_join_pull(reason: String) -> void:
	if _join_world_arrived:
		return
	_awaiting_resync = false
	request_resync(reason, true)


# ── receive side ──────────────────────────────────────────────────────────────

func _on_resync_request(payload: Dictionary) -> void:
	if _role() != NetworkConfig.Role.HOST:
		return
	var reason := String(payload.get(KEY_SUMMARY, "peer asked"))
	_log("↓ resync requested by peer — %s" % reason)
	# The join flag rides the request through, so the answer is recognisable as
	# the join's world on the way back down.
	send_resync(reason, bool(payload.get(KEY_JOIN, false)))


## Applied in dependency order: entities (spawn/remove), graph, the entities'
## graph refs, HP (a pool clamps to a cap the owner's now-whole board decides),
## then the turn cursor (its [signal TurnManager.turn_started] reaches the HUD,
## so it must not fire over a half-restored world).
func _on_resync(payload: Dictionary) -> void:
	if _role() != NetworkConfig.Role.CLIENT or graph == null:
		return
	var entity_bytes: PackedByteArray = payload.get(KEY_ENTITIES, PackedByteArray())
	var graph_bytes: PackedByteArray = payload.get(KEY_SNAPSHOT, PackedByteArray())
	var reason := String(payload.get(KEY_SUMMARY, ""))
	if graph_bytes.is_empty():
		# `GraphSnapshot._unpack` reads a size header off the front, so an empty
		# payload is a decode error, not a no-op.
		_log("← resync with no graph half, dropped")
		return
	var is_join_world := bool(payload.get(KEY_JOIN, false))
	if is_join_world and _join_world_arrived:
		# The join race's loser: both legs carry a WHOLE world, and the transport
		# is one ordered channel, so this peer already holds what this describes.
		# Re-applying would re-emit [signal resync_applied] and re-enter
		# [member entity_spawner]. Scoped to the flag, never to "a world is
		# present" — a mid-run repair carries no flag and must always apply.
		_log("← join world already applied, dropped — %s" % reason)
		return
	EntitySnapshot.decode(entity_bytes, graph, entity_spawner)
	GraphSnapshot.decode(graph_bytes, graph)
	EntitySnapshot.resolve_graph_refs(entity_bytes, graph, entity_spawner)
	GraphSnapshot.restore_hp(graph_bytes, graph)
	EntitySnapshot.restore_turn_cursor(entity_bytes, graph, turn_manager)
	# The repair has landed: the next compare says whether it worked, and the
	# world this peer was missing is now the host's, so the drop window is over.
	_awaiting_resync = false
	link.defer_until_world = false
	if is_join_world:
		_join_world_arrived = true
	_log("⟳ resync applied — %s (%s)" % [reason, WorldFingerprint.describe(graph)])
	resync_applied.emit(reason)


func _on_graph_snapshot(payload: Dictionary) -> void:
	var bytes: PackedByteArray = payload.get(KEY_SNAPSHOT, PackedByteArray())
	if graph == null or bytes.is_empty():
		return
	GraphSnapshot.decode(bytes, graph)
	# An entity snapshot that landed first parked here: its `core_location` and
	# node-sourced effects need nodes to resolve against, and now they exist.
	_drain_pending_entities()
	_log("← graph snapshot (%s)" % WorldFingerprint.describe(graph))


func _on_run_setup(payload: Dictionary) -> void:
	var config := RunConfig.from_dict(payload.get(KEY_CONFIG, {}))
	var roster := ParticipantRoster.from_dict(payload.get(KEY_ROSTER, {}))
	GameSession.apply_received(config, roster)
	_log("← run setup (seed %d, %d participants)" % [config.seed, roster.all().size()])


func _on_entity_snapshot(payload: Dictionary) -> void:
	var bytes: PackedByteArray = payload.get(KEY_ENTITIES, PackedByteArray())
	if graph == null or bytes.is_empty():
		return
	EntitySnapshot.decode(bytes, graph, entity_spawner)
	_pending_entities = bytes
	if not graph.get_skill_nodes().is_empty():
		_drain_pending_entities()
	_log("← entity snapshot (%d entities)" % EntitySnapshot.entities_of(graph).size())


func _drain_pending_entities() -> void:
	if _pending_entities.is_empty() or graph == null:
		return
	var bytes := _pending_entities
	_pending_entities = PackedByteArray()
	EntitySnapshot.resolve_graph_refs(bytes, graph, entity_spawner)
	EntitySnapshot.restore_turn_cursor(bytes, graph, turn_manager)


# ── the check ─────────────────────────────────────────────────────────────────

## The link-up compare: the host's hello carries its world's fingerprint.
func _on_hello_accepted(payload: Dictionary) -> void:
	var remote := int(payload.get(KEY_FINGERPRINT, 0))
	var local := WorldFingerprint.compute(graph)
	_log("host world: %s" % payload.get(KEY_SUMMARY, "?"))
	_log("mine:       %s" % WorldFingerprint.describe(graph))
	_report_sync(local, remote, "at link-up")


## The per-command compare, at this peer's own stamp point inside the applier's
## drain: pre-state against the host's pre-state. An unstamped command is the
## command channel's to count ([method DeterminismProbe.observe_skipped]).
func _on_command_stamped(command: Command) -> void:
	if _role() != NetworkConfig.Role.CLIENT or command == null or command.host_fingerprint == 0:
		return
	var agrees := _report_sync(command.pre_fingerprint, command.host_fingerprint,
			"before %s" % command.type_tag())
	if probe != null:
		probe.observe_world(command, agrees)


## A verdict is always reported — [signal sync_checked] and a loud log line —
## and a disagreeing one is then healed, never swallowed.
func _report_sync(local: int, remote: int, when: String) -> bool:
	var agrees := local == remote
	sync_checked.emit(agrees, local, remote)
	if agrees:
		_log("  ✓ in sync %s (fp %d)" % [when, local])
		# The repair landed and the next boundary agreed, so the client may ask
		# again if it ever drifts a second time.
		_awaiting_resync = false
		return true
	_log("  ✗ DIVERGED %s — mine %d, host %d" % [when, local, remote])
	_heal_desync("%s (mine %d, host %d)" % [when, local, remote])
	return false


## The authority pushes, a mirror asks — a client never reconstructs state.
func _heal_desync(reason: String) -> void:
	match _role():
		NetworkConfig.Role.HOST:
			send_resync(reason)
		NetworkConfig.Role.CLIENT:
			request_resync(reason)
