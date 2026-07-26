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
@export var constitution: ScalarStat    ## CON / White — defensive bulk; scales node_health only (D-11).

@export_group("Survivability")
## Entity's **Core** health, entity dies if it reaches 0.
@export var health: PoolStat
## Board-level scalar baseline that seeds owned-node max HP. The per-node
## ephemeral combat pool lives on each TreeNode's combat component (see the
## "Per-Node Health" section of the design doc); this is the aggregate itw
## reads from.
@export var node_health: ScalarStat
## Base HP a node regenerates at its owner's turn start (D-9). Node-local —
## read per-node via SkillNode.get_local_value, gated by whether the node
## took damage since the last turn start. See docs/domain/node-hp.md.
@export var node_healing: ScalarStat
## Extra node_healing per consecutive undamaged turn (SkillNode.regen_stacks,
## D-9). Self-limiting: the ramp stops at max HP and resets, so there is no
## cap stat. Node-local, same read path as node_healing.
@export var node_healing_ramp: ScalarStat
## Flat damage reduction. Applied by Mitigation.apply before the
## min_damage_taken floor. Default 0.
@export var armor: ScalarStat
## Floor on post-armor damage. A landed hit always deals at least this much
## unless TRUE-typed. Default 3; defensive classes (Bulwark) may push lower.
@export var min_damage_taken: ScalarStat
## Flat HP damage dealt to this entity per node forced-deallocated in a battle
## cascade. Bypasses mitigation (currency-exchange semantics — the cascade also
## wounds 1 SP per node, separately). Default 1; fragile-core classes raise it.
@export var dealloc_damage: ScalarStat

@export_group("Economy")
@export var xp: PoolStat            ## XP pool; fires Entity.leveled_up on fill.
@export var xp_per_turn: ScalarStat
## Entity level. Written (+1) on each XP-pool fill by Entity._on_xp_replenished;
## a plain ScalarStat (not a bespoke derived class) so level-scaling formula
## modifiers can bind to it and auto-recalc via base_value's value_changed, and
## so it stays moddable like every other stat. `Entity.level` proxies `.value`.
@export var level: ScalarStat

@export_group( "Allocation")
## Allocation budget — careful tracking via SkillPointStat (current/wounded/max
## with `used + current + wounded == max` invariant; see skill_point_stat.gd).
@export var skill_points: SkillPointStat
## Wounds healed at this entity's turn start. SkillPointStat.heal(N) flows
## that many from `wounded` back into `current`. Consumed by
## Entity._on_turn_started.
@export var wound_heal_per_turn: ScalarStat
## SP minted on each level-up (D-16, #271), read by Entity._on_xp_replenished
## in place of the old hardcoded grant(1). Default 2 — #268-tunable, not a
## pinned balance value. A milestone bonus (+1) applies on every 5th level,
## computed in Entity, not stored here.
@export var sp_gain_on_levelup: ScalarStat

@export_group("Turn Budget")
@export var deallocation_points: SurplusPoolStat  ## Default 3/3 — reshape budget. Surplus bin for #152 transient boost.
@export var action_points: PoolStat        	## Default 2/2 — attacks per turn.
@export var movement_points: SurplusPoolStat	## Default 1/1 — moves Core along edges. Surplus bin for #152 transient boost.
## Default 2 — each unused AP at turn end grants this many bonus DP + MP surplus
## next turn (#152). A modifier target like any other stat, so class identity
## tunes it (Pacifist raises, Berserker → 0) with no bespoke mechanism.
@export var ap_transfer_rate: ScalarStat

@export_group("Turn Order")
@export var initiative: PoolStat				## Turn clock; cap = action threshold (100). Cyclic — carries overshoot.
@export var initiative_speed: ScalarStat	## Ticks of initiative added per clock tick.

@export_group("Vision")
@export var vision_range: ScalarStat	## Euclidean sight radius in scene pixels.
@export var sensor_range: ScalarStat	## Topology sensor radius in hops past owned nodes.

@export_group("Ranged")
@export var range: ScalarStat			## Per-leaf firing distance in scene pixels. Localized on leaves.
@export var ranged_damage: ScalarStat	## Damage per shot. Base 1, +1 per 10 DEX. Node-local addons add on top per-node via node_board.

@export_group("Magic")
@export var mana: PoolStat				## Casting resource. Max = base + INT//10; regen = floor(log(INT)) per turn.
@export var mana_per_turn: ScalarStat	## Mana restored at turn start. Base: floor(log(INT)).
@export var spell_range: ScalarStat		## Percent bonus to magic-spell reach. Scales with INT via intrinsic.

@export_group("Melee")
@export var blade_size: ScalarStat		## Max blade-member nodes per melee attack (excl. pivot). Base 1, +STR//10.
@export var blade_damage: ScalarStat	## Damage per node contact. Base 1, +1 per 10 STR. Node-local addons (e.g. SpikeRing) add on top per-node via node_board.

