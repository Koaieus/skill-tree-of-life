# Procgen v3 — phased draw + StatPack content

> **SUPERSEDED by [procgen-v4.md](procgen-v4.md) (#321).** v4 replaces the
> phased `TierPool`+`TierDef` draw (primary → off → defensive → rare) with a
> flat `StatPool` authoring surface, a spend-until-broke + per-(stat,op)
> aggregation draw, and deletes the off-archetype phase, slots, and `Role`.
> This file is kept for design history only.

Successor to [procgen-v2.md](procgen-v2.md). v2 introduced the universal
ModifierPool + weight-profile pipeline; v3 reorganises **what content exists**
(per-archetype `StatPack` files) and **how it's drawn** (phased: slot count
→ primary → off-attribute with cost cap → defensive → rare).

Implemented. Wired into `GraphProcgenConfig.modifier_pool_set`. If
`modifier_pool_set` is set, the v3 draw runs and the v2 `modifier_pool` is
bypassed.

## The resource stack

```
GraphProcgenConfig
  └── modifier_pool_set: ModifierPoolSet
        ├── packs: Array[StatPack]          ← author surface
        │     ├── archetype_stat: StringName   (&"strength", &"" for cross-cutting)
        │     ├── pools: Array[TierPool]
        │     │     ├── stat_id (target stat)
        │     │     ├── operation (ADD_BASE/INCREASE/MULTIPLY/ADD_BONUS)
        │     │     ├── role: PRIMARY | DEFENSIVE | RARE
        │     │     └── tiers: Array[TierDef] { value_range, cost, weight }
        │     └── off_phase_op_weights: Dictionary[Operation, float]
        ├── slot_count_weights: Dictionary[int, float]  (e.g. {1:5, 2:55, 3:30, 4:8, 5:2})
        ├── primary_share_ratio: float       (default 0.6)
        ├── off_cost_cap_offset: int         (default 1)
        └── off_cost_cap_factor: float       (default 1.0)
```

**Archetype linkage:** `ArchetypePolicy.primary_stat: StringName` on the
archetype defs (e.g. red → `&"strength"`) matches against `StatPack.archetype_stat`
at draw time. Each StatPack belongs to exactly one archetype but is consumed by
all archetypes' off-phases.

## The phased draw

For each node:

1. **Sample slot count** from `slot_count_weights`. Split:
   - `primary_share = ceil(slots * primary_share_ratio)`
   - `off_share = slots - primary_share`

2. **Phase 2 (primary):** Repeatedly draw from PRIMARY pools where
   `archetype_stat == node.primary_stat`, weighted-and-affordable, until
   `primary_share` slots are filled or budget exhausted. Tracks
   `peak_primary_cost`.

3. **Phase 3 (off-attribute + defensive + rare):** One combined pool:
   - **Off-attribute** entries: PRIMARY pools where `archetype_stat != node.primary_stat`
     and `≠ &""`, filtered to `cost ≤ floor(peak * off_cost_cap_factor) - off_cost_cap_offset`.
     Each entry's weight is multiplied by its source pack's
     `off_phase_op_weights[entry.operation]` (zero hard-excludes).
   - **Defensive** entries (any pack): exempt from cost cap.
   - **Rare** entries (any pack): exempt from cost cap.

   Drawn `off_share` times.

## What lives in each StatPack file

Convention: one .tres per archetype in `procgen/pools/`.

