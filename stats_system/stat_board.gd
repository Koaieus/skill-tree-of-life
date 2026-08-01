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
@export var constitution: ScalarStat    ## CON / White — defensive bulk; scales node_health (D-11) and the entity health pool (D-21).

@export_group("Survivability")
## Entity's **Core** health, entity dies if it reaches 0. Max is
## `10 + core_health_scaling × CON` (D-21/D-26); the flat 10 is the pool's
## `base_value`, the CON term is a board intrinsic.
@export var health: PoolStat
## Entity HP restored at turn start (D-25) — `health`'s ADD-mode companion,
## named for the mechanic rather than the `<pool>_per_turn` convention (see
## PoolStatDef.per_turn_stat_id). Ungated and unramped by design: taking damage
## never suppresses it. Placeholder 1; the real rate is a #268 measurement.
@export var core_healing: ScalarStat
## HP one point of CON buys (D-26). The class-facing half of the D-21 pair —
## `core_health_scaling` sizes the pool, `dealloc_damage` sizes the chip, and
## `nodes_lost_before_death = health / dealloc_damage` is where class identity
## lives. Entity-scope only; meaningless node-locally (see #287).
@export var core_health_scaling: ScalarStat
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
##
## Rejects (push_warning, no-op) a modifier that would close a dependency
## cycle against everything currently applied — see [method cycle_from] (#322).
## Checked BEFORE any leaf is bound, so a rejection leaves the board untouched.
func add_modifier(m: StatModifier) -> void:
	# The offending path, not m.stat_id — a CompositeStatModifier's stat_id is
	# vestigial (empty), and the bundle is exactly the case worth diagnosing.
	var cycle := cycle_from(m)
	if not cycle.is_empty():
		push_warning(
			"StatBoard.add_modifier: rejected a modifier that would close a formula dependency cycle: %s" % cycle
		)
		return
	# flatten() expands a CompositeStatModifier into its leaves; a plain
	# modifier is its own singleton, so the leaf path below is unchanged (#183).
	for leaf in m.flatten():
		leaf.bind(self)
		var s := get_stat(leaf.stat_id)
		if s == null:
			push_warning("StatBoard has no stat for id %s" % leaf.stat_id)
			continue
		s.add_modifier(leaf)


## True if applying [param m] would close a dependency cycle against the formula
## graph already live on this board. Bool wrapper over [method cycle_from].
func would_cycle(m: StatModifier) -> bool:
	return not cycle_from(m).is_empty()


## The dependency cycle applying [param m] would close, as a printable path
## ("intelligence -> mana -> intelligence"), or "" when it closes none (#322 —
## the runtime half of test_stat_dependency_graph.gd's static DAG check; a
## looted formula modifier rebinding to a new board is the case that check
## can't cover).
##
## Searches only from the candidate's OWN target stats, not from every vertex.
## Edges run `stat_id -> formula input`, so any cycle containing a newly added
## edge is reachable from that edge's tail by construction — rooting there is
## both sufficient and strictly narrower. That matters for correctness, not just
## speed: a whole-graph search would report a cycle the candidate had no part in
## and reject an innocent modifier for it. (Reachable only via a seam that
## bypasses this method — [method Stat.add_modifier] called directly on an
## entity board — but the failure would be invisible if it ever happened.)
##
## Costs nothing when the candidate has no edges to add: a modifier that is
## static (no formula) or whose formula declares no inputs (a bare constant)
## yields no roots, and the live graph is never folded at all.
func cycle_from(m: StatModifier) -> String:
	var adjacency := {}
	m.collect_formula_edges(adjacency)
	var roots := adjacency.keys()   # captured BEFORE the live edges merge in
	if roots.is_empty():
		return ""
	collect_formula_edges(adjacency)
	return find_cycle(adjacency, roots)


## Fold every formula edge currently APPLIED to this board — hardcoded `@export`
## stat fields plus dynamically-created ones — into [param out], in place.
## The "what's already live" half of [method cycle_from]'s graph.
##
## Note this reads what is APPLIED (each Stat's modifier list), not the authored
## [member intrinsic_modifiers] array, which is inert until [method
## apply_intrinsics] attaches it. Each Stat contributes its own edges, so no
## intermediate modifier list and no per-stat array copy is built.
func collect_formula_edges(out: Dictionary) -> void:
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var v: Variant = get(prop.name)
		if v is Stat:
			v.collect_formula_edges(out)
	for id in _extra_stats:
		_extra_stats[id].collect_formula_edges(out)


## {stat_id: [depends_on_id, ...]} over an AUTHORED modifier list — the static
## counterpart to [method collect_formula_edges]'s live read, used by
## test_stat_dependency_graph.gd to check shipped content (board intrinsics +
## each CoreClass) BEFORE anything is applied. Composites recurse; the edge rule
## itself lives on [method StatModifier.collect_formula_edges].
static func adjacency_from(mods: Array) -> Dictionary:
	var out := {}
	for m in mods:
		if m != null:
			m.collect_formula_edges(out)
	return out


## Depth-first three-colour search over an adjacency graph. Returns the
## offending path ("a -> b -> a") on the first cycle found, or "" when no cycle
## is reachable. [param roots] limits the search to cycles reachable from those
## vertices; empty (the default) searches the whole graph, which is what the
## static shipped-content check wants.
static func find_cycle(adjacency: Dictionary, roots: Array = []) -> String:
	var done := {}       # fully explored — can never be part of a new cycle
	var on_stack := {}   # in the current DFS path — a hit here IS the cycle
	var path: Array[StringName] = []
	for root in (roots if not roots.is_empty() else adjacency.keys()):
		var found := _visit_for_cycle(root, adjacency, done, on_stack, path)
		if not found.is_empty():
			return found
	return ""


static func _visit_for_cycle(
	id: StringName,
	adjacency: Dictionary,
	done: Dictionary,
	on_stack: Dictionary,
	path: Array[StringName]
) -> String:
	if done.has(id):
		return ""
	if on_stack.has(id):
		var from := path.find(id)
		var loop := path.slice(from) if from >= 0 else path.duplicate()
		loop.append(id)
		return " -> ".join(loop)
	on_stack[id] = true
	path.append(id)
	for dep in adjacency.get(id, []):
		var found := _visit_for_cycle(dep, adjacency, done, on_stack, path)
		if not found.is_empty():
			return found
	path.pop_back()
	on_stack.erase(id)
	done[id] = true
	return ""


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
