@tool
class_name StatBoard
extends Resource

## An entity's stat board. Holds runtime Stat instances as typed fields.
## Scaffold under Option A from docs/design/stat_system.md — every entity
## carries every stat; tighten to typed PlayerStatBoard / EntityStatBoard
## inheritance after the first playable slice.
##
## Property names match each Stat's `definition.id` — so `get_stat(id)` is
## just `Object.get(id)`, which transparently resolves both @export fields
## and the derived getter properties for pool maxes below.
##
## Scalar fields use `ScalarStat` (not `Stat`) so the inspector dropdown
## offers only "New ScalarStat" — Stat itself is abstract.

# Six-attribute attack/utility spine.
@export var strength: ScalarStat        ## STR / Red — melee.
@export var dexterity: ScalarStat       ## DEX / Green — ranged.
@export var intelligence: ScalarStat    ## INT / Blue — magic potency.
@export var wisdom: ScalarStat          ## WIS / Gold — XP / economy.
@export var perception: ScalarStat      ## PER / Purple — vision / sensing.

# Survivability.
@export var health: PoolStat
## Board-level scalar baseline that seeds owned-node max HP. The per-node
## ephemeral combat pool lives on each TreeNode's combat component (see the
## "Per-Node Health" section of the design doc); this is the aggregate it
## reads from.
@export var node_health: ScalarStat

# Economy.
@export var xp_per_turn: ScalarStat

# Allocation budget — careful tracking via SkillPointStat (current/wounded/max
# with `used + current + wounded == max` invariant; see skill_point_stat.gd).
@export var skill_points: SkillPointStat

# Per-turn budgets — both are pools whose current resets at turn start
# (TurnManager owns that reset; unspent are wasted).
@export var deallocation_points: PoolStat  ## Default 3/3 — reshape budget.
@export var action_points: PoolStat        ## Default 2/2 — attacks per turn.


# --- Pool max stats (derived) ----------------------------------------------
# Each pool already owns its `max_stat` reference, so the board exposes a
# computed view rather than a second @export. Single source of truth:
# edit `health.max_stat` in the inspector; `board.health_max` follows.
# Non-@export so the inspector doesn't show an uneditable shadow and
# nothing serializes twice. `Object.get(&"health_max")` invokes the getter,
# so `get_stat()` / modifier routing keep working.

var health_max: ScalarStat:
	get: return health.max_stat if health != null else null

var skill_points_max: ScalarStat:
	get: return skill_points.max_stat if skill_points != null else null

var deallocation_points_max: ScalarStat:
	get: return deallocation_points.max_stat if deallocation_points != null else null

var action_points_max: ScalarStat:
	get: return action_points.max_stat if action_points != null else null


# --- Lookup + modifier routing ---------------------------------------------

## Lookup a Stat by its StatDef id. Property-name == id convention; works
## for @exports and the derived getters above.
func get_stat(id: StringName) -> Stat:
	return get(id)


## Read the computed value of a Stat by id. Returns null if the id is unknown.
func get_value(id: StringName) -> Variant:
	var s := get_stat(id)
	return s.get_value() if s != null else null


## Route a modifier to its target Stat by id. The intended one-liner from
## AllocationSystem: `for m in node.modifiers: entity.stat_board.add_modifier(m)`.
func add_modifier(m: StatModifierDef) -> void:
	var s := get_stat(m.stat_id)
	if s == null:
		push_warning("StatBoard has no stat for id %s" % m.stat_id)
		return
	s.add_modifier(m)


func remove_modifier(m: StatModifierDef) -> void:
	var s := get_stat(m.stat_id)
	if s == null:
		return
	s.remove_modifier(m)
