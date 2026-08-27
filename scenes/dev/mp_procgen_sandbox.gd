extends "res://scenes/game_root.gd"

## Rung 2 of the multiplayer harness (#533, ladder in
## `docs/domain/multiplayer-harness.md`): the HOST procgens a level from a
## fixed [RunConfig] and ships it across the wire — run settings (#528) then
## the graph itself (#527) — instead of the CLIENT re-deriving either from a
## shared seed. Rung 1 (`mp_dev_sandbox.gd`) proves messaging with a
## hand-authored graph on both peers and NOTHING crossing; this proves state
## actually crosses.
##
## [b]Why this matters beyond the harness (#547):[/b] `procgen/` leans on
## `pow`/`exp`/`sin`/`cos` for continuous placement math (draw weights, a
## Poisson roll, a Gaussian bump, points on a circle) — real math that would
## be wrong to rewrite, but whose last bit is not IEEE-754-portable across
## platforms' `libm`. Two peers "typing the same seed" can silently generate
## DIFFERENT maps, and every command after that lands on a node that isn't
## there. `CommandLink.send_graph_snapshot` (#527) and `send_run_setup`
## (#528) already existed with ZERO non-test callers before this unit — this
## is mostly wiring a caller, not new mechanism.
##
## [b]Reuses #531's mounted Transport/CommandLink[/b], exactly like rung 1:
## swap the mounted [Transport]'s script for [EnetTransport] in the .tscn,
## drive `--role` / `--port` / `--address` off the command line, never author
## a second pair.
##
## [b]No hot-seat here.[/b] Owner framing (2026-08-22): a client bound to Blue
## and staying bound through every handover is WANTED, not a divergence to
## chase. Unlike rung 1 — where the HOST hot-seats a human Red against an AI
## Blue — BOTH peers here are pinned with [method SeatPolicy.seat] to their
## own participant (host → Red, client → Blue) and never swing. Blue is still
## AI-driven (only the authority's [AIController] ever decides — the same
## `CommandApplier.is_authority` gate rung 1's class docstring documents at
## length), so the run still needs no upward intent channel (#463, unfiled
## rung 3).
##
## [b]The client never calls [GraphProcgen].[/b] It spawns bare placeholder
## [Entity] nodes — no `core_location`, so no graph is needed yet — in the
## SAME order the host does, so [Graph]'s per-entry `entity_id` minting
## (`graph/graph.gd::_mint_entity_id`) lands on the identical numbers. Only
## [b]This harness is its own composer, deliberately[/b] — one of the two
## exceptions to #584's "a level consumes a run, it never invents one". It
## opens the session itself ([method GameSession.ensure_started]) and writes
## the roster, because the run it builds is the thing it then SENDS to a peer;
## there is no lobby upstream of it and a [RunBootstrap] would only be able to
## author a run it must instead vary per harness case. The other exception is
## the client half, which receives its run from the host.
##
## once [signal GameSession.run_started] fires (via
## [method CommandLink._on_run_setup] → [method GameSession.apply_received])
## does it know how many participants there are and in what order; only once
## the graph snapshot itself arrives can ownership resolve — GraphSnapshot's
## own contract is that ownership resolves through the RECEIVING graph's
## entities, so those placeholders must already exist and be correctly ID'd.
##
## [b]`core_location` and the receiving board ride [EntitySnapshot] (#560),
## not [GraphSnapshot].[/b] [GraphSnapshot] carries which [Entity] owns each
## [SkillNode] (by `entity_id`) but nothing rebuilds the OWNER's board from
## that — #560's own framing: a client whose board never got the starting
## node's grants shows the wrong HP/stats from its first frame, silently.
## `CommandLink.send_entity_snapshot` is the sibling send this scene also
## makes: it DECORATES the entities the roster already spawned (never mints
## one — #560 D7), and its own two-pass decode is what resolves
## `core_location` — pass 1 needs no graph, pass 2 (entity → node) runs once
## [method CommandLink._on_graph_snapshot] has one to resolve against, or
## immediately if the entity snapshot arrives second. Order between graph and
## entity snapshots does NOT matter (both sides of that are idempotent); hello
## still has to be last — see below.
##
## [b]Send order: run_setup, graph snapshot, entity snapshot, THEN hello.[/b]
## [method CommandLink.send_hello] is what produces the "✓ in sync at link-up"
## verdict, comparing [WorldFingerprint] on both sides — and the CLIENT's
## graph is empty until the snapshot decodes. Sending hello first (rung 1's
## order, safe there because both peers already share a graph) would report a
## structural, false DIVERGED before a single real state difference could
## exist. Sending it last makes "at link-up" mean what it says: HOST's
## fingerprint (stamped at hello-SEND time, always after generation) is
## compared against the CLIENT's graph after both snapshots have decoded
## (ENet's reliable channel is ordered, so every send before hello arrives
## before it does). One accepted consequence, already called out in
## `command_link.gd`'s own #546 note: `KIND_SETUP` / `KIND_SNAPSHOT` /
## `KIND_ENTITIES` are all handled regardless of a prior hello, so a build
## mismatch is NOT caught until after every one of them has already been
## applied. That gap is pre-existing and explicitly flagged there as future
## work, not something this unit closes.

