@tool
class_name StatPool
extends Resource

## Authoring unit for procgen modifier content (v4, #321). Replaces the v3
## two-resource pool shape (a pool plus one sub-resource per tier) with a
## single flat resource: ~8 fields per pool, no per-tier sub-resources. The
## cost/value ladder lives once in [TierLadder] — a pool carries only
## `unit_value` (the T1 magnitude) and an optional sparse `value_overrides`
## escape hatch (#321 D11).
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
## Negative pools (D9): set `unit_value` negative for a pool that always rolls
## a downside. It ladders like any other pool — cost is `+T` like any other
## tier (the old refund economics were retired #637, superseded 2026-08-30)
## and, per #628/#637, it rolls a real `[L, H]` range the same as a positive
## pool; nothing branches on the sign except display formatting.
##
## Archetype affinity vs target stat:
##   - `stat_id`     — what the modifier writes to (e.g. `&"xp_per_turn"`).
##   - `archetype_stat` — which archetype's nodes the pool belongs to. `&""`
##     = universal (armor, node_health, movement_points, …): always available
##     to every node regardless of primary stat (D7 — universal pools stay
##     shared, they are NOT duplicated per archetype).

## Target stat the rolled modifier writes to.
@export var stat_id: StringName = &"":
	set(v):
		stat_id = v
		_update_resource_name()

@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_BASE:
	set(v):
		operation = v
		_update_resource_name()


## Archetype affinity — matches against the node's `primary_stat`. `&""` =
## universal pool (drawn by every node). See D7: there is no off-archetype
## phase — universal pools are the shared defensive/mobility content.
@export var archetype_stat: StringName = &""

## Tags shared by every tier of this pool, auto-stamped onto each entry
## alongside the ladder's tier/rarity tags at flatten. Validated against
## [TagRegistry].
@export var tags: Array[StringName] = []

## T1 magnitude. The per-tier value is `unit_value × V[t]` (V from
## [TierLadder]), indexed relative to [member min_tier] — a pool's first tier
## is V1 (×1) whatever it costs, so `min_tier=3` rolls t3 at cost 4 with the
## V1 magnitude and t4 at cost 8 with V2. A per-tier [member value_overrides]
## entry replaces that default. For MULTIPLY the rolled modifier value is
## `1 + unit × V[t]` (a "more" excess — `unit 0.05, V[T3]=7 → ×1.35`), so
## `unit_value` is the *excess*, not the full multiplier. Negative `unit_value`
## marks a *debuff pool* (D9): its cost is `-T` (refunds budget), value is
## negative.
@export var unit_value: float = 1.0

## Sparse per-tier value override (D11): `tier -> T-magnitude` — the *excess*
## for MULTIPLY pools (the +1 is applied by to_entries), the raw value
## otherwise. Most pools carry none — the global V
## curve is the default; the escape hatch exists for pools that want a
## steeper/flatter ladder than V (e.g. `crit_chance`). Naive authoring here is
## load-bearing, so a test should pin the repo-wide override count under a
## budget (seed: ≤ 6).
@export var value_overrides: Dictionary[int, float] = {}

