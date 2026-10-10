---
status: exploring
---

# Inner aspect tree, stake economy, run pacing — shapes that would fit

Owner idea dump of 2026-10-10 (quoted on the issues: staking, health rebase, XP
economy, addon cap, blessed/blighted, and #199), explored the same day with
three Sonnet design passes and the code facts from the research pass. This doc
is the *diverge* beat: candidate shapes with pacing, gating, cost and reward,
and a recommended package per cluster. Nothing here is decided; the owner says
when the picture is clear, and the conclusion then moves to the issue (dated,
attributed) or an ADR. Numbers are estimates unless a path is cited.

## 0. The one measurement nothing else can replace

No run length in turns is recorded anywhere (`docs/playtests/lan-2026-09-06.md`
has "many runs end after 1~3 turns" and one 20k-INT outlier, no durations; the
first level has no turn cap, `session/scenario.gd:72-73`). Every pacing number
below assumes a 30–60 turn run. **One logged 800-node playthrough with turn
counts per level and per kill is the cheapest thing on this page.**

## 1. Run pacing (health ×10, XP curve, level cadence)

### Health ×10 is safe only as a full rebase

Today: core 10 + CON (≈30), node 10 + CON, every damage source ≈ 1/hit, heal
1/turn, blocker cores 1 + CON = 11 / 31 / 71, large-blocker armor 5, footprint
falloff −5/hop. Turns-to-kill at lv1 (3 dmg/turn, heal 1): small 6, medium 16,
large 36; lv5 vs lv5 core 7. These ratios survive ×10 **only if every flat
number moves**:

| must move ×10 | why |
|---|---|
| health, node_health, both CON scalings, core/node healing | the pools and their regen |
| blade / ranged / spell / dealloc damage, crit floors, DoT ticks | the hits |
| blocker cores → **110 / 310 / 710**, armor 5 → 50, falloff −5 → −50 | the owner's "~300 for large" is a *different* design: 110/130/170 turns a 36-turn large into a 9-turn one |
| not wounds (`wound_heal_per_turn` is SP, not health) | wrong unit |

Where ×10 is *not* neutral and that is the point: spell power 0.4 × (1+√20)
= 2.2 rounds to 2 today, 22 after — the owner's "magic does big things with
numbers" is the rounding floor; it goes away. Armor goes from "immune to
1-damage arrows" to "halves 10-damage arrows" unless it is ×10 too.

### XP: kills must scale with the curve, and WIS must not run the game

Today's curve is cap 5L (lv1→2 is **5**, cumulative lv5 50 / lv7 105 / lv10
225), kills pay 5 per node + 20/40/60 per blocker core, passive floor(WIS/5).
A medium blocker from lv1 is +4 levels; a level-13 player at turn 45 holds ~29
nodes of 800. The owner's "lv7 in two turns" for the +30-WIS AI is kill XP,
not passive (8/turn today).

| curve | caps | cum. lv5 / lv7 / lv10 | medium kill from lv1 | lv5 at (passive 5/turn + kills) |
|---|---|---|---|---|
| today 5 + 5L | 5, 10, 15 | 50 / 105 / 225 | +4 levels | turn ~10 |
| **A** base 50, flat 10 | 50, 60, 70 | 260 / 450 / 810 | +1 | turn ~24 |
| **F** base 25, flat 10 | 25, 35, 45 | 160 / 300 / 585 | +1–2 | turn ~18 |
| B base 50, flat 25 | 50, 75, 100 | 350 / 675 / 1350 | +1 | turn ~30 |

Two findings that overturn the pass's first tentative picks on the XP issue:

- **Under A, 20/40/60 kill XP stops mattering**: passive is 38% of income at
  turn 45 and the AI's WIS head start decides the game. Kill XP must scale with
  the curve — ×5 (100 / 200 / 300 per core, 25 per node) keeps "a kill is an
  event" while a medium kill is one level, not four.
- **Keep the divisor at 5.** Divisor 2 makes the +30-WIS AI 20 XP/turn against
  the player's 5 — lv5 at turn 13 vs 24, lv10 at 40 vs 62. The LAN deaths
  (LAN-02) get worse, not better. Raise the *procgen* WIS unit (2 → 3) instead
  so WIS is something you find, not something the cheater is born with.

Recommended: **curve F, kills ×5, divisor 5, procgen WIS unit 3, cheater WIS
+30 → +15.** The one number that matters: real run length.

### Level cadence → specialisation points

| interval | points by lv5 (~T18–24) | by lv10 (~T50–62) | verdict |
|---|---|---|---|
| every 5 | 1 | 2 | too sparse: cannot finish one spoke |
| **every 3** | 1 | 3 | a run is "one spoke to T2 plus a second T1" |
| every 2 | 2 | 4–5 | wheel-fillers, the choice disappears |

Plus **one bonus point on the first 3/3 stake of the run** — ties the inner
tree to the thing the game is about, and gives staking a reward that is not SP.

## 2. The inner aspect tree

