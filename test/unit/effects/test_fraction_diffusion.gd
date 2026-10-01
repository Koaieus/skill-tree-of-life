extends GutTest

## [FractionDiffusion]'s floored Metropolis rule, unit-tier over a dictionary
## [StackField]: from the sweep's start snapshot, every masked edge `u→v` with
## `h_u > h_v` moves `⌊fraction · (h_u − h_v) / (1 + max(deg_u, deg_v))⌋`,
## `deg` the [method StackField.masked_degree]. No no-inversion claim: a
## gap-scaled rule can overshoot an edge for a sweep (`2 – 40 – 10` → `14 – 18 – 20`).

const BOARDS := 300
const POOL := 8
const SEED := 1264
const MAX_H := 100
const MAX_SWEEPS := 200
const FRACTIONS := [1.0, 0.5, 0.25]

var _me: Entity
var _def: StatusDef
var _pool: Array[NodeCombat] = []


func before_all() -> void:
	_me = Entity.new()
	_def = StatusDef.new()
	_def.id = &"seep"
	_def.power_max = 0.0  # uncapped
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	for i in POOL:
		var sn := SkillNode.new()
		sn.owned_by = _me
		_pool.append(sn.get_combat())


func after_all() -> void:
	for c in _pool:
		c.real().free()
	_pool.clear()
	_me.free()


func _set_heights(nodes: Array[NodeCombat], heights: Array) -> void:
	for i in nodes.size():
		var n := nodes[i]
		n.adjust_status_power(_def, float(heights[i]) - n.get_status_power(_def.id))


func _heights(nodes: Array[NodeCombat]) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(int(n.get_status_power(_def.id)))
	return out


## A board over the first `heights.size()` pool slices, undirected edges as index pairs.
func _field(heights: Array, edges: Array, order: Array = []) -> StackField:
	var nodes := _pool.slice(0, heights.size())
	_set_heights(nodes, heights)
	var adj := {}
	var keys: Array = order if not order.is_empty() else range(heights.size())
	for i in keys:
		adj[nodes[i]] = [] as Array[NodeCombat]
	for e in edges:
		(adj[nodes[e[0]]] as Array[NodeCombat]).append(nodes[e[1]])
		(adj[nodes[e[1]]] as Array[NodeCombat]).append(nodes[e[0]])
	return StackField.new(_def, SkillNode.Ownership.MINE, adj)


func _rule(fraction: float = 1.0) -> FractionDiffusion:
	var r := FractionDiffusion.new()
	r.fraction = fraction
	return r


func _sweep(heights: Array, edges: Array, fraction: float = 1.0) -> Array:
	var f := _field(heights, edges)
	SpreadApplier.apply(_def, _rule(fraction).on_tick(f))
	return _heights(_pool.slice(0, heights.size()))


func _signature(transfers: Array[StackTransfer]) -> Array:
	var out: Array = []
	for t in transfers:
		out.append("%d>%d:%s" % [_pool.find(t.from), _pool.find(t.to), t.amount])
	out.sort()
	return out


# ── Fixed boards ───────────────────────────────────────────────────────────

func test_two_leaves_ten_zero_level_to_five_five() -> void:
	assert_eq(_sweep([10, 0], [[0, 1]]), [5, 5])


func test_star_hub_fifty_five_leaves_zero_goes_to_ten_and_eights() -> void:
	var edges := [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
	assert_eq(_sweep([50, 0, 0, 0, 0, 0], edges), [10, 8, 8, 8, 8, 8])


func test_a_gap_of_one_moves_nothing() -> void:
	assert_eq(_rule().on_tick(_field([4, 3], [[0, 1]])).size(), 0, "⌊1/2⌋ = 0")


# ── masked_degree ──────────────────────────────────────────────────────────

func test_masked_degree_excludes_a_hostile_neighbour_under_mine() -> void:
	var them := Entity.new()
	var foe_sn := SkillNode.new()
	foe_sn.owned_by = them
	var foe := foe_sn.get_combat()
	var a := _pool[0]
	var adj := {
		a: [_pool[1], _pool[2], foe] as Array[NodeCombat],
		_pool[1]: [a] as Array[NodeCombat],
		_pool[2]: [a] as Array[NodeCombat],
	}
	var f := StackField.new(_def, SkillNode.Ownership.MINE, adj)
	assert_eq(f.masked_degree(a), 2, "the Hostile neighbour is outside the Mine mask")
	assert_eq(f.masked_degree(_pool[1]), 1)
	foe_sn.free()
	them.free()


# ── Property: random connected boards ──────────────────────────────────────

func _random_board(rng: RandomNumberGenerator) -> Array:
	var n := rng.randi_range(2, POOL)
	var heights: Array = []
	for i in n:
		heights.append(rng.randi_range(0, MAX_H))
	var edges: Array = []
	var seen := {}
	for i in range(1, n):  # a random spanning tree keeps it connected
		var j := rng.randi_range(0, i - 1)
		edges.append([j, i])
		seen[Vector2i(j, i)] = true
	for k in rng.randi_range(0, n):  # plus a few chords
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		var key := Vector2i(mini(a, b), maxi(a, b))
		if a != b and not seen.has(key):
			seen[key] = true
			edges.append([key.x, key.y])
	return [heights, edges]


func _sq(h: Array) -> int:
	var s := 0
	for x in h:
		s += x * x
	return s


func _sum(h: Array) -> int:
	var s := 0
	for x in h:
		s += x
	return s


## Every node of [param after] within its closed neighbourhood's `[min, max]` in [param before].
func _within_closed_neighbourhood(before: Array, after: Array, edges: Array) -> bool:
	for i in before.size():
		var lo: int = before[i]
		var hi: int = before[i]
		for e in edges:
			if e[0] == i or e[1] == i:
				var other: int = before[e[1] if e[0] == i else e[0]]
				lo = mini(lo, other)
				hi = maxi(hi, other)
		if after[i] < lo or after[i] > hi:
			return false
	return true


func test_random_boards_conserve_descend_stay_bounded_and_settle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var failures := 0
	for fraction: float in FRACTIONS:
		var rule := _rule(fraction)
		for b in BOARDS:
			var board := _random_board(rng)
			var h: Array = board[0]
			var edges: Array = board[1]
			var nodes := _pool.slice(0, h.size())
			var total := _sum(h)
			var settled := false
			var ok := true
			var after: Array = h
			for sweep in MAX_SWEEPS:
				var transfers := rule.on_tick(_field(h, edges))
				if transfers.is_empty():
					settled = true
					break
				SpreadApplier.apply(_def, transfers)
				after = _heights(nodes)
				ok = _sum(after) == total and _sq(after) < _sq(h) and after.min() >= 0 \
					and _within_closed_neighbourhood(h, after, edges)
				if not ok:
					break
				h = after
			if not (ok and settled):
				failures += 1
				if failures == 1:
					fail_test("fraction %s board %d: settled=%s, %s -> %s over %s"
						% [fraction, b, settled, h, after, edges])
	assert_eq(failures, 0, "every sweep conserves, descends, stays in-neighbourhood; every board settles")


func test_shuffled_iteration_order_yields_the_same_transfers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for fraction: float in FRACTIONS:
		var rule := _rule(fraction)
		for b in 100:
			var board := _random_board(rng)
			var h: Array = board[0]
			var order: Array = range(h.size())
			var base := _signature(rule.on_tick(_field(h, board[1])))
			order.shuffle()
			var shuffled := _signature(rule.on_tick(_field(h, board[1], order)))
			assert_eq(shuffled, base, "fraction %s board %d: order %s" % [fraction, b, order])