| File | archetype_stat | Notable contents |
|---|---|---|
| `strength.tres` | `&"strength"` | strength add_base/increase/multiply |
| `dexterity.tres` | `&"dexterity"` | dexterity add_base/increase/multiply, crit_chance + crit_multiplier INCREASE pools (3 tiers each). Rationale: DEX is precision/finesse — crit chance reads as "precision strike" and multiplier as "finding the gap." Both are INCREASE (percent-scaled) targets; low weight (2/4/6), premium cost (3/9/27) keeps crit growth restrained. |
| `intelligence.tres` | `&"intelligence"` | intelligence + mana + mana_per_turn pools, INCREASE includes negative tiers |
| `wisdom.tres` | `&"wisdom"` | wisdom + xp_per_turn (flat-primary, INCREASE secondary). `off_phase_op_weights = {ADD_BASE:0.2, INCREASE:0.05, MULTIPLY:0.0, ADD_BONUS:0.05}` |
| `perception.tres` | `&"perception"` | perception + vision_range INCREASE/ADD_BONUS + sensor_range. Same suppression as wisdom |
| `constitution.tres` | `&"constitution"` **+ cross-cutting** | The one **mixed** pack. role=PRIMARY: constitution add_base/increase/multiply. role=DEFENSIVE: node_health INCREASE (`+5–15%`) + armor add_base — universal, cost-cap-exempt, absorbed from the deleted `defensive.tres` (#299). `off_phase_op_weights = {ADD_BASE:0.5, INCREASE:0.3, MULTIPLY:0.1, ADD_BONUS:0.3}` — softer than WIS/PER, D-12's named exception. Together those are D-12's two halves in one file. Legal because the flatten filters per-`TierPool`, never on the pack's own `archetype_stat` |
| `rare.tres` | `&""` (cross-cutting) | min_damage_taken −1, vision_range flat additions, ×2 multipliers. role=RARE |
| `mobility.tres` | `&""` (cross-cutting) | movement_points + deallocation_points add_base, +1/+2/+3 low-integer tiers (#41). role=DEFENSIVE — universal, not DEX-gated, since it always draws off `flatten_for_phase(&"defensive", ...)` regardless of a node's `primary_stat` |

The set of these is bundled into `specimen_pool_set.tres`.

## Authoring conventions

- **No UIDs on hand-authored ext_resources for in-project scripts** (lint-mismatch silently nulls fields). Either omit `uid=` or verify from `.uid` files. (The editor will fill UIDs on save once it touches the file — that's safe; the lint is "don't *copy-paste* a UID and hope.")
- **TierDef magnitudes:** prefer integer values for ADD_BASE (especially INT-typed stats). INCREASE auto-snaps to int via `ModifierPoolEntry._coerce_to_stat_type`. MULTIPLY stays float (`×1.5` is meaningful).
- **Cost progression:** geometric per tier (1, 3, 9, 27, 81 is the strength curve). With `off_cost_cap_offset=1` only excludes exact-peak entries — `off_cost_cap_factor=0.4` better expresses "off one full tier below."
- **`off_phase_op_weights`** lives on the StatPack, not on individual TierPools. The same suppression applies to all of a pack's PRIMARY pools when they appear in another archetype's off-phase.
- **Cross-stat pools in one pack:** wisdom.tres includes both `wisdom` and `xp_per_turn` pools, both with `archetype_stat = &"wisdom"`. The pack's archetype identity is what couples them.

## Self-loop distribution (#42)

Self-loops are placed by a **4-tier floor-guaranteed staged draw without
replacement** — not per-node RNG (the old `randf() < self_loop_rate` roll).
Tier 1 draws `floor(N × p1)` nodes uniformly from all generated nodes
(partial Fisher-Yates); tier 2 draws `floor(K1 × p2)` from the tier-1 set;
tier 3 `floor(K2 × p3)` from tier-2; tier 4 `floor(K3 × p4)` from tier-3.
Each tier then does **one** Bernoulli on the fractional remainder to add +1,
so each tier lands at `floor + 0-or-1` nodes. Each tier **upgrades** its draw
by one loop, so a node that hits tier k ends with exactly k self-loops
(`add_edge(node, node)` is called k times total for it across the cascade).

**Knobs** (on `GraphProcgenConfig`, all `@export_range(0.0, 1.0)`):

| Knob | Default | Meaning |
|---|---|---|
| `self_loop_tier1_rate` | 0.10 | fraction of all nodes upgraded to ≥1 self-loop |
| `self_loop_tier2_rate` | 0.17 | fraction of the tier-1 set upgraded to =2 |
| `self_loop_tier3_rate` | 0.30 | fraction of the tier-2 set upgraded to =3 |
| `self_loop_tier4_rate` | 0.30 | fraction of the tier-3 set upgraded to =4 |

The number of tier knobs **is** the cap (4). Raising it later = adding a
tier-5 knob. Cores (`starting_points`) are **not** excluded from the tier-1
pool — a self-loop on a core is a defining launch condition by design; no
`allow_self_loop_on_core` knob.

**Floor contract:** the floors are the guarantee — no bad-luck empty maps. At
the defaults with N generated nodes: at least `floor(N×0.10)` nodes with ≥1
self-loop, `floor(K1×0.17)` with exactly 2, `floor(K2×0.30)` with exactly 3,
`floor(K3×0.30)` with exactly 4.

**Map-size framing:** a 300-node map is *extra-extra-extra-small*, not
"default". Late-game entities hold 100–150 nodes; a 300-node map is cozy for
low-level entities (holding ~10 nodes), and a knife fight in a phone booth
for mid/late-game entities wielding ~100+. The self-loop rarity ladder is
visible at 300 by construction (floors: 30 / 5 / 1 / 0-or-1), and scales
linearly to 3000 (floors: 300 / 51 / 15 / 4).

Downstream notes: degree counts each self-loop as +2 (`graph/graph.gd`);
`SelfLoopCritCondition` keys on `state.predecessor == target` (per-traversal),
so 4 self-loops = 4 crit opportunities per visit, not bigger crits.

## Print-tool

`@export_tool_button` on `ModifierPoolSet` ("Print pools as tables"). Open
`specimen_pool_set.tres` in the inspector, click → markdown-ish dump to
editor output. Includes per-tier weight % within each pool.

## Hover debug (`c` to clipboard)

`autoload/debug_clipboard.gd` (autoload `DebugClipboard`) listens for `c` while
the global tooltip's hover state is active and copies a formatted dump (archetype,
primary_stat, hp, modifiers, addons) to the system clipboard — for sharing
generated content in feedback loops.

## Migration notes from v2

- `ModifierPool` + `ModifierPoolEntry` still exist; v3 builds entries via
  `TierPool.to_entries()` at flatten time. Existing weight profiles
  (ArchetypeWeightProfile, CollisionProfile, RadialBandProfile) still apply
  identically — they key off entries, not the new pack/pool structure.
- `BudgetPolicy` gained `budget_floor_field` + `budget_ceiling_field`. The
  original `budget_field` is retained as an orthogonal global multiplier.
- `AddonPolicy` reshaped: dropped `chance_per_node` / `addon_budget_*`, added
  `slot_count_weights`. Unicity via `SkillNodeAddon.unique` + scene dedup.
- `ArchetypePolicy.primary_stat` is the v3-required new field — old archetype
  .tres files need it set or phase 2 returns empty.
