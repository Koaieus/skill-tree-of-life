@tool
class_name StatPool
extends Resource

## Authoring unit for procgen modifier content (v4, #321). Replaces the old
## [TierPool] + [TierDef] pair with one flat resource: ~8 fields per pool, no
## per-tier sub-resources. The cost/value ladder lives once in [TierLadder] —
## a pool carries only `unit_value` (the T1 magnitude) and an optional sparse
## `value_overrides` escape hatch (#321 D11).
##
## Mapping to runtime: [method to_entries] expands this pool into one
## [ModifierPoolEntry] per tier in `min_tier..max_tier`, computing each entry's
## `cost` (from the ladder), `value_range` (fixed at `unit × V[T]`, or the
## override for that tier), `weight` (`pool_weight × |cost|^tier_bias_k`), and
## `tags` (this pool's tags + [TierLadder] auto-tags for the tier). The draw
## loop ([method GraphProcgen._roll_modifiers_v4]) picks among those entries
## with weight profiles, spends budget until broke, then aggregates per
## (stat_id, operation): ADD*/INCREASE sum, MULTIPLY product, SET max.
##
## Debuffs (D9): set `unit_value` negative. The single debuff tier refunds
## budget (`cost = -T`); pin `max_tier = 1` and the draw enforces
## `max_refunds = 1` per node.
##
## Archetype affinity vs target stat:
##   - `stat_id`     — what the modifier writes to (e.g. `&"xp_per_turn"`).
##   - `archetype_stat` — which archetype's nodes the pool belongs to. `&""`
##     = universal (armor, node_health, movement_points, …): always available
##     to every node regardless of primary stat (D7 — universal pools stay
##     shared, they are NOT duplicated per archetype).

## Target stat the rolled modifier writes to.
@export var stat_id: StringName = &""
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_BASE

## Archetype affinity — matches against the node's `primary_stat`. `&""` =
## universal pool (drawn by every node). See D7: there is no off-archetype
## phase — universal pools are the shared defensive/mobility content.
@export var archetype_stat: StringName = &""

## Tags shared by every tier of this pool, auto-stamped onto each entry
## alongside the ladder's tier/rarity tags at flatten. Validated against
## [TagRegistry].
@export var tags: Array[StringName] = []

## T1 magnitude. The per-tier value is `unit_value × V[t]` (V from
## [TierLadder]); a per-tier [member value_overrides] entry replaces that
## default. For MULTIPLY the rolled modifier value is `1 + unit × V[t]`
## (a "more" excess — `unit 0.05, V[T3]=7 → ×1.35`), so `unit_value` is the
## *excess*, not the full multiplier. Negative `unit_value` marks a *debuff
## pool* (D9): its cost is `-T` (refunds budget), value is negative.
@export var unit_value: float = 1.0

## Sparse per-tier value override (D11): `tier -> T-magnitude` — the *excess*
## for MULTIPLY pools (the +1 is applied by to_entries), the raw value
## otherwise. Most pools carry none — the global V
## curve is the default; the escape hatch exists for pools that want a
## steeper/flatter ladder than V (e.g. `crit_chance`). Naive authoring here is
## load-bearing, so a test should pin the repo-wide override count under a
## budget (seed: ≤ 6).
@export var value_overrides: Dictionary[int, float] = {}

## Base sampling weight for this pool (the pool-selection axis). Tier weight
## within a pool is `|cost|^tier_bias_k`; the draw multiplies the two.
@export var pool_weight: float = 1.0

## Tier-weight exponent (D4): `w ∝ |cost|^k`. `k = 1.0` default. A *texture*
## dial, not a power dial — it moves chunky-vs-granular, not balance.
## Negative suppresses high tiers (reproduces the descending curves
## `mobility` / `deallocation_points` / `rare` wrote by hand).
@export var tier_bias_k: float = 1.0

## Lowest tier this pool offers (cost = [TierLadder.cost] min-1). Almost
## always 1 — lowering it is how a pool "starts expensive."
@export_range(1, 4) var min_tier: int = 1

## Highest tier offered. `max_tier < 4` is the honest brake that replaces the
## old descending weight curves: capping a flat ladder (movement, deallocation)
## states it instead of hiding it in weights. Debuff pools pin `max_tier = 1`.
@export_range(1, 4) var max_tier: int = 4


