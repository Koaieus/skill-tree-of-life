@tool
class_name Quiver
extends PoolStat

## The entity's ammo — the `arrows` stat on [EntityStatBoard]. One [PoolStat]
## (current = PLAIN stock, max = quiver capacity, from the modifier pipeline
## like any pool) plus per-[AmmoType] bins: the plain bin IS `current`, and
## each special bin sits beside it, capped by its own type's `max_stock`
## rather than by capacity (ADR 0041, superseding ADR 0019 on that point). The
## identity `current == bins[BASE_ID]` holds after every transfer below.
##
## The class IS the stat: there is no separate Quiver resource on [Entity].
## The ranged command-tray body is a view of this stat exactly as the magic
## body is a view of [SpellBook]. Authored as `@export var arrows: Quiver` on
## the board + the `default_entity_board.tres` instance (never minted through
## `StatBoard._mint_stat`, which would mint a plain PoolStat).
##
## Cap policy comes from `arrows.tres`: PIN on rise (a capacity modifier never
## gifts arrows) and CLAMP on fall — a fall trims the plain bin with `current`;
## specials never shrink on a capacity change (see [method _apply_max_change]).
##
## A special's cap reaches this class as an argument ([method add],
## [method room_for]) — `stats_system/` sits below `attack/`, so it never reads
## the [AmmoType] roster.

## Emitted after any bin changes (add / take / clamp / restore), with the type touched.
signal bin_changed(type_id: StringName)

## The plain arrow's id — the one bin that is `current`. Must equal
## `AmmoTypeRoster.BASE_ID` (pinned by test_quiver); this class sits below
## `attack/` and may not name the roster.
const BASE_ID: StringName = &"arrow"
## A special's cap when the caller passes none; the default of
## `AmmoType.max_stock` (owner, 2026-10-01: "capped at 999 per type").
const DEFAULT_MAX_STOCK := 999

## `{AmmoType.id: count}`, positive counts only. Exported so a shadow world's
## [method StatBoard.clone_live] (`duplicate(true)`) carries the stock across;
## nothing outside this class writes it — the accessor is [method ammo_bins].
@export var _bins: Dictionary[StringName, int] = {}


## Arrows of [param type_id] in stock.
func stock_of(type_id: StringName) -> int:
	return _bins.get(type_id, 0)


## Adds [param n] arrows of [param type_id], clamped to that bin's room
## ([method room_for]): plain arrows against capacity, a special against
## [param max_stock] (its type's cap; ignored for the plain bin). Returns the
## number actually added.
func add(type_id: StringName, n: int, max_stock: int = DEFAULT_MAX_STOCK) -> int:
	var actual: int = clampi(n, 0, room_for(type_id, max_stock))
	if actual <= 0:
		return 0
	_bins[type_id] = stock_of(type_id) + actual
	if type_id == BASE_ID:
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
	if type_id == BASE_ID:
		set_current(current - float(actual))
	bin_changed.emit(type_id)
	return actual


## Every arrow held, plain and special — what a volley can draw on.
func total_stock() -> int:
	var total := 0
	for k in _bins:
		total += _bins[k]
	return total


## How many more arrows of [param type_id] fit: capacity minus `current` for
## the plain bin, [param max_stock] minus the bin for a special.
func room_for(type_id: StringName, max_stock: int = DEFAULT_MAX_STOCK) -> int:
	if type_id == BASE_ID:
		return maxi(0, int(get_value()) - roundi(current))
	return maxi(0, max_stock - stock_of(type_id))


## `{type_id: count}` for every bin with a positive count. A copy — mutate
## through [method add] / [method take] only.
func ammo_bins() -> Dictionary:
	return _bins.duplicate()


## The cap-change policy, plus the bin half of the invariant: after the base
## class has clamped `current` to a fallen cap (CLAMP — `arrows.tres` never
## FOLLOWs), the plain bin follows `current` down. Specials are untouched. A
## rise is PIN and touches nothing.
func _apply_max_change(old_max: float) -> void:
	super(old_max)
	var plain := roundi(current)
	if stock_of(BASE_ID) > plain:
		_set_bin(BASE_ID, plain)
		bin_changed.emit(BASE_ID)


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
