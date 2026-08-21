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
## just `Object.get(id)`, and a subclass's fields are discovered for free by
## the introspection walk in [method _stat_property_names], cached per board
## class and shared by [method collect_formula_edges], [method get_pool_stats]
## and [method get_stat_ids] (#402). That introspection IS the mechanism, and
## it is why the split is inheritance rather than an array of sub-boards:
## sub-boards would mean reimplementing discovery in five places.

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

## Coalescing state — see [method begin_batch].
const _MAX_FLUSH_ROUNDS := 16

var _batch_depth: int = 0
var _dirty_stats: Dictionary = {}  # Stat → true


# --- Stat-typed field discovery (cached per board class) -------------------

## [Script] → PackedStringArray of that script's declared Stat-typed field
## names. Keyed by class rather than instance because the answer is a CLASS
## fact (which fields exist), not an instance fact (which are populated) —
## see [method _stat_property_names].
static var _stat_props_by_script: Dictionary = {}

## Names of this board's declared `@export` fields whose type is [Stat] or a
## subclass — computed once per board class ([method Object.get_script]) and
## cached in [member _stat_props_by_script], since [method
## Object.get_property_list] costs ~11us per call and this walk used to run on
## every [method collect_formula_edges] / [method get_pool_stats] / [method
## get_stat_ids] call, once per [SkillNode] at level-generation scale (#402).
##
## Deliberately keyed on the DECLARED type (`prop.class_name`, a class fact),
## not on whether `get(prop.name) is Stat` (an instance fact) — a sparse
## `.tres` may leave a declared field null, and two boards of the same class
## can disagree on which fields are populated. Caching "fields non-null on the
## first instance seen" would silently drop a stat on the second one, so every
## call site below still does its own per-instance null check; this cache only
## narrows which property names are worth checking.
##
## `key` is deliberately untyped (`:=` on [method Object.get_script] crashes
## the script loader with "p_script->implicit_initializer is null" the first
## time a subclass instance calls in — verified empirically; the plain `=`
## form works fine).
func _stat_property_names() -> PackedStringArray:
	var key = get_script()
	var cached = _stat_props_by_script.get(key)
	if cached != null:
		return cached
	var names := PackedStringArray()
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var cls: String = prop.class_name
		if cls != "" and _class_extends_stat(cls):
			names.append(prop.name)
	_stat_props_by_script[key] = names
	return names


## Whether [param cls] (a global `class_name`) is [Stat] or a descendant, by
## walking [method ProjectSettings.get_global_class_list] rather than
## `ClassDB` — GDScript's global classes (Stat, ScalarStat, PoolStat, …) are
## NOT registered with `ClassDB`, so `ClassDB.is_parent_class` silently
## returns false for every one of them (verified empirically: same shape as
## [code]test_stat_accessors.gd[/code]'s `_extends_stat` helper).
static func _class_extends_stat(cls: String) -> bool:
	var guard := 0
	while cls != "" and guard < 16:
		if cls == "Stat":
			return true
		var found := false
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == cls:
				cls = entry.get("base", "")
				found = true
				break
		if not found:
			return false
		guard += 1
	return false


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
	for prop_name in _stat_property_names():
		var v: Variant = get(prop_name)
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
## Coalesce `value_changed` notifications until the matching [method end_batch].
##
## [b]Why.[/b] Installing a node's modifiers is a loop of [method add_modifier],
## and each one emits immediately. When two of a node's modifiers both feed the
## same downstream stat, every listener runs the full cascade twice for one
## logical event. Measured 2026-08-17 on a 2000-node level at 200 owned: a node
## granting `constitution` AND `node_health` moved the entity's `node_health`
## twice (1362 -> 1382 -> 1411), and each move re-synced the combat health pool
## of EVERY owned node — 397 syncs for 197 nodes, 75-83% of the whole
## allocation. Batching makes that one cascade instead of two.
##
## [b]This defers notification, never value.[/b] [method Stat.get_value]
## recomputes from the bins on every call, so a read taken mid-batch is already
## correct — only the signal waits. Pool ratcheting is likewise unaffected:
## [method PoolStat._apply_max_change] runs on the add/remove path itself, not
## off `value_changed`.
##
## Re-entrant: nested begin/end pairs flush once, at the outermost end.
## ALWAYS pair it — an unmatched `begin_batch` silently swallows every
## subsequent notification on this board.
func begin_batch() -> void:
	_batch_depth += 1


func is_batching() -> bool:
	return _batch_depth > 0


## Records a stat whose notification was suppressed. Called by
## [method Stat._emit_value_changed]; not meant for outside callers.
func mark_stat_dirty(s: Stat) -> void:
	_dirty_stats[s] = true


