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
## Plain-int mirrors of CoreHalos.CoreHaloStyle (this probe never types against
## the leaf component — see blocker_visual.gd for the same mirrors).
const _STYLE_NONE := 0
const _STYLE_GIMBAL := 3
const _STYLE_COG := 4
const _STYLE_NAMES: Array[String] = ["NONE", "RINGS", "ORBIT", "GIMBAL", "COG"]

var _viewport_rid: RID
var _baseline_stats: Dictionary = {}
var _halo_style_before: Dictionary = {}
var _fog_visible_before := true
var _injected_env: WorldEnvironment = null
var _turn_owner_name := "<none>"
var _frozen: Array[Node] = []


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
	await _apply_zoom_override(float(bench.get("zoom_override")), root)

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


## Parks the camera on the whole graph at [param wanted] zoom, so the halo
## census measures a board where halos genuinely ARE on screen (#802). `<= 0`
## leaves the camera alone.
##
## Goes straight at [method GraphCamera.begin_directed_focus] rather than
## through [CameraDirector] on purpose: the director's job is to decide WHERE
## to look from gameplay events (#523), and a bench has no gameplay event to
## express "show me everything" with. The camera clamps the zoom up to its own
## `_min_zoom_floor`, so this can never ask for more than the level allows.
##
## The settle wait is load-bearing: SkillNode halos learn they are on screen
## from a [VisibleOnScreenNotifier2D], which reports one frame late, and the
## whole point of this segment is to measure the state AFTER that has settled.
func _apply_zoom_override(wanted: float, root: GameRoot) -> void:
	if wanted <= 0.0 or root.camera == null:
		return
	var bounds := Rect2()
	var first := true
	for n: SkillNode in root.graph.get_skill_nodes():
		if first:
			bounds = Rect2(n.global_position, Vector2.ZERO)
			first = false
		else:
			bounds = bounds.expand(n.global_position)
	if first:
		return
	root.camera.begin_directed_focus(bounds.get_center(), wanted, 0.0)
	await get_tree().create_timer(1.0).timeout


## Average per-frame samples over `sample_seconds`, after discarding
## `warmup_seconds`. Samples once per drawn frame, like overlay_perf_harness.
##
## [b]TIME_PROCESS gotcha[/b]: [code]Performance.TIME_PROCESS[/code] is NOT a
## per-frame value — the engine accumulates the MAX process-step duration
## within each 1-second reporting window and resets at the window boundary
## (main.cpp: process_max = MAX(...), set_process_time at the fps-print
## reset). Averaging per-frame reads is therefore wrong: one spike anywhere
## in the window (e.g. the bench's own park/end_turn phase, or a segment
## transition) contaminates every later read in that window — this probe
## once read 94ms of "process time" on a frame whose wall time was 6.9ms.
## So the cpu column is collected as: discard warmup, align to the first
## reset boundary (a value DROP — maxima can only rise within a window),
## then record each complete window's max plus the final partial window's
## max. "cpu proc" is the mean worst process frame per second — the honest
## CPU floor, and the same semantics apply to TIME_PHYSICS_PROCESS.
func _measure(warmup_seconds: float, sample_seconds: float) -> Dictionary:
	var deadline := Time.get_ticks_usec() + int(warmup_seconds * 1_000_000.0)
	var last_cpu := 0.0
	while Time.get_ticks_usec() < deadline:
		await _frame_tick()
		last_cpu = Performance.get_monitor(Performance.TIME_PROCESS)
	# Align: wait for the first reset boundary so every recorded window is
	# fully inside the sample.
	while true:
		await _frame_tick()
		var cpu := Performance.get_monitor(Performance.TIME_PROCESS)
		if cpu < last_cpu:
			last_cpu = cpu
			break
		last_cpu = cpu

	var wall_us: Array[int] = []
	var cpu_maxima_ms: Array[float] = []
	var phys_maxima_ms: Array[float] = []
	var rs_us: Array[int] = []
	var gpu_ms: Array[float] = []
	var draws: Array[int] = []
	var objects: Array[int] = []
	var prims: Array[int] = []

	var prev := Time.get_ticks_usec()
	deadline = prev + int(sample_seconds * 1_000_000.0)
	var window_max_us := int(last_cpu * 1_000_000.0)
	var phys_max_us := 0
	while Time.get_ticks_usec() < deadline:
		await _frame_tick()
		var now := Time.get_ticks_usec()
		wall_us.append(now - prev)
		prev = now
		var cpu := Performance.get_monitor(Performance.TIME_PROCESS)
		if cpu * 1_000_000.0 < window_max_us:
			# Engine reset its reporting window: finalize the one that ended.
			cpu_maxima_ms.append(window_max_us / 1000.0)
			phys_maxima_ms.append(phys_max_us / 1000.0)
			window_max_us = int(cpu * 1_000_000.0)
			phys_max_us = 0
		else:
			window_max_us = maxi(window_max_us, int(cpu * 1_000_000.0))
		phys_max_us = maxi(phys_max_us,
				int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0))
		rs_us.append(RenderingServer.get_frame_setup_time_cpu())
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	# The final partial window — aligned start, so its max is honest.
	cpu_maxima_ms.append(window_max_us / 1000.0)
	phys_maxima_ms.append(phys_max_us / 1000.0)

	return {
		"frames": wall_us.size(),
		"wall_p50_ms": _pct_ms(wall_us, 0.50),
		"wall_p95_ms": _pct_ms(wall_us, 0.95),
		"wall_max_ms": _pct_ms(wall_us, 1.0),
		"cpu_ms": _mean(cpu_maxima_ms),
		"cpu_max_ms": _max_f(cpu_maxima_ms),
		"phys_ms": _mean(phys_maxima_ms),
		"rs_ms": _mean_us_as_ms(rs_us),
		"gpu_ms": _mean(gpu_ms),
		"gpu_p95_ms": _pct_f(gpu_ms, 0.95),
		"draws": _mean_i(draws),
		"objects": _mean_i(objects),
		"prims_k": _mean_i(prims) / 1000.0,
	}


