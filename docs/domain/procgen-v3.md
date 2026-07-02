# Procgen v3 — phased draw + StatPack content

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
| `dexterity.tres` | `&"dexterity"` | dexterity add_base/increase/multiply |
| `intelligence.tres` | `&"intelligence"` | intelligence + mana + mana_per_turn pools, INCREASE includes negative tiers |
| `wisdom.tres` | `&"wisdom"` | wisdom + xp_per_turn (flat-primary, INCREASE secondary). `off_phase_op_weights = {ADD_BASE:0.2, INCREASE:0.05, MULTIPLY:0.0, ADD_BONUS:0.05}` |
| `perception.tres` | `&"perception"` | perception + vision_range INCREASE/ADD_BONUS + sensor_range. Same suppression as wisdom |
| `defensive.tres` | `&""` (cross-cutting) | node_health add_base/increase + armor add_base. role=DEFENSIVE |
| `rare.tres` | `&""` (cross-cutting) | min_damage_taken −1, vision_range flat additions, ×2 multipliers. role=RARE |
| `mobility.tres` | `&""` (cross-cutting) | movement_points + deallocation_points add_base, +1/+2/+3 low-integer tiers (#41). role=DEFENSIVE — universal, not DEX-gated, since it always draws off `flatten_for_phase(&"defensive", ...)` regardless of a node's `primary_stat` |

The set of these is bundled into `specimen_pool_set.tres`.

## Authoring conventions

- **No UIDs on hand-authored ext_resources for in-project scripts** (lint-mismatch silently nulls fields). Either omit `uid=` or verify from `.uid` files. (The editor will fill UIDs on save once it touches the file — that's safe; the lint is "don't *copy-paste* a UID and hope.")
- **TierDef magnitudes:** prefer integer values for ADD_BASE (especially INT-typed stats). INCREASE auto-snaps to int via `ModifierPoolEntry._coerce_to_stat_type`. MULTIPLY stays float (`×1.5` is meaningful).
- **Cost progression:** geometric per tier (1, 3, 9, 27, 81 is the strength curve). With `off_cost_cap_offset=1` only excludes exact-peak entries — `off_cost_cap_factor=0.4` better expresses "off one full tier below."
- **`off_phase_op_weights`** lives on the StatPack, not on individual TierPools. The same suppression applies to all of a pack's PRIMARY pools when they appear in another archetype's off-phase.
- **Cross-stat pools in one pack:** wisdom.tres includes both `wisdom` and `xp_per_turn` pools, both with `archetype_stat = &"wisdom"`. The pack's archetype identity is what couples them.

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
