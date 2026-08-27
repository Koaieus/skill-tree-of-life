class_name AuraDistanceCache
extends RefCounted

## Shared per-[code](mirror, source)[/code] hop-distance cache (#626).
##
## [HopMetric] is the sole reader/writer — see [method HopMetric.distances].
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
## "generation": int } }
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


## The full raw distance map for [param source] over [param mirror]. Walks
## fresh via [param walk_fn] (a zero-arg [Callable] returning
## [code]Dictionary[SkillNode, float][/code]) only when nothing valid is
## cached for the mirror's current topology generation; every other caller
## within that generation gets the same [Dictionary] back untouched.
static func get_or_walk(mirror: GraphMirror, source: SkillNode, walk_fn: Callable) -> Dictionary:
	if mirror == null or source == null:
		return walk_fn.call()
	var gen := _generation_of(mirror)
	if gen < 0:
		return walk_fn.call()
	if not _entries.has(mirror):
		_entries[mirror] = {}
	var by_source: Dictionary = _entries[mirror]
	var entry: Dictionary = by_source.get(source, {})
	if entry.get("generation", -1) != gen:
		walk_count += 1
		entry = {"raw": walk_fn.call(), "generation": gen}
		by_source[source] = entry
	return entry["raw"]


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
