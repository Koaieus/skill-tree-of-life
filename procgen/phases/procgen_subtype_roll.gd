@tool
class_name ProcgenSubtypeRoll
extends RefCounted

## The per-node subtype roll of [method GraphProcgen.generate] (hub #422,
## child 1), extracted from `graph_procgen.gd` with its body unchanged.
## Static and stateless — the caller derives the salted stream
## (`_SUBTYPE_RNG_SALT` on [GraphProcgen]), computes [method build_drawability]
## ONCE per generate() and hands both in; this phase never touches the
## progress callback. Same seed → byte-identical graph is guarded by
## `test/integration/procgen/test_procgen_golden.gd`.
## See docs/domain/node-subtypes.md (D13, D14).


## D13's guard, precomputed ONCE per `generate()` — never inside the node loop.
## Keyed `"<primary_stat>|<subtype id>"` over every authored archetype × every
## weighted subtype, because the predicate is per-(archetype, subtype): whether
## a rolled subtype has anything to draw depends on the node's archetype and
## nothing else about the node.
static func build_drawability(content: GraphProcgenContent) -> Dictionary:
	var out: Dictionary = {}
	if content == null or content.subtypes.is_empty():
		return out
	for policy in content.archetypes:
		if policy == null or policy.archetype == null:
			continue
		var primary: StringName = policy.archetype.primary_stat
		for subtype in content.subtypes:
			if subtype == null:
				continue
			var key := "%s|%s" % [primary, subtype.id]
			if not out.has(key):
				out[key] = has_pool_naming_subtype(
						content.modifier_pool_set, primary, subtype)
	return out


## Strictly "some reachable pool NAMES this subtype". An ungated (`[]`) pool
## deliberately does not count: it is drawn by every subtype, so counting it
## would let every roll stand while drawing exactly the default's content —
## which is the "looks blighted, plays regular" node D13 exists to prevent.
static func has_pool_naming_subtype(
		pool_set: ModifierPoolSet,
		primary_stat: StringName,
		subtype: NodeSubtype,
) -> bool:
	if pool_set == null:
		return false
	for pack in pool_set.packs:
		if pack == null:
			continue
		if pack.archetype_stat != &"" and pack.archetype_stat != primary_stat:
			continue
		for pool in pack.pools:
			if pool == null or pool.subtypes.is_empty():
				continue
			if pool.admits_subtype(subtype):
				return true
	return false


## The per-node weighted pick: each subtype claims its own
## `base_chance` slice, the default is the remainder. Exactly one draw per node
## whatever the authored chances say, so retuning one never shifts another
## node's roll — and NO draw at all when nothing is authored, which is what
## keeps "with subtypes" and "without" honestly comparable on the main stream.
## A rolled subtype with no drawable content demotes to the default (D13) — it
## still consumed its draw.
static func run(
		subtypes: Array[NodeSubtype],
		primary_stat: StringName,
		drawable: Dictionary,
		default_subtype: NodeSubtype,
		rng: RandomNumberGenerator,
) -> NodeSubtype:
	if subtypes.is_empty():
		return default_subtype
	var r := rng.randf()
	var acc := 0.0
	for s in subtypes:
		if s == null:
			continue
		acc += s.base_chance
		if r < acc:
			if drawable.get("%s|%s" % [primary_stat, s.id], false):
				return s
			return default_subtype
	return default_subtype
