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
## [b]Blue stays the AI opponent (rung 1, #532).[/b] The old justification for
## making it human — "the AI still calls [AllocationSystem] / [BattleSystem]
## directly" — is stale: #512 landed, and [AIController] emits commands through
## [CommandApplier] like everything else. Restoring the AI is what makes this a
## player-against-an-opponent harness rather than two humans hot-seated.
##
## Restoring it exposes a real trap: [method GameRoot._ensure_controllers]
## attaches an [AIController] to Blue on BOTH peers, and that controller
## resolves [member GameRoot.command_applier] — its OWN peer's applier — so a
## MIRROR peer's copy would decide and submit independently of the host's AI
## the moment its local [TurnManager] hands Blue the turn (which a mirrored
## [EndTurnCommand] does). Closed by gating [method AIController.take_turn] on
## [member CommandApplier.is_authority] (`network/command_link.gd`'s `mode`
## setter is the only writer), extending the same "a non-authority peer does
## not originate mutations" invariant [SkillDustAddon]'s claim flow already
## relies on. The host hot-seats between Red and Blue; the client watches,
## bound to Blue.

const DEFAULT_PORT := 9099
const DEFAULT_ADDRESS := "127.0.0.1"

## How long the wire must stay quiet before the probe's breakdown is printed.
## Comfortably longer than the slowest single verb's tail (a multi-hop core
## walk beats at 0.18 s/hop; an attack's animation is seconds) and shorter than
## a human's next click, so a terminal-driven `--autopilot` run prints exactly
## once, at the end of the sweep, rather than after every command.
const PROBE_REPORT_QUIET_SECONDS := 4.0

## And how often it prints ANYWAY while the wire is busy. Quiet alone is not
## enough: under `--turns` the autopilot sweeps back to back and the wire never
## goes quiet for four seconds, so a run measured for ten minutes printed its
## last table two minutes in and the numbers that mattered were never emitted.
## A repeating tick means the readout is always at most this stale, and killing
## the process costs at most one period of results.
const PROBE_REPORT_PERIOD_SECONDS := 60.0

## `--turns` with no value: keep sweeping until the process is killed. There is
## no natural end — the sandbox has no victory condition wired — so an unbounded
## run is a stopwatch decision, not a scene one.
const AUTOPILOT_TURNS_UNBOUNDED := -1

@onready var _transport: NetworkTransport = $Transport
@onready var _link: CommandLink = $CommandLink
@onready var _probe: DeterminismProbe = $DeterminismProbe
@onready var _banner: Label = %NetBanner
@onready var _log: RichTextLabel = %NetLog

var _role: NetworkTransport.Role = NetworkTransport.Role.OFFLINE
var _address: String = DEFAULT_ADDRESS
var _port: int = DEFAULT_PORT
var _blue: Entity
## Red — the entity every autopilot step drives. Resolved by node path rather
## than reused off [member player], because [member player] repoints to
## [member _blue] on the CLIENT (see [method _setup_level]) and the boost
## below must land on the SAME entity, identically, on both peers — see
## [method _boost_autopilot_budget].
var _red: Entity
## `--autopilot` (host only): run the full verb sweep once a client links, so
## the pair is verifiable from a terminal. See [method _run_autopilot].
var _autopilot: bool = false
## `--probe` (#529, client only — a host receives nothing to re-derive): arm
## [DeterminismProbe] and print its per-command-type breakdown once the wire
## goes quiet. Off unless asked for, per the issue's own decision.
var _probe_enabled: bool = false
## One-shot, restarted on every compared command; see [constant
## PROBE_REPORT_QUIET_SECONDS].
var _probe_report_timer: Timer
## How many of Red's turns `--autopilot` sweeps. One by default — the original
## #532 behaviour, a single pass to prove every verb crosses. `--turns=N` (or
## bare `--turns`) is what #529 needs; see [method _on_turn_started].
var _autopilot_turns: int = 1
var _autopilot_turns_run: int = 0
## True for the whole of one sweep. [method _run_autopilot] is a long coroutine
## and [EndTurnCommand]'s application spans Blue's ENTIRE AI turn (see
## [CommandApplier]'s class note), so `turn_started(_red)` can fire while a
## sweep is still parked in [method _submit_and_wait]. Two concurrent sweeps
## both drive [method BattleSystem.request_attack_mode] and stomp each other's
## `attack_plan`. Never observed in a 40-turn run — and one flag is cheaper
## than finding out it can.
var _autopilot_running: bool = false


