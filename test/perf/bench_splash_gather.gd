extends GutTest
## #1482: does the per-volley splash gather cache ([member HitLanding.gather_cache])
## earn its place? A volley of Euclidean-splash arrows on a 3k-node board,
## compiled with one shared cache (what [RangedAttackPlan] does) vs a fresh
## one per arrow (every arrow sweeps the board).
##
## Run: [code]mise run test:one -- res://test/perf/bench_splash_gather.gd[/code]
## Not collected by the suite (see `bench_allocation_cost.gd` for why `test/perf/`
## + the `bench_` prefix is the whole opt-out).
##
## What is timed is the volley's riders pass — [method RangedDamageFormula.compute]
## + [method RangedDamageFormula.riders_for] per arrow, the only part of a
## ranged compile the cache touches. [EuclideanRangeFinder.gather] is a full
## linear scan whatever the radius, so the uncached cost is ~arrows × one scan.
## The mask is HOSTILE on an unowned board: the blast emits on the target only,
## so the numbers are the gather, not the damage hits.
##
## Measured 2026-10-08 (dev desktop CPU, load 0.74; a CPU cost — the GPU plays no part), riders pass, off → on:
## 20 arrows one radius 76.9 → 4.2 ms; 10+10 two radii 77.0 → 8.1 ms;
## 100 arrows 383.7 → 5.6 ms; 50+50 388.5 → 9.7 ms. One sweep ≈ 3.8 ms at 3k
## nodes, far above the ~1 ms bar: the cache earns its place.
##
## Numbers move with the machine AND with box load — record `uptime` alongside.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PRESET := preload("res://procgen/presets/first_level/first_level.tres")

const _SEED := 0x5A1A54
const _NODES := 3000
const _RADII: Array[float] = [300.0, 600.0]
const _REPS := 10

var _graph: Graph
var _attacker: Entity
var _firing: SkillNode
var _target: SkillNode


func test_bench_cache_on_vs_off() -> void:
	gut.p("--- load: %s ---" % _uptime())
	var cfg: GraphProcgenConfig = _PRESET.duplicate(true)
	cfg.topology = cfg.topology.duplicate(true)
	cfg.topology.node_count = _NODES
	cfg.seed = _SEED
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	await GraphProcgen.generate(cfg, _graph)
	_attacker = Entity.new()
	_attacker.stat_board = TestBoards.flat_entity_board()
	_graph.entities_container.add_child(_attacker)
	autofree(_attacker)
	await get_tree().process_frame
	assert_not_null(_attacker.navigator, "the attacker has a navigator, or every gather is empty")
	var nodes := _graph.navigator.get_mirrored_nodes()
	_firing = nodes[0]
	_target = nodes[nodes.size() / 2]
	gut.p("--- board: %d nodes ---" % nodes.size())

	var one := _blast(_RADII[0])
	var two := _blast(_RADII[1])
	var probe := one.on_hit_effects[0].range_finder.gather(_target, _graph.navigator) as Dictionary
	assert_gt(probe.size(), 1, "the radius reaches past the target")
	gut.p("  gathered at r=%d: %d nodes" % [int(_RADII[0]), probe.size()])

	gut.p("\nvolley                  | cache off | cache on | speedup")
	for n in [20, 100]:
		_row("%d arrows, one radius" % n, _repeat(one, n))
		var split := _repeat(one, n / 2)
		split.append_array(_repeat(two, n / 2))
		_row("%d+%d, two radii" % [n / 2, n / 2], split)


func _row(label: String, ammo: Array[AmmoType]) -> void:
	var off := _median(func(): _compile(ammo, false))
	var on := _median(func(): _compile(ammo, true))
	gut.p("%-23s | %6.2f ms | %5.2f ms | %5.1fx" % [label, off / 1000.0, on / 1000.0,
			off / maxf(on, 1.0)])


## The riders pass of one volley: [param shared] = one cache for every arrow.
func _compile(ammo: Array[AmmoType], shared: bool) -> void:
	var cache := {}
	for a in ammo:
		var arrow := RangedDamageFormula.compute(_attacker, _firing, _target, a)
		RangedDamageFormula.riders_for(arrow, cache if shared else {})


func _blast(r: float) -> AmmoType:
	var finder := EuclideanRangeFinder.new()
	finder.max_distance = r
	var splash := SplashEffect.new()
	splash.inner = PairedDamageEffect.new()
	splash.ownership_filter = SkillNode.Ownership.HOSTILE
	splash.range_finder = finder
	var ammo := AmmoType.new()
	ammo.id = &"bench_blast"
	ammo.on_hit_effects = [splash]
	return ammo


func _repeat(ammo: AmmoType, n: int) -> Array[AmmoType]:
	var out: Array[AmmoType] = []
	for _i in n:
		out.append(ammo)
	return out


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
