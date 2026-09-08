extends Node

## The measurement half of the #763 idle-turn bench — see
## [code]scenes/idle_turn_bench.gd[/code] for the run it sits in.
##
## Waits for the level to compose, parks on the PLAYER's turn (a stationary
## turn is a player turn waiting on input; a parked AI turn would act and the
## number would be "AI turn cost", not idle), then sweeps the configured
## segments and prints one pasteable block, then quits.
##
## CPU and GPU are reported separately, which is the whole point of #763:
## - [code]wall[/code] — frame-to-frame wall clock (uncapped, vsync off)
## - [code]cpu proc[/code] — [code]Performance.TIME_PROCESS[/code], the engine's
##   process step (game logic + RenderingServer scene sync)
## - [code]rs setup[/code] — [code]RenderingServer.get_frame_setup_time_cpu()[/code],
##   the CPU cost of building the frame's draw lists
## - [code]gpu[/code] — [code]RenderingServer.viewport_get_measured_render_time_gpu[/code],
##   real raster time (same source the editor profiler uses; 0 under
##   [code]--headless[/code], where the whole GPU half is absent by construction)
##
## Judge DELTAS between segments, not absolutes — the same lesson
## [code]scenes/overlay_perf_harness.gd[/code] encodes for the overlay sweep.

const _SOFTWARE_HINTS: Array[String] = ["llvmpipe", "softpipe", "swiftshader"]
const _BASELINE := "baseline"

var _viewport_rid: RID
var _baseline_stats: Dictionary = {}
var _halo_style_before: Dictionary = {}
var _fog_visible_before := true
var _injected_env: WorldEnvironment = null
var _turn_owner_name := "<none>"


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var bench: Node = owner
	var root := owner as GameRoot
	while not root.is_reveal_ready():
		await get_tree().process_frame
	await _park_on_player_turn(root)
	await get_tree().create_timer(float(bench.get("settle_seconds"))).timeout

	# Measurement mode: vsync would clamp the rate and hide everything; the
	# cap (Settings.max_fps) would too. Headless has no DisplayServer window.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)

	_print_header(bench, root)
	var segments_cfg: Array = bench.get("segments")
	for segment in segments_cfg:
		await _enter_segment(segment, root)
		var stats := await _measure(
				float(bench.get("warmup_seconds")),
				float(bench.get("sample_seconds")))
		_print_segment(segment, stats)
		await _exit_segment(segment, root)
	_print_footer()


## A stationary turn is the PLAYER's turn. If initiative landed the first turn
## on an AI camp, advance until it isn't (bounded) — those AI turns play out
## for real, which is fine: we only need to END parked on the player.
func _park_on_player_turn(root: GameRoot) -> void:
	var tm: TurnManager = root.turn_manager
	for i in 10:
		if tm.current_entity != null and tm.current_entity == root.player:
			_turn_owner_name = tm.current_entity.name
			return
		await get_tree().process_frame
	for i in 8:
		if tm.current_entity != null and tm.current_entity == root.player:
			break
		var before := tm.current_entity
		tm.end_turn()
		# end_turn ticks inside the call; the next turn may already be current,
		# so poll frames rather than awaiting a turn_started we may have missed.
		for j in 60:
			await get_tree().process_frame
			if tm.current_entity != before:
				break
		await get_tree().create_timer(0.25).timeout
	if tm.current_entity != null:
		_turn_owner_name = tm.current_entity.name
		if tm.current_entity != root.player:
			push_warning("idle bench: could not park on the player's turn — "
					+ "measuring %s's turn instead" % _turn_owner_name)


