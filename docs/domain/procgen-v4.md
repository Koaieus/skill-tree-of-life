# Procgen v4 — flat StatPool + spend-until-broke draw

Successor to [procgen-v3.md](procgen-v3.md). v3's phased `TierPool`+`TierDef`
draw (primary → cost-capped off-attribute → defensive → rare) is replaced by:

- **One flat authoring resource** — `StatPool` (`procgen/pools/stat_pool.gd`)
  replaces the `TierPool` + `TierDef` pair. ~8 fields per pool, no per-tier
  sub-resources.
- **One shared ladder** — `TierLadder` (`procgen/pools/tier_ladder.gd`):
  `cost[t] = 2^(t-1)` → `[1,2,4,8]`; `value = 2·cost − 1` → `V = [1,3,7,15]`.
  Retuning the game's cost curve is now a one-file edit (the original ask of
  #321). Per-pool authoring carries only `unit_value` (the T1 magnitude) and an
  optional sparse `value_overrides` escape hatch (D11; seed budget ≤ 6
  repo-wide, pinned by `test_specimen_pool_set.gd`).
- **Spend-until-broke draw** — `_roll_modifiers_v4` (`graph_procgen.gd`):
  flatten the node's pools, then repeatedly weighted-pick an affordable entry
  (weight = `pool_weight · |cost|^tier_bias_k`, modulated by weight profiles),
  subtract its cost, until nothing's affordable. T1 always costs 1, so leftover
  budget always drains into T1 filler — budget is never wasted.
- **Per-(stat,op) aggregation** — after the draw, rolled modifiers combine by
  `(stat_id, operation)`: ADD_BASE / ADD_BONUS / INCREASE **sum**;
  MULTIPLY **products** (`×1.15 · ×1.15 = ×1.3225`, not `×2.30`); SET **max**.
  Line count on a node is bounded by the number of distinct `(stat, op)` pairs
  it drew — not by the number of draws.
- **Tier is auto-stamped, not authored.** `TierLadder.auto_tags(t)` stamps
  `tier_1..tier_4` always. `StatPool.tags` holds only the pool's flavour tags;
  a `WeightProfile` can key on the auto-stamped `tier_N` directly. `#552`
  deleted the `common`/`rare`/`mythic` rarity tag and `RadialBandProfile`,
  the profile that keyed on it — rarity was a lossier alias for tier (`T1`
  and `T2` both read `common`) and, because `value(t) = 2·cost(t) − 1`,
  composing chunkier tiers is itself a power lever (up to ~1.875x at a fixed
  budget) — so the band profile was a second, hidden power gradient stacked
  on top of the budget-field gradient, not a flavour/texture one. Budget is
  now the sole radial power lever.

## What v4 deleted (vs v3)

- `TierPool` + `TierDef` classes — replaced by `StatPool`.
- `TierPool.Role` (PRIMARY / DEFENSIVE / RARE) — only `RARE` had staying power
  and it's gone (D8: rare content becomes hand-authored keystone SkillNode
  scenes; see "Rare content → landmarks" below).
- `ModifierPoolSet.slot_count_weights`, `primary_share_ratio`,
  `off_cost_cap_offset/factor`, `flatten_for_phase` — replaced by
  `flatten_for_node(primary_stat)` (pools where `archetype_stat == primary_stat`
  OR `== &""`).
- `StatPack.off_phase_op_weights` + `off_weight_for` — D7 removed the
  off-archetype phase entirely. All budget goes to the node's primary
  archetype; **universal** pools (`archetype_stat == &""` — armor,
  node_health, movement_points, deallocation_points, the intelligence debuff)
  are the shared defensive/mobility content, drawn by every node.
- `CollisionProfile` from `first_level.tres`'s `weight_profiles` — its "zero
  duplicate `(stat,op)`" rule does not compose with aggregation (which
  *wants* duplicates to combine). The class + `test_weight_profiles.gd` remain
  for anyone who wants the primitive, but a v4 preset must not include it.

