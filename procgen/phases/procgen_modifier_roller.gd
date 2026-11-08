@tool
class_name ProcgenModifierRoller
extends RefCounted

## Stage 5 of [method GraphProcgen.generate] (hub #422, child 0): the per-node
## modifier draw, extracted from `graph_procgen.gd` with its body unchanged.
## Static and stateless — the caller hands in the pools, profiles and the
## `rng`, owns every salt and the draw order, and emits progress itself; this
## phase never touches the callback. Same seed → byte-identical graph is
## guarded by `test/integration/procgen/test_procgen_golden.gd`.
##
## v4 modifier draw. Spend-until-broke with per-(stat,op) aggregation:
##   1. Flatten the pools relevant to this node: those of every pack whose
##      archetype_stat == primary_stat OR == &"" (universal). No off-archetype phase, no defensive/rare roles.
##   2. Spend `budget` until broke: weighted-pick an affordable entry applying
##      weight profiles (archetype), subtract its cost, repeat. Every entry
##      costs `+T`, whatever its rolled value's sign (no refund economics for
##      negative pools; see docs/domain/procgen-v4.md). T1 always costs 1, so
##      leftover budget always drains into T1 filler — budget is never
##      wasted (D3).
##   3. Aggregate the rolled modifiers per (stat_id, operation): ADD* and
##      INCREASE sum, MULTIPLY delta sum floored at `multiply_fuse_floor`,
##      SET max (D3). Line count on a node is
##      now bounded by the number of distinct (stat, op) pairs it drew — not
##      by the number of draws.
##
## See docs/domain/procgen-v4.md.

## A fused (stat,op) result equal to its operation's neutral element
## (0 for ADD*/INCREASE, 1 for MULTIPLY — SET has none, see [method
## is_neutral_result]) is a no-op slot and gets re-rolled. Bounded and
## seeded (never an unbounded retry loop) so two peers on the same seed
## retry an identical number of times — see .claude/rules/multiplayer-sync.md.
## Proposed by the issue; not tuned further.
const NO_OP_RETRY_CAP := 3

## The `remaining` an extra roll pass hands the pick: large enough that every
## entry is affordable, which is how "cost ignored" is stated.
const EXTRA_PASS_UNBOUNDED_BUDGET := 1 << 30