## Average per-frame samples over `sample_seconds`, after discarding
## `warmup_seconds`. Samples once per drawn frame, like overlay_perf_harness.
func _measure(warmup_seconds: float, sample_seconds: float) -> Dictionary:
	var deadline := Time.get_ticks_usec() + int(warmup_seconds * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw

	var wall_us: Array[int] = []
	var cpu_us: Array[int] = []
	var phys_us: Array[int] = []
	var rs_us: Array[int] = []
	var gpu_ms: Array[float] = []
	var draws: Array[int] = []
	var objects: Array[int] = []
	var prims: Array[int] = []

	var prev := Time.get_ticks_usec()
	deadline = prev + int(sample_seconds * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall_us.append(now - prev)
		prev = now
		cpu_us.append(int(Performance.get_monitor(Performance.TIME_PROCESS) * 1_000_000.0))
		phys_us.append(int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0))
		rs_us.append(RenderingServer.get_frame_setup_time_cpu())
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))

	return {
		"frames": wall_us.size(),
		"wall_p50_ms": _pct_ms(wall_us, 0.50),
		"wall_p95_ms": _pct_ms(wall_us, 0.95),
		"wall_max_ms": _pct_ms(wall_us, 1.0),
		"cpu_ms": _mean_us_as_ms(cpu_us),
		"phys_ms": _mean_us_as_ms(phys_us),
		"rs_ms": _mean_us_as_ms(rs_us),
		"gpu_ms": _mean(gpu_ms),
		"gpu_p95_ms": _pct_f(gpu_ms, 0.95),
		"draws": _mean_i(draws),
		"objects": _mean_i(objects),
		"prims_k": _mean_i(prims) / 1000.0,
	}


## — segment toggles ————————————————————————————————————————————————————————————
## Each toggle measures one named suspect. Restore is verbatim, not
## sentinel-based: [code]core_halo_style = -1[/code] means "whatever the scene
## authored" — restoring blocker nodes with it would UN-pin their authored COG
## style and quietly add gimbals to the level. Snapshot, then restore exactly.

func _enter_segment(segment: String, root: GameRoot) -> void:
	match segment:
		_BASELINE:
			pass
		"gimbals-off":
			for n: SkillNode in root.graph.get_skill_nodes():
				_halo_style_before[n.get_instance_id()] = n.core_halo_style
				n.core_halo_style = 0 # CoreHaloStyle.NONE
		"fog-pass-off":
			var fog := root.get_node_or_null("Graph/FogOverlay")
			if fog != null:
				_fog_visible_before = fog.visible
				fog.visible = false
		"glow-off":
			_inject_glow_off_environment(root)
		_:
			push_warning("idle bench: unknown segment '%s' — measured as baseline" % segment)


func _exit_segment(segment: String, root: GameRoot) -> void:
	match segment:
		_BASELINE:
			pass
		"gimbals-off":
			for n: SkillNode in root.graph.get_skill_nodes():
				var id := n.get_instance_id()
				if _halo_style_before.has(id):
					n.core_halo_style = _halo_style_before[id]
			_halo_style_before.clear()
		"fog-pass-off":
			var fog := root.get_node_or_null("Graph/FogOverlay")
			if fog != null:
				fog.visible = _fog_visible_before
		"glow-off":
			if _injected_env != null:
				_injected_env.queue_free()
				_injected_env = null


## WorldEnvironment carrying a glow-less duplicate of the project's default
## environment. Whether a runtime WorldEnvironment overrides the
## project-default environment for 2D post-FX is exactly what this segment
## exists to find out — the driver's launch-time env patch is the authoritative
## cross-check. If the two disagree, trust the patch.
func _inject_glow_off_environment(root: GameRoot) -> void:
	if _injected_env != null:
		return
	var env := (load("res://ui/theme/default_game_env.tres") as Environment).duplicate()
	env.glow_enabled = false
	_injected_env = WorldEnvironment.new()
	_injected_env.environment = env
	root.add_child(_injected_env)


# — report —————————————————————————————————————————————————————————————————————

