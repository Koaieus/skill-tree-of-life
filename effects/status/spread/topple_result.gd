class_name ToppleResult
extends RefCounted

## What one [method SandpileSpread.stabilize] call settled to — a value, never
## a world write. [member transfers] lands through [SpreadApplier];
## [member topples] and [member thresholds] are what a burst-damage pass
## ([method StatusDef._on_burst]) reads per host.
##
## [member transfers] are PER-NODE NETS, not per-edge flows: each host whose
## pile shrank sends exactly its net loss (≤ what it held, so the applier's
## debit-first pass never floors), paired greedily onto the hosts whose pile
## grew, the remainder burned (`to = null`). A transfer may therefore join two
## non-adjacent hosts; read [member topples] for "who popped", never the list.

var transfers: Array[StackTransfer] = []
## [NodeCombat] → how many times it toppled.
var topples: Dictionary = {}
## [NodeCombat] → its threshold `T` (fixed for the whole call).
var thresholds: Dictionary = {}


## Sum of every host's topple count.
func total_topples() -> int:
	var n := 0
	for c: int in topples.values():
		n += c
	return n
