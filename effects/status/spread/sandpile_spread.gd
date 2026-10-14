@tool
class_name SandpileSpread
extends StatusSpread

## Corruption's abelian sandpile. A host holding at least its threshold
## `T = masked degree + burn + keep` TOPPLES: 1 stack down each masked edge,
## [member burn] burned, and so at least [member keep] left behind. A pile
## settles fully within one [method stabilize] call. Adds and topples commute
## at fixed degrees, so the fixed point and each host's topple count are
## independent of order: the drain's queue only sequences the loop.
##
## Pure, like every [StatusSpread]: works on a local copy of the field's
## stacks and returns a [ToppleResult]. Deals no damage and knows nothing about
## deaths; the caller turns [member ToppleResult.topples] into bursts
## ([method StatusDef._on_burst]) and re-runs after degrees change.
##
## [method StackField.nodes] seed the drain; a host topples iff
## [method StackField.topples] says so. Any other masked neighbour receives and
## keeps what it gets (an absorber).

## Stacks burned per topple (`B`). At least 1: the sink that guarantees every
## cascade ends (a call topples at most `total stacks / burn` times).
## Tentative, easy to change.
@export_range(1, 10) var burn: int = 1
## Stacks a toppled host keeps (`K`); raises `T` without changing what flows.
## Tentative, easy to change.
@export_range(0, 10) var keep: int = 0
## Safety cap on topples in one [method stabilize] call. `burn ≥ 1` bounds the
## real count well below it, so reaching it is a [method @GlobalScope.push_error],
## not a balance knob.
@export var max_topples: int = 4096


## [param n]'s topple threshold in [param field].
func threshold(field: StackField, n: NodeCombat) -> int:
	return field.masked_degree(n) + burn + keep


## Topple until no field host holds `≥ T`: a DRAIN seeded with
## [method StackField.nodes]. Pop a host; if it holds `≥ T`, bulk-topple it and
## push every masked neighbour that [method StackField.topples] and now holds
## `≥ T`. Cost scales with what topples, never with the field's size; the
## abelian property keeps the fixed point and per-host counts order-free.
## A neighbour's adjacency is asked for only when it is reached, so a lazy
## field may resolve it then. Transfers are per-node nets (see [ToppleResult]),
## so [SpreadApplier]'s debit-first landing is exact.
func stabilize(field: StackField) -> ToppleResult:
	var result := ToppleResult.new()
	var around := {}
	var pile := {}
	var initial := {}
	var order: Array[NodeCombat] = []
	var queue: Array[NodeCombat] = []
	var queued := {}
	for n in field.nodes():
		if not queued.has(n) and field.topples(n):
			queued[n] = true
			queue.append(n)
			_track(field, pile, initial, order, n)
	var step := maxi(1, burn)
	var total := 0
	var head := 0
	while head < queue.size():
		var n := queue[head]
		head += 1
		queued.erase(n)
		var t := _threshold_of(field, around, result, n)
		var s: int = pile[n]
		if s < t:
			continue
		# Each topple removes `degree + burn`, not `T`: pop while S stays ≥ T.
		var loss: int = (around[n] as Array).size() + step
		var k := (s - t) / loss + 1
		if total + k > max_topples:
			k = max_topples - total
		if k <= 0:
			push_error("SandpileSpread: hit max_topples (%d); pile left unstable" % max_topples)
			break
		total += k
		result.topples[n] = result.topples.get(n, 0) + k
		pile[n] = s - k * loss
		for m: NodeCombat in around[n]:
			_track(field, pile, initial, order, m)
			pile[m] += k
			if queued.has(m) or not field.topples(m):
				continue
			if pile[m] >= _threshold_of(field, around, result, m):
				queued[m] = true
				queue.append(m)
	result.transfers = _net_transfers(order, initial, pile, field.key)
	return result


func _threshold_of(field: StackField, around: Dictionary, result: ToppleResult, n: NodeCombat) -> int:
	if not around.has(n):
		around[n] = field.masked_neighbours(n)
		result.thresholds[n] = (around[n] as Array).size() + burn + keep
	return result.thresholds[n]


func settles() -> bool:
	return true


## Nothing: [method CombatWorld.settle_topples] owns every topple, at the tail
## of each beat's flush — the turn end's included, which runs before its
## spread sweep — so the sweep moving stacks here would topple twice.
func on_tick(_field: StackField) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]


## A removed host's stacks vanish (owner call): nothing spills.
func on_removed(_field: StackField, _removed: Array[NodeCombat], _cause: int) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]


func _track(field: StackField, pile: Dictionary, initial: Dictionary,
		order: Array[NodeCombat], n: NodeCombat) -> void:
	if pile.has(n):
		return
	pile[n] = int(field.stacks(n))
	initial[n] = pile[n]
	order.append(n)


## Each shrunk host sends exactly its net loss, greedily onto the grown hosts
## in [param order]; what no host gained is burned.
static func _net_transfers(order: Array[NodeCombat], initial: Dictionary, pile: Dictionary,
		key: Variant) -> Array[StackTransfer]:
	var out: Array[StackTransfer] = []
	var sinks: Array[NodeCombat] = []
	var need := {}
	for n in order:
		var d: int = pile[n] - initial[n]
		if d > 0:
			sinks.append(n)
			need[n] = d
	var i := 0
	for n in order:
		var give: int = initial[n] - pile[n]
		while give > 0 and i < sinks.size():
			var to := sinks[i]
			var amt := mini(give, need[to])
			out.append(StackTransfer.new(n, to, float(amt), key))
			give -= amt
			need[to] -= amt
			if need[to] == 0:
				i += 1
		if give > 0:
			out.append(StackTransfer.new(n, null, float(give), key))
	return out
