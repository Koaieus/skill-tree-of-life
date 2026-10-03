class_name StatModifierAggregator
extends RefCounted

## The v4 draw's per-(stat_id, operation) fuse (#321 D3): every rolled
## modifier is appended, and those sharing a `(stat_id, operation)` fuse into
## one line — ADD_BASE / ADD_BONUS / INCREASE sum, MULTIPLY by delta sum
## `1 + Σ(mᵢ − 1)` (×1.15 & ×1.15 = ×1.30, not ×1.3225) clamped once at the
## content's `multiply_fuse_floor`. SET has no merge rule yet (see
## [method merge_into]).
##
## The delta sum tames the spread of stacked small rolls on one node; it
## deliberately differs from in-game stacking, where MULTIPLY instances
## multiply through the stat pipeline.
##
## Invariants:
## - One [Group] per key; the key is built from `stat_id` and `operation`
##   only — nothing else distinguishes two mergeable modifiers.
## - A group's `entries` are the pool entries that fused into it, in append
##   (pick) order. [method reroll_into] replays exactly that order, so it is a
##   cross-peer determinism invariant, not incidental
##   (.claude/rules/multiplayer-sync.md).
## - The floor clamps the whole fused MULTIPLY line, never a pairwise merge
##   (clamping per merge would make the fuse depend on pick order beyond
##   the sum: 0.5, 0.5, 1.5 must read 0.5).
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
var _multiply_fuse_floor: float


## `multiply_fuse_floor` is the lowest value a fused MULTIPLY line reads
## ([member GraphProcgenContent.multiply_fuse_floor]).
func _init(multiply_fuse_floor: float) -> void:
	_multiply_fuse_floor = multiply_fuse_floor


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


## The fused modifiers, descending total cost. Clamps MULTIPLY lines to the
## floor IN PLACE (idempotent): call it after the last [method append], which
## would otherwise delta-sum onto a clamped value.
func get_aggregate() -> Array[StatModifier]:
	var groups := _groups.values()
	groups.sort_custom(func(a: Group, b: Group): return a.cost > b.cost)
	var out: Array[StatModifier] = []
	for g: Group in groups:
		apply_floor(g.mod, _multiply_fuse_floor)
		out.append(g.mod)
	return out


## The entries that fused into `mod`'s line, in pick order; empty if none.
func entries_for(mod: StatModifier) -> Array[ModifierPoolEntry]:
	var group: Group = _groups.get(key_of(mod))
	if group == null:
		return [] as Array[ModifierPoolEntry]
	return group.entries


## Updates `a` by merging in the contribution of `b`. MULTIPLY is the
## UNCLAMPED delta sum — the floor is [method apply_floor]'s, once per line. Static (#629): also the
## primitive [method reroll_into] fuses fresh rolls with — one merge
## implementation. The asserts document the precondition that
## [method append]'s keying guarantees (tested through `append`, since GUT
## cannot catch an assert and release builds strip them).
static func merge_into(a: StatModifier, b: StatModifier) -> StatModifier:
	assert(a.stat_id == b.stat_id, "Can't merge modifiers that don't have the same Stat ID")
	assert(a.operation == b.operation, "Can't merge modifiers that don't have the same operation")
	match a.operation:
		StatModifier.Operation.MULTIPLY:
			a.value += b.value - 1.0
		StatModifier.Operation.SET:
			assert(false, "Can't merge SET value yet. No sensible outcome.")
		_:
			a.value += b.value
	return a


## Clamps a fused MULTIPLY line at `multiply_fuse_floor`; other ops pass.
static func apply_floor(mod: StatModifier, multiply_fuse_floor: float) -> void:
	if mod.operation == StatModifier.Operation.MULTIPLY:
		mod.value = maxf(mod.value, multiply_fuse_floor)


## #629: re-rolls every entry in `group` (same entries, same order as the
## original draw) from `rng` and fuses them into `mod` IN PLACE, replacing its
## stale value. `rng` must be the same seeded stream the original draw used —
## this is what makes the retry deterministic across peers.
static func reroll_into(mod: StatModifier, group: Array, rng: RandomNumberGenerator,
		multiply_fuse_floor: float) -> void:
	var fresh: StatModifier = null
	for e in group:
		var m: StatModifier = (e as ModifierPoolEntry).roll(rng)
		if fresh == null:
			fresh = m
		else:
			merge_into(fresh, m)
	apply_floor(fresh, multiply_fuse_floor)
	mod.value = fresh.value
