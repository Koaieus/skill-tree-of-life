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
  `tier_1..tier_4` always, plus rarity (`T1/T2 → common`, `T3 → rare`,
  `T4 → mythic`). `StatPool.tags` holds only the pool's flavour tags; the
  radial band profile (`rbp_main`) keys on the auto-stamped `common`/`rare`/
  `mythic` to gate content by region.

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

## Debuffs (D9)

A `StatPool` with negative `unit_value` is a debuff pool. It ladders like any
other pool (settled 2026-08-07): each tier `T` has `cost = -T` (so the draw
**refunds** budget when picked) alongside its negative rolled value — a
deeper debuff hurts more AND refunds more, in lockstep, so a bigger refund is
never free budget. The draw enforces `max_refunds = 1` per node and only
offers a debuff while `remaining ≥ 1`. The economics self-balance on an
exponential ladder: a T1 debuff only pays when the refund crosses a
power-of-two threshold into a higher tier (budget 7 → T3+T2+T1 = 11 value;
budget 7 + T1 debuff → budget 8 → T4 = 15, −1 = 14 value). The repo's debuff
is the `intelligence` INCREASE `unit_value = -2` (`max_tier = 3`) in
`constitution.tres`.

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
mean ~10, anomalous to ~28. Floor of 2 = no budget-1 dead nodes. The rim
power ratio (~5×) is set by the budget field, not the cost ladder.
`rbp_main` outer `mythic = 3.0` (was 8.0 — at 8.0 the rim was 86% T4; at 3.0
it's ~70%, with mean node value unchanged). Retuning from these seeds is
#268's job once the balance harness exists.