func _ready() -> void:
	_parse_cmdline()
	# Authority is set HERE, before `super()`, not inside `_start_link()` where
	# it looks like it belongs. `GameRoot._ready` is a coroutine that calls
	# `turn_manager.start_turn(player)` (`auto_start_turn`) partway through,
	# and returns from `super()` below at its first internal await — well
	# before the two `await process_frame`s that gate `_start_link()`. A
	# CLIENT's Blue already has a real [AIController] (#532: Blue stays AI),
	# so if the opening turn lands on Blue before `_start_link()` runs,
	# that controller's authority gate reads the library default
	# (`CommandApplier.is_authority == true`) and Blue's AI decides and
	# submits LOCALLY on the client — silently diverging the world before a
	# single command has crossed the wire. Setting it early closes that
	# window; `_start_link()` still sets `_link.mode` itself (idempotent) so
	# it stays the one documented writer once the link is actually up.
	if command_applier != null:
		command_applier.is_authority = _role != NetworkTransport.Role.CLIENT
	# GameRoot's own opening `start_turn` (`auto_start_turn`) targets [member
	# player] — but `player` is a PER-MACHINE view pointer, re-pointed to Blue
	# on the CLIENT for the HUD/camera (see `_setup_level`). Turn order is
	# SHARED SIMULATION STATE, not a view concern: `SeatPolicy`'s whole
	# contract is "never feed anything a peer must reproduce"
	# (`.claude/rules/seat-policy.md`), and the harness's own class docstring
	# promises the SAME graph with no seed on the wire — the opening actor is
	# part of that same promise. Left wired to `player`, the CLIENT would open
	# its OWN local turn on Blue while the host opens on Red, so Red's
	# turn-start upkeep (AP/DP/mana refilled to cap) never fires on the
	# client's own simulation — invisible until a verb spends deep enough into
	# a budget for the missed refill to matter, which #532's sweep is the
	# first thing to do. Disabled here; kicked off by hand on `_red` below,
	# identically regardless of role.
	auto_start_turn = false
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
	_start_opening_turn()
	_start_link()


## Replicates `GameRoot._ready`'s `auto_start_turn` block, targeting `_red`
## instead of `player` — see the note in `_ready` for why the two must not be
## the same variable here.
func _start_opening_turn() -> void:
	if _red == null or turn_manager == null:
		return
	if _red.stat_board != null and _red.stat_board.initiative != null:
		_red.stat_board.initiative.restore_to_full()
	turn_manager.start_turn(_red)


## Blue keeps whatever the base scene authored (AI, per [method
## GameRoot._ensure_controllers] — see the class docstring). The CLIENT binds
## Blue as its local hero anyway: a SEAT watches whoever it's pinned to, human
## or not, and #532 rung 1 is a spectator client regardless.
func _setup_level() -> void:
	await super()
	_blue = get_node_or_null(^"Graph/Entities/Enemy") as Entity
	_red = get_node_or_null(^"Graph/Entities/Player") as Entity
	if _blue == null:
		return
	if _role == NetworkTransport.Role.CLIENT:
		player = _blue
		# The client is a SEAT, not a couch: its view is pinned to Blue. Said
		# once, as policy — previously this was two separate un-decisions
		# (re-point `player`, then disconnect GameRoot's handover), and the
		# second had to be re-made after `_ready` had already wired it. Left a
		# COUCH on the host, which hot-seats between Red and Blue as the base
		# scene does.
		seat_policy = SeatPolicy.seat(_blue.entity_id)
	_boost_autopilot_budget()


