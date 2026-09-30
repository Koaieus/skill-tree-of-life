# The Aspect Matrix — every concept × every attack mode

> Design doc: the living table. Every status/concept must fill every column —
> Ranged (arrow), Melee (addon), Magic (infusion) — each delivered through
> whatever hit kind the concept actually is (Scout is a reveal, not a damage
> status). An empty cell is a deliberate call written into the table, never
> a gap.

## The rule (owner, 2026-09-30)

Every concept gets a stat, an arrow, an addon, and a magic infusion. Naming:
`<concept>_aspect` (e.g. `poison_aspect`), so it sorts with the concept's
other `poison_*` stats. Supply model of the aspect stat (per-turn refill
pool vs Civ-style capacity vs minting arrows on reload) is **open**, on
#1199.

**Addon column note:** "addon" and "temp addon" are one thing — a
`SkillNodeAddon` scene (entity + node-local modifier lists, plus the
overridable `apply_to_blade` hook). A map addon is placed by procgen and
stays; a temp addon is added to a blade before a swing, costs aspect
charges + blade size budget, and is removed after. Addons are copied onto
melee blade nodes and take effect there — hence one column, not two.

**Magic infusion** is a fifth spell component (an `Infusion` resource adding
an on-hit effect plus optional drawback on another component), not a patch
onto the existing four — keeps #1200 (composable spells) open. Mechanics
TBD on #1199.

## The Matrix

| Concept | Stat | Ranged (arrow) | Melee (addon: map / temp) | Magic (infusion) | Notes |
|---|---|---|---|---|---|
| Poison | `poison_aspect` | shipped (`poison_arrows_per_reload`, to be replaced by aspect supply) | `toxin_addon.tscn` (on shared `dot_addon.gd`) | spells apply poison; infusion TBD | spread signature undecided (#1204) |
| Corruption | `corruption_aspect` | #971 | #971 | #971 | spreads as a sandpile by nature (#1202); health bar shows blips per stack, extra-mean when critical (#1092) |
| Curse | `curse_aspect` | #972 | #972 | #972 | raises `min_damage_taken`; spills to surviving direct neighbours on death AND dealloc (#1204) |
| Wither | `wither_aspect` | #973 | #973 | #973 | drives healing received negative |
| Blindness | TBD | TBD | TBD | TBD | count stacks, effect reads as a % via a saturating curve |
| Scout (a reveal, #949) | TBD | scouting arrow (shipped) | watchtower addon (shipped); temp: lit blade node pushing back fog (owner pitch, perf-sensitive: one moving mark per blade, never a second vision path) | TBD | `effects/status/scouted.tres` is live (VisionSystem's decay rule); first-class concept (owner, 2026-09-30) |
| Armor break | TBD | #395 | #395 | #395 | flat −1 armor per stack, uncapped, can go below zero (#1203, owner 2026-09-30) |
| Explosive | `explosive_aspect` | explosive arrow (#1211) | explosive addon, procgen at low rate; detonation kills the blade node, reuses spike-pop plumbing (#1211) | stub (#1211) | euclidean hitscan radius from `SkillNode.radius`; barrels / friendly fire open (#1211) |

## Contenders

Not yet promoted into the Matrix proper — fill cells when a good idea shows up.

| Concept | Stat | Ranged (arrow) | Melee (addon) | Magic (infusion) | Notes |
|---|---|---|---|---|---|
| Spikes | TBD | TBD | `spike_ring_addon.tscn` (×1.5 local `blade_damage` + stake-scaled `spikes`) | TBD | owner estimate ~×4.5 damage at 3/3 allocation, unmeasured |
| Blunting | TBD | TBD | today only a spiked node's +1 | TBD | — |

## Open

- Supply model for `<concept>_aspect` (#1199).
- Attribute archetype per concept: the 2026-09-22 grid in
  [node_subtypes.md](node_subtypes.md) (DEX poison, STR corruption, INT
  wither, CON curse, PER blindness/scout, WIS none) vs. the owner's
  2026-09-29 mapping (INT curse, CON wither, STR also armor break) —
  unresolved (#1199).
- Can one hit carry two aspects (#1199).
- WIS status family (#1199 brainstorm).

Related: #1199 (design discussion), #1211, #1212 (addons become scenes),
#1202, #1204, #1203, #1217, #971–#973, #395, #1200.
