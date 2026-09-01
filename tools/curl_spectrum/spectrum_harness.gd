class_name SpectrumHarness
extends RefCounted

## #705's measurement run: Cyclone's coefficients swept over ground procgen
## actually makes, instead of over hand-drawn lattices.
##
## Five tables, and they answer different questions — read the header of each
## before quoting a number:
## [codeblock]
## A calibration   idealised terrain, the #703 table, reproduced
## B map-wide rho  whole generated map vs connectivity — an UPPER bound
## C territory rho the induced ball a cast really walks vs connectivity
## D 8-wave damage finite horizon (max_hops = 8), which is what a cast IS
## E closing gain  real SpellResolver casts: what the linear model omits
## [/codeblock]
##
## [b]Map-wide rho is the least useful number here[/b] and is reported only as
## a ceiling. A dominant eigenvalue localises: on 300 nodes it reads whatever
## the single densest patch on the map supports, so it says "somewhere on this
## map, Cyclone could sustain" — never "a cast here does". Table C's territory
## balls and table D's 8-wave totals are the playable readings.
##
## Informative, like `tools/balance/` — see its README. This produces numbers
## and recommends; freezing a coefficient is an owner pinning call (D-13).

const SHIPPED_LABEL := "0.70/0.40/0.20"
const SNAPSHOT_PATH := "res://tools/curl_spectrum/snapshot.md"

## The candidate sets #705 names, plus the shipped one.
##
## `static var`, not `const`: a [PackedFloat32Array] literal is not a constant
## expression in GDScript, and a `const` Dictionary holding one is a parse error
## rather than a runtime one — it takes the whole script down with it.
static var COEFFICIENT_SETS := {
	"0.80/0.30": PackedFloat32Array([0.80, 0.30]),
	"0.70/0.40/0.20": PackedFloat32Array([0.70, 0.40, 0.20]),
	"0.65/0.45/0.25": PackedFloat32Array([0.65, 0.45, 0.25]),
}

## Both shipped topology modules author 0.25 (`procgen/modules/*/topology.tres`);
## the module default is 0.55. The grid is dense under 0.30 because that is
## where the shipped value sits and where the floor was expected.
const CONNECTIVITY_GRID := [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.35, 0.55, 0.75, 1.0]

## `cyclone.tres` authors `max_hops = 8`, and a cast is that finite walk — not
## the limit the spectral radius describes.
const WAVES := 8

## Territory sizes for table C, in nodes: a fresh camp, a mid-run holding, a
## large one. Growing one breadth-first is not a convenience — the shipped
## [TerritorySeeder] runs a [GreedyBfsBallPolicy], so a seeded holding IS a
## ball. It is the DENSEST holding of its size, though (a whole ring before the
## next one), so a stringier real territory pushes the floor up, never down.
const BALL_SIZES := [20, 60, 150]

## The size table D reports its territory column at — a mid-run holding.
const TERRITORY_DOMAIN := 60

## `closing_gain` values probed against real casts in table E — 1.0 is "off",
## 1.35 is shipped.
const CLOSING_GAINS := [1.0, 1.35, 1.70]
const SHIPPED_CLOSING_GAIN := 1.35
## Table E is a spot check, not a sweep: real casts cost seconds each.
const CAST_CONNECTIVITIES := [0.10, 0.25, 0.55]


static func run(root: Node, node_count: int, seeds: int, targets_per_map: int) -> Dictionary:
	return {
		"params": {"node_count": node_count, "seeds": seeds, "targets": targets_per_map},
		"calibration": _calibration(),
		"map_rho": _map_rho(node_count, seeds),
		"territory_rho": _territory_rho(node_count, seeds, targets_per_map),
		"waves": _wave_totals(node_count, seeds, targets_per_map),
		"casts": _cast_probe(root, node_count, seeds),
	}


# ── A: the idealised table, reproduced ─────────────────────────────────────

static func _calibration() -> Array:
	var rows: Array = []
	for terrain in CurlLattices.calibration_set():
		var op := CurlOperator.build(terrain)
		var row := {"label": terrain.label, "edges": terrain.edge_count(), "rho": {}}
		for name in COEFFICIENT_SETS:
			row["rho"][name] = op.spectral_radius(COEFFICIENT_SETS[name])
		rows.append(row)
	return rows


# ── B: whole-map spectral radius vs connectivity ───────────────────────────

