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
## Stub (#496 swarmify, 2026-09-18): signatures only. The child issue's first
## commit flips `test/unit/test_quiver.gd` from `pending()` to red.

## Emitted after any bin changes (add / take / clamp), with the type touched.
signal bin_changed(type_id: StringName)


## Arrows of [param type_id] in stock.
func stock_of(_type_id: StringName) -> int:
	return 0


## Adds [param n] arrows of [param type_id], clamped to remaining capacity.
## Returns the number actually added.
func add(_type_id: StringName, _n: int) -> int:
	return 0


## Removes up to [param n] arrows of [param type_id]. Returns the number
## actually taken (fewer than [param n] only when the bin runs dry).
func take(_type_id: StringName, _n: int) -> int:
	return 0


## `{type_id: count}` for every bin with a positive count.
func bins() -> Dictionary:
	return {}