## Rung 1's verb sweep drives every [CommandApplier] verb from ONE turn, which
## the default per-turn budget (3 SP / 2 AP / 3 DP) cannot cover — allocate +
## mass_allocate + stake alone already want more SP than a level-1 board grants,
## and three attack modes plus a temp-upgrade toggle want more AP. Boosted on
## [member _red] IDENTICALLY on every peer — this runs in [method _setup_level],
## before any command has crossed the wire, unconditionally on role — because
## [method CommandApplier._apply_mass_allocate] RE-derives affordability from
## the RECEIVING peer's own board (#458: a stale sender must not dictate spend).
## Boosting only the host's local copy would make that recompute disagree with
## what the host actually applied, the instant a budget-gated verb crossed.
func _boost_autopilot_budget() -> void:
	if _red == null or _red.stat_board == null:
		return
	var board := _red.stat_board
	if board.skill_points != null:
		board.skill_points.set_base_ratcheted(30.0)
	if board.action_points != null:
		board.action_points.set_base_ratcheted(12.0)
	if board.deallocation_points != null:
		board.deallocation_points.set_base_ratcheted(10.0)
	if board.mana != null:
		board.mana.set_base_ratcheted(200.0)


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autopilot":
			_autopilot = true
			continue
		if arg == "--turns":
			_autopilot_turns = AUTOPILOT_TURNS_UNBOUNDED
			continue
		if arg == "--probe":
			_probe_enabled = true
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
			"turns":
				_autopilot_turns = maxi(1, int(pair[1]))


func _start_link() -> void:
	_link.logged.connect(_write_log)
	_transport.link_changed.connect(_refresh_banner.unbind(1))
	_arm_probe()
	if turn_manager != null:
		turn_manager.turn_started.connect(_on_turn_started)

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

	_refresh_banner()


## #529. Armed only on the CLIENT and only with `--probe`: the probe measures
## what a MIRRORING peer could have derived, and a host receives no command to
## re-derive, so arming it there would report an empty table and read as a
## clean result.
##
## The readout fires on QUIET rather than on an end-of-sweep hook, because such
## a hook would leave a human clicking in the window with no way to see the
## number at all — quiet covers both, the sweep's last verb starting the timer
## exactly as a human's last click does. It ALSO fires on a plain heartbeat,
## because quiet alone silently failed: under `--turns` the sweeps run back to
## back and the wire never goes quiet, so a ten-minute measured run printed its
## last table two minutes in.
func _arm_probe() -> void:
	if _probe == null or not _probe_enabled:
		return
	if _role != NetworkTransport.Role.CLIENT:
		_write_log("--probe ignored: it measures the MIRRORING peer, and this is not one")
		return
	_probe.enabled = true
	_probe.logged.connect(_write_log)
	_probe_report_timer = Timer.new()
	_probe_report_timer.one_shot = true
	_probe_report_timer.wait_time = PROBE_REPORT_QUIET_SECONDS
	_probe_report_timer.timeout.connect(_print_probe_report)
	add_child(_probe_report_timer)
	var heartbeat := Timer.new()
	heartbeat.wait_time = PROBE_REPORT_PERIOD_SECONDS
	heartbeat.timeout.connect(_print_probe_report)
	add_child(heartbeat)
	heartbeat.start()
	# `sync_checked` fires once per COMPARED command; the skipped ones ride in
	# on the same burst and are already tallied, so this is enough to keep the
	# timer alive for as long as the wire is busy.
	_link.sync_checked.connect(func(_a: bool, _l: int, _r: int) -> void:
			_probe_report_timer.start())
	_write_log("determinism probe ARMED (#529) — breakdown every %.0fs, and %.0fs after the wire goes quiet"
			% [PROBE_REPORT_PERIOD_SECONDS, PROBE_REPORT_QUIET_SECONDS])


func _print_probe_report() -> void:
	for line in _probe.report().split("\n"):
		_write_log(line)


