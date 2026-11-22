## Graph-wide Heat / Cold / Charge bookkeeping, one sample per world turn.
##
## A sample is `{ &"heat": {...}, &"cold": {...}, &"charge": {...} }`, each
## element a Dictionary of ints keyed `produced`, `effect`, `voided`,
## `decayed`, `onto_opposite`, `from_opposite`, `total` (Charge has no
## opposite: its two opposite keys stay 0). Per element, every closed sample
## satisfies Δtotal = produced + effect − voided − decayed − onto_opposite
## + from_opposite. Session-only debug telemetry: never saved, never synced.
## Counts live landings only; a shadow resolve adds nothing.
extends Node
class_name TerrainLedger

## Closed once per world turn, oldest first in [method samples].
signal sample_closed(sample: Dictionary)

const ELEMENTS: Array[StringName] = [&"heat", &"cold", &"charge"]
const FIELDS: Array[StringName] = [
	&"produced", &"effect", &"voided", &"decayed",
	&"onto_opposite", &"from_opposite", &"total",
]

## World turns kept (tentative, easy to change).
@export_range(5, 400) var window_turns: int = 40

var _samples: Array[Dictionary] = []
var _current: Dictionary = empty_sample()


## The closed samples, oldest first, at most [member window_turns].
func samples() -> Array[Dictionary]:
	return _samples


## The open sample for this world turn.
func current() -> Dictionary:
	return _current


static func empty_sample() -> Dictionary:
	var s := {}
	for e in ELEMENTS:
		var row := {}
		for f in FIELDS:
			row[f] = 0
		s[e] = row
	return s