## Tunable floor + computed tier bounds (#628)

Every tier now has a `[L, H]` range instead of a fixed value. `H(t)` is
unchanged (`unit_value × V[t]`, or a `value_overrides` entry) — the ladder's
existing ceiling. `L` is new, driven by a per-pool `StatPool.range_floor`
("M"):

```
L(min_tier) = M
L(t+1)      = H(t) + M
H(t)        = unit_value × V(t)      # unchanged
```

`TierLadder.low(is_first_tier, prev_high, m)` is the single implementation of
this recurrence — it chains off the *actual* previous high, which may be a
`value_overrides` entry, so it is never reimplemented as a closed form.

**Validation is one rule: `M <= unit_value`.** A negative `M` is legal and
intended — it spans the range across zero so a normal pool can roll a small
penalty alongside its usual upside. Non-overlap between tiers (`L(t+1) >
H(t)`) is a **consequence** of a positive `M`, not a guaranteed property of
the model — do not assert it for negative `M`; players never see individual
tiers anyway, only the fused result (see "Uniform roll" below).

Anchors for authors:
- `M = -unit_value` makes the first tier EV-neutral (mean 0, a symmetric coin
  flip) — a tier's mean is `(L+H)/2`. More negative than that and the
  cheapest tier is negative-EV.
- How far negatives reach up the ladder: tier `t+1` can roll negative iff
  `unit_value × V(t) < |M|`. With `V = [1,3,7,15]` the breakpoints are
  `|M| > u` (reaches T2), `> 3u` (T3), `> 7u` (T4).