func _greet_if_linked(_status: String) -> void:
	if not _transport.is_linked():
		return
	_link.send_hello()
	# Through the same gate as a turn-driven sweep: `link_changed` fires again
	# on a reconnect, and this entry point used to bypass the `--turns` budget
	# entirely.
	if _autopilot:
		_start_sweep_if_due()


## Sweep again every time the turn comes back around to Red (#529). One sweep
## produces ~17 commands, which is a demo, not a measurement — the determinism
## probe wants a few hundred before its "0 diverged" means anything.
##
## Hooked on [signal TurnManager.turn_started] rather than chained off the end
## of [method _run_autopilot], because the turn does NOT come straight back:
## `end_turn` ticks initiative, Blue's [AIController] takes a real turn of its
## own, and only then is it Red's again. Waiting on the signal is waiting on
## the actual loop; a timer would be guessing at its length.
##
## The default stays ONE sweep, so #532's single-pass proof is unchanged for
## anyone not asking for more.
func _on_turn_started(entity: Entity) -> void:
	if not _autopilot or entity != _red:
		return
	_start_sweep_if_due()


## The one gate every sweep goes through: the `--turns` budget, the
## authority check, and the in-flight guard.
##
## `turn_started` fires on BOTH peers' own TurnManagers — a mirrored `end_turn`
## ticks the client's initiative too. Only the authority may originate, or the
## client would submit a sweep of its own and diverge the very thing being
## measured.
##
## No budget re-boost here: [method _boost_autopilot_budget] ratchets the
## pools' BASE once at setup, and turn-start upkeep refills current to that cap
## every turn. Re-calling it per turn would be a mutation on a per-peer signal,
## which is exactly the shape a determinism probe exists to catch.
func _start_sweep_if_due() -> void:
	if _autopilot_running:
		return
	if _autopilot_turns != AUTOPILOT_TURNS_UNBOUNDED \
			and _autopilot_turns_run >= _autopilot_turns:
		return
	if command_applier != null and not command_applier.is_authority:
		return
	_run_autopilot()


## Headless self-check (`--autopilot` on the host, after `--`): drive every verb
## [CommandApplier] handles from Red's opening turn, so a terminal-driven pair
## proves the whole path per verb — command confirmed here, decoded and applied
## there, fingerprints compared — without a human clicking. Never fires unless
## asked for. `end_turn` runs LAST, deliberately: everything before it needs
## Red still holding the turn (see `_boost_autopilot_budget`'s note on
## why one turn is enough SP/AP/DP for all of it).
func _run_autopilot() -> void:
	_autopilot_turns_run += 1
	_autopilot_running = true
	await get_tree().create_timer(1.0).timeout
	await _sweep_allocate()
	await _sweep_mass_allocate()
	await _sweep_stake_and_extract()
	await _sweep_deallocate()
	await _sweep_deallocate_set()
	await _sweep_move_core()
	await _sweep_magic()
	await _sweep_ranged()
	await _sweep_melee()
	await _sweep_loot()
	await _sweep_end_turn()
	# Cleared here and not in a `defer`-alike: every step above either applies
	# or logs SKIPPED, so the sweep always reaches this line. It must clear
	# BEFORE Red's next `turn_started`, which it does —
	# [method CommandApplier._apply] calls [method TurnManager.end_turn] and
	# returns without awaiting it, so `command_applied` fires long before Blue's
	# AI turn has played out.
	_autopilot_running = false
	_write_log("autopilot: sweep complete (turn %d)" % _autopilot_turns_run)


## Submit [param command] and suspend until the applier has actually applied
## it, returning its verdict — same shape as [method AIController._submit_and_wait]
## (this script has no controller to share it with).
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


func _sweep_allocate() -> void:
	var target := _first_frontier_node()
	if target == null:
		_write_log("autopilot: allocate SKIPPED — no frontier node")
		return
	_write_log("autopilot: allocating %s" % target.name)
	var ok := await _submit_and_wait(
			AllocateCommand.new(_red.entity_id, graph.get_stable_id(target)))
	_write_log("autopilot: allocate %s" % ("OK" if ok else "SKIPPED — command refused"))