static func _map_rho(node_count: int, seeds: int) -> Array:
	var rows: Array = []
	for connectivity in CONNECTIVITY_GRID:
		var row := {"connectivity": connectivity, "rho": {}, "degree": 0.0}
		var per_set := {}
		for name in COEFFICIENT_SETS:
			per_set[name] = []
		var degrees: Array[float] = []
		for s in seeds:
			var terrain := CurlProcgenTerrain.sample(_seed_value(s), node_count, connectivity)
			degrees.append(2.0 * float(terrain.edge_count()) / float(terrain.positions.size()))
			var op := CurlOperator.build(terrain)
			for name in COEFFICIENT_SETS:
				(per_set[name] as Array).append(op.spectral_radius(COEFFICIENT_SETS[name]))
		for name in COEFFICIENT_SETS:
			row["rho"][name] = _mean(per_set[name])
		row["degree"] = _mean(degrees)
		rows.append(row)
	return rows


# ── C: the ball a cast actually walks ──────────────────────────────────────

static func _territory_rho(node_count: int, seeds: int, targets_per_map: int) -> Array:
	var rows: Array = []
	for connectivity in CONNECTIVITY_GRID:
		var row := {"connectivity": connectivity, "rho": {}, "sustaining": {}}
		var per_key := {}
		for size in BALL_SIZES:
			for name in COEFFICIENT_SETS:
				per_key["%d|%s" % [size, name]] = []
		for s in seeds:
			var terrain := CurlProcgenTerrain.sample(_seed_value(s), node_count, connectivity)
			for target in _sample_targets(terrain, targets_per_map):
				for size in BALL_SIZES:
					var ball: CurlTerrain = terrain.bfs_ball(target, size)["terrain"]
					var op := CurlOperator.build(ball)
					for name in COEFFICIENT_SETS:
						(per_key["%d|%s" % [size, name]] as Array).append(
								op.spectral_radius(COEFFICIENT_SETS[name]))
		for key in per_key:
			row["rho"][key] = _mean(per_key[key])
			row["sustaining"][key] = _share_at_least(per_key[key], 1.0)
		rows.append(row)
	return rows


# ── D: the finite walk a cast actually is ──────────────────────────────────

static func _wave_totals(node_count: int, seeds: int, targets_per_map: int) -> Array:
	var rows: Array = []
	for connectivity in CONNECTIVITY_GRID:
		var row := {
			"connectivity": connectivity,
			"total": {}, "last_growth": {}, "profile": {}, "total_ball": {},
		}
		var totals := {}
		var growth := {}
		var profiles := {}
		var ball_totals := {}
		for name in COEFFICIENT_SETS:
			totals[name] = []
			growth[name] = []
			profiles[name] = []
			ball_totals[name] = []
		for s in seeds:
			var terrain := CurlProcgenTerrain.sample(_seed_value(s), node_count, connectivity)
			var op := CurlOperator.build(terrain)
			for target in _sample_targets(terrain, targets_per_map):
				# The same eight waves confined to the holding the OwnerFilter
				# would actually let a cast walk. `bfs_ball` grows out of the
				# target, so the target is index 0 of the ball it returns.
				var ball: CurlTerrain = terrain.bfs_ball(target, TERRITORY_DOMAIN)["terrain"]
				var ball_op := CurlOperator.build(ball)
				for ball_from in ball.adjacency[0]:
					for name in COEFFICIENT_SETS:
						var ball_waves := ball_op.wave_energies(
								ball_from, 0, COEFFICIENT_SETS[name], WAVES)
						if ball_waves.is_empty():
							continue
						var ball_total := 1.0
						for e in ball_waves:
							ball_total += e
						(ball_totals[name] as Array).append(ball_total)
				for from_index in terrain.adjacency[target]:
					for name in COEFFICIENT_SETS:
						var energies := op.wave_energies(
								from_index, target, COEFFICIENT_SETS[name], WAVES)
						if energies.is_empty():
							continue
						var total := 1.0  # the seed impact itself
						for e in energies:
							total += e
						(totals[name] as Array).append(total)
						(growth[name] as Array).append(
								energies[WAVES - 1] / maxf(energies[WAVES - 2], 1e-30))
						(profiles[name] as Array).append(energies)
		for name in COEFFICIENT_SETS:
			row["total"][name] = _mean(totals[name])
			row["total_ball"][name] = _mean(ball_totals[name])
			row["last_growth"][name] = _mean(growth[name])
			row["profile"][name] = _mean_profile(profiles[name])
		rows.append(row)
	return rows


