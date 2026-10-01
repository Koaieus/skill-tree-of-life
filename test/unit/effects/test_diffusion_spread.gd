extends GutTest

## #1260 — [DiffusionSpread]'s edge-local FLAT rule, unit-tier over a
## dictionary [StackField]: from the sweep's start snapshot, `u` moves 1 stack
## to a masked neighbour `v` iff `h_u − h_v ≥ max(min_diff, N_u + M_v)`.

const BOARDS := 500
const POOL := 8
const SEED := 1260
const MAX_H := 8

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


func _sweep(heights: Array, edges: Array) -> Array:
	var f := _field(heights, edges)
	SpreadApplier.apply(_def, DiffusionSpread.new().on_tick(f))
	return _heights(_pool.slice(0, heights.size()))


func _signature(transfers: Array[StackTransfer]) -> Array:
	var out: Array = []
	for t in transfers:
		out.append("%d>%d:%s" % [_pool.find(t.from), _pool.find(t.to), t.amount])
	out.sort()
	return out


# ── Fixed boards ───────────────────────────────────────────────────────────

func test_star_hub_zero_five_leaves_two_moves_nothing() -> void:
	var edges := [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
	var f := _field([0, 2, 2, 2, 2, 2], edges)
	assert_eq(DiffusionSpread.new().on_tick(f).size(), 0, "M_hub = 5 > 2: no leaf feeds it")


func test_chain_three_one_levels_to_two_two() -> void:
	assert_eq(_sweep([3, 1], [[0, 1]]), [2, 2])


func test_chain_five_three_zero_feeds_the_zero_not_the_shallow_three() -> void:
	assert_eq(_sweep([5, 3, 0], [[0, 1], [1, 2]]), [4, 3, 1])


func test_a_diff_below_min_diff_moves_nothing() -> void:
	var f := _field([3, 2], [[0, 1]])
	var rule := DiffusionSpread.new()
	assert_eq(rule.on_tick(f).size(), 0, "diff 1 < min_diff 2")
	f = _field([4, 1], [[0, 1]])
	rule.min_diff = 4
	assert_eq(rule.on_tick(f).size(), 0, "diff 3 < min_diff 4")


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


func test_random_boards_conserve_descend_never_invert_never_revisit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rule := DiffusionSpread.new()
	var failures := 0
	for b in BOARDS:
		var board := _random_board(rng)
		var h: Array = board[0]
		var edges: Array = board[1]
		var nodes := _pool.slice(0, h.size())
		var visited := {str(h): true}
		var total := _sum(h)
		for sweep in 200:
			var f := _field(h, edges)
			var transfers := rule.on_tick(f)
			if transfers.is_empty():
				break
			var before_sq := _sq(h)
			SpreadApplier.apply(_def, transfers)
			var after := _heights(nodes)
			var ok := _sum(after) == total and _sq(after) < before_sq \
				and not visited.has(str(after))
			for t in transfers:
				if t.to == null or t.from.get_status_power(_def.id) < t.to.get_status_power(_def.id):
					ok = false
			if not ok:
				failures += 1
				if failures == 1:
					fail_test("seed %d board %d sweep %d: %s -> %s over %s" % [SEED, b, sweep, h, after, edges])
				break
			visited[str(after)] = true
			h = after
	assert_eq(failures, 0, "every sweep conserves, descends, never inverts, never revisits")


func test_shuffled_iteration_order_yields_the_same_transfers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var rule := DiffusionSpread.new()
	for b in 100:
		var board := _random_board(rng)
		var h: Array = board[0]
		var order: Array = range(h.size())
		var base := _signature(rule.on_tick(_field(h, board[1])))
		order.shuffle()
		var shuffled := _signature(rule.on_tick(_field(h, board[1], order)))
		assert_eq(shuffled, base, "board %d: order %s" % [b, order])