const DEFAULT_PORT := 9100
const DEFAULT_ADDRESS := "127.0.0.1"
const _DEFAULT_ROUNDS := 3

const _RED_COLOR := Color(0.4, 0.8, 1.0)
const _BLUE_COLOR := Color(0.95, 0.4, 0.4)
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")
const _CORE_CLASS_HUMAN := preload("res://entity/core/balanced_core.tres")
const _CORE_CLASS_AI := preload("res://entity/core/basic_enemy_core.tres")

## The "fixed RunConfig" the issue asks for — a real map, not a token one, but
## small enough that a headless join + a few scripted turns finishes fast.
## `first_level.tres` already authors one starting point + a shape mask; this
## harness only overrides the size and adds one random starter (below) so the
## fixed roster's 2 participants each get one.
@export var preset: GraphProcgenConfig = preload("res://procgen/presets/first_level/first_level.tres")
@export var node_count_override: int = 60
@export var fixed_seed: int = 90210533

@onready var _transport: NetworkTransport = $Transport
@onready var _link: CommandLink = $CommandLink
@onready var _banner: Label = %NetBanner
@onready var _log: RichTextLabel = %NetLog

var _role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE
var _address: String = DEFAULT_ADDRESS
var _port: int = DEFAULT_PORT
## Participant 0 (host's hero) and participant 1 (Blue, AI-driven, client's
## bound view) — resolved by both `_setup_level` branches, never by node path,
## since the CLIENT's copies are placeholders spawned fresh, not scene-authored.
var _red: Entity
var _blue: Entity
## `--rounds`: how many of Red's turns get a scripted allocate + end_turn, to
## prove "a scripted run of several turns keeps them identical" (the issue's
## own acceptance wording) — not an exhaustive verb sweep like rung 1's
## `--autopilot`; that already exists there and this rung's job is the join,
## not re-proving every verb crosses.
var _rounds: int = _DEFAULT_ROUNDS
var _rounds_run: int = 0
var _round_running: bool = false
var _link_refused: bool = false

## Fired once BOTH `KIND_SNAPSHOT` and `KIND_ENTITIES` have been OBSERVED
## arriving — after [CommandLink] has already decoded each (see [method
## _observe_snapshots] for why that ordering is guaranteed, not assumed).
signal _snapshots_arrived


func _ready() -> void:
	_parse_cmdline()
	# Set before `super()`, same reasoning as rung 1's own note: an
	# AIController's authority gate must never read the library default while
	# a role is still being adopted.
	if command_applier != null:
		command_applier.is_authority = _role != NetworkTransport.Role.CLIENT
	auto_start_turn = false
	# BEFORE `super()`, unlike rung 1. A CLIENT's `_setup_level` (below) has
	# nothing to read locally and must AWAIT wire data — so the socket has to
	# already be dialing and CommandLink's listeners already wired by the
	# time that await runs, or the await never resolves. `super()` calling
	# into `_setup_level()`'s own await suspends AT that inner await (GDScript
	# coroutine semantics — see rung 1's `_ready` for the same mechanism used
	# the other way round), so this ordering is what makes the wait legal.
	if _role != NetworkTransport.Role.OFFLINE:
		_start_link()
	super()
	if Engine.is_editor_hint():
		return