# ── E: what the linear model cannot see ────────────────────────────────────

static func _cast_probe(root: Node, node_count: int, seeds: int) -> Array:
	var rows: Array = []
	if root == null:
		return rows
	for connectivity in CAST_CONNECTIVITIES:
		var row := {
			"connectivity": connectivity,
			"linear": 0.0,
			"cast": {},
			"samples": 0,
			"linear_profile": PackedFloat64Array(),
			"cast_profile": PackedFloat64Array(),
		}
		var linear: Array[float] = []
		var linear_profiles: Array = []
		var cast_profiles: Array = []
		var per_gain := {}
		for gain in CLOSING_GAINS:
			per_gain[gain] = []
		for s in seeds:
			var terrain := CurlProcgenTerrain.sample(_seed_value(s), node_count, connectivity)
			var caster := _caster_index(terrain)
			var target := CurlCastProbe.castable_neighbour(terrain, caster)
			if target < 0:
				continue
			var op := CurlOperator.build(terrain)
			var energies := op.wave_energies(
					caster, target, COEFFICIENT_SETS[SHIPPED_LABEL], WAVES)
			var predicted := 1.0
			for e in energies:
				predicted += e
			linear.append(predicted)
			linear_profiles.append(energies)
			var probe := CurlCastProbe.build(terrain, caster, root)
			for gain in CLOSING_GAINS:
				var measured := probe.wave_damage(target, caster, {"closing_gain": gain})
				var total := 0.0
				for value in measured:
					total += value
				(per_gain[gain] as Array).append(total)
				if is_equal_approx(gain, SHIPPED_CLOSING_GAIN):
					cast_profiles.append(_drop_seed_beat(measured))
			probe.graph.queue_free()
			row["samples"] = row["samples"] + 1
		row["linear"] = _mean(linear)
		row["linear_profile"] = _mean_profile(linear_profiles)
		row["cast_profile"] = _mean_profile(cast_profiles)
		for gain in CLOSING_GAINS:
			row["cast"][gain] = _mean(per_gain[gain])
		rows.append(row)
	return rows


# ── Sampling helpers ───────────────────────────────────────────────────────

## Seeds are fixed constants, not rolled: a sweep somebody re-runs after
## retuning has to walk the SAME ground as the run it is compared against.
static func _seed_value(index: int) -> int:
	return 1_000_003 + index * 7919


## `count` castable nodes spread evenly through the map's target list, so the
## sample is not all one corner and does not move between coefficient sets.
static func _sample_targets(terrain: CurlTerrain, count: int) -> PackedInt32Array:
	var castable := CurlProcgenTerrain.castable_targets(terrain)
	var out := PackedInt32Array()
	if castable.is_empty():
		return out
	var stride := maxi(1, castable.size() / maxi(1, count))
	var i := 0
	while i < castable.size() and out.size() < count:
		out.append(castable[i])
		i += stride
	return out


## A node with a castable neighbour, for the cast probe to stand on. Interior,
## not the first index: the rim is where Poisson's boundary effects live.
static func _caster_index(terrain: CurlTerrain) -> int:
	var best := 0
	var best_degree := -1
	for i in terrain.positions.size():
		if terrain.degree(i) > best_degree and CurlCastProbe.castable_neighbour(terrain, i) >= 0:
			best_degree = terrain.degree(i)
			best = i
	return best


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


static func _share_at_least(values: Array, threshold: float) -> float:
	if values.is_empty():
		return 0.0
	var hits := 0
	for v in values:
		if float(v) >= threshold:
			hits += 1
	return float(hits) / float(values.size())


## A cast profile is indexed by BEAT, and beat 0 is the seed impact — which the
## operator's `wave_energies` does not include, since it starts one hop in.
## Dropping it is what makes the two comparable term by term.
static func _drop_seed_beat(profile: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(1, profile.size()):
		out.append(profile[i])
	return out


static func _mean_profile(profiles: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if profiles.is_empty():
		return out
	out.resize(WAVES)
	for p in profiles:
		for i in mini(WAVES, (p as PackedFloat64Array).size()):
			out[i] += p[i]
	for i in out.size():
		out[i] /= float(profiles.size())
	return out
