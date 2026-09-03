# Stat → UI Visibility Checklist

Where each stat appears (or doesn't) in the HUD. Add a row when adding a new
stat or UI component — this file surfaces coverage gaps and multi-location
duplication.

> **Legend:** `→` = derived from (the source stat is shown via a computed value)

## Attributes

| Stat | HeroSigil | AttrPanel | AttrTooltip | CombatReadout | Other |
|---|---|---|---|---|---|
| `strength` | | value + radar | → blade_size, blade_damage | MeleeCard (→blip/dmg) | |
| `dexterity` | | value + radar | → sensor_range, range | RangedCard (→dmg/leaf) | RangedBody → dmg/leaf |
| `intelligence` | | value + radar | → mana, mana_per_turn | | |
| `wisdom` | | value + radar | → xp_per_turn | | |
| `perception` | | value + radar | → vision_range | | |

## Survivability

| Stat | HeroSigil | NodeTooltip | CombatReadout | Other |
|---|---|---|---|---|
| `health` | PoolGauge | Core HP bar | | |
| `node_health` | | **(none — only derived per-node HP appears)** | | |
| `node_combat_health` | | LabeledProgressBar | | InspectorCard N/M |
| `armor` | | (if mod present) | DefenseCard row | |
| `min_damage_taken` | | | DefenseCard row | |
| `dealloc_damage` | | **(none)** | | |

## Economy

| Stat | HeroSigil | Other |
|---|---|---|
| `xp` | **(none — moved #320)** | XpTrack: PoolGauge + level-up anim + XpDeltaChip |
| `xp_per_turn` | **(none — moved #320)** | XpTrack: gauge preview_gain + caption |
| `level` | badge (driven by `XpTrack.level_display_changed`) | XpTrack "LEVEL N" readout |

> **XP left the Hero Sigil card in #320.** It now lives on `XpTrack`
> (`ui/hud/xp_track/`), the top-center strip — XP is the currency the game is
> denominated in, and it was reading as third billing under health and mana. The
> card's `XPRow` survives as **hidden, unbound scenery** while the placement
> settles; do not re-bind it, a second binder on the `xp` pool double-narrates
> every level-up. The card keeps the level badge only.

## Allocation

| Stat | TurnResourcesPanel | Other |
|---|---|---|
| `skill_points` | CompositeBar (4 buckets + legend) | |
| `wound_heal_per_turn` | label + ProgressBar sliver | |

## Turn Budget

| Stat | TurnResourcesPanel | ActionCluster | Other |
|---|---|---|---|
| `action_points` | PoolGauge | battery + N/M label | CommandTray (mana cost checks) |
| `deallocation_points` | SurplusPoolGauge | | |
| `movement_points` | SurplusPoolGauge | | |
| `ap_transfer_rate` | | conversion preview text | |

## Turn Order

| Stat | InitiativeBar |
|---|---|
| `initiative` | progress bar (tint at threshold) |
| `initiative_speed` | **(none)** |

## Vision

| Stat | AttrPanel label | Other |
|---|---|---|
| `vision_range` | "N px" | |
| `sensor_range` | "N hops" | |

## Ranged

| Stat | RangedCard | RangedBody | Other |
|---|---|---|---|
| `range` | CombatValueRow + px | "N dmg/leaf · N px" | |

## Magic

| Stat | HeroSigil | MagicBody | SpellTooltip | Other |
|---|---|---|---|---|
| `mana` | PoolGauge | "mana N" | | |
| `mana_per_turn` | gauge preview_gain | | | |
| `spell_range` | | | (→effective euclidean range, "Range" row) | |
| `spell_hops` | | | (→effective hops, "Range" row for hop-ranged spells) | |

## Melee

| Stat | MeleeCard | MeleeBody |
|---|---|---|
| `blade_size` | CapacityBlips + breakpoint | plan blips |
| `blade_damage` | CombatValueRow + breakpoint | |

---

## Stats with NO UI representation

These three are system-internal — consumed by game logic but never surfaced
to the player. Likely intentional (visual clutter vs. player need-to-know),
but listed for triage awareness.

| Stat | Consumed by | Notes |
|---|---|---|
| `initiative_speed` | `TurnManager` to tick initiative | Harder to tune blind — player can't see why initiative is fast/slow |
| `node_health` | Seeds per-node `node_combat_health` max | Already visible indirectly through node HP; showing it separately would be redundant |
| `dealloc_damage` | `BattleSystem._on_node_depleted` cascade | Tuning lever with zero feedback; a core that raises this gives no UI clue |

---

## Stats in multiple UI locations (review these for intentionality)

| Stat | Locations | Justification |
|---|---|---|
| `action_points` | TurnResourcesPanel (budget plan), ActionCluster (turn action state), CommandTray (suff. check) | Three distinct roles — pool overview, action readiness, spending gate. Intentional. |
| `strength` | AttrPanel (+radar), MeleeCard (→blade), NodeTooltip (if mod present) | Attributes show raw; combat shows effective; tooltip shows mods. Clear separation. |
| `dexterity` | AttrPanel (+radar), RangedCard (→dmg/leaf), RangedBody, NodeTooltip | Same pattern. |
| `health` | HeroSigilCard (entity gauge), NodeTooltip (core HP) | Entity-level vs. node-level — different contexts. |
| `mana` | HeroSigilCard (gauge), MagicBody (spending context) | Budget vs. spend. |
| `armor` | DefenseCard (combat readout), NodeTooltip (if mod present) | Effective vs. mod breakdown. |
| `range` | RangedCard, RangedBody | Both combat-context, but RangedBody is in the tray while planning a shot — acceptable duplication. |
| `node_combat_health` | NodeTooltip (hover), NodeInspectorCard (selected node) | Hover vs. persistent selection — different interaction modes. |

---

## How to update this file

1. **New stat:** add its `StatDef` `.tres`, then add a row to the matching
   group table above (or create a new group). If it's not shown anywhere,
   list it in "Stats with NO UI representation" with the consuming system.
2. **New UI component:** add a column to the relevant tables, or add a row
   to "Stats in multiple UI locations" if the component re-displays an
   already-visible stat.
3. **Out of date?** Run a grep for `get_stat`/`get_local_value`/`bind.*stat`
   in `ui/` and cross-check against the tables above.
