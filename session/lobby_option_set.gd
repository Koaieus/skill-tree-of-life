@tool
class_name LobbyOptionSet
extends Resource

## The ordered ladder one run-section picker offers (#642 acceptance 6, #597 D13).
##
## [b]An authored Array, never a directory scan[/b], and the first ground is
## decisive on its own: [i]order is information[/i]. XS -> S -> M -> L -> XL ->
## XXL is a sequence a player reads as one, and `DirAccess.get_files_at` would
## hand back `l, m, s, xl, xs, xxl` — alphabetical noise presented as a ladder.
## The second ground is that an `@export` array is a hard dependency edge that
## survives export while a scan is not (#640). The general rule this instantiates:
## directory scan for editor and test code, authored array for runtime.

## The options this picker lists, in dropdown order. Authored order IS the
## presented order — nothing sorts this.
@export var options: Array[LobbyOption] = []

## Which [member choices] entry the picker shows pre-selected, so a fresh lobby
## doesn't hand the host a blank dropdown. Display only: it does not count as a
## pick, so [OptionChoiceRow] never reports it through `option_picked` and it
## writes no [ScenarioOverride] on its own (#643 acceptance 5 is unaffected —
## that governs what a pick WRITES, not what the widget shows before one
## happens). `-1` is legal and means "no sensible default", falling back to
## blank. Author it to match the preset this ladder's route actually runs —
## nothing re-derives it from the preset automatically, so it drifts if the
## preset's authored value changes without this being re-checked.
@export var default_index: int = -1


## [member options] with nulls dropped, which is what a picker should actually
## list. An authored array with an empty slot is an editing accident, not a
## separator.
func choices() -> Array[LobbyOption]:
	var out: Array[LobbyOption] = []
	for o in options:
		if o != null:
			out.append(o)
	return out


## Every patch the option at [param index] writes, or `[]` for an out-of-range
## index — which is the "nothing was picked" case the lobby leans on rather than
## guarding separately.
func patches_at(index: int) -> Array[ScenarioOverride]:
	var list := choices()
	if index < 0 or index >= list.size():
		return []
	return list[index].patches
