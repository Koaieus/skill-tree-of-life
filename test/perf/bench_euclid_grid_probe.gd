extends GutTest
## Probe for #1701: a uniform-grid candidate source for
## `EuclideanRangeFinder.gather` vs the shipped scan vs physics `intersect_shape`.
## Run: mise run test:one -- res://test/perf/bench_euclid_grid_probe.gd
## Not collected by the suite (test/perf/ + bench_ prefix). Measurement only.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")
const _FINDER := preload("res://attack/range_finder/euclidean_range_finder.gd")

const _SEED := 0x57A17EE
const _BOARDS: Array[int] = [800, 2000, 3000]
const _REACHES: Array[float] = [250.0, 1500.0]
const _MULTI_REACH := 1500.0
const _SOURCES := 8
const _REPS := 20
const _LAYER_1_MASK := 1
const CELL_PX := 128.0
const _MAX_CELLS_PER_AXIS := 128
const _SENS_CELLS: Array[float] = [64.0, 256.0]

var _rows: Array[String] = []
var _build_rows: Array[String] = []
var _multi_rows: Array[String] = []
var _sens_rows: Array[String] = []
var _mismatches := 0


## Uniform grid over the positions' bounding box.
class Grid extends RefCounted:
	var cell := 128.0
	var origin := Vector2.ZERO
	var cols := 1
	var rows := 1
	var cells: Array = []  # flat, cols*rows, each an Array of SkillNode
	var max_radius := 0.0
	var examined := 0

	func build(nodes: Array[SkillNode], cell_px: float, max_axis: int) -> void:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		max_radius = 0.0
		for n in nodes:
			var p := n.global_position
			lo = lo.min(p)
			hi = hi.max(p)
			max_radius = maxf(max_radius, n.radius)
		origin = lo
		var span := hi - lo
		cell = maxf(cell_px, maxf(span.x, span.y) / float(max_axis))
		cols = int(span.x / cell) + 1
		rows = int(span.y / cell) + 1
		cells = []
		cells.resize(cols * rows)
		for i in cells.size():
			cells[i] = []
		for n in nodes:
			var p := n.global_position - origin
			var cx := clampi(int(p.x / cell), 0, cols - 1)
			var cy := clampi(int(p.y / cell), 0, rows - 1)
			(cells[cy * cols + cx] as Array).append(n)

	func gather(source: SkillNode, reach: float) -> Dictionary[SkillNode, float]:
		var out: Dictionary[SkillNode, float] = {}
		var c := source.global_position
		var expand := reach + max_radius
		var e2 := expand * expand
		var x0 := clampi(int(floorf((c.x - expand - origin.x) / cell)), 0, cols - 1)
		var x1 := clampi(int(floorf((c.x + expand - origin.x) / cell)), 0, cols - 1)
		var y0 := clampi(int(floorf((c.y - expand - origin.y) / cell)), 0, rows - 1)
		var y1 := clampi(int(floorf((c.y + expand - origin.y) / cell)), 0, rows - 1)
		for cy in range(y0, y1 + 1):
			var ry0 := origin.y + cy * cell
			var ny := clampf(c.y, ry0, ry0 + cell) - c.y
			for cx in range(x0, x1 + 1):
				var rx0 := origin.x + cx * cell
				var nx := clampf(c.x, rx0, rx0 + cell) - c.x
				if nx * nx + ny * ny > e2:
					continue
				for n: SkillNode in cells[cy * cols + cx]:
					examined += 1
					var d := c.distance_to(n.global_position)
					if EuclideanRangeFinder._reaches(d, n, reach):
						out[n] = d
		return out


func test_bench_grid_probe() -> void:
	gut.p("--- load: %s ---" % _uptime())
	for count in _BOARDS:
		await _bench_board(count)
	gut.p("\nboard | reach | scan us | physics us | grid us | cand examined | set size | scan/grid")
	for row in _rows:
		gut.p(row)
	gut.p("\ngrid build (CELL_PX=%d):" % int(CELL_PX))
	for row in _build_rows:
		gut.p(row)
	gut.p("\ngather_multi, %d sources @ %d px:" % [_SOURCES, int(_MULTI_REACH)])
	for row in _multi_rows:
		gut.p(row)
	gut.p("\ncell-size sensitivity (3000 board, grid us / cand examined):")
	for row in _sens_rows:
		gut.p(row)
	gut.p("\nset-equality mismatches: %d" % _mismatches)
	assert_eq(_mismatches, 0, "grid set equals scan set everywhere")
	gut.p("--- load after: %s ---" % _uptime())


