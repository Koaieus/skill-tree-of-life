class_name RevealTimeline
extends RefCounted

## An ordered schedule of [RevealEvent]s, built by [RevealRecorder] during a
## mutation and consumed by [PresentationPlayer] afterward. See #488.

## Seconds between cascade layers' reveal slots. Lives here (not on the VFX
## consumer) because the stagger is now timeline data authored by the systems
## that record cascades, not a view constant. `AllocationVFX` references this
## constant rather than keeping its own copy.
const CASCADE_STEP: float = 0.35

var events: Array[RevealEvent] = []


func append(e: RevealEvent) -> void:
	events.append(e)


func duration() -> float:
	var d := 0.0
	for e in events:
		d = maxf(d, e.t)
	return d


## Sorts [member events] by [member RevealEvent.t], STABLY. `Array.sort_custom`
## in Godot is not stable, so ties are broken explicitly by original insertion
## index. Equal-`t` events must keep record order — that is the causal order
## they were recorded in (a node's HP change, then its death, then its owner
## loss) and is the death-ordering fix; an unstable sort silently reintroduces
## the bug this timeline exists to fix.
func finalize() -> void:
	var indexed: Array = []
	for i in events.size():
		indexed.append([events[i], i])
	indexed.sort_custom(func(a, b):
		if a[0].t == b[0].t:
			return a[1] < b[1]
		return a[0].t < b[0].t
	)
	var sorted_events: Array[RevealEvent] = []
	for pair in indexed:
		sorted_events.append(pair[0])
	events = sorted_events
