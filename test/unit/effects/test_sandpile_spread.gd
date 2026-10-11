extends GutTest

## [SandpileSpread] — corruption's abelian sandpile, unit-tier over a
## dictionary [StackField]: a host at `T = masked degree + burn + keep` topples,
## sending 1 stack down each masked edge, burning `burn`, keeping `keep`.
## Every assert reads the exports, never their literal defaults.

const POOL := 10
const SEED := 1566
const SWEEPS := 40

const _PLAYER := preload("res://entity/factions/player.tres")
const _NPC := preload("res://entity/factions/npc.tres")

var _me: Entity
var _ally: Entity
var _foe: Entity
var _def: StatusDef
var _pool: Array[NodeCombat] = []
var _spare: Array[SkillNode] = []


func before_all() -> void:
	_me = Entity.new()
	_me.faction = _PLAYER
	_ally = Entity.new()
	_ally.faction = _PLAYER
	_foe = Entity.new()
	_foe.faction = _NPC
	_def = StatusDef.new()
	_def.id = &"pile"
	_def.power_max = 0.0
	_def.reapply = StatusDef.Reapply.ACCUMULATE
	for i in POOL:
		var sn := SkillNode.new()
		sn.owned_by = _me
		_pool.append(sn.get_combat())


func after_all() -> void:
	for c in _pool:
		c.real().free()
	_pool.clear()
	for sn in _spare:
		sn.free()
	_me.free()
	_ally.free()
	_foe.free()


func _put(n: NodeCombat, h: int) -> void:
	n.adjust_status_power(_def, float(h) - n.get_status_power(_def.id))


func _h(n: NodeCombat) -> int:
	return int(n.get_status_power(_def.id))


func _heights(nodes: Array[NodeCombat]) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(_h(n))
	return out


func _total(nodes: Array[NodeCombat]) -> int:
	var t := 0
	for n in nodes:
		t += _h(n)
	return t


## The first `heights.size()` pool slices, set to [param heights], every one a
## sender; undirected [param edges] as index pairs.
func _field(heights: Array, edges: Array, mask: int = SkillNode.Ownership.MINE) -> StackField:
	var nodes := _pool.slice(0, heights.size())
	for i in heights.size():
		_put(nodes[i], heights[i])
	var adj := {}
	for n in nodes:
		adj[n] = [] as Array[NodeCombat]
	for e in edges:
		(adj[nodes[e[0]]] as Array[NodeCombat]).append(nodes[e[1]])
		(adj[nodes[e[1]]] as Array[NodeCombat]).append(nodes[e[0]])
	return StackField.new(_def, mask, adj)


func _settle(rule: SandpileSpread, field: StackField) -> ToppleResult:
	var r := rule.stabilize(field)
	SpreadApplier.apply(_def, r.transfers)
	return r


func _rule(burn: int = -1, keep: int = -1) -> SandpileSpread:
	var r := SandpileSpread.new()
	if burn >= 0:
		r.burn = burn
	if keep >= 0:
		r.keep = keep
	return r


# ── 1: one topple on a chain ──────────────────────────────────────────────────

func _check_leaf_topples_once(rule: SandpileSpread) -> void:
	var t_leaf := 1 + rule.burn + rule.keep
	var f := _field([t_leaf - 1, 0, 0], [[0, 1], [1, 2]])
	assert_eq(rule.threshold(f, _pool[0]), t_leaf, "leaf T = 1 + burn + keep")
	assert_eq(rule.stabilize(f).total_topples(), 0, "T − 1 is stable")
	_put(_pool[0], t_leaf)
	var r := _settle(rule, f)
	assert_eq(r.topples.get(_pool[0], 0), 1, "the leaf toppled once")
	assert_eq(r.total_topples(), 1, "nothing else toppled")
	assert_eq(r.thresholds.get(_pool[0], -1), t_leaf, "thresholds[leaf]")
	assert_eq(_heights(_pool.slice(0, 3)), [rule.keep, 1, 0],
			"1 down the edge, burn burned, keep kept")


func test_leaf_at_threshold_topples_once_defaults() -> void:
	_check_leaf_topples_once(_rule())


func test_leaf_at_threshold_topples_once_with_burn_and_keep() -> void:
	_check_leaf_topples_once(_rule(2, 3))


func test_a_big_pile_topples_by_its_loss_not_by_its_threshold() -> void:
	# An isolated host loses `burn` per topple and keeps `keep`: 20 at burn 2,
	# keep 3 pops 20→18→…→4, eight times — ⌊S / T⌋ would say four.
	var rule := _rule(2, 3)
	var f := _field([20], [])
	var r := _settle(rule, f)
	assert_eq(r.topples.get(_pool[0], 0), 8, "one topple per burn while S ≥ T")
	assert_eq(_h(_pool[0]), 4, "stops below T = burn + keep")


# ── 2: abelian ───────────────────────────────────────────────────────────────

func _random_board(rng: RandomNumberGenerator, n: int) -> Array:
	var edges: Array = []
	for i in range(1, n):
		edges.append([rng.randi_range(0, i - 1), i])
	for _k in rng.randi_range(0, n):
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		if a != b and not ([a, b] in edges or [b, a] in edges):
			edges.append([a, b])
	return edges


func _add(nodes: Array[NodeCombat], amounts: Array) -> void:
	for i in nodes.size():
		_put(nodes[i], _h(nodes[i]) + int(amounts[i]))


