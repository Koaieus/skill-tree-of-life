extends GutTest
## Ranged-design geometry probe (design session 2026-09-18, ranged role):
## the numbers two proposals are gated on, measured on the shipped preset.
##
## Run: [code]mise run test:one -- res://test/perf/bench_ranged_geometry.gd[/code]
## Not collected by the suite (`test/perf/` + `bench_` prefix is the opt-out).
##
## 1. Spacing — node radius, edge length, nearest-neighbour centre distance.
##    A "focus radius" in px is meaningless until these are known.
## 2. Focus disc — how many nodes a disc of radius R centred on a node's centre
##    touches (dist <= R + other.radius), excluding itself.
## 3. Lanes choice metric (Arc's gate) — walking the graph path from each start
##    toward its nearest rival start, at each step how many neighbours would
##    give a leaf pointing within 45° / 90° of the bearing to the rival. Median
##    0–1 ⇒ allocation is never aiming, lanes are luck.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")

const _SEEDS: Array[int] = [0x57A17EE, 1, 2, 3, 4]
const _FOCUS_RADII: Array[float] = [40.0, 80.0, 120.0, 160.0]


func test_geometry() -> void:
	var radii: Array[float] = []
	var edge_lens: Array[float] = []
	var nn_dists: Array[float] = []
	var disc_counts: Dictionary = {}
	for r in _FOCUS_RADII:
		disc_counts[r] = [] as Array[float]
	var choice45: Array[float] = []
	var choice90: Array[float] = []
	var degrees: Array[float] = []

	for seed in _SEEDS:
		var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
		cfg.seed = seed
		var graph: Graph = _GRAPH_SCENE.instantiate()
		add_child(graph)
		var result: Dictionary = await GraphProcgen.generate(cfg, graph)
		await get_tree().physics_frame
		var nodes: Array[SkillNode] = graph.get_skill_nodes()
		var starts: Array[SkillNode] = result.get("starting_nodes", [] as Array[SkillNode])
		gut.p("seed %d: %d nodes, %d starts" % [seed, nodes.size(), starts.size()])

		# -- 1. spacing ----------------------------------------------------
		for n in nodes:
			radii.append(n.radius)
			var deg := graph.get_neighbours(n).size()
			degrees.append(float(deg))
			var best := INF
			for m in nodes:
				if m == n:
					continue
				var d := n.global_position.distance_to(m.global_position)
				if d < best:
					best = d
			nn_dists.append(best)
			for m in graph.get_neighbours(n):
				if n.get_instance_id() < m.get_instance_id():
					edge_lens.append(n.global_position.distance_to(m.global_position))
			# -- 2. focus disc ---------------------------------------------
			for r in _FOCUS_RADII:
				var hit := 0
				for m in nodes:
					if m == n:
						continue
					if n.global_position.distance_to(m.global_position) <= r + m.radius:
						hit += 1
				(disc_counts[r] as Array[float]).append(float(hit))

		# -- 3. lanes choice metric --------------------------------------
		var mirror: GraphMirror = graph.navigator
		# The bare preset carries no start anchors (those come from the
		# scenario), so sample start/rival pairs at camp-like separations.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var pairs := 0
		while pairs < 12:
			var s: SkillNode = nodes[rng.randi_range(0, nodes.size() - 1)]
			var rival: SkillNode = nodes[rng.randi_range(0, nodes.size() - 1)]
			var sep := s.global_position.distance_to(rival.global_position)
			if sep < 600.0 or sep > 1600.0:
				continue
			pairs += 1
			var path: Array[SkillNode] = mirror.path_between(s, rival)
			# Every node on the path short of the rival is a frontier the
			# expanding player stands on; the predecessor is already owned.
			for i in range(path.size() - 1):
				var f := path[i]
				var prev: SkillNode = path[i - 1] if i > 0 else null
				var bearing := (rival.global_position - f.global_position).normalized()
				var c45 := 0
				var c90 := 0
				for nb in graph.get_neighbours(f):
					if nb == prev:
						continue
					var dir := (nb.global_position - f.global_position).normalized()
					var ang := rad_to_deg(acos(clampf(bearing.dot(dir), -1.0, 1.0)))
					if ang <= 45.0:
						c45 += 1
					if ang <= 90.0:
						c90 += 1
				choice45.append(float(c45))
				choice90.append(float(c90))
		graph.queue_free()
		await get_tree().process_frame

	gut.p("\n=== spacing (px) ===")
	gut.p("node radius        " + _stats(radii))
	gut.p("edge length        " + _stats(edge_lens))
	gut.p("nearest-nbr centre " + _stats(nn_dists))
	gut.p("graph degree       " + _stats(degrees))
	gut.p("\n=== focus disc: other nodes touched by a disc centred on a node ===")
	for r in _FOCUS_RADII:
		gut.p("R=%3d px  %s" % [int(r), _stats(disc_counts[r])])
	gut.p("\n=== lanes choice metric: neighbours pointing toward the rival, per frontier step ===")
	gut.p("within 45°  " + _stats(choice45))
	gut.p("within 90°  " + _stats(choice90))
	gut.p("share of steps with >=2 choices within 45°: %.2f" % _share_ge(choice45, 2.0))
	gut.p("share of steps with  0 choices within 45°: %.2f" % _share_ge(choice45, 0.0, true))
	assert_true(true)


func _stats(a: Array[float]) -> String:
	if a.is_empty():
		return "(none)"
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	var n := s.size()
	return "n=%d min=%.1f p10=%.1f med=%.1f mean=%.1f p90=%.1f max=%.1f" % [
		n, s[0], s[int(n * 0.1)], s[n / 2], sum / n, s[mini(int(n * 0.9), n - 1)], s[n - 1]]


func _share_ge(a: Array[float], k: float, equal_only: bool = false) -> float:
	if a.is_empty():
		return 0.0
	var c := 0
	for v in a:
		if (equal_only and is_equal_approx(v, k)) or (not equal_only and v >= k):
			c += 1
	return float(c) / a.size()