## Tunable floor magnitude — "M" in #628. `L(min_tier) = range_floor`; every
## higher tier's low bound is `H(previous tier) + range_floor` ([method
## TierLadder.low]). Same units as `unit_value` — the *excess* for MULTIPLY
## pools (the +1 is folded in at flatten, same as `unit_value`), raw
## otherwise. Validation is sign-aware (#637): for a positive (or zero)
## `unit_value` the constraint stays `range_floor <= unit_value` (a floor
## above the T1 ceiling inverts the range) — negative `range_floor` is legal
## and intended, it spans the range across zero so a normal pool can roll a
## small penalty alongside its usual upside. For a negative `unit_value` the
## constraint is magnitude-based instead — `sign(range_floor) ==
## sign(unit_value) and abs(range_floor) <= abs(unit_value)` — because an
## always-negative pool must stay always-negative; a floor that crossed zero
## or overshot the T1 ceiling's magnitude would break that guarantee.
## `_get_configuration_warnings` enforces both branches; see
## docs/domain/procgen-v4.md.
##
## Sentinel default: [constant FLOOR_UNSET] means "not authored" and resolves
## to `unit_value`, which is always valid under either branch above (equality
## trivially satisfies both) and reproduces pre-#628 behaviour exactly — a
## zero-width min_tier, unchanged highs. A literal numeric default could not
## do this: it would fail validation for any pool whose `unit_value` is
## smaller than it (e.g. `attribute .mul`'s 0.05) or wrong-signed (a negative
## pool's `unit_value`). Every already-authored `.tres` under
## `procgen/pools/` that doesn't deliberately author a `range_floor` omits
## this field and so gets `range_floor == unit_value` for free — the "no
## existing pool rebalances" regression the acceptance spec asks for.
##
## Negative pools (`unit_value < 0`, D9) are NOT exempt from `range_floor` as
## of #637 — they roll a real range like any other pool. See [method
## _tier_magnitude_bounds] for how the recurrence's near/far pair is ordered
## for a negative pool.
const FLOOR_UNSET := INF
@export var range_floor: float = FLOOR_UNSET

## Base sampling weight for this pool (the pool-selection axis). Tier weight
## within a pool is `|cost|^tier_bias_k`; the draw multiplies the two.
@export var pool_weight: float = 1.0

## Tier-weight exponent (D4): `w ∝ |cost|^k`. `k = 1.0` default. `value(t) =
## 2*cost(t) - 1`, so composition is itself a power lever — spending budget
## `B` entirely at tier `t` yields `2B - B/cost(t)`; a chunkier `k` moves
## real balance (up to ~1.875x at a fixed budget), not just texture.
## Negative suppresses high tiers (reproduces the descending curves
## `mobility` / `deallocation_points` wrote by hand).
@export var tier_bias_k: float = 1.0

## Lowest tier this pool offers (cost = [TierLadder.cost] min-1). Almost
## always 1 — lowering it is how a pool "starts expensive." Value rungs are
## indexed relative to this: the first tier offered is V1 (×1) regardless of
## its cost; only the cost stays absolute.
@export_range(1, 4) var min_tier: int = 1

## Highest tier offered. `max_tier < 4` is the honest brake that replaces the
## old descending weight curves: capping a flat ladder (movement, deallocation)
## states it instead of hiding it in weights. Debuff pools ladder like any
## other pool (settled 2026-08-07) — a deeper debuff hurts more and refunds
## more, in lockstep, so there is no restriction to `max_tier = 1`.
@export_range(1, 4) var max_tier: int = 4


func _init() -> void:
	_update_resource_name()

func _update_resource_name():
	resource_name = '%s %s' % [stat_id, _op_symbol()]

## Resolves [member range_floor]'s sentinel — see its docstring.
func _effective_floor() -> float:
	return unit_value if is_inf(range_floor) else range_floor