@export_group("Crit")
@export var crit_chance: ScalarStat		## Probability (0..1) a hit crits. Baseline 5%.
@export var crit_multiplier: ScalarStat	## Damage multiplier on crit. Baseline 2.0 (double damage).

## Scaling rules intrinsic to this board — formula-driven StatModifiers that
## describe how stats on this board relate to each other (e.g. PER scales
## vision_range). Applied once by Entity._ready() via apply_intrinsics(). These
## are board-level truths, not per-entity bonuses (those live on Entity.core_class).
@export_group("Scaling Rules")
@export var intrinsic_modifiers: Array[StatModifier] = []

@export_group("")


# --- Dynamic stats (sparse boards) -----------------------------------------

## Stats that don't correspond to a hardcoded @export field — created on
## demand by [method _ensure_stat] for sparse boards (e.g. node-local stats).
var _extra_stats: Dictionary = {}  # StringName → Stat


# --- Lookup + modifier routing ---------------------------------------------

## Lookup a Stat by its StatDef id. Checks hardcoded fields first, then
## dynamically-created stats in [member _extra_stats].
func get_stat(id: StringName) -> Stat:
	var s: Stat = get(id)
	if s != null:
		return s
	return _extra_stats.get(id, null)


## Ensure a Stat exists for [param id], creating one if necessary from
## [code]StatRegistry[/code]. Returns the existing or newly created Stat,
## or [code]null[/code] if the id is unknown to the registry. Use this on
## sparse boards (like [member SkillNode.node_board]) where stats are not
## pre-populated; entity boards should have all stats already.
func _ensure_stat(stat_id: StringName) -> Stat:
	var s := get_stat(stat_id)
	if s != null:
		return s
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def == null:
		push_warning("StatBoard._ensure_stat: unknown stat id '%s'" % stat_id)
		return null
	if def is PoolStatDef:
		s = PoolStat.new()
	else:
		s = ScalarStat.new()
	s.definition = def
	s.base_value = def.default_value
	_extra_stats[stat_id] = s
	return s


## Read the computed value of a Stat by id. Returns null if the id is unknown.
func get_value(id: StringName) -> Variant:
	var s := get_stat(id)
	return s.get_value() if s != null else null


## Route a modifier to its target Stat by id. The intended one-liner from
## AllocationSystem: `for m in node.modifiers: entity.stat_board.add_modifier(m)`.
## Always calls bind() — no-op for modifiers without a formula, subscribes to
## source stats for formula-driven ones.
func add_modifier(m: StatModifier) -> void:
	# flatten() expands a CompositeStatModifier into its leaves; a plain
	# modifier is its own singleton, so the leaf path below is unchanged (#183).
	for leaf in m.flatten():
		leaf.bind(self)
		var s := get_stat(leaf.stat_id)
		if s == null:
			push_warning("StatBoard has no stat for id %s" % leaf.stat_id)
			continue
		s.add_modifier(leaf)


func remove_modifier(m: StatModifier) -> void:
	# Symmetric with add_modifier: flatten() returns the same stable child
	# instances, so a composite added earlier is removed leaf-for-leaf.
	for leaf in m.flatten():
		leaf.unbind()
		var s := get_stat(leaf.stat_id)
		if s == null:
			continue
		s.remove_modifier(leaf)


## Apply intrinsic_modifiers. Call once from Entity._ready() after the board
## is fully wired. Entries are duplicated automatically so each entity board
## gets its own bound instance — callers don't need to think about this.
func apply_intrinsics() -> void:
	for m in intrinsic_modifiers:
		add_modifier(m.duplicate(true))


## The ids of every dynamically-created stat currently on this board (i.e. the
## sparse [member _extra_stats] set — hardcoded @export fields are never
## included). For a sparse board like [member SkillNode.node_board] this is the
## only way to enumerate "what's actually on it" — read-only, creates nothing.
## Sorted lexicographically so repeated calls return the same order (Dictionary
## iteration order isn't a contract to lean on for UI row stability).
func get_dynamic_stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _extra_stats:
		ids.append(id)
	ids.sort()
	return ids


## Every PoolStat field on this board, discovered by introspection so adding a
## new pool needs no registration here. Includes SkillPointStat (a PoolStat).
func get_pool_stats() -> Array[PoolStat]:
	var pools: Array[PoolStat] = []
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var v: Variant = get(prop.name)
		if v is PoolStat:
			pools.append(v)
	return pools


## Start-of-turn pool replenishment. Called once from Entity._on_turn_started;
## each pool replenishes itself per its def's per_turn_mode (REFILL / ADD /
## CUSTOM / NONE) — the per-pool behaviour lives on PoolStat.run_turn_upkeep(),
## so this is just the sweep. No per-pool wiring here or in the Entity.
func apply_per_turn_upkeep() -> void:
	for pool in get_pool_stats():
		pool.run_turn_upkeep(self)
