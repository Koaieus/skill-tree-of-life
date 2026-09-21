@tool
class_name TableScale
extends DistanceScale

## A per-step multiplier list — `5, -4, 3, -2, 1` — indexed by the rounded
## distance. The one shape no continuous scale can author: it alternates
## sign and stops dead. The designer types the list; nothing is derived.
##
## [b]Wants a hop metric.[/b] The index is `int(round(d))` of whatever the
## aura's metric measured — on a hop metric that is the hop count; on a
## euclidean metric it is whole pixels, which is almost never what a list
## means.
##
## [b]Past the end is absence, not 0.[/b] With [member past_end] at
## [constant PastEnd.NOT_GRANTED] a node beyond the last entry gets
## [constant DistanceScale.NOT_GRANTED] — no ledger row under any
## [member AuraEffect.discard], unlike a `0` entry, which under `discard =
## NONE` is a real +0. [constant PastEnd.HOLD_LAST] repeats the last entry
## instead — the "ramp, then flat" shape. An empty table is
## [constant DistanceScale.NOT_GRANTED] everywhere, and says so in the editor.
##
## A multiplier table, per the library convention: the result is
## `value * per_step[i]`. The cheapest scale there is — one array read — and
## it never reads the bound.

enum PastEnd {
	## Beyond the last entry: [constant DistanceScale.NOT_GRANTED].
	NOT_GRANTED,
	## Beyond the last entry: the last entry, forever.
	HOLD_LAST,
}

## Multiplier at step 0, 1, 2, … — `d` rounded to the nearest whole step.
@export var per_step: Array[float] = []:
	set(v):
		per_step = v
		# A Resource has no configuration-warning slot; the editor hears it
		# in the output panel instead, once per edit, never per node.
		if Engine.is_editor_hint() and per_step.is_empty():
			push_warning("TableScale: per_step is empty, so this scale grants nothing anywhere.")

## What a distance past the last entry gets.
@export var past_end: PastEnd = PastEnd.NOT_GRANTED


func scale(distance: float, _max_distance: float, value: float) -> float:
	var count := per_step.size()
	if count == 0:
		return NOT_GRANTED
	var i := int(roundf(distance))
	if i < 0:
		i = 0
	if i >= count:
		if past_end == PastEnd.HOLD_LAST:
			i = count - 1
		else:
			return NOT_GRANTED
	return value * per_step[i]
