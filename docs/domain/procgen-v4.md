# Procgen v4 — flat StatPool + spend-until-broke draw

The content model: flat `StatPool`s drawn spend-until-broke. It replaces the deleted
`TierPool`/`TierDef` phased draw.

- **One flat authoring resource** — `StatPool` (`procgen/pools/stat_pool.gd`)
  replaces the `TierPool` + `TierDef` pair. ~8 fields per pool, no per-tier
  sub-resources.
- **One shared ladder** — `TierLadder` (`procgen/pools/tier_ladder.gd`):
  `cost[t] = 2^(t-1)` → `[1,2,4,8]`; `value = 2·cost − 1` → `V = [1,3,7,15]`.
  Retuning the game's cost curve is a one-file edit. Per-pool authoring carries only `unit_value` (the T1 magnitude) and an
  optional sparse `value_overrides` escape hatch (D11; seed budget ≤ 6
  repo-wide, pinned by `test_specimen_pool_set.gd`).
- **Spend-until-broke draw** — `_roll_modifiers_v4` (`graph_procgen.gd`):
  flatten the node's pools, then repeatedly pick an affordable entry from the
  renormalized three-level distribution (see "The renormalized draw" below),
  subtract its cost, until nothing's affordable. T1 always costs 1, so leftover
  budget always drains into T1 filler — budget is never wasted.
- **Per-(stat,op) aggregation** — after the draw, rolled modifiers combine by
  `(stat_id, operation)`: ADD_BASE / ADD_BONUS / INCREASE **sum**;
  MULTIPLY **delta sum** `1 + Σ(mᵢ − 1)` (`×1.15 & ×1.15 = ×1.30`, not
  `×1.3225`), clamped once per line at `GraphProcgenContent.multiply_fuse_floor`
  (a variance call; in game MULTIPLY instances still multiply); SET **max**.
  Line count on a node is bounded by the number of distinct `(stat, op)` pairs
  it drew — not by the number of draws.
- **Tier is auto-stamped, not authored.** `TierLadder.auto_tags(t)` stamps
  `tier_1..tier_4` always. `StatPool.tags` holds only the pool's flavour tags;
  a `WeightProfile` can key on the auto-stamped `tier_N` directly. There is no
  rarity tag and no radial-band profile: **budget is the sole radial power lever**
  (tier composition is itself a power lever, `value(t) = 2·cost(t) − 1`).

## Consequences of the flat model

- Pools reach a node through `ModifierPoolSet.flatten_for_node(primary_stat)`:
  pools where `archetype_stat == primary_stat` or `== &""`.
- All budget goes to the node's primary archetype; **universal** pools
  (`archetype_stat == &""` — armor, node_health, movement_points,
  deallocation_points; no curse is universal, see "The curse law") are the
  shared defensive/mobility content, drawn by every node.
- There is no collision profile: a "zero duplicate `(stat,op)`" rule would
  contradict aggregation, which wants duplicates to fuse. A soft-bias profile
  ("no two vision mods on one node") would read the **fused** modifiers, not raw
  picks. `test_weight_profiles.gd` pins that duplicate picks fuse.

## The renormalized draw (#1079)

Each pick is one sample from `GraphProcgen._v4_pick_distribution` (entry →
probability, summing to 1, or empty when the node is broke). Three levels,
each renormalized over what is **drawable at this pick** — an entry passes
`forbid_tags`, every weight profile leaves it a positive multiplier, and (at
the tier level) it is affordable:

1. **Group** — universal (`archetype_stat == &""`) vs archetype.
   `GraphProcgenContent.universal_share` (default 0.2) is the universal group's
   share of **picks** (not of budget spent), whatever the node's archetype. A
   group with nothing drawable cedes the whole pick to the other; neither →
   the pick is null.
2. **Pool** within its group — mass `pool_weight × m̄`, where
   `m̄ = Σ w_t·m_t / Σ w_t` over the pool's drawable tiers (`w_t` =
   `StatPool.tier_weight(t)`, `m_t` = product of profile multipliers). So
   `pool_weight` means **share among sibling pools**: more or pricier tiers
   never grow a pool. A pool-wide profile multiplier scales pool mass; a
   tier-tag multiplier reshapes tiers and moves pool mass only via `m̄`.
3. **Tier** within its pool — `w_t·m_t`, normalized over its affordable tiers.

**Budget tail: keep mass, reshape tiers.** `m̄` ignores budget, so a pool with
any affordable tier keeps its full mass and only its tier split narrows; a pool
with none drops out and its siblings share its mass. Low-tier-heavy pools
therefore gain nothing late in a draw — the group and pool split holds exactly
at every pick.