**Default `M = unit_value`** (sentinel: `StatPool.range_floor ==
StatPool.FLOOR_UNSET`, unset). This is always valid (`M <= unit_value` holds
as equality), yields a zero-width `min_tier` (a fixed point, same as
pre-#628), and leaves every already-authored pool's high bounds untouched —
no existing pool rebalances. Authors opt into variance by lowering
`range_floor` below `unit_value`.

**Debuff pools (`unit_value < 0`, D9) are exempt.** `range_floor` doesn't
apply to them — they keep the pre-#628 fixed point (`L == H`) unconditionally.
The recurrence assumes `H` grows in the direction `M` points; a debuff's `H`
trends *more* negative per tier, so applying it verbatim would swap which end
is numerically smaller without meaning anything. This is deliberate, not an
oversight: "Negative M replaces debuff pools" is a separate, not-yet-filed
migration, and #628 only needs to not obstruct it, not make the two compose.

**`value_overrides` is keyed on *absolute* tier while the ladder indexes
*relative*.** An overridden tier is itself always a fixed point — `L(T) =
H(T) = override` — never chain-computed (#629's decision: overrides "pin a
tier to an exact value, bypassing the roll entirely"), so it can never
invert on its own. But its `H` still feeds `L(T+1) = H(T) + M` for the
*next* tier, which is NOT exempt: a large enough override can inflate that
next tier's chained low past its own high. `_get_configuration_warnings()`
flags that case (a non-overridden tier whose chained `L > H`), naming the
pool.

An inspector button ("Print tier table") on `StatPool` itself dumps
`format_table()` — tier, `L..H`, cost, weight, and mean — so an author can see
the consequences of a chosen `M` directly, which is what makes relaxed
validation safe.

## Uniform roll within L..H (#629)

`ModifierPoolEntry.roll(rng)` already samples `value_range` with
`rng.randf_range` — #628 widening `value_range` to a real `[L, H]` is what
activates uniform rolling; #629 didn't need to touch the sampling call at
all. Its own content is the fused-no-op re-roll: procgen's spend-until-broke
draw fuses same-`(stat, op)` picks (see "Per-(stat,op) aggregation" above),
and with negative `M` legal, a fused result can land exactly on its
operation's neutral element (`0` for ADD*/INCREASE, `1` for MULTIPLY — `SET`
has none) — a slot that does nothing. `_roll_modifiers_v4` detects this
*after* fusion (never per-roll — individual rolls are allowed to be small or
negative) and re-rolls just that group's contributing picks, up to a fixed
retry cap, dropping the modifier if it still no-ops after exhausting
retries. The retry path draws from the same seeded `rng` in the same
deterministic order as the original picks, so two peers retry identically —
see `.claude/rules/multiplayer-sync.md`.

The roll is baked in at generation time, same as everything else in this
draw — it is not re-rolled on load.

## Negative pools (D9, revised 2026-08-30)

A `StatPool` with negative `unit_value` authors negative values. That is the
whole of what its sign means: **it is an ordinary pool that happens to author
downsides.** It ladders, rolls a range, and costs budget exactly like every
other pool. There is no `is_debuff` concept in the code and nothing branches
on the sign except display formatting.

Ranges come from the same recurrence as everywhere else — `TierLadder.low()`
is sign-agnostic, and for a negative pool the recurrence yields the *near* end
while the ladder yields the *far* end. The pair is **ordered before it reaches
`value_range`**, so "low ends up right of high" is a naming artefact, never a
math failure.

Validation is magnitude-based rather than signed, because `range_floor <=
unit_value` is wrong-signed for a negative pool — it would reject the valid
`u = -3, M = -1` and accept the invalid `u = -1, M = -10`:

```
negative pools:  sign(M) == sign(unit_value)  and  abs(M) <= abs(unit_value)
positive pools:  M <= unit_value              # unchanged; negative M stays legal (#628)
```

The two authored entries, both in `constitution.tres`:

| Entry | Authoring | Flattens to |
|---|---|---|
| `min_damage_taken` | `unit_value = -1.0`, `min_tier = 3` (unchanged) | T3 `-1..-1` cost 4; T4 `-2..-3` cost 8 |
| `intelligence +%` | `unit_value = -3.0`, `range_floor = -1.0`, `max_tier = 3` | T1 `-1..-3`; T2 `-4..-9`; T3 `-10..-21` |

### The refund economics are retired — owner call, 2026-08-30

**This supersedes the 2026-08-07 decision** recorded in earlier revisions of
this section, which gave a debuff pool `cost = -T` (so picking one *refunded*
budget) and capped it at `max_refunds = 1` per node. Constant, counter,
pick-filter branch and covering test are all deleted. **Cost is always `+T`;
budget spend is monotonic and no draw increases `remaining`.**

The owner's reason, verbatim (#637, 2026-08-30):

> "the budget refund lever disappears. given that modifiers now roll ranges,
> they generally are lower (before: they picked the new [max] of the range,
> now there's a [min] too) in value and can hence tweak budget ranges instead.
> so having no refund concept is fine — besides, negative rolls are more added
> flavor, they don't make up the bulk of what we author by a long margin."

The **one-curse-per-node cap is knowingly given up** with it (same call):
several negative rolls on one node is acceptable. Note this cap *was* real —
it was implemented as `_MAX_DEBUFF_REFUNDS`, not under the `max_refunds` name
the old docs used, which is why an earlier audit wrongly reported it missing.

Negative pools now consume RNG draws they previously did not, so **the seed
stream changed deliberately** and the golden fixtures were regenerated rather
than preserved.

## Rare content → hand-authored landmarks (D8)

`rare.tres` is deleted. Its four headline rolls are now pre-authored
`SkillNode` scenes under `entity/keystone/instances/` — each an inherited
`skill_node.tscn` with a `Keystone` resource whose `StatEffect` bakes the
granted `StatModifier`:

| scene | grant | op |
|---|---|---|
| `mythic_ward_node.tscn`  | `min_damage_taken = −1` | ADD_BASE |
| `farsight_node.tscn`    | `vision_range = +100` | ADD_BASE |
| `titan_node.tscn`       | `strength ×2.0` | MULTIPLY |
| `archmage_node.tscn`    | `intelligence ×2.0` | MULTIPLY |

`test_keystone_landmarks.gd` pins the grant on each. **Placement wiring
(stitching these N-per-map into procgen) is a separate open issue** — the
scenes exist and load; they are not yet placed by `first_level.tres`.

## Seed table (settled in #321)

`unit` = `unit_value` (T1 magnitude; negative = debuff). `pool_w` =
`pool_weight`. Default `jitter = 0.25`, `tier_bias_k = 1.0`. ADD*/INCREASE/
ADD_BONUS magnitude = `unit · V[t]`; MULTIPLY = `1 + unit · V[t]`.

| pool | unit | overrides | pool_w | min_T | max_T | resulting T1..T4 |
|---|---|---|---|---|---|---|
| `{str,dex,int,con,per,wis}` .addb | 2 | — | 10 | 1 | 4 | +2 +6 +14 +30 |
| attribute .inc | 7 | — | 3 | 1 | 3 | +7% +21% +49% |
| attribute .mul | 0.05 | — | 1 | 3 | 4 | ×1.35 ×1.75 |
| `armor` .addb (universal) | 1.5 | — | 2.5 | 1 | 3 | +1.5 +4.5 +10.5 |
| `node_health` .inc (universal) | 6.5 | — | 1 | 1 | 2 | +6.5% +19.5% |
| `mana` .addb | 1.5 | — | 4 | 1 | 4 | +1.5 +4.5 +10.5 +22.5 |
| `mana_per_turn` .addb | 1 | — | 2 | 1 | 2 | +1 +3 |
| `crit_chance` .inc | 5 | `{3:50, 4:100}` | 1.5 | 1 | 4 | +5% +15% +50% +100% |
| `crit_multiplier` .inc | 17.5 | — | 1.5 | 1 | 3 | +17.5% +52.5% +122.5% |
| `sensor_range` .addb | 1 | — | 2 | 1 | 2 | +1 +3 |
| `vision_range` .addn | 10 | — | 1 | 1 | 2 | +10 +30 |
| `vision_range` .inc | 7.5 | — | 2.5 | 1 | 3 | +7.5% +22.5% +52.5% |
| `xp_per_turn` .addb | 10 | — | 2 | 1 | 3 | +10 +30 +70 |
| `xp_per_turn` .inc | 7.5 | — | 0.5 | 1 | 2 | +7.5% +22.5% |
| `movement_points` .addb (universal) | 1 | — | 0.6 | 1 | 2 | +1 +3 |
| `deallocation_points` .addb (universal) | 1 | — | 0.8 | 1 | 2 | +1 +3 |
| `intelligence` .inc **debuff** (universal) | −5 | — | 0.5 | 1 | 1 | −5% (cost −1) |

Per-pack homes: str/dex/int/wis/per/con each carry their attribute's addb+inc+
mul; dex adds crit_chance+crit_multiplier; int adds mana+mana_per_turn; wis
adds xp_per_turn (addb+inc); per adds vision_range (inc+addn)+sensor_range;
con adds node_health+armor (universal) + the intelligence debuff (universal);
`mobility.tres` (universal pack) carries movement_points+deallocation_points.

## Budget envelope (first_level.tres)

`base 2..4 × RadialGradientField 1.0→4.0 × anomalous 1.75` → range 2..16,
mean ~10, anomalous to ~28. Floor of 2 = no budget-1 dead nodes. The
budget field's authored 4x is the *entire* rim power ratio (#552): before,
the deleted `RadialBandProfile` (`rbp_main`) additionally biased the rim
toward `mythic`-tagged (T4) content, and because `value(t) = 2·cost(t) − 1`
composition is itself a power lever, the real swing was closer to ~7.5x —
a hidden second gradient stacked on the budget one. Retuning from these
seeds is #268's job once the balance harness exists.