@tool
extends PanelContainer

## The multiplayer harness launcher — spawns two OS processes of the same scene,
## one as host, one as client, and keeps their PIDs so you can kill both.
##
## [b]Two processes, not two viewports.[/b] [Events] is a process-global bus and
## every system connects to it unconditionally, so two worlds in one process
## would cross-wire death, loot and victory. Separate processes give separate
## autoloads for free — which is also why this cannot be a [SandboxPlayedTab]:
## that tab's Run button calls `EditorInterface.play_custom_scene`, which gives
## you exactly one instance.
##
## What the launched pair proves, and what it does not, is spelled out in the
## blurb this panel draws — keep the two in step. See
## `docs/domain/multiplayer-harness.md`.

## Emitted for [SandboxLiveTab]'s Reload button (#144) — a stale PID list after
## an editor reload is worth a hard reset.
signal reload_requested

const DEFAULT_SCENE := "res://scenes/dev/mp_dev_sandbox.tscn"

## Window geometry per role, so the two do not land on top of each other.
const WINDOW_SIZE := Vector2i(960, 600)
const HOST_POSITION := Vector2i(40, 80)
const CLIENT_POSITION := Vector2i(1020, 80)

@onready var _scene_field: LineEdit = %SceneField
@onready var _address_field: LineEdit = %AddressField
@onready var _port_field: SpinBox = %PortField
@onready var _autopilot_toggle: CheckBox = %AutopilotToggle
@onready var _probe_toggle: CheckBox = %ProbeToggle
@onready var _log: RichTextLabel = %Log

## Live child processes, newest last. A PID here may already be dead — the OS is
## the authority and [method OS.kill] on a dead PID is a harmless error, so this
## list is a convenience, never a source of truth.
var _pids: Array[int] = []

## `pid -> was it launched with --autopilot`. Only exists so
## [method _warn_if_the_pair_would_be_asymmetric] can catch the one flag mismatch
## that produces a lying DIVERGED line.
var _sweeping_by_pid: Dictionary = {}


func _ready() -> void:
	if _scene_field.text.is_empty():
		_scene_field.text = DEFAULT_SCENE
	%LaunchBoth.pressed.connect(_on_launch_both)
	%LaunchHost.pressed.connect(_on_launch_host)
	%LaunchClient.pressed.connect(_on_launch_client)
	%KillAll.pressed.connect(_on_kill_all)
	_write("Ready. Launch both, then allocate a node in the HOST window.")
	_write("Tick both toggles for #529's measured run — the breakdown prints "
			+ "in the CLIENT window, not here.")


## Sandbox-host contract: the tab forwards the inspected resource here. Nothing
## to load — the launcher has no per-resource state.
func load_object(_obj: Object) -> void:
	pass


func _on_launch_both() -> void:
	if _launch(NetworkTransport.Role.HOST) == -1:
		return
	_launch(NetworkTransport.Role.CLIENT)


func _on_launch_host() -> void:
	_launch(NetworkTransport.Role.HOST)


func _on_launch_client() -> void:
	_launch(NetworkTransport.Role.CLIENT)


func _on_kill_all() -> void:
	if _pids.is_empty():
		_write("Nothing to kill.")
		return
	for pid in _pids:
		OS.kill(pid)
	_write("Killed %d process(es)." % _pids.size())
	_pids.clear()
	_sweeping_by_pid.clear()


## The command line one instance is spawned with.
##
## Split out from [method _launch] so the peer-symmetry rule below is assertable
## without spawning an OS process — see
## `test/unit/network/test_harness_budget_boost.gd`.
##
## The role rides AFTER `--`, which is what puts it in
## [method OS.get_cmdline_user_args] rather than in Godot's own argument
## namespace — pass it before the separator and the engine tries to interpret it.
func build_args(role: NetworkTransport.Role, scene: String) -> PackedStringArray:
	var is_host := role == NetworkTransport.Role.HOST
	var position := HOST_POSITION if is_host else CLIENT_POSITION
	var args: PackedStringArray = [
		"--path", ProjectSettings.globalize_path("res://"),
		scene,
		"--resolution", "%dx%d" % [WINDOW_SIZE.x, WINDOW_SIZE.y],
		"--position", "%d,%d" % [position.x, position.y],
		"--",
		"--role=%s" % ("host" if is_host else "client"),
		"--port=%d" % int(_port_field.value),
	]
	# `--probe` (#529) goes to exactly the role that can act on it — the peer that
	# RECEIVES commands. Sent to a host it is a no-op that logs a refusal, which
	# is noise dressed as a result.
	#
	# `--autopilot` is the deliberate exception: it goes to BOTH. Only the
	# authority ever sweeps (`_start_sweep_if_due` gates on
	# `CommandApplier.is_authority`), but the flag also gates the budget boost
	# `_boost_autopilot_budget` applies to Red — and that boost must land
	# identically on every peer, because `CommandApplier._apply_mass_allocate`
	# re-derives affordability from the RECEIVING peer's own board. Host-only
	# here would desync the first budget-gated verb that crossed.
	if _autopilot_toggle.button_pressed:
		args.append("--autopilot")
	if not is_host:
		args.append("--address=%s" % _address_field.text.strip_edges())
		if _probe_toggle.button_pressed:
			args.append("--probe")
	return args


## Spawns one instance. Returns its PID, or -1 on failure.
func _launch(role: NetworkTransport.Role) -> int:
	var scene := _scene_field.text.strip_edges()
	if not ResourceLoader.exists(scene):
		_write("[color=#e06c60]No such scene: %s[/color]" % scene)
		return -1
	var is_host := role == NetworkTransport.Role.HOST
	var sweeping := _autopilot_toggle.button_pressed
	_warn_if_the_pair_would_be_asymmetric(sweeping)
	var pid := OS.create_instance(build_args(role, scene))
	if pid <= 0:
		_write("[color=#e06c60]Failed to spawn %s.[/color]" \
				% ("host" if is_host else "client"))
		return -1
	_pids.append(pid)
	_sweeping_by_pid[pid] = sweeping
	_write("Launched %s (pid %d) on port %d%s." \
			% ["HOST" if is_host else "CLIENT", pid, int(_port_field.value),
			" [color=#8ab4d8]--autopilot[/color]" if sweeping else ""])
	return pid


## "Launch host" and "Launch client" are separate buttons, so the toggle can be
## flipped between the two halves of one pair — and `--autopilot` is the flag
## where that matters, because it carries Red's budget boost. Boosted on one peer
## only, the host spends a budget the client re-derives as unaffordable and the
## overlay reports [color=#e06c60]DIVERGED[/color]: a false positive in the one
## readout this harness exists to make trustworthy.
##
## A warning and not a refusal. [member _pids] is a convenience and the OS is the
## authority — a PID here may already be dead, so this cannot know what is
## actually running, and blocking a launch on a guess is worse than saying so.
func _warn_if_the_pair_would_be_asymmetric(sweeping: bool) -> void:
	for pid in _pids:
		if _sweeping_by_pid.get(pid, false) == sweeping:
			continue
		_write("[color=#e0a860]Careful: pid %d was launched %s --autopilot and this one " \
				% [pid, "WITH" if not sweeping else "WITHOUT"] \
				+ "is not. That flag carries Red's budget boost, so a mismatched pair " \
				+ "reports DIVERGED for reasons that are not a sync bug. Kill all and " \
				+ "relaunch both with the toggle settled.[/color]")
		return


func _write(line: String) -> void:
	if _log != null:
		_log.append_text(line + "\n")
