@tool
class_name StatBoard
extends Resource

## Board mechanism, no stats. Holds runtime [Stat] instances, routes modifiers
## to them, owns formula binding and the dependency-cycle gate — and declares
## not one stat field of its own. The two concrete boards are siblings, not a
## chain: [EntityStatBoard] (every stat an entity can hold, as typed fields)
## and [NodeStatBoard] (node-only stats baked, borrowed ones sparse). #332/#287
## split them; the base keeps this name so nothing typed `StatBoard` churned.
##
## Property names match each Stat's `definition.id` — so [method get_stat] is
## just `Object.get(id)`, and a subclass's fields are discovered for free by the
## `get_property_list()` walks in [method collect_formula_edges] and
## [method get_pool_stats]. That introspection IS the mechanism, and it is why
## the split is inheritance rather than an array of sub-boards: sub-boards would
## mean reimplementing discovery in five places.

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


## Ensure a Stat exists for [param stat_id], creating one if necessary from
## [code]StatRegistry[/code]. Returns the existing or newly created Stat,
## or [code]null[/code] if the id is unknown to the registry. Use this on
## sparse boards (like [member SkillNode.node_board]) where stats are not
## pre-populated; an [EntityStatBoard] declares every stat it can hold as a
## field and refuses to mint (see its [method _mint_stat] override).
##
## Rejects decorated accessor tokens (`health__current` and friends): those are
## formula-read tokens, not stats — no [StatDef], no write path through the
## modifier pipeline (#333). Letting one through here would happily mint a
## phantom stat for it on any board, exactly the silent-wrong-state failure
## this gate exists to prevent. That gate lives HERE, above the [method
## _mint_stat] seam, so no subclass can forget it.
func _ensure_stat(stat_id: StringName) -> Stat:
	if StatFormula.is_accessor_token(stat_id):
		push_warning(
			"StatBoard._ensure_stat: '%s' is a formula accessor token, not a stat id"
			% stat_id
		)
		return null
	var s := get_stat(stat_id)
	if s != null:
		return s
	return _mint_stat(stat_id)


## Create the Stat for an id this board has no field for, and file it under
## [member _extra_stats]. The overridable half of [method _ensure_stat] — the
## sparse default mints from [StatRegistry]; [EntityStatBoard] refuses.
## Never call directly: [method _ensure_stat] owns the accessor-token gate and
## the already-exists short-circuit.
func _mint_stat(stat_id: StringName) -> Stat:
	var s: Stat = null
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def == null:
		push_warning("StatBoard._mint_stat: unknown stat id '%s'" % stat_id)
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
##
## Cross-reference (#340): [method SkillNode.add_local_modifier] mirrors this
## cycle-check -> bind -> resolve-target sequence against node_board instead of
## routing through here (get_stat would silently drop a sparse-board target, or
## an ensuring variant would leak node-only stats onto an entity board). A
## future change to "how a modifier is admitted to a board" must update both.
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
		bind_modifier(leaf)
		if StatFormula.is_accessor_token(leaf.stat_id):
			# An accessor token (e.g. `health__current`) is a formula-read handle,
			# not a stat id — a modifier canTarget one as well as it can target
			# `min_damage_taken`. The existing get_stat lookup would already miss
			# it, but the warning below says *why* rather than just "no stat for id".
			push_warning(
				"StatBoard.add_modifier: rejected a modifier whose target stat_id '%s' is a formula accessor token, not a stat"
				% leaf.stat_id
			)
			continue
		var s := get_stat(leaf.stat_id)
		if s == null:
			push_warning("StatBoard has no stat for id %s" % leaf.stat_id)
			continue
		s.add_modifier(leaf, self)


## Subscribe [param m] to its formula's source stats on THIS board, so a source
## change here recomputes it (#377). No-op when [param m] has no formula —
## static modifiers pay zero binding cost. No storage: connections are looked
## up again by [method unbind_modifier] via the same formula/get_stat walk, not
## remembered, because [member _extra_stats] never erases an entry once created
## — get_stat(id) is guaranteed to resolve the same Stat later. A modifier
## applied to N boards gets N independent connections into its own
## [method StatModifier._on_source_changed], one per board.
func bind_modifier(m: StatModifier) -> void:
	if m.formula == null:
		return
	for id in m.formula.get_input_ids():
		var s := get_stat(id)
		if s == null:
			push_warning("StatBoard.bind_modifier: formula source stat '%s' not found in board" % id)
			continue
		if not s.value_changed.is_connected(m._on_source_changed):
			s.value_changed.connect(m._on_source_changed)


## Reverse of [method bind_modifier] — recomputes the same source list from
## [param m]'s formula and disconnects. Safe to call on an unbound modifier
## (formula == null, or nothing was ever connected — `is_connected` guards).
func unbind_modifier(m: StatModifier) -> void:
	if m.formula == null:
		return
	for id in m.formula.get_input_ids():
		var s := get_stat(id)
		if s != null and s.value_changed.is_connected(m._on_source_changed):
			s.value_changed.disconnect(m._on_source_changed)


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
		unbind_modifier(leaf)
		var s := get_stat(leaf.stat_id)
		if s == null:
			continue
		s.remove_modifier(leaf, self)


## Apply intrinsic_modifiers. Call once from Entity._ready() after the board
## is fully wired. No per-entry duplication needed (#377) — binding lives on
## THIS board, so applying the same instance to another board's
## intrinsic_modifiers (itself already a distinct array: Entity._ready
## duplicates the whole board with `duplicate(true)` before calling this)
## computes independently there too.
func apply_intrinsics() -> void:
	for m in intrinsic_modifiers:
		add_modifier(m)


## Sorted lexicographically so repeated calls return the same order (Dictionary
## iteration order isn't a contract to lean on for UI row stability).
## Every stat id LIVE on this board: non-null typed fields plus everything
## dynamically minted. This is what a UI enumerating "what's actually on this
## node" wants — [method get_dynamic_stat_ids] answers the strictly narrower
## "what got minted", and promoting a stat to a typed field silently drops it
## from that answer. Sorted lexicographically, same stability contract.
##
## Read-only: creates nothing, and skips a declared-but-null field (an entity
## board with a sparse `.tres` reports only what it carries).
func get_stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		if get(prop.name) is Stat:
			ids.append(StringName(prop.name))
	for id in _extra_stats:
		ids.append(id)
	ids.sort()
	return ids


## The ids of every DYNAMICALLY-created stat on this board — the sparse
## [member _extra_stats] set only. Typed `@export` fields are never included;
## use [method get_stat_ids] if you want everything.
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
