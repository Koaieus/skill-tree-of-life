class_name TerrainSettle
extends RefCounted

## The ONE bulk commit of terrain ints (#1795; `docs/domain/elements.md` §
## Flow). A [TerrainSettle.Batch] holds per-node sums computed against one
## snapshot; [method commit] applies each node's sums (net first, then toward
## zero; Charge clamped at 0), runs the settle seat's readers, and writes the
## result once per int through [method NodeCombat.add_terrain] — the writer
## that announces a band crossing and keeps the live index in step. Callers:
## the world turn's pass ([method CombatWorld.flow_temperature]: once per
## diffusion step, once for decay) and #1798's beat (a land batch and a spend
## batch per generation). Nothing else writes terrain ints in bulk. Static,
## integer only, roll-free, no transcendental: every peer reproduces it.


## One node's sums in a batch.
class Sums:
	extends RefCounted
	## Signed: riders and flow. Nets through zero.
	var net_t: int = 0
	## >= 0: spends and decay. Pulls t toward zero, never across it.
	var toward_zero_t: int = 0
	## Signed; the result clamps at 0.
	var charge: int = 0


## Per-node sums, insertion-ordered. The order never reaches the result: a
## node's sums commute and its write is its own.
class Batch:
	extends RefCounted
	var _sums: Dictionary = {}  # NodeCombat -> Sums

	## [param node]'s sums, opened on first ask.
	func sums(node: NodeCombat) -> Sums:
		var s: Sums = _sums.get(node)
		if s == null:
			s = Sums.new()
			_sums[node] = s
		return s

	func add_net_t(node: NodeCombat, delta: int) -> void:
		sums(node).net_t += delta

	## [param amount] >= 0; a negative one is a caller's bug and adds nothing.
	func add_toward_zero_t(node: NodeCombat, amount: int) -> void:
		assert(amount >= 0, "TerrainSettle: toward_zero_t is never negative")
		sums(node).toward_zero_t += maxi(amount, 0)

	func add_charge(node: NodeCombat, delta: int) -> void:
		sums(node).charge += delta

	func nodes() -> Array[NodeCombat]:
		var out: Array[NodeCombat] = []
		out.assign(_sums.keys())
		return out

	func is_empty() -> bool:
		return _sums.is_empty()


## The settle seat: a reader sees one node's ints before the batch and after
## it, and may add to that node's [param sums] before the one write (#1801's
## prime conversion is the first). It writes nothing itself and rolls nothing.
class SettleReader:
	extends RefCounted

	func read(_node: NodeCombat, _pre_t: int, _pre_charge: int,
			_post_t: int, _post_charge: int, _sums: Sums) -> void:
		pass


## Stub (#1801 C, red first).
class PrimeConversion:
	extends SettleReader
	var def: CatalystStatus

	func _init(catalyst: CatalystStatus) -> void:
		def = catalyst


## The readers every [method commit] runs. Empty until #1801 seats the first.
static func seat() -> Array[SettleReader]:
	var out: Array[SettleReader] = []
	return out


## Commit [param batch] with the seat's readers. Returns the nodes whose ints
## moved.
static func commit(batch: Batch) -> Array[NodeCombat]:
	return commit_with(batch, seat())


## Commit [param batch] with [param readers]: per node, the post-batch ints
## from its sums; each reader once; the ints again with the readers' deltas
## folded in; then one [method NodeCombat.add_terrain] per int that moved
## (Fire for t, Lightning for Charge). Returns the nodes whose ints moved.
static func commit_with(batch: Batch, readers: Array[SettleReader]) -> Array[NodeCombat]:
	var changed: Array[NodeCombat] = []
	if batch == null or batch.is_empty():
		return changed
	var heat := element_on(Terrain.Axis.HEAT)
	var charge := element_on(Terrain.Axis.CHARGE)
	for node in batch.nodes():
		if node == null:
			continue
		var s := batch.sums(node)
		var pre_t := node.terrain_t()
		var pre_c := node.charge()
		var post_t := settled_t(pre_t, s)
		var post_c := settled_charge(pre_c, s)
		if not readers.is_empty():
			for r in readers:
				r.read(node, pre_t, pre_c, post_t, post_c, s)
			post_t = settled_t(pre_t, s)
			post_c = settled_charge(pre_c, s)
		if post_t != pre_t:
			node.add_terrain(heat, post_t - pre_t)
		if post_c != pre_c:
			node.add_terrain(charge, post_c - pre_c)
		if post_t != pre_t or post_c != pre_c:
			changed.append(node)
	return changed


## [param t] after [param s]: the net first, then toward zero, never across it.
static func settled_t(t: int, s: Sums) -> int:
	var v := t + s.net_t
	var pull := mini(absi(v), maxi(s.toward_zero_t, 0))
	return v - pull if v > 0 else v + pull


## [param charge] after [param s], clamped at 0.
static func settled_charge(charge: int, s: Sums) -> int:
	return maxi(charge + s.charge, 0)


## [param node]'s decay this world turn on [param element]'s count: the rate
## its band answers ([member ElementBand.decay_per_world_turn]), or the
## element's own ([member Element.decay_per_world_turn]) at or below T, where
## the band is null.
static func decay_rate(node: NodeCombat, element: Element) -> int:
	if element == null:
		return 0
	var band := node.terrain_band(element)
	return band.decay_per_world_turn if band != null else element.decay_per_world_turn


## The roster's element on [param axis] (Fire, Ice, Lightning); null if none.
static func element_on(axis: Terrain.Axis) -> Element:
	for e in ElementRoster.shared().elements:
		if Terrain.axis_of(e) == axis:
			return e
	return null
