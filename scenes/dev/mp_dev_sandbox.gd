extends "res://scenes/dev_sandbox.gd"

## `dev_sandbox` with a network role — the world half of the multiplayer
## harness (see `docs/domain/multiplayer-harness.md` and the sandbox host's
## **Multiplayer** tab, which launches two of these).
##
## [b]Why an inherited scene and not a copy.[/b] The harness wants the SAME
## hand-authored 71-node graph on both peers, with no seed on the wire. A
## duplicated `.tscn` gives you that exactly until somebody edits the original;
## inheriting means the two can never drift.
##
## [b]Why two OS processes and not two viewports.[/b] [Events] is a
## process-global bus carrying live [SkillNode] / [Entity] references, and every
## listener ([LootSystem], [VictorySystem], [AllocationSystem], [BattleSystem],
## [HudRoot]) connects unconditionally. Two worlds in one process means world
## B's [VictorySystem] latches on world A's death. Separate processes give
## separate autoloads for free.
##
## [b]Role comes from the command line[/b], after the `--` separator:
## [codeblock]
## godot --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host --port=9099
## godot --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099
## [/codeblock]
## No role, or `--role=solo`, runs the scene as an ordinary offline sandbox.
##
## [b]Both heroes are human here.[/b] The base scene's Blue is an AI; the AI
## still calls [AllocationSystem] / [BattleSystem] directly (#512), so its turns
## would mutate the host's world without ever passing through [CommandApplier]
## and the client would silently drift. Making Blue human keeps every mutation
## in this scene on the one path the harness mirrors. The host hot-seats between
## the two; the client watches, bound to Blue.

const DEFAULT_PORT := 9099
const DEFAULT_ADDRESS := "127.0.0.1"

@onready var _transport: NetworkTransport = $Transport
@onready var _link: CommandLink = $CommandLink
@onready var _banner: Label = %NetBanner
@onready var _log: RichTextLabel = %NetLog

var _role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE
var _address: String = DEFAULT_ADDRESS
var _port: int = DEFAULT_PORT
var _blue: Entity
## `--autopilot` (host only): fire one scripted allocate once a client links, so
## the pair is verifiable from a terminal. See [method _run_autopilot].
var _autopilot: bool = false


func _ready() -> void:
	_parse_cmdline()
	super()
	if Engine.is_editor_hint():
		return
	# GameRoot._ready is a coroutine (it awaits `_setup_level`, then a layout
	# frame when the HUD composes), so `super()` above returns at its first
	# await and the player is not bound yet. One frame is enough for the whole
	# chain — including `bind_player`, whose `clear_transient_state` would
	# otherwise wipe the input freeze we set below.
	await get_tree().process_frame
	await get_tree().process_frame
	_start_link()


## Both entities become human, and the CLIENT binds Blue as its local hero.
## Runs before [method GameRoot._ensure_controllers], which is the window where
## `is_human_controlled` still decides which controller gets attached.
func _setup_level() -> void:
	await super()
	_blue = get_node_or_null(^"Graph/Entities/Enemy") as Entity
	if _blue == null:
		return
	_blue.is_human_controlled = true
	if _role == NetworkTransport.Role.CLIENT:
		player = _blue


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autopilot":
			_autopilot = true
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"role":
				match pair[1]:
					"host":
						_role = NetworkTransport.Role.HOST
					"client":
						_role = NetworkTransport.Role.CLIENT
			"address":
				_address = pair[1]
			"port":
				_port = int(pair[1])


func _start_link() -> void:
	_link.logged.connect(_write_log)
	_transport.link_changed.connect(_refresh_banner.unbind(1))

	match _role:
		NetworkTransport.Role.HOST:
			_link.mode = CommandLink.Mode.BROADCAST
			_write_log(WorldFingerprint.describe(graph))
			var err := _transport.start_host(_port)
			if err == OK:
				# The client connects later; greet it when it does.
				_transport.link_changed.connect(_greet_if_linked)
		NetworkTransport.Role.CLIENT:
			_link.mode = CommandLink.Mode.MIRROR
			# A spectator, on purpose: wave 0 has no intent channel upward, so a
			# local mutation here would diverge from the host with nothing to
			# correct it. `set_input_frozen` (#486) is the existing seam for
			# "every input channel off" and needs no change to the controller.
			input_ctl.set_input_frozen(true)
			_write_log(WorldFingerprint.describe(graph))
			_transport.start_client(_address, _port)
		_:
			_link.mode = CommandLink.Mode.OFF
			# Hot-seat, as the base scene plays — leave handover connected.
			_refresh_banner()
			return

	# On a networked peer the local view is fixed to the local hero, so the
	# hot-seat handover GameRoot wires in `_ready` is wrong here: it would swing
	# the host's HUD onto Blue and the client's onto Red.
	if _role == NetworkTransport.Role.CLIENT and turn_manager != null \
			and turn_manager.turn_started.is_connected(_on_turn_started_for_handover):
		turn_manager.turn_started.disconnect(_on_turn_started_for_handover)
	_refresh_banner()


func _greet_if_linked(_status: String) -> void:
	if not _transport.is_linked():
		return
	_link.send_hello()
	if _autopilot:
		_run_autopilot()


## Headless self-check (`--autopilot` on the host, after `--`): allocate one
## frontier node so a terminal-driven pair proves the whole path — command
## confirmed here, decoded and applied there, fingerprints compared — without a
## human clicking. Never fires unless asked for.
func _run_autopilot() -> void:
	await get_tree().create_timer(1.0).timeout
	var target := _first_frontier_node()
	if target == null:
		_write_log("autopilot: no frontier node to allocate")
		return
	# No SP grant here, deliberately: granting on the host only is itself an
	# unmirrored mutation, and on a tighter scene the client's `allocate` gate
	# would then refuse and autopilot would report a divergence it caused. It
	# spends the SP the scene authored, same as a player would.
	_write_log("autopilot: allocating %s" % target.name)
	input_ctl.command_applier.submit(
			AllocateCommand.new(player.entity_id, graph.get_stable_id(target)))


## First unowned node touching the local player's territory. Deliberately not
## routed through [AiRecon] — this wants the dumbest possible legal target, not
## a good one.
func _first_frontier_node() -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == player:
				return node
	return null


## On screen AND on stdout. The overlay is what you read in the launched window;
## the print is what you read when the pair is driven headless from a terminal
## (and `OS.create_instance` detaches stdout, so the overlay is the only channel
## that survives a launch from the sandbox tab).
func _write_log(line: String) -> void:
	print("[%s] %s" % [_role_name(), line])
	if _log == null:
		return
	_log.append_text(line + "\n")


func _role_name() -> String:
	match _role:
		NetworkTransport.Role.HOST:
			return "host"
		NetworkTransport.Role.CLIENT:
			return "client"
		_:
			return "solo"


func _refresh_banner() -> void:
	if _banner == null:
		return
	var linked := " · linked" if _transport.is_linked() else " · waiting"
	match _role:
		NetworkTransport.Role.HOST:
			_banner.text = "HOST — Red + Blue (hot-seat)%s" % linked
			_banner.modulate = Color(1.0, 0.55, 0.5)
		NetworkTransport.Role.CLIENT:
			_banner.text = "CLIENT — Blue, spectating%s" % linked
			_banner.modulate = Color(0.55, 0.75, 1.0)
		_:
			_banner.text = "SOLO — no link"
			_banner.modulate = Color(0.7, 0.75, 0.8)