static func run(
		pool_set: ModifierPoolSet,
		profiles: Array[Resource],
		archetype: StringName,
		primary_stat: StringName,
		forbid_tags: Array[StringName],
		position: Vector2,
		node_index: int,
		budget: int,
		rng: RandomNumberGenerator,
		fp: Dictionary = {},
		# Last and defaulted on purpose: every existing caller passes `fp`
		# positionally, and a subtype-less caller is a node with no subtype.
		subtype: NodeSubtype = null,
		universal_share: float = GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE,
		multiply_fuse_floor: float = GraphProcgenContent.DEFAULT_MULTIPLY_FUSE_FLOOR,
) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	fp["phase"] = "v4"
	if pool_set == null or pool_set.packs.is_empty() or budget <= 0:
		return out

	var entries := pool_set.flatten_for_node(primary_stat, subtype, StatPool.BUDGET_PASS)
	var extra_passes: Array[RollPass] = []
	if subtype != null:
		extra_passes = subtype.extra_passes
	if entries.is_empty() and extra_passes.is_empty():
		return out

	var ctx := WeightContext.new()
	ctx.archetype = archetype
	ctx.position = position
	ctx.node_index = node_index
	ctx.forbid_tags = forbid_tags

	var remaining := budget
	# Rolled values collected per (stat_id, op) for aggregation. Each entry.roll
	# already coerces the sampled value (INCREASE → int, ADD by stat value_type,
	# MULTIPLY/SET raw float), so aggregating the coerced values keeps the
	# snapping semantics of ModifierPoolEntry.coerce_to_stat_type.
	var rolled := StatModifierAggregator.new(multiply_fuse_floor)
	var draws := 0

	while remaining > 0:
		var entry := weighted_pick(entries, profiles, ctx, remaining, rng, universal_share)
		if entry == null:
			break
		rolled.append(entry.roll(rng), entry.cost, entry)
		remaining -= entry.cost  # cost is always positive — spend is monotonic.
		draws += 1
		# Safety net: every cost is >= 1 (TierLadder floor), so this loop is
		# already bounded by `budget`, but cap draws generously anyway in
		# case a mis-authored pool ever ships a 0-or-negative cost.
		if draws > 64:
			break

	fp["draws"] = draws
	fp["remaining"] = remaining

	# Extra roll passes: after the budget loop, on the same rng, in array
	# order — a replay input. Each spends no budget (the pick sees an
	# unbounded `remaining`, so cost gates nothing) and makes one weighted
	# pick among the entries that pass admits. Its roll stacks with any
	# budget roll of the same stat through the aggregator below.
	# See docs/domain/node-subtypes.md § Roll passes.
	var extra_rolls := 0
	for roll_pass in extra_passes:
		if roll_pass == null or rng.randf() >= roll_pass.chance:
			continue
		var pass_entries := pool_set.flatten_for_node(primary_stat, subtype, roll_pass.id)
		var pick := weighted_pick(pass_entries, profiles, ctx, EXTRA_PASS_UNBOUNDED_BUDGET, rng, universal_share)
		if pick == null:
			continue
		rolled.append(pick.roll(rng), pick.cost, pick)
		extra_rolls += 1
	fp["extra_rolls"] = extra_rolls

	# Aggregate per (stat_id, operation). ADD_BASE / ADD_BONUS / INCREASE sum
	# (PoE-additive); MULTIPLY delta sum (\times1.15 & \times1.15 = \times1.30,
	# not \times1.3225), floored once per line; SET max. Emitted in
	# descending aggregated-cost order, so tooltips read
	# biggest-investment-first.
	#
	# A fused result can land exactly on its operation's neutral element
	# (M can be negative — see docs/domain/procgen-v4.md) — a slot that does
	# nothing. Detected AFTER fusion (never per-roll: individual rolls are
	# allowed to be small or negative), re-rolled from the SAME contributing
	# entries in the SAME order — deterministic, so two peers on one seed
	# retry identically — up to NO_OP_RETRY_CAP times, then dropped rather
	# than shipped as a visible no-op.
	var aggregate := rolled.get_aggregate()
	var final: Array[StatModifier] = []
	var no_op_retries := 0
	var dropped := 0
	for mod in aggregate:
		var group: Array = rolled.entries_for(mod)
		var attempt := 0
		while is_neutral_result(mod) and attempt < NO_OP_RETRY_CAP:
			StatModifierAggregator.reroll_into(mod, group, rng, multiply_fuse_floor)
			attempt += 1
			no_op_retries += 1
		if is_neutral_result(mod):
			dropped += 1
		else:
			final.append(mod)
	fp["no_op_retries"] = no_op_retries
	fp["dropped"] = dropped
	return final

## True iff `mod`'s value is its operation's neutral element (a fused no-op).
## Which value that IS per op is not restated here — it is
## [method StatModifier.displacement_from_neutral], the one home of the law;
## a no-op is a zero displacement.
##
## Two rules stay at THIS call site because they are procgen's, not the stat
## system's: `SET` is never a no-op even though it has no neutral
## element to displace from, and the value is coercion-aware via the same
## [method ModifierPoolEntry.coerce_to_stat_type] the roll path uses — a
## `+0.4` on an INT stat coerces to `0` (a no-op) where the same value on a
## FLOAT stat does not.
static func is_neutral_result(mod: StatModifier) -> bool:
	if mod.operation == StatModifier.Operation.SET:
		return false
	var v := mod.value
	if mod.operation != StatModifier.Operation.MULTIPLY:
		v = ModifierPoolEntry.coerce_to_stat_type(mod.value, mod.operation, mod.stat_id)
	return is_zero_approx(StatModifier.displacement_from_neutral(mod.operation, v))

