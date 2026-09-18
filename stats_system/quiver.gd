@tool
class_name Quiver
extends PoolStat

## The entity's ammo — the `arrows` stat on [EntityStatBoard]. One [PoolStat]
## (current = total stock, max = quiver capacity, from the modifier pipeline
## like any pool) with per-[AmmoType] bins *inside* current, the way
## [SkillPointStat] keeps `wounded` / `staked` inside max. The bins are the
## only extra state; the identity `current == Σ bins` holds after every
## transfer below.
##
## The class IS the stat: there is no separate Quiver resource on [Entity].
## The ranged command-tray body is a view of this stat exactly as the magic
## body is a view of [SpellBook]. Authored as `@export var arrows: Quiver` on
## the board + the `default_entity_board.tres` instance (never minted through
## `StatBoard._mint_stat`, which would mint a plain PoolStat).
##
## Cap policy comes from `arrows.tres`: PIN on rise (a capacity modifier never
## gifts arrows) and CLAMP on fall — and a fall that clamps `current` also
## trims the bins, last sorted key first, so the identity holds on every peer
## in the same way (see [method _apply_max_change]).

## Emitted after any bin changes (add / take / clamp / restore), with the type touched.
signal bin_changed(type_id: StringName)

## `{AmmoType.id: count}`, positive counts only. Exported so a shadow world's
## [method StatBoard.clone_live] (`duplicate(true)`) carries the stock across;
## nothing outside this class writes it — the accessor is [method ammo_bins].
@export var _bins: Dictionary[StringName, int] = {}


## Arrows of [param type_id] in stock.
func stock_of(type_id: StringName) -> int:
	return _bins.get(type_id, 0)


## Adds [param n] arrows of [param type_id], clamped to remaining capacity.
## Returns the number actually added.
func add(type_id: StringName, n: int) -> int:
	var room: int = int(get_value()) - roundi(current)
	var actual: int = clampi(n, 0, room)
	if actual <= 0:
		return 0
	_bins[type_id] = stock_of(type_id) + actual
	set_current(current + float(actual))
	bin_changed.emit(type_id)
	return actual


## Removes up to [param n] arrows of [param type_id]. Returns the number
## actually taken (fewer than [param n] only when the bin runs dry).
func take(type_id: StringName, n: int) -> int:
	var actual: int = clampi(n, 0, stock_of(type_id))
	if actual <= 0:
		return 0
	_set_bin(type_id, stock_of(type_id) - actual)
	set_current(current - float(actual))
	bin_changed.emit(type_id)
	return actual


## `{type_id: count}` for every bin with a positive count. A copy — mutate
## through [method add] / [method take] only.
func ammo_bins() -> Dictionary:
	return _bins.duplicate()


## The cap-change policy, plus the bin half of the invariant: after the base
## class has clamped `current` to a fallen cap (CLAMP — `arrows.tres` never
## FOLLOWs), shed the surplus from the bins in reverse sorted-key order, so
## every peer trims the same arrows. A rise is PIN and touches nothing.
func _apply_max_change(old_max: float) -> void:
	super(old_max)
	_trim_bins_to_current()


func _trim_bins_to_current() -> void:
	var excess: int = _sum_bins() - roundi(current)
	if excess <= 0:
		return
	var keys: Array = _bins.keys()
	keys.sort()
	keys.reverse()
	for k in keys:
		if excess <= 0:
			break
		var shed: int = mini(excess, _bins[k])
		_set_bin(k, _bins[k] - shed)
		excess -= shed
		bin_changed.emit(k)


func _sum_bins() -> int:
	var total := 0
	for k in _bins:
		total += _bins[k]
	return total


func _set_bin(type_id: StringName, count: int) -> void:
	if count <= 0:
		_bins.erase(type_id)
	else:
		_bins[type_id] = count


## Adds the bins to [method PoolStat.to_dict]; `current` already crosses there.
func to_dict() -> Dictionary:
	var d := super()
	var bins: Dictionary = {}
	for k in _bins:
		bins[String(k)] = _bins[k]
	d["bins"] = bins
	return d


## Restores the bins RAW, like the `current` [method PoolStat.read_dict]
## restores just before: the payload is a state that already happened, never
## reconciled against the receiver's cap. Keys arrive as String or StringName.
func read_dict(d: Dictionary, board: StatBoard = null) -> void:
	super(d, board)
	var incoming: Dictionary = d.get("bins", {})
	var touched: Dictionary = {}
	for k in _bins:
		touched[k] = true
	_bins.clear()
	for k in incoming:
		var count := int(incoming[k])
		if count > 0:
			_bins[StringName(k)] = count
			touched[StringName(k)] = true
	for k in touched:
		bin_changed.emit(k)
