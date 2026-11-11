class_name TerrainSettle
extends RefCounted

## STUB (#1795 red): the shapes only.


class Sums:
	extends RefCounted
	var net_t: int = 0
	var toward_zero_t: int = 0
	var charge: int = 0


class Batch:
	extends RefCounted
	var _sums: Dictionary = {}

	func sums(node: NodeCombat) -> Sums:
		var s: Sums = _sums.get(node)
		if s == null:
			s = Sums.new()
			_sums[node] = s
		return s

	func add_net_t(node: NodeCombat, delta: int) -> void:
		sums(node).net_t += delta

	func add_toward_zero_t(node: NodeCombat, amount: int) -> void:
		sums(node).toward_zero_t += maxi(amount, 0)

	func add_charge(node: NodeCombat, delta: int) -> void:
		sums(node).charge += delta

	func nodes() -> Array[NodeCombat]:
		var out: Array[NodeCombat] = []
		out.assign(_sums.keys())
		return out

	func is_empty() -> bool:
		return _sums.is_empty()


class SettleReader:
	extends RefCounted

	func read(_node: NodeCombat, _pre_t: int, _pre_charge: int,
			_post_t: int, _post_charge: int, _sums: Sums) -> void:
		pass


static func seat() -> Array[SettleReader]:
	var out: Array[SettleReader] = []
	return out


static func commit(batch: Batch) -> Array[NodeCombat]:
	return commit_with(batch, seat())


static func commit_with(_batch: Batch, _readers: Array[SettleReader]) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	return out