## The v4 pick as a distribution: entry → probability, summing to 1, or empty
## when nothing is drawable (the node is broke). Three levels, each
## renormalized over what is drawable at THIS pick — an entry is drawable iff
## it passes `forbid_tags`, every profile leaves it a positive multiplier, and
## (for the tier level) it is affordable:
##   group — universal (`entry.universal`) gets `universal_share`, archetype the
##           rest; a group with nothing drawable cedes the whole pick.
##   pool  — `pool_weight × m̄` within its group, `m̄ = Σ w_t·m_t / Σ w_t` over
##           the pool's drawable tiers regardless of budget, so a pool with any
##           affordable tier keeps its full mass (budget reshapes tiers only);
##           a pool with none drops out and its siblings share its mass.
##   tier  — `w_t·m_t` over the pool's affordable drawable tiers.
## `w_t` is the entry's bare tier weight, `m_t` the product of profile
## multipliers. Pools are keyed by `pool_key` (a keyless hand-built entry is its
## own pool) in first-appearance order, so iteration is entry order and every
## peer reproduces the same distribution. Zero-probability entries are omitted.
static func pick_distribution(
		entries: Array[ModifierPoolEntry],
		profiles: Array[Resource],
		context: WeightContext,
		remaining: int,
		universal_share: float,
) -> Dictionary:
	var pools := {}
	for e in entries:
		if e == null or e.weight <= 0.0 or e.pool_weight <= 0.0:
			continue
		if not context.forbid_tags.is_empty() and _has_forbidden_tag(e, context.forbid_tags):
			continue
		var wm := e.weight
		for p in profiles:
			if p == null:
				continue
			wm *= p.multiplier_for(e, context)
			if wm <= 0.0:
				break
		if wm <= 0.0:
			continue
		@warning_ignore("incompatible_ternary")
		var key: Variant = e.pool_key if e.pool_key != &"" else e
		if not pools.has(key):
			pools[key] = {"universal": e.universal, "pool_weight": e.pool_weight,
				"w": 0.0, "wm": 0.0, "tiers": [], "tier_wm": [], "tier_total": 0.0}
		var pool: Dictionary = pools[key]
		pool.w += e.weight
		pool.wm += wm
		if e.cost <= remaining:
			pool.tiers.append(e)
			pool.tier_wm.append(wm)
			pool.tier_total += wm
	# Index 0 = archetype, 1 = universal.
	var group_mass: Array[float] = [0.0, 0.0]
	var live: Array[Dictionary] = []
	for pool: Dictionary in pools.values():
		if pool.tier_total <= 0.0:
			continue
		pool.mass = pool.pool_weight * pool.wm / pool.w
		pool.group = 1 if pool.universal else 0
		group_mass[pool.group] += pool.mass
		live.append(pool)
	var out := {}
	if live.is_empty():
		return out
	var u := clampf(universal_share, 0.0, 1.0)
	if group_mass[1] <= 0.0:
		u = 0.0
	elif group_mass[0] <= 0.0:
		u = 1.0
	var group_p: Array[float] = [1.0 - u, u]
	for pool in live:
		var pool_p: float = group_p[pool.group] * pool.mass / group_mass[pool.group]
		if pool_p <= 0.0:
			continue
		for i in pool.tiers.size():
			out[pool.tiers[i]] = pool_p * pool.tier_wm[i] / pool.tier_total
	return out


## One weighted sample over [method pick_distribution] — a single
## `randf()`, in the distribution's (entry) order. Null iff nothing is
## drawable. Cost is always positive — one affordability rule for every
## pool regardless of its rolled value's sign.
static func weighted_pick(
		entries: Array[ModifierPoolEntry],
		profiles: Array[Resource],
		context: WeightContext,
		remaining: int,
		rng: RandomNumberGenerator,
		universal_share: float = GraphProcgenContent.DEFAULT_UNIVERSAL_SHARE,
) -> ModifierPoolEntry:
	var dist := pick_distribution(entries, profiles, context, remaining, universal_share)
	if dist.is_empty():
		return null
	var r := rng.randf()
	var last: ModifierPoolEntry = null
	for e: ModifierPoolEntry in dist:
		last = e
		r -= dist[e]
		if r <= 0.0:
			return e
	return last


static func _has_forbidden_tag(entry: ModifierPoolEntry, forbid: Array[StringName]) -> bool:
	for t in entry.tags:
		if t in forbid:
			return true
	return false