## One engine frame. [signal RenderingServer.frame_post_draw] never fires
## under the headless dummy renderer (no draw happens — the main loop still
## ticks, but the signal is posted by the real rasterizer), so a headless
## run awaiting it hangs forever with the game alive at full uncapped fps.
## [signal SceneTree.process_frame] fires either way.
func _frame_tick() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## Turns off only the halos whose EFFECTIVE style matches `only_style`
## (`-1` = every style, the old blanket toggle). Isolating matters: the level
## carries ~10x more cheap COG blockers (#478) than true GIMBAL cores, so a
## blanket toggle measures "all core halos" and any per-gimbal division of that
## delta is contaminated by the COGs.
func _disable_halos(root: GameRoot, only_style: int) -> void:
	for n: SkillNode in root.graph.get_skill_nodes():
		if only_style != -1 and _effective_style(n) != only_style:
			continue
		_halo_style_before[n.get_instance_id()] = n.core_halo_style
		n.core_halo_style = _STYLE_NONE


func _restore_halos(root: GameRoot) -> void:
	for n: SkillNode in root.graph.get_skill_nodes():
		var id := n.get_instance_id()
		if _halo_style_before.has(id):
			n.core_halo_style = _halo_style_before[id]
	_halo_style_before.clear()


## The style the node's CoreHalos is ACTUALLY drawing. `core_halo_style == -1`
## is the "whatever the scene authored" sentinel, so it can't be read directly;
## ask the live component through the composite instead.
func _effective_style(n: SkillNode) -> int:
	var halos := _find_halos(n)
	return int(halos.halo_style) if halos != null else _STYLE_NONE


func _find_halos(n: Node) -> Node:
	for child in n.get_children():
		if child.has_method("is_gimbal_active"):
			return child
		var found := _find_halos(child)
		if found != null:
			return found
	return null


