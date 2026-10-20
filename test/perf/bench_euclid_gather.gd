extends GutTest
## #945 → #1701: Euclidean gather, three candidate sources behind one predicate.
##
## Run: [code]mise run test:one -- res://test/perf/bench_euclid_gather.gd[/code]
## Not collected by the suite (see `bench_allocation_cost.gd` for why `test/perf/`
## + the `bench_` prefix is the whole opt-out).
##
## - **scan** — the graph-less fallback: [method EuclideanRangeFinder.gather] on
##   a bare [GraphMirror] holding every node (the pre-#1701 production path).
## - **physics** — `PhysicsDirectSpaceState2D.intersect_shape` with a
##   [CircleShape2D] of radius `reach` at the source's centre, layer 1 only
##   (never the drag/deflect layers, #810), areas only, `max_results` = board
##   size. #945 benched it and ADR 0068 rejected it; kept as the yardstick.
## - **grid** — the shipped path: `gather` on `graph.navigator`, candidates from
##   [method Graph.spatial_candidates] ([SkillNodeGrid]).
##
## Each proposes candidates; [method EuclideanRangeFinder._reaches] decides.
## Verdict (printed, never a timer assert): grid ≤ physics at 1500 px / 3000
## nodes, grid ≤ scan ÷ 10 at 250 px on every board, set equality everywhere —
## the one thing asserted.
##
## Measured 2026-10-20 (dev desktop CPU, load 4.8 — noisy), µs per gather,
## median of 20 reps over 8 sources, cell 128 px, 0 set mismatches:
##
##   board | reach | scan | physics | grid | candidates | hits
##     800 |   250 | 1002 |      22 |   24 |         13 |    8
##     800 |  1500 | 1046 |     340 |  314 |        157 |  143
##    2000 |   250 | 2433 |      21 |   23 |         13 |    8
##    2000 |  1500 | 2484 |     414 |  366 |        191 |  170
##    3000 |   250 | 3636 |      20 |   22 |         12 |    7
##    3000 |  1500 | 3684 |     451 |  382 |        197 |  175
##
## gather_multi 8 × 1500 px, whole call (800/2000/3000): scan 8450/19752/29373,
## physics 2756/3268/3385, grid 2569/2941/3072. Grid build 1271/3128/4722 µs
## (once per board — never in play). Cell sweep at 3000: 64/128/256 px →
## 26/22/25 µs at 250 px, 457/382/336 µs at 1500 px; 128 stays the default.
## Grid ≈ physics at 250 px (within noise), flat in N like it, with none of its
## clauses.
##
## Cone seeds (#1704), measured 2026-10-20 (load 6.4 — noisy), µs per
## [method AimedTargeting.seeds], default 20° cone at 400 px, seeds asserted
## equal (set and order) to [method AimShape.crossed] over the whole board:
##
##   board | scan | grid | seeds
##     800 |  895 |   72 |   2.4
##    2000 | 2344 |   72 |   2.4
##    3000 | 3563 |   72 |   2.1
##
## Grid seeds are flat in N; the whole-board scan grows linearly.
##
## Numbers move with the machine AND with box load — record `uptime` alongside.
## `main` re-runs on a quiet master before accepting a verdict.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _FINDER := preload("res://attack/range_finder/euclidean_range_finder.gd")

const _SEED := 0x57A17EE
const _BOARDS: Array[int] = [800, 2000, 3000]
const _REACHES: Array[float] = [250.0, 1500.0]
## Acceptance: "gather_multi (8 sources, 1500px)".
const _MULTI_REACH := 1500.0
const _SOURCES := 8
const _REPS := 20
## Cell-size sweep, on the largest board only.
const _SWEEP_CELLS: Array[float] = [64.0, 128.0, 256.0]
## Cone seeds (#1704): the default cone (20 deg half-angle) at a cast range.
const _CONE_REACH := 400.0
## Layer 1 is the untouched Godot default every SkillNode's Area2D sits on;
## layers 2/3 are the sparse defender bits (#810) and must be excluded.
const _LAYER_1_MASK := 1

var _rows: Array[String] = []
var _multi_rows: Array[String] = []
var _build_rows: Array[String] = []
var _sweep_rows: Array[String] = []
var _cone_rows: Array[String] = []
var _verdicts: Array[String] = []


