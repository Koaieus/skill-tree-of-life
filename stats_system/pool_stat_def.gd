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
##   ADD    — current += the value of the companion stat `&"<id>_per_turn"` (mana, xp),
##            or of [member per_turn_stat_id] when the rate stat is named
##            independently (health ← `core_healing`).
##   CUSTOM — dispatches to PoolStat._custom_turn_upkeep(board), a virtual the
##            *stat* subclass overrides. For upkeep that touches the stat's own
##            extra state (skill_points' wound-heal moves the `wounded` bin).
##            (The other two PoolStatDef virtuals live on the *def* because they
##            vary by cap-shape; this one's on the stat because it varies by the
##            stat's bins — behaviour lives where its data lives.)
enum PerTurnMode { NONE, REFILL, ADD, CUSTOM }
@export var per_turn_mode: PerTurnMode = PerTurnMode.NONE

## ADD-mode override: the id of the scalar carrying the per-turn amount. Empty
## (the default) means the `<id>_per_turn` convention — mana reads
## `mana_per_turn`, xp reads `xp_per_turn`. Set this only when the rate stat
## has a name of its own: `health` replenishes by `core_healing` (D-25), which
## is named for the mechanic rather than for the pool it fills.
@export var per_turn_stat_id: StringName = &""


## The stat id this pool's ADD upkeep reads, resolving the `<id>_per_turn`
## convention when no explicit [member per_turn_stat_id] is set.
func resolved_per_turn_stat_id() -> StringName:
	if per_turn_stat_id != &"":
		return per_turn_stat_id
	return StringName("%s_per_turn" % id)


## Called by PoolStat when `current` crosses *up* to the cap (replenish event).
## `excess` is the amount of the inbound replenish that was clipped by the
## cap-clamp — defs may use it (e.g. OVERFLOW growth carries it forward) or
## ignore it. Default: no-op.
func on_pool_filled(_stat: PoolStat, _excess: float) -> void:
	pass


## How `current` responds when this pool's cap MOVES UP.
##   PIN    — cap rises, `current` sits where it is (the bar looks emptier).
##   FOLLOW — `current` rises by the same delta, so the relative fill holds.
##            This is the D-21 ratchet on `health`; see PoolStat._follow_cap_delta.
enum CapRise { PIN, FOLLOW }

## How `current` responds when this pool's cap MOVES DOWN.
##   CLAMP  — `current` only moves if it would exceed the new cap.
##   FOLLOW — `current` drops by the same delta even when it had headroom
##            ("shrink with"), then the clamp invariant still applies.
enum CapFall { CLAMP, FOLLOW }

## [b]The clamp is an INVARIANT, not one of these modes.[/b] `current` is bounded
## by the cap after either policy runs, and no mode can switch that off. Budget
## that legitimately exceeds the maximum is a *separate bin* — see
## [SurplusPoolStat], whose `surplus` sits outside the cap and which the
## cap-change policy must never touch (deallocation_points / movement_points).
##
## Replaces `StandardPoolStatDef.heal_on_max_increase` (#555): that bool was a
## degenerate two-value CapRise living on one subclass, while the fall half was
## hardcoded and the whole thing was skippable by writing `base_value` directly.
@export var on_cap_rise: CapRise = CapRise.PIN
@export var on_cap_fall: CapFall = CapFall.CLAMP


func _validate_property(prop: Dictionary) -> void:
	if prop.name == "value_type":
		# BOOL is meaningless for a pool cap; hide it from the inspector.
		prop.hint_string = "INT,FLOAT"