## Flatten into runtime entries (one per tier in `min_tier..max_tier`).
## Stable id per tier: `<stat_id>_<op>_<arch>_t<tier>` so weight profiles target
## stably across re-flattens.
func to_entries() -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	var op_short := _op_short()
	var arch_seg := String(archetype_stat) if archetype_stat != &"" else "any"
	var lo := clampi(min_tier, TierLadder.MIN_TIER, TierLadder.MAX_TIER)
	var hi := clampi(max_tier, lo, TierLadder.MAX_TIER)
	for t in range(lo, hi + 1):
		var e := ModifierPoolEntry.new()
		e.id = StringName("%s_%s_%s_t%d" % [stat_id, op_short, arch_seg, t])
		e.stat_id = stat_id
		e.operation = operation
		# Debuff pools (unit_value < 0): cost is -T (refunds budget).
		var is_debuff := unit_value < 0.0
		var t_cost := TierLadder.cost(t)
		e.cost = -t_cost if is_debuff else t_cost
		# value_range = magnitude = override or unit*V[T]. For MULTIPLY, the
		# rolled StatModifier value is `1 + magnitude` (the "more" excess), so
		# the +1 is folded in here while the ×1 base stays fixed. No per-roll
		# jitter (deleted #326): draw count + tier spread are the variance
		# sources — how many draws a node's budget affords *is* the variability.
		var mag := float(value_overrides.get(t, unit_value * TierLadder.value(t)))
		if operation == StatModifier.Operation.MULTIPLY:
			e.value_range = Vector2(1.0 + mag, 1.0 + mag)
		else:
			e.value_range = Vector2(mag, mag)
		# weight = pool_weight * |cost|^k.
		e.weight = pool_weight * pow(float(t_cost), tier_bias_k)
		# tags = pool tags + ladder auto-tags (tier_N + rarity).
		var merged: Array[StringName] = []
		merged.append_array(tags)
		merged.append_array(TierLadder.auto_tags(t))
		e.tags = merged
		out.append(e)
	return out


func _op_short() -> String:
	match operation:
		StatModifier.Operation.ADD_BASE: return "addb"
		StatModifier.Operation.INCREASE: return "inc"
		StatModifier.Operation.MULTIPLY: return "mul"
		StatModifier.Operation.ADD_BONUS: return "addn"
		StatModifier.Operation.SET: return "set"
	return "op"


## Markdown-ish table for the print-tool. Caller prefixes with the pool id.
func format_table() -> String:
	var lines: PackedStringArray = []
	var arch := String(archetype_stat) if archetype_stat != &"" else "—"
	lines.append("  stat=%s op=%s archetype=%s tags=%s" % [
			String(stat_id), _op_short(), arch, str(tags)])
	lines.append("  tier  magnitude          cost  weight   tags")
	lines.append("  ----  -----------------  ----  -------  ----")
	var lo := clampi(min_tier, TierLadder.MIN_TIER, TierLadder.MAX_TIER)
	var hi := clampi(max_tier, lo, TierLadder.MAX_TIER)
	for t in range(lo, hi + 1):
		var mag := float(value_overrides.get(t, unit_value * TierLadder.value(t)))
		var tc := TierLadder.cost(t)
		var w := pool_weight * pow(float(tc), tier_bias_k)
		var ttags := TierLadder.auto_tags(t)
		var disp: float
		if operation == StatModifier.Operation.MULTIPLY:
			disp = 1.0 + mag
		else:
			disp = mag
		lines.append("  T%-3d  %7.2f         %-4d  %7.3f  %s" % [
				t, disp,
				(-tc if unit_value < 0.0 else tc), w, str(ttags)])
	return "\n".join(lines)


func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if stat_id == &"":
		out.append("stat_id is empty — entries mint StatModifiers targeting nothing.")
	var lo := clampi(min_tier, TierLadder.MIN_TIER, TierLadder.MAX_TIER)
	var hi := clampi(max_tier, lo, TierLadder.MAX_TIER)
	if hi < lo:
		out.append("max_tier < min_tier — pool will draw nothing.")
	if unit_value == 0.0 and value_overrides.is_empty():
		out.append("unit_value 0 with no overrides — every tier rolls 0.")
	if unit_value < 0.0 and hi > 1:
		out.append("debuff pool (unit_value < 0) with max_tier > 1 — D9 pins debuffs to a single tier.")
	var registry := TagRegistry.canonical()
	if registry != null:
		var unknown := registry.unknown_tags(tags)
		for tag in unknown:
			out.append("unknown tag: %s" % String(tag))
	return out
