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

## How this pool replenishes at its owner's turn start. Read by
## StatBoard.apply_per_turn_upkeep(), which delegates to PoolStat.run_turn_upkeep()
## per pool — no hand-wired line in Entity._on_turn_started. See
## .claude/rules/stats-system.md "Turn-start upkeep" for the verb model.
##   NONE   — no automatic upkeep (default).
##   REFILL — current restored to the cap. For reset-each-turn budgets (AP, DP, movement).
##   ADD    — current += the value of the companion stat `&"<id>_per_turn"` (mana, xp).
##   CUSTOM — dispatches to PoolStat._custom_turn_upkeep(board), a virtual the
##            *stat* subclass overrides. For upkeep that touches the stat's own
##            extra state (skill_points' wound-heal moves the `wounded` bin).
##            (The other two PoolStatDef virtuals live on the *def* because they
##            vary by cap-shape; this one's on the stat because it varies by the
##            stat's bins — behaviour lives where its data lives.)
enum PerTurnMode { NONE, REFILL, ADD, CUSTOM }
@export var per_turn_mode: PerTurnMode = PerTurnMode.NONE


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
