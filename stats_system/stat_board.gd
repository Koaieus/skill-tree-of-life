@tool
class_name StatBoard
extends Resource

## An entity's stat board. Holds runtime Stat instances as typed fields.
## Scaffold under Option A from docs/design/stat_system.md — every entity
## carries every stat; tighten to typed PlayerStatBoard / EntityStatBoard
## inheritance after the first playable slice.
##
## Property names match each Stat's `definition.id` — so `get_stat(id)` is
## just `Object.get(id)`.
##
## Scalar fields use `ScalarStat` (not `Stat`) so the inspector dropdown
## offers only "New ScalarStat" — Stat itself is abstract.
## Pool fields use `PoolStat`; `.value` is the modifier-computed cap,
## `.current` is the ephemeral game state.

@export_group("Attributes")
@export var strength: ScalarStat        ## STR / Red — melee.
@export var dexterity: ScalarStat       ## DEX / Green — ranged.
@export var intelligence: ScalarStat    ## INT / Blue — magic potency.
@export var wisdom: ScalarStat          ## WIS / Gold — XP / economy.
@export var perception: ScalarStat      ## PER / Purple — vision / sensing.

@export_group("Survivability")
@export var health: PoolStat
## Board-level scalar baseline that seeds owned-node max HP. The per-node
## ephemeral combat pool lives on each TreeNode's combat component (see the
## "Per-Node Health" section of the design doc); this is the aggregate itw
## reads from.
@export var node_health: ScalarStat
## Flat damage reduction. Applied by Mitigation.apply before the
## min_damage_taken floor. Default 0.
@export var armor: ScalarStat
## Floor on post-armor damage. A landed hit always deals at least this much
## unless TRUE-typed. Default 3; defensive classes (Bulwark) may push lower.
@export var min_damage_taken: ScalarStat

@export_group("Economy")
@export var xp: PoolStat            ## XP pool; fires Entity.leveled_up on fill.
@export var xp_per_turn: ScalarStat

@export_group( "Allocation")
## Allocation budget — careful tracking via SkillPointStat (current/wounded/max
## with `used + current + wounded == max` invariant; see skill_point_stat.gd).
@export var skill_points: SkillPointStat
## Wounds healed at this entity's turn start. SkillPointStat.heal(N) flows
## that many from `wounded` back into `current`. Consumed by
## Entity._on_turn_started.
@export var wound_heal_per_turn: ScalarStat

@export_group("Turn Budget")
@export var deallocation_points: PoolStat  ## Default 3/3 — reshape budget.
@export var action_points: PoolStat        	## Default 2/2 — attacks per turn.
@export var movement_points: PoolStat		## Default 1/1 — moves Core along edges.

@export_group("Turn Order")
@export var initiative_speed: ScalarStat	## Ticks of initiative added per clock tick.

@export_group("Vision")
@export var vision_range: ScalarStat	## Euclidean sight radius in scene pixels.
@export var sensor_range: ScalarStat	## Topology sensor radius in hops past owned nodes.

@export_group("Ranged")
@export var range: ScalarStat			## Per-leaf firing distance in scene pixels. Localized on leaves.

@export_group("Magic")
@export var mana: PoolStat				## Casting resource. Max = base + INT//10; regen = floor(log(INT)) per turn.
@export var mana_per_turn: ScalarStat	## Mana restored at turn start. Base: floor(log(INT)).
@export var spell_range: ScalarStat		## Percent bonus to magic-spell reach. Scales with INT via intrinsic.

@export_group("Melee")
@export var blade_size: ScalarStat		## Max blade-member nodes per melee attack (excl. pivot). Base 1, +STR//10.

## Scaling rules intrinsic to this board — formula-driven StatModifiers that
## describe how stats on this board relate to each other (e.g. PER scales
## vision_range). Applied once by Entity._ready() via apply_intrinsics(). These
## are board-level truths, not per-entity bonuses (those live on Entity.core_class).
@export_group("Scaling Rules")
@export var intrinsic_modifiers: Array[StatModifier] = []

@export_group("")


# --- Lookup + modifier routing ---------------------------------------------

## Lookup a Stat by its StatDef id. Property-name == id convention.
func get_stat(id: StringName) -> Stat:
	return get(id)


## Read the computed value of a Stat by id. Returns null if the id is unknown.
func get_value(id: StringName) -> Variant:
	var s := get_stat(id)
	return s.get_value() if s != null else null


## Route a modifier to its target Stat by id. The intended one-liner from
## AllocationSystem: `for m in node.modifiers: entity.stat_board.add_modifier(m)`.
## Always calls bind() — no-op for modifiers without a formula, subscribes to
## source stats for formula-driven ones.
func add_modifier(m: StatModifier) -> void:
	m.bind(self)
	var s := get_stat(m.stat_id)
	if s == null:
		push_warning("StatBoard has no stat for id %s" % m.stat_id)
		return
	s.add_modifier(m)


func remove_modifier(m: StatModifier) -> void:
	m.unbind()
	var s := get_stat(m.stat_id)
	if s == null:
		return
	s.remove_modifier(m)


## Apply intrinsic_modifiers. Call once from Entity._ready() after the board
## is fully wired. Entries are duplicated automatically so each entity board
## gets its own bound instance — callers don't need to think about this.
func apply_intrinsics() -> void:
	for m in intrinsic_modifiers:
		add_modifier(m.duplicate(true))