## One (lo, hi) magnitude pair per tier in `min_tier..max_tier` — the shared
## computation behind [method to_entries], [method format_table], and
## [method _get_configuration_warnings]. "Magnitude" = pre-"+1" excess for
## MULTIPLY pools, raw value otherwise (the transform is applied by callers,
## same split [method to_entries] always used for `unit_value`). Single
## source of the low-bound recurrence so every reader sees the same chain
## through (possibly overridden) highs — see [method TierLadder.low].
##
## Negative pools (`unit_value < 0`, D9) roll a real range too, as of #637 —
## the old exemption ("low ends up right of high") was a **naming** problem,
## not a math failure: [method TierLadder.low] is sign-agnostic, and for a
## negative pool the recurrence yields the tier's *near*-zero end while the
## ladder (`unit_value × V(t)`) yields its *far* end — the mirror image of a
## positive pool, where the recurrence yields the near end and the ladder the
## far end. This function orders the pair by that role (not by raw numeric
## sort) before returning it, so both [method to_entries]'s `value_range` and
## [method _get_configuration_warnings]'s inversion check can keep comparing
## `lo` against `hi` with the exact same `>` — unchanged for either sign — and
## get the right answer: `lo` is always "the end nearer zero should not have
## overshot past hi" in the appropriate direction. Example, the repo's INT
## pool (`unit_value = -3`, `range_floor = -1`): T1 near = -1, far = -3 →
## ordered (lo, hi) = (-3, -1); T2 near = -4, far = -9 → (lo, hi) = (-9, -4).
##
## A tier with a [member value_overrides] entry is ALSO a fixed point at its
## own tier — #629's decision text: "value_overrides still pins a tier to an
## exact value, bypassing the roll entirely." Its (overridden) `H` still
## feeds the NEXT tier's low bound via the chain — the guard [method
## _get_configuration_warnings] enforces is specifically about THAT: a large
## override can invert a LATER, non-overridden tier, not the overridden tier
## itself (which can never invert — its own lo and hi are the same number).
func _tier_magnitude_bounds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lo := clampi(min_tier, TierLadder.MIN_TIER, TierLadder.MAX_TIER)
	var hi := clampi(max_tier, lo, TierLadder.MAX_TIER)
	var floor_m := _effective_floor()
	var prev_high := 0.0
	var first := true
	for t in range(lo, hi + 1):
		# Value is indexed relative to the pool's first tier: `min_tier=3`
		# rolls t3 at cost 4 with the V1 magnitude (×1) and t4 at cost 8 with
		# V2 — a pool's first tier is worth ×1 whatever it costs. Cost stays
		# absolute; only the value rung shifts.
		var overridden := value_overrides.has(t)
		var far := float(value_overrides.get(t, unit_value * TierLadder.value(t - min_tier + 1)))
		var near := far if overridden else TierLadder.low(first, prev_high, floor_m)
		# Role-order, not numeric sort (#637): a negative pool's near end is
		# numerically the LARGER of the two (closer to zero), so swap which
		# raw quantity plays "lo" vs "hi" by sign — see docstring above.
		var l := far if unit_value < 0.0 else near
		var h := near if unit_value < 0.0 else far
		out.append({"tier": t, "lo": l, "hi": h})
		prev_high = far
		first = false
	return out

## Flatten into runtime entries (one per tier in `min_tier..max_tier`).
## Stable id per tier: `<stat_id>_<op>_<arch>_t<tier>` so weight profiles target
## stably across re-flattens.
func to_entries() -> Array[ModifierPoolEntry]:
	var out: Array[ModifierPoolEntry] = []
	var op_short := _op_short()
	var arch_seg := String(archetype_stat) if archetype_stat != &"" else "any"
	for b in _tier_magnitude_bounds():
		var t: int = b.tier
		var e := ModifierPoolEntry.new()
		e.id = StringName("%s_%s_%s_t%d" % [stat_id, op_short, arch_seg, t])
		e.stat_id = stat_id
		e.operation = operation
		# Cost is always positive (#637 — the refund economics of negative
		# pools are retired): every pool, whatever its sign, spends `+T`.
		var t_cost := TierLadder.cost(t)
		e.cost = t_cost
		# value_range = [lo, hi] magnitude (#628/#629 — the draw rolls
		# uniformly within it, see [method ModifierPoolEntry.roll]). For
		# MULTIPLY, the rolled StatModifier value is `1 + magnitude` (the
		# "more" excess), so the +1 is folded into both ends here while the
		# ×1 base stays fixed.
		if operation == StatModifier.Operation.MULTIPLY:
			e.value_range = Vector2(1.0 + b.lo, 1.0 + b.hi)
		else:
			e.value_range = Vector2(b.lo, b.hi)
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
		StatModifier.Operation.ADD_BASE: return "addb" # TODO: maybe switch base add (the default!) to be just `add` and let the BONUS add be `addb` instead? throughout the codebase. or is that confusing?
		StatModifier.Operation.INCREASE: return "inc"
		StatModifier.Operation.MULTIPLY: return "mul"
		StatModifier.Operation.ADD_BONUS: return "addn"
		StatModifier.Operation.SET: return "set"
	return "op"