func _sum_topples(acc: Dictionary, r: ToppleResult) -> void:
	for k in r.topples:
		acc[k] = acc.get(k, 0) + r.topples[k]


func test_landing_a_then_b_settles_like_a_plus_b() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for sweep in SWEEPS:
		var n := rng.randi_range(3, POOL)
		var edges := _random_board(rng, n)
		var rule := _rule(rng.randi_range(1, 3), rng.randi_range(0, 2))
		var a: Array = []
		var b: Array = []
		var ab: Array = []
		for i in n:
			a.append(rng.randi_range(0, 12))
			b.append(rng.randi_range(0, 12))
			ab.append(a[i] + b[i])
		var nodes := _pool.slice(0, n)

		var f := _field(a, edges)
		var split := {}
		_sum_topples(split, _settle(rule, f))
		_add(nodes, b)
		_sum_topples(split, _settle(rule, f))
		var split_heights := _heights(nodes)

		f = _field(ab, edges)
		var whole := {}
		_sum_topples(whole, _settle(rule, f))
		assert_eq(split_heights, _heights(nodes), "sweep %d: same final piles" % sweep)
		for k in nodes:
			assert_eq(split.get(k, 0), whole.get(k, 0), "sweep %d: same topple counts" % sweep)


# ── 3: conservation and termination ──────────────────────────────────────────

func test_every_topple_burns_burn_and_nothing_else_leaves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	for sweep in SWEEPS:
		var n := rng.randi_range(3, POOL)
		var edges := _random_board(rng, n)
		var rule := _rule(rng.randi_range(1, 3), rng.randi_range(0, 2))
		var heights: Array = []
		for i in n:
			heights.append(rng.randi_range(0, 25))
		var f := _field(heights, edges)
		var nodes := _pool.slice(0, n)
		var before := _total(nodes)
		var r := _settle(rule, f)
		assert_eq(_total(nodes), before - rule.burn * r.total_topples(),
				"sweep %d: total − burn × Σtopples" % sweep)
		for x in nodes:
			assert_lt(_h(x), rule.threshold(f, x), "sweep %d: settled below T" % sweep)


func test_a_big_pile_on_a_hub_terminates_under_the_cap() -> void:
	var rule := _rule()
	var edges := [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [3, 4]]
	var f := _field([600, 0, 0, 0, 0, 0], edges)
	var nodes := _pool.slice(0, 6)
	var r := _settle(rule, f)
	assert_gt(r.total_topples(), 0, "the hub toppled")
	assert_lt(r.total_topples(), rule.max_topples, "ended on its own, not at the cap")
	assert_eq(_total(nodes), 600 - rule.burn * r.total_topples(), "conserved but for the burn")
	for x in nodes:
		assert_lt(_h(x), rule.threshold(f, x), "every host settled")


# ── 4: the mask ──────────────────────────────────────────────────────────────

func _owned_by(e: Entity) -> NodeCombat:
	var sn := SkillNode.new()
	sn.owned_by = e
	_spare.append(sn)
	return sn.get_combat()


func _mixed_field(mask: int) -> Array:
	var c := _pool[0]
	var mine := _pool[1]
	var ally := _owned_by(_ally)
	var foe := _owned_by(_foe)
	var free := _owned_by(null)
	var around: Array[NodeCombat] = [mine, ally, foe, free]
	var adj := {c: around}
	for x in [c, mine]:
		_put(x, 0)
	return [StackField.new(_def, mask, adj), c, mine, ally, foe, free]


func test_mine_or_ally_mask_feeds_and_counts_the_ally_only() -> void:
	var rule := _rule()
	var s: Array = _mixed_field(SkillNode.Ownership.MINE | SkillNode.Ownership.ALLY)
	var f: StackField = s[0]
	var c: NodeCombat = s[1]
	assert_eq(rule.threshold(f, c), 2 + rule.burn + rule.keep, "mine + ally count; foe and unowned do not")
	_put(c, rule.threshold(f, c))
	var r := _settle(rule, f)
	assert_eq(r.topples.get(c, 0), 1, "toppled once")
	assert_eq([_h(c), _h(s[2]), _h(s[3]), _h(s[4]), _h(s[5])], [rule.keep, 1, 1, 0, 0],
			"mine and ally receive; hostile and unowned do not")


func test_mine_mask_leaves_the_ally_out() -> void:
	var rule := _rule()
	var s: Array = _mixed_field(SkillNode.Ownership.MINE)
	assert_eq(rule.threshold(s[0], s[1]), 1 + rule.burn + rule.keep, "only the Mine neighbour counts")


# ── hooks ────────────────────────────────────────────────────────────────────

func test_on_tick_lands_the_stabilized_transfers() -> void:
	var rule := _rule()
	var t := 1 + rule.burn + rule.keep
	var f := _field([t, 0], [[0, 1]])
	var ticked := rule.on_tick(f)
	assert_eq(ticked.size(), rule.stabilize(f).transfers.size(), "on_tick is stabilize's transfers")
	SpreadApplier.apply(_def, ticked)
	assert_eq(_heights(_pool.slice(0, 2)), [rule.keep, 1])


func test_on_removed_spills_nothing() -> void:
	var f := _field([50, 0], [[0, 1]])
	var gone: Array[NodeCombat] = [_pool[0]]
	assert_eq(_rule().on_removed(f, gone, StatusSpread.CAUSE_DEATH).size(), 0, "a removed pile vanishes")