Entries carry what the draw needs: `ModifierPoolEntry.pool_key` (id minus
`_t<N>`), `pool_weight`, `universal`, and `weight` = the bare tier weight —
`StatPool.to_entries()` stamps them. Pools iterate in first-appearance order of
the `flatten_for_node` output, so peers reproduce the distribution; one
`randf()` per pick.

- Tests assert the distribution exactly (`test_renormalized_draw.gd`,
  `test_specimen_pool_set.gd`) — no Monte Carlo on the shares.
- The live per-pool roster is `ModifierPoolSet.format_tables()` /
  `StatPool.format_table()` (the inspector print buttons) — never a
  hand-maintained table.

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
as equality), yields a zero-width `min_tier` (a fixed point), and leaves every already-authored pool's high bounds untouched —
no existing pool rebalances. Authors opt into variance by lowering
`range_floor` below `unit_value`.

**Negative pools are not exempt** — the recurrence applies with a magnitude-based validation; see "Negative pools".

**`value_overrides` is keyed on *absolute* tier while the ladder indexes
*relative*.** An overridden tier is itself always a fixed point — `L(T) =
H(T) = override` — never chain-computed (overrides "pin a
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
`rng.randf_range`, so a real `[L, H]` `value_range` is uniform rolling. The
fused-no-op re-roll is the rest of the roll: procgen's spend-until-broke
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

Two authored entries, both in `constitution.tres`:

| Entry | Authoring | Flattens to |
|---|---|---|
| `min_damage_taken` | `unit_value = -1.0`, `min_tier = 3` (unchanged) | T3 `-1..-1` cost 4; T4 `-2..-3` cost 8 |
| `dexterity -%` | `unit_value = -3.0`, `range_floor = -1.0`, `max_tier = 3` | T1 `-1..-3`; T2 `-4..-9`; T3 `-10..-21` |

## The curse law (#718)

Every downside pool is **archetype-scoped and untagged**. Which of the six
archetypes taxes what:

| archetype | taxes | reads as |
|---|---|---|
| STR | `intelligence -%` | power over thought |
| CON | `dexterity -%` | armor is heavy |
| INT | `node_health -%` | the mage's territory is brittle |
| DEX | `armor -%` | the duelist wears no plate |
| WIS, PER | — | deliberately curse-free |

Stated as one line: *the two solid archetypes tax the two quick/clever
attributes; the two quick/clever archetypes tax the two defensive stats.*

- **The pack is the gate.** A pool rolls where its `.tres` says: a CON curse
  lives in `constitution.tres` and rolls on CON nodes only (ADR 0028;
  `.claude/rules/procgen-pool-scoping.md`).
- **Empty `tags`.** Tags feed `ArchetypeWeightProfile` and
  `ArchetypePolicy.forbid_tags` (a brick wall); a curse that keeps stale tags
  gets boosted or banned per archetype.
- **`armor -%` is INCREASE, not ADD_BASE.** `armor`'s base is 0 and procgen
  writes `SkillNode.modifiers`, which is *entity*-scoped — a flat curse would
  mint unbounded negative armor across the whole territory, and
  `Mitigation.compute` floors at `min_damage_taken` rather than capping. As an
  INCREASE it scales down accumulated armor: self-limiting, and free until you
  own armor at all.

WIS/PER being curse-free is a stated asymmetry, not an omission — they are 5% /
3% of the graph and are already locked out of universal *defensive* content
(armor, node_health) by their `forbid_tags` (#750); mobility still rolls.

`test/unit/test_pool_scoping.gd` pins all of this structurally, plus a headless
sweep of `_get_configuration_warnings()` across every pack and pool — that
warning is `@tool`-only, so nothing outside the editor would otherwise read it.

### No refunds

Cost is always `+T`; budget spend is monotonic and no draw increases `remaining`.
Several negative rolls on one node are acceptable (there is no one-curse cap).
Negative rolls are flavour, not the bulk of authored content.

## Rare content → hand-authored landmarks

Rare content is hand-authored keystone `SkillNode` scenes under
`skill_node/keystone/instances/` (inherited `keystone_skill_node.tscn`, a
`StatEffect` on `SkillNode.effects` baking the granted `StatModifier`): titan,
archmage, farsight, mythic_ward, ap_keystone, natural_xp, wisdom, inversion.
`procgen/modules/first_level/content.tres` places each through a `ScenePlacement`
in `guaranteed_placements` (see [procgen.md](procgen.md)).
`test_keystone_landmarks.gd` pins the grants.

## Pack homes

Authored values live in `procgen/pools/*.tres`; read them with the "Print tier
table" inspector button on a `StatPool` (or the set-level button on
`ModifierPoolSet`), never from a doc table. The pack is the gate (ADR 0028).

- **str / dex / int / con / wis / per** — each carries its attribute's addb+inc+mul.
- **str** — `intelligence -%` curse; blighted `corruption_stacks_per_hit`, blessed
  `corruption_resistance` and `bleeding_resistance`.
- **dex** — crit chance/multiplier (`[regular, bless]`), `armor -%` curse, poison
  aspect / arrows / shots-per-leaf (`[regular, blight]`), blighted
  `poison_stacks_per_hit`, blessed `poison_resistance`.
- **int** — `node_health -%` curse; cast range (`[regular, blight]`); blighted
  `wither_stacks_per_hit`.
- **con** — `dexterity -%` curse, `min_damage_taken` (`[regular, bless]`); blighted
  `curse_stacks_per_hit`, blessed `curse_resistance`.
- **wis** — regular `xp_per_turn`; blighted `dot_stacks_per_hit` (the archive
  umbrella, WIS-only); blessed `wound_heal_per_turn` plus a fatter `xp_per_turn`
  pair — the XP engine plus recovery, not a DoT pole.
- **per** — vision_range inc (all) and flat (`[regular, blight]`), `sensor_range`
  (`[regular, bless]`); blighted `blindness_stacks_per_hit`, blessed
  `blindness_resistance`; `scout_aspect` is shared by all three poles.
- **universal.tres** — node_health, armor, movement_points, deallocation_points.

Each DoT family has one attribute home holding both poles, gated by subtype:
potency (the family `_stacks_per_hit` INCREASE row) rolls only on blighted nodes,
resistance only on blessed ones. WIS and PER carry no family INCREASE row.
Hybrids are the deal — poison on a melee blade means allocating blighted DEX
nodes. Resistances are T2+, so they never crowd a T1 draw. Subtype rules:
[node-subtypes.md](node-subtypes.md).

## Budget envelope

Budget is `BudgetPolicy.compute_budget` = `max(1, round(lerp(base_min, base_max) × budget_field × role bonus))`.
`first_level/content.tres`: `base_min 1 .. base_max 4`, a `RadialGradientField`
1.0 → 4.0 over r = 200..2500, `anomalous` ×1.75. Floor of 1 = no budget-0 dead nodes;
the field's authored 4x is the entire rim power ratio. Live numbers: the preset's `content.tres`.

## Tuning a pool: what goes red, and what to run

**Only the procgen goldens should go red on a content tune.** Editing
`unit_value` / `range_floor` / `pool_weight` / `min_tier` / `max_tier`, or
adding a pool to a pack, must not fail a unit test. If it does, that test is
asserting the tuner's numbers instead of the engine's behaviour — fix the
test, not the tuning.

The three layers, and what each is allowed to know:

| layer | reads | goes red on a tune? |
|---|---|---|
| `test_pool_seed_values.gd` | nothing — hand-built `StatPool`s | never |
| `test_pool_range_bounds.gd` | every pool in the specimen set, as **input** | never |
| `test_preset_generation_golden.gd` | full generated output | **yes, by design** |

- The **formula** (`H = unit × V[t]`, `L(1) = M`, `L(t+1) = H(t) + M`, cost
  ladder, override fixed points, min_tier-relative rungs, negative-pool
  role-ordering) is pinned as **literals on hand-built pools**. Never re-derive
  the recurrence from a pool's own fields in a test: it is stateful enough that
  the mirror would reproduce any bug in `_tier_magnitude_bounds` and the
  assertion would be vacuous.
- **Shipped content** is only ever swept for *conformance* to that formula. The
  `.tres` is the input, never the expectation.  The sweep covers pools that author an explicit `range_floor` too.
- A pack's **stat allowlist** is derived from the pack, not hand-listed. A
  literal list goes stale the moment a pool is added and then blames the roll
  for a fact about the fixture.

**A pool re-tune reshuffles both goldens wholesale — a value-only diff is the
exception.** Pool *selection* is weighted, so changing a `pool_weight`, adding a
pool, or dropping a `max_tier` cap changes how much RNG the draw consumes at the
first node of that archetype; everything downstream differs by *position*. Don't
reconcile such a diff line by line — check it in aggregate: the line-tag census
(counts per `MOD`/`ADDON`/`SPELL` kind) should be unchanged *in kind*, and spot-check
that any new extreme value is reachable under the new authoring.

The fix for a red golden is deliberate: `mise run procgen-golden-regenerate`, then
re-verify with `mise run test:one -- res://test/unit/procgen/test_preset_generation_golden.gd`.
Commit the fixtures with a message saying *why* generation was supposed to change.

**One test is meant to be tune-sensitive:**
`test_specimen_pool_set.gd::test_value_overrides_stay_under_repo_budget` caps
the repo at 6 `value_overrides` (D11). Adding a seventh turns it red on
purpose — that is the escape hatch's budget working, not fragility. Raise the
budget deliberately or use the ladder instead.