## A frontier node reached only THROUGH another unowned node, so the resulting
## path exercises more than one hop — the thing plain allocate cannot prove.
func _mass_allocate_target() -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		var adjacent_to_owned := false
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == _red:
				adjacent_to_owned = true
				break
		if adjacent_to_owned:
			continue
		var path := allocation_system.allocation_path(_red, node)
		if path.size() >= 3: # anchor + at least 2 hops
			return node
	return null


func _sweep_mass_allocate() -> void:
	var target := _mass_allocate_target()
	if target == null:
		_write_log("autopilot: mass_allocate SKIPPED — no 2+-hop frontier target")
		return
	var path := allocation_system.allocation_path(_red, target)
	var affordable := allocation_system.affordable_allocation_count(_red, path)
	if affordable < 1:
		_write_log("autopilot: mass_allocate SKIPPED — unaffordable")
		return
	var ids: Array[int] = []
	for n in path:
		ids.append(graph.get_stable_id(n))
	_write_log("autopilot: mass-allocating toward %s (%d hops)" % [target.name, affordable])
	var ok := await _submit_and_wait(MassAllocateCommand.new(_red.entity_id, ids))
	_write_log("autopilot: mass_allocate %s" % ("OK" if ok else "SKIPPED — command refused"))


## Self-contained on Red's own core — no topology dependency, so it never
## competes with the other steps for a scarce frontier node.
func _sweep_stake_and_extract() -> void:
	var core := _red.core_location
	if core == null:
		_write_log("autopilot: stake SKIPPED — no core_location")
		_write_log("autopilot: extract SKIPPED — no core_location")
		return
	var core_id := graph.get_stable_id(core)
	var staked := await _submit_and_wait(StakeCommand.new(_red.entity_id, core_id))
	_write_log("autopilot: stake %s" % ("OK" if staked else "SKIPPED — command refused"))
	if not staked:
		_write_log("autopilot: extract SKIPPED — nothing was staked")
		return
	var extracted := await _submit_and_wait(ExtractCommand.new(_red.entity_id, core_id))
	_write_log("autopilot: extract %s" % ("OK" if extracted else "SKIPPED — command refused"))


func _owned_non_core_nodes() -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for node in graph.get_skill_nodes():
		if node.owned_by == _red and not node.is_core():
			out.append(node)
	return out


func _sweep_deallocate() -> void:
	var picked: SkillNode = null
	for node in _owned_non_core_nodes():
		if allocation_system.can_deallocate(node, _red):
			picked = node
			break
	if picked == null:
		_write_log("autopilot: deallocate SKIPPED — no safely-deallocatable node")
		return
	_write_log("autopilot: deallocating %s" % picked.name)
	var ok := await _submit_and_wait(
			DeallocateCommand.new(_red.entity_id, graph.get_stable_id(picked)))
	_write_log("autopilot: deallocate %s" % ("OK" if ok else "SKIPPED — command refused"))


## Any pair of owned non-core nodes whose JOINT removal still passes
## `can_deallocate_set` — the set gate, not two individual `can_deallocate`
## checks, since a pair can island the graph together even when each alone
## would not.
func _sweep_deallocate_set() -> void:
	var candidates := _owned_non_core_nodes()
	for a_i in candidates.size():
		for b_i in range(a_i + 1, candidates.size()):
			var pair: Array[SkillNode] = [candidates[a_i], candidates[b_i]]
			if not allocation_system.can_deallocate_set(pair, _red):
				continue
			var ids: Array[int] = [graph.get_stable_id(pair[0]), graph.get_stable_id(pair[1])]
			_write_log("autopilot: deallocating set {%s, %s}" % [pair[0].name, pair[1].name])
			var ok := await _submit_and_wait(DeallocateSetCommand.new(_red.entity_id, ids))
			_write_log("autopilot: deallocate_set %s" % ("OK" if ok else "SKIPPED — command refused"))
			return
	_write_log("autopilot: deallocate_set SKIPPED — no safely-deallocatable pair")