## Half one of `_setup_level`: HOST procgens for real; SOLO (no `--role`, an
## ordinary tab launch) gets the identical treatment minus the wire, so the
## scene is also a normal — if small — playable procgen sandbox.
func _setup_level_as_host_or_solo() -> void:
	GameSession.ensure_started(fixed_seed)
	var cfg: GraphProcgenConfig = preset.duplicate(true)
	# #349: topology is a top-level module .tres (ExtResource); duplicate(true)
	# does not cross that boundary, so re-duplicate before mutating (acceptance 4).
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = node_count_override
	# 1 authored `starting_points` entry (first_level.tres) + 1 random = the 2
	# this harness's fixed roster needs. See the class docstring's #551/#553
	# cross-reference in `docs/domain/multiplayer-harness.md` for why a
	# roster-sized level would normally compute this instead of hardcoding
	# it — this harness has no roster to grow past 2.
	cfg.n_random_starters = 1
	cfg.seed = GameSession.config.seed
	var result: Dictionary = await GraphProcgen.generate(cfg, graph)
	var starting_nodes: Array = result.get("starting_nodes", [])
	if starting_nodes.size() < 2:
		push_warning("MpProcgenSandbox: procgen returned %d starting node(s), need 2"
				% starting_nodes.size())
		return

	var roster := _fixed_roster()
	GameSession.roster = roster
	_red = spawn_entity("Red", _RED_COLOR, starting_nodes[0], _CORE_CLASS_HUMAN)
	_blue = spawn_entity("Blue", _BLUE_COLOR, starting_nodes[1], _CORE_CLASS_AI)
	GameRoot.apply_roster({0: _red, 1: _blue}, roster)
	player = _red
	if _role == NetworkTransport.Role.HOST:
		# No hot-seat (class docstring) — pinned to Red instead of the couch
		# `apply_roster` alone would otherwise leave in place.
		seat_policy = SeatPolicy.seat(_red.entity_id)
		# Deferred to `_greet_if_linked_and_ready`, AFTER the snapshots go
		# out — see that method's note on why starting the opening turn here
		# would double-apply its upkeep once a client joins.
		return
	_start_opening_turn()


## Half two: CLIENT never generates. Waits for the run's shape (#528), spawns
## placeholders in the SAME order so `entity_id` minting matches, then waits
## for BOTH the graph (#527) and the entity state (#560) to decode — the
## latter is what actually resolves `core_location` and rebuilds each board
## from what the host granted (see the class docstring).
func _setup_level_as_client() -> void:
	await GameSession.run_started
	var roster := GameSession.roster
	var participants := roster.all()
	participants.sort_custom(func(a: Participant, b: Participant) -> bool: return a.id < b.id)
	var entities_by_participant_id: Dictionary = {}
	for p in participants:
		var core_class: CoreClass = _CORE_CLASS_HUMAN if p.kind != Participant.Kind.AI else _CORE_CLASS_AI
		# No `core_location` — no graph exists yet to allocate onto. Minting
		# `entity_id` only needs entry into `entities_container` (#509).
		# EntitySnapshot decorates this same entity once it arrives (#560 D7)
		# — never mints a second one.
		var ent := spawn_entity(p.display_name, p.color, null, core_class)
		entities_by_participant_id[p.id] = ent
		if p.id == 0:
			_red = ent
		else:
			_blue = ent
	GameRoot.apply_roster(entities_by_participant_id, roster)

	await _snapshots_arrived

	player = _blue
	if _blue != null:
		seat_policy = SeatPolicy.seat(_blue.entity_id)
	_start_opening_turn()


func _fixed_roster() -> ParticipantRoster:
	var roster := ParticipantRoster.new()
	var red := Participant.new()
	red.id = 0
	red.display_name = "Red"
	red.color = _RED_COLOR
	red.camp = _PLAYER_FACTION
	red.kind = Participant.Kind.HUMAN
	roster.add(red)
	var blue := Participant.new()
	blue.id = 1
	blue.display_name = "Blue"
	blue.color = _BLUE_COLOR
	blue.camp = _NPC_FACTION
	blue.kind = Participant.Kind.AI
	roster.add(blue)
	return roster


