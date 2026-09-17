extends GutTest
## Spike #945: is a physics-broadphase gather faster than the linear scan
## `EuclideanRangeFinder.gather` runs over the whole board — and by how much?
##
## Run: [code]mise run test:one -- res://test/perf/bench_euclid_gather.gd[/code]
## Not collected by the suite (see `bench_allocation_cost.gd` for why `test/perf/`
## + the `bench_` prefix is the whole opt-out).
##
## Two strategies, one predicate. The scan is the shipped code path. The physics
## strategy is `PhysicsDirectSpaceState2D.intersect_shape` with a
## [CircleShape2D] of radius `reach` at the source's centre, `collision_mask`
## = layer 1 only (never the drag/deflect layers, #810), `collide_with_areas`,
## `max_results = node_count` (uncapped, so the set is exact and the
## broadphase-ordering caveat on the melee blade scan does not apply). Physics
## returns a CANDIDATE set; [method EuclideanRangeFinder._reaches] still
## decides, so a stale broadphase can only miss a node, never admit one. The
## bench asserts the two strategies agree on every board, per acceptance:
## "if physics and the scan disagree on any fixture, the scan wins and the
## spike closes negative".
##
## Numbers move with the machine AND with box load — record `uptime` alongside.
## `main` re-runs on a quiet master before accepting a verdict.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _FINDER := preload("res://attack/range_finder/euclidean_range_finder.gd")

const _SEED := 0x57A17EE
const _BOARDS: Array[int] = [800, 2000, 3000]
## Acceptance: "gather_multi (8 sources, 1500px)".
const _REACH := 1500.0
const _SOURCES := 8
const _REPS := 20
## Layer 1 is the untouched Godot default every SkillNode's Area2D sits on;
## layers 2/3 are the sparse defender bits (#810) and must be excluded.
const _LAYER_1_MASK := 1

var _rows: Array[String] = []


func test_bench_scan_vs_physics() -> void:
	gut.p("--- load: %s ---" % _uptime())
	for count in _BOARDS:
		await _bench_board(count)
	gut.p("\nboard | gather scan | gather physics | speedup | multi scan | multi physics | speedup")
	for row in _rows:
		gut.p(row)


func _bench_board(count: int) -> void:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = count
	cfg.seed = _SEED
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child(graph)
	var t_gen := Time.get_ticks_msec()
	await GraphProcgen.generate(cfg, graph)
	var gen_ms := Time.get_ticks_msec() - t_gen
	# Shapes register on the next physics flush.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var mirror: GraphMirror = graph.navigator
	var nodes := mirror.get_mirrored_nodes()
	var n := nodes.size()
	assert_eq(n, graph.get_skill_nodes().size(), "navigator mirrors the whole board")
	gut.p("--- board %d: %d nodes, generated in %d ms ---" % [count, n, gen_ms])

	var finder := _FINDER.new() as EuclideanRangeFinder
	finder.max_distance = _REACH
	var sources := _pick_sources(nodes)
	var space := graph.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = _LAYER_1_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var circle := CircleShape2D.new()
	params.shape = circle

	# -- correctness first: physics must reproduce the scan bit-for-bit -------
	for s in sources:
		var scan := finder.gather(s, mirror)
		var phys := _physics_gather(finder, s, mirror, space, params, circle, n)
		assert_eq(phys.size(), scan.size(), "board %d: physics/scan set size at %s" % [count, s.name])
		for k in scan:
			assert_true(phys.has(k), "board %d: physics missed %s from %s" % [count, k.name, s.name])
		for k in phys:
			assert_true(scan.has(k), "board %d: physics admitted %s from %s" % [count, k.name, s.name])
	var scan_multi := finder.gather_multi(sources, mirror)
	var phys_multi := _physics_gather_multi(finder, sources, mirror, space, params, circle, n)
	for s in sources:
		assert_eq((phys_multi[s] as Dictionary).size(), (scan_multi[s] as Dictionary).size(),
			"board %d: multi set size at %s" % [count, s.name])
	gut.p("  hits per source (scan): %s" % [sources.map(func(s): return scan_multi[s].size())])

	# -- timing ---------------------------------------------------------------
	var t_scan := _median(func():
		for s in sources:
			finder.gather(s, mirror)) / float(_SOURCES)
	var t_phys := _median(func():
		for s in sources:
			_physics_gather(finder, s, mirror, space, params, circle, n)) / float(_SOURCES)
	var t_scan_m := _median(func(): finder.gather_multi(sources, mirror))
	var t_phys_m := _median(func():
		_physics_gather_multi(finder, sources, mirror, space, params, circle, n))
	var row := "%5d | %8d us | %8d us | %5.1fx | %8d us | %8d us | %5.1fx" % [
		n, t_scan, t_phys, t_scan / maxf(t_phys, 1.0),
		t_scan_m, t_phys_m, t_scan_m / maxf(t_phys_m, 1.0)]
	gut.p(row)
	_rows.append(row)

	remove_child(graph)
	graph.free()


## Physics as an ITERATION STRATEGY behind the same predicate: the broadphase
## proposes candidates, `_reaches` + mirror membership decide.
func _physics_gather(finder: EuclideanRangeFinder, source: SkillNode, mirror: GraphMirror,
		space: PhysicsDirectSpaceState2D, params: PhysicsShapeQueryParameters2D,
		circle: CircleShape2D, max_results: int) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	var reach := finder.max_distance
	circle.radius = reach
	params.transform = Transform2D(0.0, source.global_position)
	for hit in space.intersect_shape(params, max_results):
		var n := hit.collider as SkillNode
		if n == null or mirror.vertex_id(n) < 0:
			continue
		var d := EuclideanRangeFinder._centre_distance(source, n)
		if EuclideanRangeFinder._reaches(d, n, reach):
			out[n] = d
	return out


func _physics_gather_multi(finder: EuclideanRangeFinder, sources: Array[SkillNode],
		mirror: GraphMirror, space: PhysicsDirectSpaceState2D,
		params: PhysicsShapeQueryParameters2D, circle: CircleShape2D,
		max_results: int) -> Dictionary[SkillNode, Dictionary]:
	var out: Dictionary[SkillNode, Dictionary] = {}
	for s in sources:
		out[s] = _physics_gather(finder, s, mirror, space, params, circle, max_results)
	return out


## Deterministic, spread across the board: every (n / 8)th node by stable_id.
func _pick_sources(nodes: Array[SkillNode]) -> Array[SkillNode]:
	var sorted := nodes.duplicate()
	sorted.sort_custom(func(a: SkillNode, b: SkillNode): return a.stable_id < b.stable_id)
	var out: Array[SkillNode] = []
	var step := maxi(1, sorted.size() / _SOURCES)
	for i in _SOURCES:
		out.append(sorted[(i * step) % sorted.size()])
	return out


## Median of _REPS timings, in microseconds.
func _median(fn: Callable) -> float:
	var times: Array[int] = []
	for i in _REPS:
		var t := Time.get_ticks_usec()
		fn.call()
		times.append(Time.get_ticks_usec() - t)
	times.sort()
	return float(times[times.size() / 2])


func _uptime() -> String:
	var out := []
	OS.execute("uptime", [], out)
	return str(out[0]).strip_edges() if not out.is_empty() else "n/a"