func _sweep_move_core() -> void:
	var core := _red.core_location
	if core == null:
		_write_log("autopilot: move_core SKIPPED — no core_location")
		return
	var target: SkillNode = null
	for neighbour in graph.get_neighbours(core):
		if allocation_system.can_move_core(_red, neighbour):
			target = neighbour
			break
	if target == null:
		_write_log("autopilot: move_core SKIPPED — no legal adjacent landing")
		return
	_write_log("autopilot: moving core to %s" % target.name)
	var ok := await _submit_and_wait(
			MoveCoreCommand.new(_red.entity_id, [graph.get_stable_id(target)] as Array[int]))
	_write_log("autopilot: move_core %s" % ("OK" if ok else "SKIPPED — command refused"))


## Magic (#511): needs no per-node `range` stat and no physics arc to
## intersect anything, only a hostile node within the spell's hop reach —
## which a hand-authored two-camp sandbox has by construction.
func _sweep_magic() -> void:
	var source := _first_owned_node_near_hostile()
	if source == null:
		_write_log("autopilot: magic SKIPPED — no owned node in reach of a hostile one")
		return
	battle_system.selected_spell = SpellCatalog.SPARK
	battle_system.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	var plan := battle_system.attack_plan as MagicAttackPlan
	plan._on_node_left_clicked(source)
	for candidate in graph.get_skill_nodes():
		if candidate.ownership_bit(_red) == SkillNode.Ownership.HOSTILE:
			plan._on_node_left_clicked(candidate)
			if plan.is_valid():
				break
	if not plan.is_valid():
		_write_log("autopilot: magic SKIPPED — no castable target (%s)" % [plan.validate()])
		battle_system.cancel_attack()
		return
	_write_log("autopilot: casting %s from %s at %s"
			% [battle_system.selected_spell.name, plan.source.name, plan.target.name])
	await battle_system.launch_attack()
	_write_log("autopilot: magic OK")


## Ranged: `range`'s default (400) reaches almost anything at sandbox scale
## (`.claude/rules/ranged-attack-fixtures.md`), so any owned leaf against any
## visible hostile is enough — no scene authoring needed.
func _sweep_ranged() -> void:
	battle_system.request_attack_mode(BattleSystem.AttackMode.RANGED)
	var plan := battle_system.attack_plan as RangedAttackPlan
	var target: SkillNode = null
	for candidate in graph.get_skill_nodes():
		if candidate.ownership_bit(_red) != SkillNode.Ownership.HOSTILE:
			continue
		plan._on_node_left_clicked(candidate)
		if plan.is_valid():
			target = candidate
			break
	if target == null:
		_write_log("autopilot: ranged SKIPPED — no reachable hostile target")
		battle_system.cancel_attack()
		return
	_write_log("autopilot: firing a ranged volley at %s" % target.name)
	await battle_system.launch_attack()
	_write_log("autopilot: ranged OK")


## Melee (owner call 2026-08-22: goes in now, #530 is not a blocker). Reuses
## [AiBladeRollout] — the SAME reach-bound-reject / steerable-proposal rollout
## [AIController] scores its own melee candidates with — rather than hand-
## building a blade, so this never needs arc geometry authored into the scene:
## if the AI can find a legal swing on this graph, so can autopilot.
func _sweep_melee() -> void:
	var hostiles: Array[SkillNode] = []
	for node in graph.get_skill_nodes():
		if node.ownership_bit(_red) == SkillNode.Ownership.HOSTILE:
			hostiles.append(node)
	if hostiles.is_empty():
		_write_log("autopilot: melee SKIPPED — no visible hostile")
		return
	var candidates := AiBladeRollout.gather_melee_candidates(_red, hostiles, 0)
	var best := AiCombatScorer.pick_best(candidates)
	if best == null:
		_write_log("autopilot: melee SKIPPED — no reachable blade")
		return
	battle_system.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := battle_system.attack_plan as MeleeAttackPlan
	plan.source = best.source_node
	plan.blade_nodes = best.blade_nodes
	if not plan.is_valid():
		_write_log("autopilot: melee SKIPPED — the rolled blade did not validate")
		battle_system.cancel_attack()
		return
	await _sweep_toggle_temp_upgrade(plan)
	_write_log("autopilot: swinging a blade from %s (%d members)"
			% [plan.source.name, plan.blade_nodes.size()])
	await battle_system.launch_attack()
	_write_log("autopilot: melee OK")