func _bench_board(count: int) -> void:
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = count
	cfg.seed = _SEED
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child(graph)
	await GraphProcgen.generate(cfg, graph)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var mirror: GraphMirror = graph.navigator
	var nodes := mirror.get_mirrored_nodes()
	var n := nodes.size()
	gut.p("--- board %d: %d nodes ---" % [count, n])

	var finder := _FINDER.new() as EuclideanRangeFinder
	var sources := _pick_sources(nodes)
	var space := graph.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = _LAYER_1_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var circle := CircleShape2D.new()
	params.shape = circle

	var grid := Grid.new()
	var t_build := _median(func(): Grid.new().build(nodes, CELL_PX, _MAX_CELLS_PER_AXIS))
	grid.build(nodes, CELL_PX, _MAX_CELLS_PER_AXIS)
	_build_rows.append("%5d nodes: build %6d us  (grid %dx%d, cell %.0f px, max_radius %.1f)" % [
		n, t_build, grid.cols, grid.rows, grid.cell, grid.max_radius])

	for reach in _REACHES:
		finder.max_distance = reach
		var set_total := 0
		for s in sources:
			var scan := finder.gather(s, mirror)
			var g := grid.gather(s, reach)
			set_total += scan.size()
			if not _same(scan, g):
				_mismatches += 1
				gut.p("MISMATCH board %d reach %d source %s: scan %d grid %d" % [n, int(reach), s.name, scan.size(), g.size()])
			var phys := _physics_gather(finder, s, mirror, space, params, circle, n)
			if not _same(scan, phys):
				gut.p("note: physics differs from scan board %d reach %d source %s: scan %d phys %d" % [n, int(reach), s.name, scan.size(), phys.size()])
		grid.examined = 0
		for s in sources:
			grid.gather(s, reach)
		var cand := float(grid.examined) / float(_SOURCES)
		var t_scan := _median(func():
			for s in sources:
				finder.gather(s, mirror)) / float(_SOURCES)
		var t_phys := _median(func():
			for s in sources:
				_physics_gather(finder, s, mirror, space, params, circle, n)) / float(_SOURCES)
		var t_grid := _median(func():
			for s in sources:
				grid.gather(s, reach)) / float(_SOURCES)
		var row := "%5d | %4d | %8.0f | %8.0f | %8.0f | %8.0f | %6.0f | %5.1fx" % [
			n, int(reach), t_scan, t_phys, t_grid, cand, float(set_total) / _SOURCES, t_scan / maxf(t_grid, 1.0)]
		gut.p(row)
		_rows.append(row)

	# -- gather_multi ---------------------------------------------------------
	finder.max_distance = _MULTI_REACH
	var scan_multi := finder.gather_multi(sources, mirror)
	var grid_multi := _grid_multi(grid, sources, _MULTI_REACH)
	for s in sources:
		if not _same(scan_multi[s], grid_multi[s]):
			_mismatches += 1
			gut.p("MISMATCH multi board %d source %s" % [n, s.name])
	var tm_scan := _median(func(): finder.gather_multi(sources, mirror))
	var tm_grid := _median(func(): _grid_multi(grid, sources, _MULTI_REACH))
	var tm_phys := _median(func():
		for s in sources:
			_physics_gather(finder, s, mirror, space, params, circle, n))
	_multi_rows.append("%5d nodes: scan %7.0f us | physics %7.0f us | grid %7.0f us | scan/grid %.1fx" % [
		n, tm_scan, tm_phys, tm_grid, tm_scan / maxf(tm_grid, 1.0)])

	# -- cell-size sensitivity on the biggest board ---------------------------
	if count == _BOARDS[-1]:
		for cp in _SENS_CELLS:
			var g2 := Grid.new()
			g2.build(nodes, cp, _MAX_CELLS_PER_AXIS)
			for reach in _REACHES:
				for s in sources:
					if not _same(_scan_at(finder, s, mirror, reach), g2.gather(s, reach)):
						_mismatches += 1
				g2.examined = 0
				for s in sources:
					g2.gather(s, reach)
				var cand2 := float(g2.examined) / _SOURCES
				var t := _median(func():
					for s in sources:
						g2.gather(s, reach)) / float(_SOURCES)
				_sens_rows.append("cell %3d (eff %.0f), reach %4d: %6.0f us, %6.0f cand" % [
					int(cp), g2.cell, int(reach), t, cand2])

	remove_child(graph)
	graph.free()


func _scan_at(finder: EuclideanRangeFinder, s: SkillNode, mirror: GraphMirror, reach: float) -> Dictionary[SkillNode, float]:
	var saved := finder.max_distance
	finder.max_distance = reach
	var r := finder.gather(s, mirror)
	finder.max_distance = saved
	return r


func _grid_multi(grid: Grid, sources: Array[SkillNode], reach: float) -> Dictionary[SkillNode, Dictionary]:
	var out: Dictionary[SkillNode, Dictionary] = {}
	for s in sources:
		out[s] = grid.gather(s, reach)
	return out


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true


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


## Seeded-random sources (distinct), stable_id-sorted pool so the pick is deterministic.
func _pick_sources(nodes: Array[SkillNode]) -> Array[SkillNode]:
	var sorted := nodes.duplicate()
	sorted.sort_custom(func(a: SkillNode, b: SkillNode): return a.stable_id < b.stable_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED
	var out: Array[SkillNode] = []
	while out.size() < _SOURCES:
		var s: SkillNode = sorted[rng.randi() % sorted.size()]
		if not out.has(s):
			out.append(s)
	return out


func _median(fn: Callable) -> float:
	var times: Array[int] = []
	for i in _REPS:
		var t := Time.get_ticks_usec()
		fn.call()
		times.append(Time.get_ticks_usec() - t)
	times.sort()
	@warning_ignore("integer_division")
	return float(times[times.size() / 2])


func _uptime() -> String:
	var out := []
	OS.execute("uptime", [], out)
	return str(out[0]).strip_edges() if not out.is_empty() else "n/a"