Facts it leans on: 12 `<aspect>_aspect` counts under the `aspects` family
parent, 10 `<aspect>_stacks_per_hit` potencies (scout, armor_break, explosive
have none yet), six schools × two aspects (`aspect_matrix.md:395-402`; #1249
still open on the map), `Entity.MILESTONE_LEVEL_INTERVAL := 5` already exists,
the loot picker is the only mid-run choice modal. Count is capped per action
for melee and magic (#1467) — a count tier is secretly a ranged buff unless the
pick text says what it does in your mode; potency is uncapped and is the
equaliser.

### Shapes

| shape | fantasy | costs | kills / awkward |
|---|---|---|---|
| **Wheel** — 12 spokes in 6 sectors, 3 tiers each | "I am a Rot Bishop (Wither + Corruption)"; a horoscope of your build | one screen, 36 cells | highest legibility load |
| **Radar** — 6 school axes 0–5, notches unlock the pair | glanceable polygon | 6 choices | throws away the 12 identities; collides with the six attributes (two 6-axis radars side by side) |
| **Milestone drafts** — pick 1 of 3 cards | roguelite surprise | loot picker exists, zero UI | not a tree; with 1–3 points a draft is a coin flip |
| **Inner graph** — 12 real SkillNodes inside the core | the fractal pitch, literally | two allocation UIs, save/sync, AP question | most expensive, least readable |
| **The Ring** (recommended) — the wheel with adjacency made physical: 12 aspects on a rim in school order, only T1s visible until a neighbour is bought | you *walk* the ring outward from where you started; an arc of 3 is a build, a split across the ring is expensive | one circle, not 36 cells | needs the spoke map (#1249) final |

### Gating, adjacency, opposition (the Ring)

- **T1** (1 pt): +1 `<aspect>_aspect`. Always buyable.
- **T2** (1 pt): +1 `<aspect>_stacks_per_hit` (+2 where base is 1 and the
  aspect is weak). Needs T1 here **and** T1 on a ring-neighbour.
- **T3** (2 pts): a signature. Needs T2 here **and** T2 on the sector partner
  (same school). Breadth before depth: three points into Poison alone never
  reach T3.
- Ring order: Bleeding, Weakness | Poison, Explosive | Curse, Hex | Wither,
  Armor break | Scout, Blindness | Corruption, Greed | back to Bleeding.
- **Opposition** (six axes through the centre; no hard lock, which hurts AI
  and experimenters — instead *one T3 per axis* and taking it doubles the
  opposite's T2 cost): Poison ↔ Explosive (slow DoT vs burst) · Bleeding ↔
  Armor break (soft wounds vs hard armour) · Wither ↔ Greed (starve vs
  amplify) · Scout ↔ Blindness (reveal vs blind) · Curse ↔ Weakness (fragility
  vs damage cut) · Hex ↔ Corruption (crit-taken vs % build-up).

### Signatures (T3), one per aspect, all rule tweaks on existing rows

Bleeding: stacks are not lost while the bleeder moves · Weakness: a weakened
node halves a neighbour's damage too · Poison: a stack that would decay holds
one extra turn · Explosive: +50% blast radius, the blast leaves one Poison or
Armor-break stack · Curse: death/dealloc spill reaches two hops · Hex: first
Hex landing per turn on a node counts double · Wither: the first stack already
zeroes healing, further stacks hurt · Armor break: each landing shaves 1 armor
from the two nearest neighbours · Scout: a camp's vision disc lingers 2 turns
after the stack · Blindness: flare reach extends to second-hop hostiles ·
Corruption: the Compromiser's flat rider is 2 stacks, no ladder · Greed: a
spent Greed stack also pays Avarice XP, refunded if the doubled hit kills.

### AI and persistence

An NPC buys by its highest school: T1 on both of that school's aspects, T2 on
both, T3 on the better one; ties by class (melee STR/CON, archer DEX/PER, mage
INT/WIS). Deterministic, so sync needs only the spent set. Spent tiers as
board modifiers ride the board row; an unspent counter is one new snapshot
row + `SaveFile.FORMAT_VERSION` bump. The inner tree resets every run and is
never on the meta tree (`metagame.md`); no node appears in both.

## 3. The stake economy

**Decided on #1524 (owner, 2026-10-10)** — stake and extract are multi-turn
*channels*: a target cap on the node, one step per K of the owner's turn
starts, initiated within a reach of hops from the core and kept alive by a
wider leash; abort wounds the pledged SP. Extract is a currency exchange out of
the entity's own `staked` bucket, paid back as wounds; no AP cost; the stake
ceiling is a node-local stat. Economy knobs ship at 1 SP cost / 1 refund with
the 2 / 1 flip a later edit. The shapes weighed are the issue's two design
comments; the rejected ones (per-node `staked_by` with minting, a pin instead
of a leash, a cost drain alone) are dead grounds in the ADR child.

Still open here, not on #1524: **tenure relief** (+1 SP per node held at cap
for 8 turns, cap 2/run) and the **inner-tree point on the first 3/3** — both
rewards for holding, parked until stake usage under channels is seen; the
**Mastery tempo dividend** lives on #887. Veins are #1531; under the
currency-exchange rule a vein pays only an entity that holds staked SP.

## 4. What falls out for free

- The vein rule answers the addon-cap issue: a pre-staked N/N multi-addon node
  is honest against a cap defined off `stake_level` (#1530) *and* is an extract
  target for an entity holding staked SP.
- The inner-tree bonus point on a 3/3 stake would give staking a non-SP reward
  without the "per X kills" farming smell.
- Kill XP ×5 with curve F makes blocker tiers matter again without touching
  blocker health; the health ×10 pass then stays a pure unit change.
