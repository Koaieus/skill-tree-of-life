class_name AuraDistanceCache
extends RefCounted

## Shared per-[code](mirror, source)[/code] hop-distance cache (#626) — of
## BOUNDED walks (#943): every entry remembers the hop cap it was walked to,
## and serves any later ask on the same generation whose cap it covers.
##
## [HopMetric] is the sole reader/writer — see [method HopMetric.depths].
## The problem it solves: two hop-metric auras sharing one source (the
## Serpent's pair, both radiating from the core) each ask [method
## DistanceMetric.distances] on every allocation/deallocation. Without this,
## that is two full unbounded BFS walks per event for what is, on the same
## topology generation, the exact same answer.
##
## [b]Validity is a generation stamp, not a signal.[/b] [EntityNavigator]
## bumps [member EntityNavigator.topology_generation] once per real structural
## change (node or edge entering/leaving the mirror) by overriding the
## handful of [GraphMirror] methods that ARE that change — see the doc comment
## there. A cached entry is stale iff its stamped generation no longer matches
## the mirror's current one; nothing here subscribes to anything.
##
## [b]Scope-limited by design.[/b] A [Scope.GLOBAL] aura's mirror is the
## whole-graph [Navigator], which carries no generation counter (that class
## isn't this issue's to touch). [method get_or_walk] degrades to "always walk
## fresh" for any mirror that doesn't expose one — correct, just unoptimized,
## exactly like every call site before this issue existed.
##
## [b]Static, not autoloaded.[/b] Every [AuraEffect] on every entity shares one
## registry, the same way the game already has exactly one [Graph] per level.
## [method forget_mirror] is how a freed [EntityNavigator] (entity death)
## avoids pinning a dangling key here forever.

## mirror(Object) -> { source(SkillNode) -> { "raw": Dictionary[SkillNode,float],
## "generation": int, "max_hops": int } }
static var _entries: Dictionary = {}

## Test seam: how many times [method get_or_walk] actually invoked its walk
## callable (a cache miss), rather than returning an already-valid entry. This
## is "the hop walk", the thing #626 acceptance 3 asserts happens once per
## topology change no matter how many auras ask. Tests reset it via
## [method clear].
static var walk_count: int = 0


## Non-mutating read of whatever raw distance map was cached for [param
## mirror]/[param source] as of the LAST walk — [code]{}[/code] if nothing has
## ever been walked. Deliberately ignores the current topology generation:
## callers use this to snapshot the "before" state for a diff, and by the time
## they ask, the generation has typically already moved past whatever's
## cached (the structural mutation that made it stale is what triggered the
## diff in the first place). Call this BEFORE [method get_or_walk] refreshes
## the entry.
static func peek(mirror: GraphMirror, source: SkillNode) -> Dictionary:
	if mirror == null or source == null:
		return {}
	var by_source: Dictionary = _entries.get(mirror, {})
	var entry: Dictionary = by_source.get(source, {})
	return entry.get("raw", {})


## The raw distance map for [param source] over [param mirror], walked to at
## least [param max_hops]. Walks fresh via [param walk_fn] (a one-arg
## [Callable] taking the hop cap and returning
## [code]Dictionary[SkillNode, float][/code]) only when nothing cached for the
## mirror's current topology generation covers the asked cap; every other
## caller within that generation gets the same [Dictionary] back untouched. A
## miss on a live generation re-walks to the WIDER of the two caps, so two
## auras asking different bounds converge on one entry instead of thrashing.
static func get_or_walk(mirror: GraphMirror, source: SkillNode, max_hops: int, walk_fn: Callable) -> Dictionary:
	if mirror == null or source == null:
		return walk_fn.call(max_hops)
	var gen := _generation_of(mirror)
	if gen < 0:
		return walk_fn.call(max_hops)
	if not _entries.has(mirror):
		_entries[mirror] = {}
	var by_source: Dictionary = _entries[mirror]
	var entry: Dictionary = by_source.get(source, {})
	var same_gen: bool = entry.get("generation", -1) == gen
	if not same_gen or int(entry.get("max_hops", -1)) < max_hops:
		var cap := maxi(max_hops, int(entry.get("max_hops", -1))) if same_gen else max_hops
		walk_count += 1
		entry = {"raw": walk_fn.call(cap), "generation": gen, "max_hops": cap}
		by_source[source] = entry
	return entry["raw"]


## The hop cap the entry for [param mirror]/[param source] was walked to on
## the mirror's CURRENT topology generation, or -1 when nothing current is
## cached (stale generation, never walked, or an uncacheable mirror). A
## widening walker ([method HopMetric.depths]) doubles from this, not from its
## own ask: a hit on a wider entry hands back that whole ball, and doubling a
## cap the entry already covers would just hit it again — no walk, no growth.
static func cached_cap(mirror: GraphMirror, source: SkillNode) -> int:
	if mirror == null or source == null:
		return -1
	var gen := _generation_of(mirror)
	if gen < 0:
		return -1
	var by_source: Dictionary = _entries.get(mirror, {})
	var entry: Dictionary = by_source.get(source, {})
	if entry.get("generation", -1) != gen:
		return -1
	return int(entry.get("max_hops", -1))


## Drop every cache entry belonging to [param mirror] — called from
## [method EntityNavigator._exit_tree] so a freed entity's navigator doesn't
## pin a dangling dictionary key forever.
static func forget_mirror(mirror: GraphMirror) -> void:
	_entries.erase(mirror)


## Test-only full reset. GUT tests share this process, so a stale entry from a
## previous test's (by-then-freed) mirror must not collide with a new mirror
## instance — object identity as a Dictionary key says nothing about lifetime.
static func clear() -> void:
	_entries.clear()
	walk_count = 0


static func _generation_of(mirror: GraphMirror) -> int:
	if mirror is EntityNavigator:
		return (mirror as EntityNavigator).topology_generation
	return -1
