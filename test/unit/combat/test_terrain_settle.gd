extends GutTest

## #1795 — [TerrainSettle], the one bulk commit of terrain ints: per node, net
## first, then toward zero; Charge clamps at 0; the settle seat's readers fold
## in; then one write per int through [method NodeCombat.add_terrain], which
## announces a band crossing. Fixture: A - B - C, all unallocated.


class StubReader extends TerrainSettle.SettleReader:
	var calls: Array = []
	var bump: NodeCombat = null

	func read(node: NodeCombat, pre_t: int, pre_charge: int,
			post_t: int, post_charge: int, sums: TerrainSettle.Sums) -> void:
		calls.append([node, pre_t, pre_charge, post_t, post_charge])
		if node == bump:
			sums.net_t += 1


var _w: TestWorld
var _a: NodeCombat
var _b: NodeCombat
var _c: NodeCombat
var _fire: Element
var _lightning: Element
## One entry per terrain_band_changed: [SkillNode, Element, from, to].
var _crossings: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	_crossings = []
	_w = TestWorld.create(self)
	var a := _w.add_node(&"A")
	var b := _w.add_node(&"B")
	var c := _w.add_node(&"C")
	_w.link(a, b)
	_w.link(b, c)
	await get_tree().process_frame
	_a = a.get_combat()
	_b = b.get_combat()
	_c = c.get_combat()
	var roster := ElementRoster.shared()
	_fire = roster.by_id(&"fire")
	_lightning = roster.by_id(&"lightning")
	for n: SkillNode in [a, b, c]:
		n.terrain_band_changed.connect(
				func(e: Element, from: ElementBand, to: ElementBand) -> void:
					_crossings.append([n, e, from, to]))


func after_each() -> void:
	CombatWorld.reset_live()


func _ints(n: NodeCombat) -> Array:
	return [n.terrain_t(), n.charge()]


func _put(n: NodeCombat, t: int, charge: int) -> void:
	n.add_terrain(_fire, t - n.terrain_t())
	n.add_terrain(_lightning, charge - n.charge())


func _crossings_on(n: NodeCombat) -> Array:
	return _crossings.filter(func(x: Array) -> bool: return x[0] == n.host)


func _contributions() -> Array:
	return [[_a, &"net", 4], [_b, &"toward", 2], [_a, &"toward", 3],
			[_c, &"charge", -1], [_b, &"net", -6], [_c, &"charge", 3], [_a, &"net", -2]]


func _batch_of(contributions: Array) -> TerrainSettle.Batch:
	var batch := TerrainSettle.Batch.new()
	for c: Array in contributions:
		match c[1]:
			&"net":
				batch.add_net_t(c[0], c[2])
			&"toward":
				batch.add_toward_zero_t(c[0], c[2])
			&"charge":
				batch.add_charge(c[0], c[2])
	return batch


func test_net_lands_before_toward_zero() -> void:
	_put(_a, 3, 0)
	var batch := TerrainSettle.Batch.new()
	batch.add_net_t(_a, -5)
	batch.add_toward_zero_t(_a, 1)
	TerrainSettle.commit(batch)
	assert_eq(_a.terrain_t(), -1, "t=+3, net −5 → −2, then 1 toward zero → −1")


func test_toward_zero_never_crosses_zero() -> void:
	_put(_a, 2, 0)
	_put(_b, -2, 0)
	var batch := TerrainSettle.Batch.new()
	batch.add_toward_zero_t(_a, 5)
	batch.add_toward_zero_t(_b, 5)
	TerrainSettle.commit(batch)
	assert_eq(_a.terrain_t(), 0, "a spend or decay stops at zero from above")
	assert_eq(_b.terrain_t(), 0, "and from below")


func test_charge_clamps_at_zero() -> void:
	_put(_a, 0, 2)
	var batch := TerrainSettle.Batch.new()
	batch.add_charge(_a, -5)
	batch.add_charge(_a, 1)
	TerrainSettle.commit(batch)
	assert_eq(_a.charge(), 0, "2 − 5 + 1 sums to −2, clamped at 0")


func test_a_batch_is_order_independent() -> void:
	var start := [[_a, 1, 0], [_b, 3, 0], [_c, -2, 1]]
	for s: Array in start:
		_put(s[0], s[1], s[2])
	TerrainSettle.commit(_batch_of(_contributions()))
	var forward := [_ints(_a), _ints(_b), _ints(_c)]
	assert_eq(forward, [[0, 0], [-1, 0], [-2, 3]], "sanity: the summed batch")
	for s: Array in start:
		_put(s[0], s[1], s[2])
	var reversed := _contributions()
	reversed.reverse()
	TerrainSettle.commit(_batch_of(reversed))
	assert_eq([_ints(_a), _ints(_b), _ints(_c)], forward, "the same sums in reverse give the same ints")


func test_a_band_crossing_announces_once_per_node_per_commit() -> void:
	var t_a := _a.terrain_threshold()
	var t_c := _c.terrain_threshold()
	var batch := TerrainSettle.Batch.new()
	batch.add_net_t(_a, 1)
	batch.add_net_t(_a, t_a)
	batch.add_net_t(_c, t_c + 3)
	batch.add_toward_zero_t(_c, 3)
	TerrainSettle.commit(batch)
	assert_eq(_a.terrain_t(), t_a + 1, "sanity: two riders summed past T")
	var on_a := _crossings_on(_a)
	assert_eq(on_a.size(), 1, "one announcement, however many riders summed")
	if on_a.size() == 1:
		assert_eq(on_a[0][1], _fire)
		assert_null(on_a[0][2], "from inert")
		assert_eq(on_a[0][3], _a.terrain_band(_fire), "to the band the summed value reads")
	assert_eq(_c.terrain_t(), t_c, "sanity: past T within the sums, back to T in the write")
	assert_eq(_crossings_on(_c).size(), 0, "a band passed only inside the sums is never announced")


func test_the_returned_changed_set_is_exact() -> void:
	_put(_c, 1, 0)
	var batch := TerrainSettle.Batch.new()
	batch.add_net_t(_a, 2)
	batch.add_net_t(_b, 1)
	batch.add_toward_zero_t(_b, 1)
	batch.add_charge(_c, -1)
	var changed := TerrainSettle.commit(batch)
	assert_eq(changed.size(), 1, "only A's ints moved: B nets to 0, C has no Charge to lose")
	assert_true(changed.has(_a))


func test_a_settle_reader_sees_each_node_once_and_its_delta_lands_in_the_one_write() -> void:
	_put(_a, 1, 0)
	var t_b := _b.terrain_threshold()
	var stub := StubReader.new()
	stub.bump = _b
	var readers: Array[TerrainSettle.SettleReader] = [stub]
	var batch := TerrainSettle.Batch.new()
	batch.add_net_t(_a, 2)
	batch.add_net_t(_a, 1)
	batch.add_net_t(_b, t_b)
	TerrainSettle.commit_with(batch, readers)
	assert_eq(stub.calls.size(), 2, "once per node in the batch")
	if stub.calls.size() == 2:
		assert_eq(stub.calls[0], [_a, 1, 0, 4, 0], "the node's pre- and post-batch ints")
		assert_eq(stub.calls[1], [_b, 0, 0, t_b, 0])
	assert_eq(_b.terrain_t(), t_b + 1, "the reader's delta lands")
	assert_eq(_crossings_on(_b).size(), 1, "in the node's one write: one crossing past T")