## A real melee sub-step, not a separate combat action: `toggle_temp_upgrade`
## only makes sense against an ARMED melee plan (`BattleSystem
## .toggle_temp_upgrade_on` reads `battle_system.attack_plan` directly), so it
## fires here, before the swing it augments.
func _sweep_toggle_temp_upgrade(plan: MeleeAttackPlan) -> void:
	var upgrade := MeleeAttackPlan.upgrade_by_id(&"clamp")
	if upgrade.is_empty() or plan.source == null:
		_write_log("autopilot: toggle_temp_upgrade SKIPPED — no catalog entry or pivot")
		return
	if not plan.has_temp_upgrade_budget(upgrade):
		_write_log("autopilot: toggle_temp_upgrade SKIPPED — no blade budget left")
		return
	var ok := await _submit_and_wait(ToggleTempUpgradeCommand.new(
			_red.entity_id, graph.get_stable_id(plan.source), &"clamp"))
	_write_log("autopilot: toggle_temp_upgrade %s"
			% ("OK — clamp on %s" % plan.source.name if ok else "SKIPPED — command refused"))


## Loot only has something to claim once an entity actually dies (#69: the
## relic lands on the VICTIM'S core, and nothing in this hand-authored graph
## pre-seeds one — see the class docstring). Found by scanning for the addon
## rather than tracked off `_blue` directly: an NPC's death frees the Entity
## node itself (`.claude/rules/entity-death.md`), so a reference held across
## the earlier attack steps' awaits is not safe to read back.
func _sweep_loot() -> void:
	var relic := _find_relic_node()
	if relic == null:
		_write_log("autopilot: loot SKIPPED — no entity died during the sweep " \
				+ "(this turn's attacks did not deplete anyone's health pool)")
		return
	_write_log("autopilot: claiming the relic on %s" % relic.name)
	var ok := await _submit_and_wait(
			AllocateCommand.new(_red.entity_id, graph.get_stable_id(relic)))
	_write_log("autopilot: loot %s"
			% ("OK — allocate opened the claim round" if ok else "SKIPPED — allocate refused"))


func _find_relic_node() -> SkillNode:
	for node in graph.get_skill_nodes():
		for addon in node.get_addons():
			if addon is SkillDustAddon:
				return node
	return null


func _sweep_end_turn() -> void:
	_write_log("autopilot: ending turn")
	var ok := await _submit_and_wait(EndTurnCommand.new(_red.entity_id))
	_write_log("autopilot: end_turn %s" % ("OK" if ok else "SKIPPED — command refused"))


## An owned node with at least one hostile node two hops out — enough for
## Spark's reach without hard-coding the sandbox's topology.
func _first_owned_node_near_hostile() -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != _red:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.ownership_bit(_red) == SkillNode.Ownership.HOSTILE:
				return node
			for second in graph.get_neighbours(neighbour):
				if second.ownership_bit(_red) == SkillNode.Ownership.HOSTILE:
					return node
	return null


## First unowned node touching Red's territory. Deliberately not routed
## through [AiRecon] — this wants the dumbest possible legal target, not a
## good one.
func _first_frontier_node() -> SkillNode:
	for node in graph.get_skill_nodes():
		if node.owned_by != null:
			continue
		for neighbour in graph.get_neighbours(node):
			if neighbour.owned_by == _red:
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