## Close the batch and emit one `value_changed` per stat that moved.
##
## Flushing stays *inside* the batch (`_batch_depth` drops only at the very end)
## because emitting is what drives formula modifiers, and those recompute
## downstream stats. Dropping the depth first would let that second wave emit
## per-stat immediately — reintroducing exactly the duplicate cascade this
## exists to remove. Instead the wave lands back in `_dirty_stats` and is
## flushed by the next loop iteration, so each stat notifies once per settle.
##
## The iteration cap is a safety net against a pathological oscillation, not an
## expected path; the formula graph is already kept acyclic by
## [method cycle_from].
func end_batch() -> void:
	if _batch_depth <= 0:
		push_warning("StatBoard.end_batch called without a matching begin_batch")
		return
	if _batch_depth > 1:
		_batch_depth -= 1
		return
	var guard := 0
	while not _dirty_stats.is_empty() and guard < _MAX_FLUSH_ROUNDS:
		guard += 1
		for s in _sorted_dirty_wave():
			# Re-check: emitting an earlier stat may already have covered this
			# one (a formula recompute erases nothing, but a listener could).
			if not _dirty_stats.has(s):
				continue
			# Erase BEFORE emitting. A dependent stat re-dirtied by this
			# emission lands back in the set and is picked up later in the SAME
			# wave — which is the whole point of the ordering. Erasing after
			# would drop that re-mark and lose the notification.
			_dirty_stats.erase(s)
			if is_instance_valid(s):
				s.value_changed.emit()
	if guard >= _MAX_FLUSH_ROUNDS:
		push_warning("StatBoard.end_batch hit the flush-round cap; a formula cascade is not settling")
	_dirty_stats.clear()
	_batch_depth = 0


## The dirty set ordered so a stat is emitted only after every stat it derives
## from — sources first, dependents last.
##
## This ordering is what makes the flush emit each stat exactly once. Emitting
## `constitution` recomputes the `node_health` intrinsic and re-dirties
## `node_health`; if `node_health` had already been emitted, that re-mark would
## force a second round and a second full cascade — which is the duplicate this
## whole mechanism exists to remove. Sorted, `node_health` is still pending when
## the re-mark lands, so one emission serves both.
##
## Depth is over the formula dependency graph, which [method cycle_from] keeps
## acyclic; the visited guard is belt-and-braces for a cycle that slipped in at
## runtime, and degrades to an arbitrary-but-terminating order.
func _sorted_dirty_wave() -> Array:
	var edges: Dictionary = {}
	collect_formula_edges(edges)
	var depths: Dictionary = {}
	var wave: Array = _dirty_stats.keys()
	wave.sort_custom(func(a: Stat, b: Stat) -> bool:
		return _formula_depth(_stat_id_of(a), edges, depths, {}) \
			< _formula_depth(_stat_id_of(b), edges, depths, {}))
	return wave


func _stat_id_of(s: Stat) -> StringName:
	return s.definition.id if s != null and s.definition != null else &""


func _formula_depth(id: StringName, edges: Dictionary, memo: Dictionary, visiting: Dictionary) -> int:
	if memo.has(id):
		return memo[id]
	if visiting.has(id):
		return 0  # cycle — treat as a source rather than recursing forever
	visiting[id] = true
	var deepest := 0
	for input_id in edges.get(id, []):
		deepest = maxi(deepest, _formula_depth(input_id, edges, memo, visiting) + 1)
	visiting.erase(id)
	memo[id] = deepest
	return deepest


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
	for prop_name in _stat_property_names():
		if get(prop_name) is Stat:
			ids.append(StringName(prop_name))
	for id in _extra_stats:
		ids.append(id)
	ids.sort()
	return ids


## Deep-clone this board INCLUDING its live state — every modifier already
## applied to it, and every dynamically-minted stat.
##
## [b]Use this, not a bare `duplicate(true)`, whenever the source board is
## already live.[/b] `duplicate(true)` carries only EXPORTED properties, so
## every typed `Stat`/`PoolStat` field survives as its own resource but each
## one's [member Stat.bins] (a plain, non-exported [ModifierBins]) comes back
## fresh and EMPTY, and [member _extra_stats] — where every dynamically-minted
## stat lives, `node_health` among them — does not survive at all. No error
## either way; the clone just quietly reads as an unmodified board.
##
## Nothing needed this before #498, which is why the gap went unnoticed: every
## other `duplicate(true)` in the codebase clones a VIRGIN template and builds
## its bins up live afterwards ([method apply_intrinsics], [AllocationSystem]'s
## `add_modifier` calls). A combat shadow ([method EntityCombat.snapshot]) is
## the first caller that must clone an already-modified board and keep what is
## on it — there, a bare `duplicate()` silently drops every applied modifier,
## which is the scoring inaccuracy #498 exists to fix, reintroduced one layer
## down.
##
## [member ModifierBins.multipliers] is copied one level deep: the Array is the
## clone's own, so membership changes are isolated, but the [StatModifier]s
## inside are SHARED with the source (as is `winning_set`). That is deliberate
## and safe — a modifier is stateless and may live on N boards at once (#377),
## and a shadow adds or revokes modifiers, it never edits one in place.
func clone_live() -> StatBoard:
	var dst := duplicate(true) as StatBoard
	if dst == null:
		return null
	for id in get_stat_ids():
		var src_stat: Stat = get_stat(id)
		if src_stat == null:
			continue
		# _ensure_stat, not get_stat — a dynamically-minted source stat has no
		# counterpart on `dst` at all yet (see above).
		var dst_stat: Stat = dst._ensure_stat(id)
		if dst_stat == null:
			continue
		dst_stat.base_value = src_stat.base_value
		if dst_stat is PoolStat and src_stat is PoolStat:
			(dst_stat as PoolStat).current = (src_stat as PoolStat).current
		dst_stat.bins.base_add = src_stat.bins.base_add
		dst_stat.bins.increase_sum = src_stat.bins.increase_sum
		dst_stat.bins.bonus_add = src_stat.bins.bonus_add
		dst_stat.bins.multipliers = src_stat.bins.multipliers.duplicate()
		dst_stat.bins.winning_set = src_stat.bins.winning_set
		dst_stat.bins.board = dst
	return dst


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
	for prop_name in _stat_property_names():
		var v: Variant = get(prop_name)
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