func test_bench_scan_vs_physics_vs_grid() -> void:
	gut.p("--- load: %s ---" % _uptime())
	for count in _BOARDS:
		await _bench_board(count)
	gut.p("\nboard | reach | scan us | physics us | grid us | candidates | set size | scan/grid")
	for row in _rows:
		gut.p(row)
	gut.p("\ngather_multi, %d sources @ %d px, whole call:" % [_SOURCES, int(_MULTI_REACH)])
	for row in _multi_rows:
		gut.p(row)
	gut.p("\ngrid build (SkillNodeGrid.rebuild, cell 128):")
	for row in _build_rows:
		gut.p(row)
	gut.p("\ncone seeds, us per AimedTargeting.seeds (whole-board crossed vs grid):")
	gut.p("board | reach | scan us | grid us | seeds  | scan/grid")
	for row in _cone_rows:
		gut.p(row)
	gut.p("\ncell-size sweep (largest board):")
	for row in _sweep_rows:
		gut.p(row)
	gut.p("\nverdict:")
	for v in _verdicts:
		gut.p(v)
	gut.p("--- load after: %s ---" % _uptime())


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
	var bare := GraphMirror.new()
	for node in nodes:
		bare.mirror_add(node)

	var finder := _FINDER.new() as EuclideanRangeFinder
	var sources := _pick_sources(nodes)
	var space := graph.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = _LAYER_1_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var circle := CircleShape2D.new()
	params.shape = circle

	for reach in _REACHES:
		finder.max_distance = reach
		var set_total := 0
		var cand_total := 0
		# -- correctness first: grid and physics must reproduce the scan ------
		for s in sources:
			var scan := finder.gather(s, bare)
			set_total += scan.size()
			cand_total += graph.spatial_candidates(s.global_position, reach).size()
			_assert_same(scan, finder.gather(s, mirror), "board %d reach %d: grid vs scan at %s" % [n, int(reach), s.name])
			_assert_same(scan, _physics_gather(finder, s, mirror, space, params, circle, n),
					"board %d reach %d: physics vs scan at %s" % [n, int(reach), s.name])
		# -- timing -----------------------------------------------------------
		var t_scan := _median(func():
			for s in sources:
				finder.gather(s, bare)) / float(_SOURCES)
		var t_phys := _median(func():
			for s in sources:
				_physics_gather(finder, s, mirror, space, params, circle, n)) / float(_SOURCES)
		var t_grid := _median(func():
			for s in sources:
				finder.gather(s, mirror)) / float(_SOURCES)
		var row := "%5d | %5d | %7.0f | %10.0f | %7.0f | %10.0f | %8.0f | %8.1fx" % [
			n, int(reach), t_scan, t_phys, t_grid, float(cand_total) / _SOURCES,
			float(set_total) / _SOURCES, t_scan / maxf(t_grid, 1.0)]
		gut.p(row)
		_rows.append(row)
		if reach == 250.0:
			_verdicts.append("%s  board %d: grid %.0f <= scan/10 %.0f at 250 px" % [
				"PASS" if t_grid <= t_scan / 10.0 else "FAIL", n, t_grid, t_scan / 10.0])
		if reach == 1500.0 and count == _BOARDS[-1]:
			_verdicts.append("%s  board %d: grid %.0f <= physics %.0f at 1500 px" % [
				"PASS" if t_grid <= t_phys else "FAIL", n, t_grid, t_phys])

	# -- gather_multi ---------------------------------------------------------
	finder.max_distance = _MULTI_REACH
	var scan_multi := finder.gather_multi(sources, bare)
	var grid_multi := finder.gather_multi(sources, mirror)
	for s in sources:
		_assert_same(scan_multi[s], grid_multi[s], "board %d: multi grid vs scan at %s" % [n, s.name])
	var tm_scan := _median(func(): finder.gather_multi(sources, bare))
	var tm_phys := _median(func():
		for s in sources:
			_physics_gather(finder, s, mirror, space, params, circle, n))
	var tm_grid := _median(func(): finder.gather_multi(sources, mirror))
	_multi_rows.append("%5d nodes: scan %7.0f us | physics %7.0f us | grid %7.0f us | scan/grid %.1fx" % [
		n, tm_scan, tm_phys, tm_grid, tm_scan / maxf(tm_grid, 1.0)])

	# -- cone seeds (#1704): AimedTargeting.seeds on the grid vs crossed over
	# the whole board, at the cast-range reach ------------------------------
	var aimed := AimedTargeting.new()
	var cone := ConeShape.new()
	aimed.shape = cone
	aimed.ownership_filter = 15
	aimed.range_finder = _FINDER.new()
	aimed.range_finder.max_distance = _CONE_REACH
	var angles: Array[float] = [0.0, 1.3, 2.6, -2.0]
	var seeds_total := 0
	for s in sources:
		var rest: Array[SkillNode] = nodes.filter(func(x: SkillNode) -> bool: return x != s)
		for a in angles:
			var got := aimed.seeds(null, s, a, graph)
			assert_eq(got, cone.crossed(s.global_position, a, _CONE_REACH, rest),
					"board %d: cone seeds grid vs whole board at %s %.1f" % [n, s.name, a])
			seeds_total += got.size()
	var tc_scan := _median(func():
		for s in sources:
			cone.crossed(s.global_position, angles[0], _CONE_REACH, nodes)) / float(_SOURCES)
	var tc_grid := _median(func():
		for s in sources:
			aimed.seeds(null, s, angles[0], graph)) / float(_SOURCES)
	_cone_rows.append("%5d | %5d | %7.0f | %7.0f | %6.1f | %8.1fx" % [
		n, int(_CONE_REACH), tc_scan, tc_grid, float(seeds_total) / (_SOURCES * angles.size()),
		tc_scan / maxf(tc_grid, 1.0)])

	# -- grid build -----------------------------------------------------------
	var sorted := graph.get_skill_nodes()
	sorted.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.stable_id < b.stable_id)
	var probe := SkillNodeGrid.new()
	var t_build := _median(func(): probe.rebuild(sorted, 128.0))
	_build_rows.append("%5d nodes: %6.0f us  (%dx%d cells of %.0f px, max_radius %.1f)" % [
		n, t_build, probe.cols, probe.rows, probe.cell, probe.max_radius])

	# -- cell-size sweep on the biggest board ----------------------------------
	if count == _BOARDS[-1]:
		for cp in _SWEEP_CELLS:
			graph.spatial_cell_px = cp
			for reach in _REACHES:
				finder.max_distance = reach
				var cands := 0
				for s in sources:
					cands += graph.spatial_candidates(s.global_position, reach).size()
					_assert_same(finder.gather(s, bare), finder.gather(s, mirror),
							"sweep cell %d reach %d at %s" % [int(cp), int(reach), s.name])
				var t := _median(func():
					for s in sources:
						finder.gather(s, mirror)) / float(_SOURCES)
				_sweep_rows.append("cell %3d px, reach %4d: %6.0f us, %6.0f candidates" % [
					int(cp), int(reach), t, float(cands) / _SOURCES])
		graph.spatial_cell_px = 128.0

	bare.free()
	remove_child(graph)
	graph.free()


func _assert_same(a: Dictionary, b: Dictionary, what: String) -> void:
	var same := a.size() == b.size()
	if same:
		for k in a:
			if not b.has(k):
				same = false
				break
	assert_true(same, "set equality: %s (%d vs %d)" % [what, a.size(), b.size()])


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


## Deterministic, spread across the board: every (n / 8)th node by stable_id.
func _pick_sources(nodes: Array[SkillNode]) -> Array[SkillNode]:
	var sorted := nodes.duplicate()
	sorted.sort_custom(func(a: SkillNode, b: SkillNode): return a.stable_id < b.stable_id)
	var out: Array[SkillNode] = []
	@warning_ignore("integer_division")  # intended truncation: index/count/offset
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
	@warning_ignore("integer_division")  # intended truncation: index/count/offset
	return float(times[times.size() / 2])


func _uptime() -> String:
	var out := []
	OS.execute("uptime", [], out)
	return str(out[0]).strip_edges() if not out.is_empty() else "n/a"
