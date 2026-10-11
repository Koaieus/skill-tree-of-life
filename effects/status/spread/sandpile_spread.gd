class_name SandpileSpread
extends StatusSpread

## Corruption's abelian sandpile. A host holding at least its threshold
## `T = masked degree + burn + keep` TOPPLES: 1 stack down each masked edge,
## [member burn] burned, and so at least [member keep] left behind. A pile
## settles fully within one [method stabilize] call. Adds and topples commute
## at fixed degrees, so the fixed point and each host's topple count are
## independent of order: the field-order sweep only sequences the loop.
##
## Pure, like every [StatusSpread]: works on a local copy of the field's
## stacks and returns a [ToppleResult]. Deals no damage and knows nothing about
## deaths; the caller turns [member ToppleResult.topples] into bursts
## ([method StatusDef._on_burst]) and re-runs after degrees change.
##
## Only [method StackField.nodes] topple. A masked neighbour outside the field
## receives and keeps what it gets (an absorber), since the field has no
## adjacency for it to compute a `T` from.

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


## Topple until no field host holds `≥ T`. Transfers are per-node nets (see
## [ToppleResult]), so [SpreadApplier]'s debit-first landing is exact.
func stabilize(field: StackField) -> ToppleResult:
	var result := ToppleResult.new()
	var senders := field.nodes()
	var around := {}
	var pile := {}
	var order: Array[NodeCombat] = []
	for n in senders:
		around[n] = field.masked_neighbours(n)
		result.thresholds[n] = (around[n] as Array).size() + burn + keep
		_track(field, pile, order, n)
		for m: NodeCombat in around[n]:
			_track(field, pile, order, m)
	var initial := pile.duplicate()
	var step := maxi(1, burn)
	var total := 0
	var moved := true
	while moved:
		moved = false
		for n in senders:
			var t: int = result.thresholds[n]
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
				moved = false
				break
			total += k
			moved = true
			result.topples[n] = result.topples.get(n, 0) + k
			pile[n] = s - k * loss
			for m: NodeCombat in around[n]:
				pile[m] += k
	result.transfers = _net_transfers(order, initial, pile, field.key)
	return result


func on_tick(field: StackField) -> Array[StackTransfer]:
	return stabilize(field).transfers


## A removed host's stacks vanish (owner call): nothing spills.
func on_removed(_field: StackField, _removed: Array[NodeCombat], _cause: int) -> Array[StackTransfer]:
	return [] as Array[StackTransfer]


func _track(field: StackField, pile: Dictionary, order: Array[NodeCombat], n: NodeCombat) -> void:
	if pile.has(n):
		return
	pile[n] = int(field.stacks(n))
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
