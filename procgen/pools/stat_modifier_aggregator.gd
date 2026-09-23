class_name StatModifierAggregator
extends RefCounted

## The v4 draw's per-(stat_id, operation) fuse (#321 D3): every rolled
## modifier is appended, and those sharing a `(stat_id, operation)` fuse into
## one line — ADD_BASE / ADD_BONUS / INCREASE sum, MULTIPLY products (×1.15 ·
## ×1.15 = ×1.3225, not ×2.30). SET has no merge rule yet (see
## [method merge_into]).
##
## Invariants:
## - One [Group] per key; the key is built from `stat_id` and `operation`
##   only — nothing else distinguishes two mergeable modifiers.
## - A group's `entries` are the pool entries that fused into it, in append
##   (pick) order. [method reroll_into] replays exactly that order, so it is a
##   cross-peer determinism invariant, not incidental
##   (.claude/rules/multiplayer-sync.md).
## - [method get_aggregate] is descending total cost (tooltips read
##   biggest-investment-first); ties keep the dictionary's insertion order
##   through the same `sort_custom` the draw has always used.
##
## See [method GraphProcgen._roll_modifiers_v4] and docs/domain/procgen-v4.md.


## One fused line: the modifier every contribution merged into, the summed
## budget spent on it, and the contributing entries in pick order.
class Group extends RefCounted:
	var mod: StatModifier
	var cost: int
	var entries: Array[ModifierPoolEntry] = []


var _groups: Dictionary[StringName, Group] = {}


## The fuse key: two modifiers merge iff their keys are equal.
static func key_of(mod: StatModifier) -> StringName:
	return StringName("%s|%d" % [mod.stat_id, mod.operation])


## Ingests `mod` (bought with `cost`, rolled from `entry`), merging it
## destructively into the existing line for its key if there is one.
func append(mod: StatModifier, cost: int, entry: ModifierPoolEntry) -> void:
	var key := key_of(mod)
	var group: Group = _groups.get(key)
	if group == null:
		group = Group.new()
		group.mod = mod
		group.cost = cost
		group.entries.append(entry)
		_groups[key] = group
		return
	merge_into(group.mod, mod)
	group.cost += cost
	group.entries.append(entry)


## The fused modifiers, descending total cost.
func get_aggregate() -> Array[StatModifier]:
	var groups := _groups.values()
	groups.sort_custom(func(a: Group, b: Group): return a.cost > b.cost)
	var out: Array[StatModifier] = []
	for g: Group in groups:
		out.append(g.mod)
	return out


## The entries that fused into `mod`'s line, in pick order; empty if none.
func entries_for(mod: StatModifier) -> Array[ModifierPoolEntry]:
	var group: Group = _groups.get(key_of(mod))
	if group == null:
		return [] as Array[ModifierPoolEntry]
	return group.entries


## Updates `a` by merging in the contribution of `b`. Static (#629): also the
## primitive [method reroll_into] fuses fresh rolls with — one merge
## implementation. The asserts document the precondition that
## [method append]'s keying guarantees (tested through `append`, since GUT
## cannot catch an assert and release builds strip them).
static func merge_into(a: StatModifier, b: StatModifier) -> StatModifier:
	assert(a.stat_id == b.stat_id, "Can't merge modifiers that don't have the same Stat ID")
	assert(a.operation == b.operation, "Can't merge modifiers that don't have the same operation")
	match a.operation:
		StatModifier.Operation.MULTIPLY:
			a.value *= b.value
		StatModifier.Operation.SET:
			assert(false, "Can't merge SET value yet. No sensible outcome.")
		_:
			a.value += b.value
	return a


## #629: re-rolls every entry in `group` (same entries, same order as the
## original draw) from `rng` and fuses them into `mod` IN PLACE, replacing its
## stale value. `rng` must be the same seeded stream the original draw used —
## this is what makes the retry deterministic across peers.
static func reroll_into(mod: StatModifier, group: Array, rng: RandomNumberGenerator) -> void:
	var fresh: StatModifier = null
	for e in group:
		var m: StatModifier = (e as ModifierPoolEntry).roll(rng)
		if fresh == null:
			fresh = m
		else:
			merge_into(fresh, m)
	mod.value = fresh.value