func _setup_level() -> void:
	match _role:
		NetworkTransport.Role.CLIENT:
			await _setup_level_as_client()
		_:
			await _setup_level_as_host_or_solo()


## Replicates `GameRoot._ready`'s `auto_start_turn` block, targeting `_red`
## directly rather than `player` — turn order is shared simulation state and
## must start on the same entity regardless of which one this machine is
## bound to (rung 1's `mp_dev_sandbox.gd` makes the identical argument).
##
## Guarded on `current_entity == null`: `TurnManager.start_turn` ASSERTS that,
## and `_greet_if_linked_and_ready` — this method's HOST caller — can re-fire
## on every `link_changed` (a reconnect, or a second `is_linked()` check
## before the first send settles).
func _start_opening_turn() -> void:
	if _red == null or turn_manager == null or turn_manager.current_entity != null:
		return
	if _red.stat_board != null and _red.stat_board.initiative != null:
		_red.stat_board.initiative.restore_to_full()
	turn_manager.start_turn(_red)


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--rounds":
			_rounds = 999999
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
			"rounds":
				_rounds = maxi(1, int(pair[1]))


func _start_link() -> void:
	_link.logged.connect(_write_log)
	_link.link_refused.connect(_on_link_refused)
	_transport.link_changed.connect(_refresh_banner.unbind(1))
	if turn_manager != null:
		turn_manager.turn_started.connect(_on_turn_started)

	match _role:
		NetworkTransport.Role.HOST:
			_link.mode = CommandLink.Mode.BROADCAST
			var err := _transport.start_host(_port)
			if err != OK:
				_die_without_a_socket(err)
				return
			# The client connects later, once `_setup_level_as_host_or_solo`
			# has generated the world it will send.
			_transport.link_changed.connect(_greet_if_linked_and_ready)
		NetworkTransport.Role.CLIENT:
			_link.mode = CommandLink.Mode.MIRROR
			# A spectator, on purpose — same reasoning as rung 1: wave 0 has
			# no intent channel upward, so a local mutation here would
			# diverge from the host with nothing to correct it.
			input_ctl.set_input_frozen(true)
			# ALONGSIDE CommandLink's own listener, not instead of it — both
			# connect to the same signal, and children ready before their
			# parent, so `_link`'s handlers (which decode each snapshot) are
			# guaranteed to run before this one (connected here, in the
			# root's own `_ready`). See the class docstring's send-order note.
			_transport.message_received.connect(_observe_snapshots)
			_transport.start_client(_address, _port)
		_:
			_link.mode = CommandLink.Mode.OFF
			_refresh_banner()
			return

	_refresh_banner()


## HOST-side: send once a peer links AND this machine's own generation has
## finished. `link_changed` can in principle fire before `_setup_level`
## returns (a client dialling in fast); re-fired on every status change, so a
## peer that arrives early is simply caught on the next one — nothing here
## needs to be told to retry.
##
## [b]The opening turn starts HERE, after sending, not in
## `_setup_level_as_host_or_solo`.[/b] `TurnManager.start_turn` unconditionally
## fires `turn_started`, which is what runs turn-start upkeep (AP/DP/SP/mana/
## wound-heal/node-refill — see `systems/turn_manager.gd`'s own class doc).
## Rung 1 gets away with calling it identically on both peers because its
## graph is hand-authored and never crosses the wire — both sides start from
## the SAME untouched baseline. Here the graph and entity state DO cross: if
## the HOST's opening turn ran before the send, the snapshot would carry an
## ALREADY-healed world, and the CLIENT's own (also-necessary — see
## `_setup_level_as_client`) `start_turn` call would heal it a SECOND time on
## top, unaccounted for by anything that crossed the wire. Sending first keeps
## both peers' upkeep applications starting from the identical pre-turn
## baseline, exactly like rung 1's.
func _greet_if_linked_and_ready() -> void:
	if not _transport.is_linked():
		return
	if not GameSession.is_active() or GameSession.roster == null:
		return
	# Run settings (#528), then the graph (#527) and the entity state (#560,
	# order between these two doesn't matter), THEN hello — see the class
	# docstring's send-order note for why hello must be last here.
	_link.send_run_setup(GameSession.config, GameSession.roster)
	_link.send_graph_snapshot()
	_link.send_entity_snapshot()
	_link.send_hello()
	_start_opening_turn()


