@tool
class_name GrowablePoolStat
extends PoolStat

## A [PoolStat] that remembers what its [GrowablePoolStatDef] growth consumed —
## XP's lifetime total:
##     total() == banked + current
##
## [member banked] is the sum of every cap a level-up consumed, added by
## [method GrowablePoolStatDef.on_pool_filled] (the one owner of "a level was
## consumed") before it mints the next cap. Banking the cap actually consumed —
## the MODIFIED one — keeps the total exact under a cap modifier or a curve
## retune, which a total re-derived from the def's curve would not be. With
## OVERFLOW nothing replenished is ever lost, so the total is monotone.

## Σ of the caps every level-up consumed. Live run state, never authored: every
## board `.tres` carries the default 0.0.
@export var banked: float = 0.0


## Lifetime earned: banked levels plus the bar. Exposed as the `total` formula
## accessor (`xp__total`).
func total() -> float:
	return banked + current


func accessors() -> Dictionary[StringName, Callable]:
	var d := super.accessors()
	d.merge({&"total": func(s: GrowablePoolStat): return s.total()})
	return d


## Adds the banked levels to [method PoolStat.to_dict].
func to_dict() -> Dictionary:
	var d := super()
	d["banked"] = banked
	return d


## Restored raw, like `current`: a snapshot transports levels already banked.
func read_dict(d: Dictionary, board: StatBoard = null) -> void:
	banked = float(d.get("banked", 0.0))
	super(d, board)