## How many nodes are drawing each halo style RIGHT NOW — the denominator for
## any per-core cost claim, measured rather than eyeballed.
##
## Four buckets, because the gap between them IS the finding: `present` counts
## every CoreHalos component carrying the style (most sit on non-core nodes
## with CorePresence hidden, so they never draw but DO still `_process`);
## `drawing` is visible-in-tree, i.e. actually rebuilding its buffer every
## frame; `revealed` and `onscreen` are the subsets that a fog-gate or a
## viewport-cull would keep. `drawing` minus `onscreen` is rebuild work whose
## pixels nobody can see.
func _halo_census(root: GameRoot) -> Dictionary:
	var counts := {}
	var drawing := {}
	var revealed := {}
	var onscreen := {}
	var view_rect := get_viewport().get_visible_rect()
	for n: SkillNode in root.graph.get_skill_nodes():
		var halos := _find_halos(n)
		if halos == null:
			continue
		var style := int(halos.halo_style)
		counts[style] = int(counts.get(style, 0)) + 1
		if not (halos as CanvasItem).is_visible_in_tree():
			continue
		drawing[style] = int(drawing.get(style, 0)) + 1
		if n.revealed:
			revealed[style] = int(revealed.get(style, 0)) + 1
		if view_rect.has_point(n.get_global_transform_with_canvas().origin):
			onscreen[style] = int(onscreen.get(style, 0)) + 1
	return {"present": counts, "drawing": drawing,
			"revealed": revealed, "onscreen": onscreen}


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
			_disable_halos(root, _STYLE_GIMBAL)
		"cogs-off":
			_disable_halos(root, _STYLE_COG)
		"halos-off":
			_disable_halos(root, -1)
		"halos-frozen":
			# Still drawn, just not re-drawn: stops the animation clock and the
			# per-frame queue_redraw, keeping the last buffer on screen. This
			# is the fork that decides the FIX — if frozen ≈ off, the cost is
			# the per-frame REBUILD (cadence/GPU-animation problem); if frozen
			# ≈ baseline, it's the draw itself (geometry/batching problem).
			for n: SkillNode in root.graph.get_skill_nodes():
				var halos := _find_halos(n)
				if halos != null and (halos as CanvasItem).is_visible_in_tree():
					_frozen.append(halos)
					halos.call("set_animating", false)
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
		"gimbals-off", "cogs-off", "halos-off":
			_restore_halos(root)
		"halos-frozen":
			for halos in _frozen:
				if is_instance_valid(halos):
					halos.call("set_animating", true)
			_frozen.clear()
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
	var size: Vector2i = get_viewport().size
	print("\n=== #763 idle-turn bench ===")
	print("godot    : %s" % Engine.get_version_info()["string"])
	print("adapter  : %s%s" % [
		adapter,
		" (SOFTWARE RASTERIZER — deltas only, absolutes meaningless)" if _is_software() else "",
	])
	print("renderer : %s   hdr_2d=%s   viewport: %s" % [
		# NB: reads the PROJECT default, not a --rendering-method override —
		# the engine's startup line ("Forward+" / "Forward Mobile" / "OpenGL")
		# is the authoritative renderer for patched runs.
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
	print("halos    : %s" % _format_census(_halo_census(root)))
	print("sampling : settle=%.1fs warmup=%.1fs sample=%.1fs" % [
		float(bench.get("settle_seconds")),
		float(bench.get("warmup_seconds")),
		float(bench.get("sample_seconds")),
	])
	print("ms = milliseconds per frame. cpu = mean worst process frame per second (TIME_PROCESS is a per-second max — see code)")
	print("%-13s %6s %8s %8s %8s %8s %8s %8s %8s %8s %7s %8s" % [
		"segment", "frames", "wall p50", "wall p95", "wall max", "cpu proc",
		"cpu max", "cpu phys", "rs setup", "gpu", "gpu p95", "draws"])
	print("%-13s %6s %8s %8s %8s %8s %8s %8s %8s %8s %7s %8s" % [
		"---------------", "------", "--------", "--------", "--------",
		"--------", "--------", "--------", "--------", "--------",
		"-------", "--------"])


## "GIMBAL 7 drawing (7 revealed, 3 onscreen) / 1700 present" — the per-core
## denominator, plus what a fog-gate or viewport-cull would leave.
func _format_census(census: Dictionary) -> String:
	var present: Dictionary = census["present"]
	var parts: Array[String] = []
	for style in present:
		if int(style) == _STYLE_NONE:
			continue
		parts.append("%s %d drawing (%d revealed, %d onscreen) / %d present" % [
			_STYLE_NAMES[int(style)] if int(style) < _STYLE_NAMES.size() else str(style),
			int((census["drawing"] as Dictionary).get(style, 0)),
			int((census["revealed"] as Dictionary).get(style, 0)),
			int((census["onscreen"] as Dictionary).get(style, 0)),
			int(present[style])])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _print_segment(segment: String, stats: Dictionary) -> void:
	if segment == _BASELINE:
		_baseline_stats = stats
	print("%-13s %6d %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f %7.2f %8.1f" % [
		segment, stats.get("frames", 0),
		stats.get("wall_p50_ms", 0.0), stats.get("wall_p95_ms", 0.0),
		stats.get("wall_max_ms", 0.0), stats.get("cpu_ms", 0.0),
		stats.get("cpu_max_ms", 0.0), stats.get("phys_ms", 0.0),
		stats.get("rs_ms", 0.0), stats.get("gpu_ms", 0.0),
		stats.get("gpu_p95_ms", 0.0), stats.get("draws", 0.0)])
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
	print("cpu proc = mean worst process frame per second (the engine reports")
	print("TIME_PROCESS as a per-second MAX, so per-frame averaging would let a")
	print("single pre-window spike contaminate the whole column — the probe")
	print("aligns to the engine's reset boundaries instead; wall max flags any")
	print("in-window spike). HEADLESS: the main loop is throttled to ~145 fps")
	print("regardless of work (6.9ms floor wall), so the headless wall column is")
	print("a floor, not a cost — the headless cpu column is the honest CPU floor.")
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


func _max_f(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var best := 0.0
	for s in samples:
		best = maxf(best, s)
	return best


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