func _op_symbol() -> String:
	match operation:
		StatModifier.Operation.ADD_BASE: return "+"  # TODO: when formalizing bool for flipping "which way is up" for a stat (some stats you want lowered), splice in condition to make this `-` instead
		StatModifier.Operation.INCREASE: return "+%"
		StatModifier.Operation.MULTIPLY: return "×"
		StatModifier.Operation.ADD_BONUS: return "+b"
		StatModifier.Operation.SET: return "="
	return "??"

## Inspector button (#628 acceptance 6): preview this pool's own tier table
## without printing the whole [ModifierPoolSet] via its set-level button.
@export_tool_button("Print tier table") var _print_button: Callable = _print_table

func _print_table() -> void:
	print(format_table())

## Markdown-ish table for the print-tool. Caller prefixes with the pool id.
## Shows the rolled L..H range (#628/#629) and its mean, not a single
## magnitude — a pool's tiers are no longer fixed points.
func format_table() -> String:
	var lines: PackedStringArray = []
	var arch := String(archetype_stat) if archetype_stat != &"" else "—"
	lines.append("  stat=%s op=%s archetype=%s tags=%s" % [
			String(stat_id), _op_short(), arch, str(tags)])
	lines.append("  tier  L..H                  cost  weight   mean     tags")
	lines.append("  ----  --------------------  ----  -------  -------  ----")
	var is_mul := operation == StatModifier.Operation.MULTIPLY
	for b in _tier_magnitude_bounds():
		var t: int = b.tier
		var lo_disp: float = (1.0 + b.lo) if is_mul else b.lo
		var hi_disp: float = (1.0 + b.hi) if is_mul else b.hi
		var tc := TierLadder.cost(t)
		var w := pool_weight * pow(float(tc), tier_bias_k)
		var ttags := TierLadder.auto_tags(t)
		lines.append("  T%-3d  %8.2f..%-9.2f  %-4d  %7.3f  %7.2f  %s" % [
				t, lo_disp, hi_disp, tc, w, (lo_disp + hi_disp) / 2.0, str(ttags)])
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
	# #628/#637: validation is sign-aware. A positive (or zero) unit_value
	# pool keeps the original rule, `range_floor <= unit_value` (a floor
	# above the T1 ceiling inverts the pool's whole range); negative
	# range_floor is legal and intended there — see its docstring. A
	# negative unit_value pool must stay always-negative, so its floor is
	# constrained by magnitude instead: it must share unit_value's sign and
	# not exceed its magnitude, or the pool would cross zero (or overshoot
	# past the T1 ceiling).
	var floor_m := _effective_floor()
	var floor_valid: bool
	if unit_value < 0.0:
		floor_valid = signf(floor_m) == signf(unit_value) and absf(floor_m) <= absf(unit_value)
	else:
		floor_valid = floor_m <= unit_value
	if not floor_valid:
		out.append("%s: range_floor (%s) is invalid for unit_value (%s) — %s." % [
				resource_name, floor_m, unit_value,
				("must share its sign and not exceed its magnitude" if unit_value < 0.0
						else "exceeds unit_value, inverting min_tier's range")])
	# #628 acceptance 7: value_overrides is keyed on ABSOLUTE tier while the
	# ladder indexes relative — an override on tier T changes H(T), and
	# L(T+1) = H(T) + range_floor chains off it. An override deep enough (or
	# range_floor large enough) can still invert a later tier even when the
	# clause above passes at min_tier. `b.lo`/`b.hi` are already role-ordered
	# by [method _tier_magnitude_bounds] (near/far by sign, not numeric
	# sort), so the SAME `>` comparison catches a genuine inversion for
	# either sign of pool (#637) — do not special-case unit_value here.
	for b in _tier_magnitude_bounds():
		if b.lo > b.hi:
			out.append("%s: T%d range inverted (lo %s > hi %s) — check value_overrides against range_floor." % [
					resource_name, b.tier, b.lo, b.hi])
	var registry := TagRegistry.canonical()
	if registry != null:
		var unknown := registry.unknown_tags(tags)
		for tag in unknown:
			out.append("unknown tag: %s" % String(tag))
	return out