func _print_header(bench: Node, root: GameRoot) -> void:
	var adapter := RenderingServer.get_video_adapter_name()
	var headless := DisplayServer.get_name() == "headless"
	var size := get_viewport().size
	print("\n=== #763 idle-turn bench ===")
	print("godot    : %s" % Engine.get_version_info()["string"])
	print("adapter  : %s%s" % [
		adapter,
		" (SOFTWARE RASTERIZER — deltas only, absolutes meaningless)" if _is_software() else "",
	])
	print("renderer : %s   hdr_2d=%s   viewport: %s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		ProjectSettings.get_setting("rendering/viewport/hdr_2d"),
		"%dx%d" % [size.x, size.y] if not headless else "headless (no renderer)",
	])
	print("map      : nodes=%d seed=%d entities=%d" % [
		root.graph.get_skill_nodes().size(),
		GameSession.config.seed,
		root.graph.entities_container.get_child_count(),
	])
	print("turn     : %s (parked, stationary)   vsync=off uncapped" % _turn_owner_name)
	print("sampling : settle=%.1fs warmup=%.1fs sample=%.1fs" % [
		float(bench.get("settle_seconds")),
		float(bench.get("warmup_seconds")),
		float(bench.get("sample_seconds")),
	])
	print("ms = milliseconds per frame. cpu = engine process step, rs = draw-list build, gpu = raster")
	print("%-13s %6s %8s %8s %8s %8s %8s %8s %8s %7s %8s" % [
		"segment", "frames", "wall p50", "wall p95", "cpu proc", "cpu phys",
		"rs setup", "gpu", "gpu p95", "draws", "prims k"])
	print("%-13s %6s %8s %8s %8s %8s %8s %8s %8s %7s %8s" % [
		"---------------", "------", "--------", "--------", "--------",
		"--------", "--------", "--------", "--------", "-------", "--------"])


func _print_segment(segment: String, stats: Dictionary) -> void:
	if segment == _BASELINE:
		_baseline_stats = stats
	print("%-13s %6d %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %7.0f %8.1f" % [
		segment, stats.get("frames", 0),
		stats.get("wall_p50_ms", 0.0), stats.get("wall_p95_ms", 0.0),
		stats.get("cpu_ms", 0.0), stats.get("phys_ms", 0.0),
		stats.get("rs_ms", 0.0), stats.get("gpu_ms", 0.0),
		stats.get("gpu_p95_ms", 0.0), stats.get("draws", 0.0),
		stats.get("prims_k", 0.0)])
	if segment != _BASELINE and not _baseline_stats.is_empty():
		print("  %-11s | wall %+.2f | cpu %+.2f | gpu %+.2f" % [
			"delta base",
			stats.get("wall_p50_ms", 0.0) - _baseline_stats.get("wall_p50_ms", 0.0),
			stats.get("cpu_ms", 0.0) - _baseline_stats.get("cpu_ms", 0.0),
			stats.get("gpu_ms", 0.0) - _baseline_stats.get("gpu_ms", 0.0)])


func _print_footer() -> void:
	print("")
	print("Read the DELTAS. cpu vs gpu answers #763's first fork (measure before")
	print("fixing: .claude/rules/graph.md's CPU-first triage). gimbals-off answers")
	print("the 80% suspicion. The p95 wall column is the 'comfortably, not")
	print("just-in-time' number: Tier L wants p50 well under 10ms at 1080p.")
	print("(The engine's own per-second 'fps' lines above come from")
	print("project.godot print_fps=true — a cross-check, not the measurement.)")
	print("=== end #763 idle-turn bench ===")


func _is_software() -> bool:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	for hint in _SOFTWARE_HINTS:
		if adapter.contains(hint):
			return true
	return false


# — stats helpers ——————————————————————————————————————————————————————————————

func _mean_us_as_ms(samples: Array[int]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0
	for s in samples:
		total += s
	return total / float(samples.size()) / 1000.0


func _pct_ms(samples_us: Array[int], fraction: float) -> float:
	if samples_us.is_empty():
		return 0.0
	var sorted_samples := samples_us.duplicate()
	sorted_samples.sort()
	var idx := mini(sorted_samples.size() - 1, int(fraction * sorted_samples.size()))
	return sorted_samples[idx] / 1000.0


func _mean(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for s in samples:
		total += s
	return total / samples.size()


func _pct_f(samples: Array[float], fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var idx := mini(sorted_samples.size() - 1, int(fraction * sorted_samples.size()))
	return sorted_samples[idx]


func _mean_i(samples: Array[int]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0
	for s in samples:
		total += s
	return total / float(samples.size())