## CLIENT-side observer, alongside (not instead of) `CommandLink`'s own
## handling of the same messages. Exists only to unblock [signal
## _snapshots_arrived] once BOTH have been seen — the decode itself, and the
## `core_location` resolution it drives, are entirely `CommandLink`'s (#560).
var _seen_graph_snapshot := false
var _seen_entity_snapshot := false


func _observe_snapshots(payload: Dictionary) -> void:
	match String(payload.get(CommandLink.KEY_KIND, "")):
		CommandLink.KIND_SNAPSHOT:
			_seen_graph_snapshot = true
		CommandLink.KIND_ENTITIES:
			_seen_entity_snapshot = true
		_:
			return
	if _seen_graph_snapshot and _seen_entity_snapshot:
		_snapshots_arrived.emit()


func _on_link_refused(_reason: String) -> void:
	_link_refused = true
	_refresh_banner()


## Same rationale as rung 1's identically-named method (#546's incident) —
## a host with no socket is not a host, and finding an orphan on the port is
## how a "clean" measurement gets attributed to a months-old process.
func _die_without_a_socket(err: Error) -> void:
	for line in bind_failure_lines(_port, err):
		_write_log(line)
	get_tree().quit(1)


static func bind_failure_lines(port: int, err: Error) -> PackedStringArray:
	return PackedStringArray([
		"port %d is already in use (%s) — another harness may still be running:"
				% [port, error_string(err)],
		"         ps aux | grep mp_procgen_sandbox",
		"a host with no socket is not a host — exiting. (--role=solo runs offline.)",
	])


## Every turn Red's TurnManager starts, run one scripted round if the budget
## allows — only the authority ever originates (rung 1's own gate, reused
## verbatim: a mirrored `end_turn` ticks the CLIENT's own TurnManager too).
## Blue's turn in between is handled entirely by its [AIController]
## (`_ensure_controllers`, generic `GameRoot` behaviour) — nothing here drives
## Blue directly.
func _on_turn_started(entity: Entity) -> void:
	if entity != _red or _rounds_run >= _rounds:
		return
	if command_applier == null or not command_applier.is_authority:
		return
	_run_round()


func _run_round() -> void:
	if _round_running:
		return
	_round_running = true
	_rounds_run += 1
	await _sweep_allocate()
	await _submit_and_wait(EndTurnCommand.new(_red.entity_id))
	_round_running = false
	_write_log("round %d/%d complete" % [_rounds_run, _rounds])


func _sweep_allocate() -> void:
	var target := _first_frontier_node()
	if target == null:
		_write_log("round: allocate SKIPPED — no frontier node")
		return
	var ok := await _submit_and_wait(
			AllocateCommand.new(_red.entity_id, graph.get_stable_id(target)))
	_write_log("round: allocate %s" % ("OK" if ok else "SKIPPED — command refused"))


## First unowned node touching Red's territory — the dumbest legal target,
## same choice rung 1's `_first_frontier_node` makes for the same reason.
func _first_frontier_node() -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == _red:
				return node
	return null


## Same shape as rung 1's `_submit_and_wait` (this script has no controller to
## share it with either).
func _submit_and_wait(command: Command) -> bool:
	var verdict: Array[bool] = [false, false] # [applied, success]
	var watch := func(applied: Command, ok: bool) -> void:
		if applied == command:
			verdict[0] = true
			verdict[1] = ok
	command_applier.command_applied.connect(watch)
	command_applier.submit(command)
	while not verdict[0] and command_applier.is_applying:
		await command_applier.command_applied
	command_applier.command_applied.disconnect(watch)
	return verdict[1]


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
	if _link_refused:
		linked = " · REFUSED (build mismatch)"
	match _role:
		NetworkTransport.Role.HOST:
			_banner.text = "HOST — procgen'd, seated on Red%s" % linked
			_banner.modulate = Color(1.0, 0.55, 0.5)
		NetworkTransport.Role.CLIENT:
			_banner.text = "CLIENT — seated on Blue, spectating%s" % linked
			_banner.modulate = Color(0.55, 0.75, 1.0)
		_:
			_banner.text = "SOLO — no link"
			_banner.modulate = Color(0.7, 0.75, 0.8)
