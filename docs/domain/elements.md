# Elements — the second axis, as the code has it

design record: `docs/design/elements.md` and `docs/design/elements/`. This
is the *what is*. Every later #1716 unit appends its part here.

An **element** sits beside the aspects, never above them: an aspect is one
status, an element is one count and a **family** of member statuses with fixed
roles. Elements are not parents of aspects, and no aspect's status is a member
(ADR 0072 §1; `test_aspect_roster.gd` guards both).

## The counts

| element | count stat | shown as | school (pool roll) | terrain stack | primed band | overflow band |
|---|---|---|---|---|---|---|
| Fire | `fire_element` | "Fire attunement" | STR (`procgen/pools/strength.tres`) | Heat | Burning | (no identity) |
| Ice | `ice_element` | "Ice attunement" | DEX (`dexterity.tres`) | Cold | Frozen | Deep freeze |
| Lightning | `lightning_element` | "Lightning attunement" | INT (`intelligence.tres`) | Charge | Shocked | (no identity) |

- Each count is `stats_system/defs/<element>_element.tres`: the element
  identity, `role = COUNT` (`StatDef.Role.COUNT`, the ordinal the old `ASPECT`
  had), no family parent, `default_value` 0 (#1809 raises it to 1). Every
  non-sparse entity board mints it through `mint_facets`; read it as
  `board.facet(&"fire", StatDef.Role.COUNT)`.
- The pool roll copies an aspect's supply entry: `passes [budget, supply]`,
  regular and blight subtypes. `test_pool_scoping.gd` (`_SUPPLY_HOME`) and
  `test_roll_pass.gd` (supply = the COUNT-role stats) pin it.
- No surface reads a count yet (`docs/domain/stat-surfaces.md` § Quiver,
  volleys, infusion, ammo aspects).

## `Element` (`elements/element.gd`)

One `elements/defs/<element>.tres` per element. The fields it shares with
`Aspect` keep `Aspect`'s names.

| field | holds |
|---|---|
| `identity` | the element's `Identity` (`Kind.ELEMENT`); `id()` reads it |
| `stat` | the COUNT facet above |
| `terrain` | the one terrain stack (`StatusDef`) |
| `movers` | the sided movers; empty in v1 (Frostbite joins Ice with #1444) |
| `school` | the attribute `Identity` whose pool rolls the count |
| `ammo`, `addon_scene`, `spells` | empty until #1810, #1804 and the spell cells |
| `decay_per_world_turn` | terrain decay per world turn below the first band; 1 on all three (owner, 2026-11-11). Read by #1795 |
| `bands` | `Array[ElementBand]`, ascending |

## `ElementBand` (`elements/element_band.gd`)

A band is a threshold, an identity and its answers. Nothing computes or
stores a band here: #1794's band function reads `bands` against
(count, T, k), and returns the highest band a count passes.

| field | holds |
|---|---|
| `threshold_multiple` | the threshold as a multiple of T (≥ 1) |
| `at_cap` | true: the threshold is the node's cap k × T and `threshold_multiple` is ignored; only the last band |
| `identity` | the band's display atom; null falls back to the band below |
| `go_off` | a `GoOff` (`elements/go_off.gd`, an empty abstract base); null on every band. #1798 owns the contract, #1799 / #1800 / #1806 the subclasses |
| `admits` | an `Admits` (`elements/admits.gd`, empty abstract base); null on every band. #1807 owns the answer |
| `travel` | `Travel { NONE, ENDS, CONDUCTS, SPREADS }` |
| `decay_per_world_turn` | the band's own decay rate (a knob) |
| `light` | the band is a light source |

The authored bands (tentative numbers are knobs on the `.tres`):

| element | band | threshold | identity | travel | decay | light |
|---|---|---|---|---|---|---|
| Fire | primed | ×1 | `burning` | SPREADS | 1 (tentative) | yes |
| Fire | overflow | at cap | — | SPREADS (lead call, tentative) | 2 (tentative) | #1805's |
| Ice | primed | ×1 | `frozen` | ENDS | 1 (tentative) | no |
| Ice | overflow | at cap | `deep_freeze` | ENDS (tentative) | 2 (tentative) | no |
| Lightning | primed | ×1 | `shocked` | CONDUCTS | 1 (tentative) | no |
| Lightning | overflow | at cap | — | CONDUCTS (lead call, tentative) | 2 (tentative) | no |

An overflow band keeps its primed band's travel verb; only its decay differs
(`test_element_roster.gd` pins the verbs, and pins overflow decay ≥ primed,
never the literal). **Volatile** (Burning, Shocked) is a word, not a field.

## `ElementRoster` (`elements/element_roster.gd` + `.tres`)

The `AspectRoster` pattern: hard `ExtResource` edges, read through
`ElementRoster.shared()`, never a directory scan.

- `by_id(&"fire")`, `for_stat(&"fire_element")`.
- `for_status(def)`: the element whose `terrain` or `movers` holds `def`, or
  null. This is the one way to ask "is this status a member, and of what".
  Catalyst is nobody's member, so it answers null.

Guard: `test/unit/elements/test_element_roster.gd` (roster vs disk, lookups,
facet identities, band order, null go-offs and admits, verbs, light, decay).

## The terrain statuses: Heat, Cold, Charge

`effects/status/{heat,cold,charge}.tres`: the plain `StatusDef` script, each on
its own identity, no tags, `power_max = 0` (uncapped here; the cap is the
node's k × T, #1794). They are on `effects/status_roster.tres` as host rows;
nothing plants them yet (#1794 diverts them).

Each member keys its own facets: `heat_resistance`, `cold_resistance`,
`charge_resistance` (`role = RESISTANCE`, parent `status_resistance`, the
`poison_resistance` shape), on `stat_def_roster.tres` and minted on every
board. No `*_stacks_per_hit` facet: a member lands its authored power as-is.

## `Identity.Kind.ELEMENT`

Appended last (ordinal 5), so stored kinds do not shift; presentation only.
Ten identities use it: `fire`, `ice`, `lightning`, `heat`, `cold`, `charge`,
`burning`, `frozen`, `shocked`, `deep_freeze`. Their hues clear the roster's
same-kind OKLab separation and the gold exclusion (`test_identity_roster.gd`).
The badge frame is a triangle (`ui/identity_badge/badge_frames.tres`, key 5).
`concept_card.gd` stays ASPECT-only; the identity sandbox lists the kind
through `Kind.values()`.

## Intake rows name their status

`AspectIntake.plants` (`attack/spell/aspect_intake.gd`): when set, `status()`
returns it; null falls back to the concept's only status through
`StatusRoster.by_concept`. No shipped row sets it yet; #1800 rekeys
`Infusion.load_of` / `use_of` so a row named by element resolves its status.
