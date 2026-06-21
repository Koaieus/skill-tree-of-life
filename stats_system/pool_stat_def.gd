@tool
class_name PoolStatDef
extends StatDef

## Abstract base for pool stats. A PoolStat IS the cap — modifiers target the
## pool stat id directly and the pipeline computes the maximum. `.current` is
## the separate ephemeral game state.
##
## Concrete subclasses:
##   - StandardPoolStatDef — fixed-cap pool (HP, mana, AP, …), optional
##     heal-on-cap-rise.
##   - GrowablePoolStatDef — gauge that grows when filled (XP), with a
##     post-grow mode (keep / reset / overflow).
##
## Subclasses customise behaviour by overriding the two virtuals below.
## PoolStat itself stays agnostic to which subclass it holds.

@export var min_value: int = 0


## Called by PoolStat when `current` crosses *up* to the cap (replenish event).
## `excess` is the amount of the inbound replenish that was clipped by the
## cap-clamp — defs may use it (e.g. OVERFLOW growth carries it forward) or
## ignore it. Default: no-op.
func on_pool_filled(_stat: PoolStat, _excess: float) -> void:
	pass


## Called by PoolStat when the cap rises via the modifier pipeline.
## `delta` is strictly positive. Cap *decreases* are handled by PoolStat
## itself (current is clamped down) — defs only react to growth.
## Default: no-op.
func on_max_increased(_stat: PoolStat, _delta: float) -> void:
	pass


func _validate_property(prop: Dictionary) -> void:
	if prop.name == "value_type":
		# BOOL is meaningless for a pool cap; hide it from the inspector.
		prop.hint_string = "INT,FLOAT"
