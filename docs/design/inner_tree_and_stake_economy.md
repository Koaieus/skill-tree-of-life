---
status: settling
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

## 1. Run pacing (health rebase, XP curve, level cadence)

### Health rebase: decided in #1525

The "×10 is safe only as a full rebase" analysis is superseded: the scale
decision is **#1525** (lv1 core and node HP ≈ 100 starting value, floor 5, heals 3,
spell damage up with HP, status per-stack values unchanged, Dormant Cores
100 / 200 / 300 core HP, footprint falloff −15/hop). Read the numbers there.

### XP curve and kill payouts

Decided in **#1527** (curve 50 + 10/level, innate WIS 15, procgen WIS unit 3,
kills 10 per node + 30 / 60 / 120 core, divisor 5). Read the numbers there.

### Level cadence → specialisation points

| interval | points by lv5 (~T18–24) | by lv10 (~T50–62) | verdict |
|---|---|---|---|
| every 5 | 1 | 2 | too sparse: cannot finish one spoke |
| **every 3** | 1 | 3 | a run is "one spoke to T2 plus a second T1" |
| every 2 | 2 | 4–5 | wheel-fillers, the choice disappears |

Plus **one bonus point on the first 3/3 stake of the run** — ties the inner
tree to the thing the game is about, and gives staking a reward that is not SP.

## 2. The inner aspect tree

**Settled (owner, 2026-10-17, #199):** *"ring (interconnected a bit tho) with
aspect sectors first, keystones already taking up spots but just use the XP
anchor keystones in there for now; when we switch to each CoreClass getting
their own bespoke innerskilltree we simply replace those keystones with a set
of coreclass-specific (or just an inherited scene?)"*. The Ring below is the
pick; T1 count, T2 potency, a keystone cell per sector; cells grant
through the core register, so they are lootable on death. T3 signatures and
opposition are a Needs-design child of #199. The point cadence (every 3) is a
knob, the milestone +1 SP stays. The wheel, radar and milestone-draft shapes are dead.

**Re-cut 2026-10-17 (owner, #1652 pass):** the ring is *"a hand authored scene
with nodes and edges and node content readily composed"* — an authored Graph
of SkillNodes, PoE-passive-tree-like, buyable by adjacency to the core or a
bought cell. This reverses the earlier "never a second graph of SkillNodes"
reading; the build and the surface are #1651 and #1652's children
(`inner_ring_ui.md`).

**Settled the same day — the "taken" channel beside this "earned" one:**
faced Dormant Cores (a per-aspect core class granting size-scaled count /
potency / resistance-where-the-stat-exists, pinned into the kill's first loot
round) and procgen-placed aspect spirits (skill dust with a fixed +1 count
offer, plus a gray mystery variant). Both are their own Ready issues filed from
#199's pass.

Facts it leans on: 12 `<aspect>_aspect` counts under the `aspects` family
parent, 10 `<aspect>_stacks_per_hit` potencies (scout, sunder, explosive
have none yet), six schools × two aspects (`aspect_matrix.md:395-402`; #1249
still open on the map), `Entity.MILESTONE_LEVEL_INTERVAL := 5` already exists,
and mid-run choice modals already exist (loot and spell-loot pickers). Count is capped per action
for melee and magic (#1467) — a count tier is secretly a ranged buff unless the
pick text says what it does in your mode; potency is uncapped and is the
equaliser.

**Settled (owner, 2026-10-17): the milestone slot is repurposed.** *"slot
repurposed sounds like a good idea"* — the every-5th-level extra SP becomes the
ring point, first at level 5. Ring points are a `PoolStat` like skill points
(cap from modifiers, current = unspent), so a one-off keystone or spirit that
grants a point is a +1 cap modifier (#1651 amendment).

**Open (owner, 2026-10-17): the cadence and the rare path.** Cadence: every
5 ships; the owner floated one point per prime level reached (15 under 50,
*"a bit lame"*) — *"this whole pacing part is one session worth of discussion
on its own"*. Rare path, owner's two options: a keystone with a one-off +1
ring point, skill-dust-like; or *"wait for a better suitor; a feat that
deserves an award. a particular show of skill, puzzle solved, jimmies
rustled"* — kills are already rewarded, *"i feel like there's more brewing"*.
Rejected the same night: SP→point exchange, the first 3/3 stake as a source
(garnish at most). Corpse spirits (a kill guarantees a spirit on the relic)
are their own Intake issue.

### Shapes

| shape | fantasy | costs | kills / awkward |
|---|---|---|---|
| **The Ring** (recommended) — the wheel with adjacency made physical: 12 aspects on a rim in school order, only T1s visible until a neighbour is bought | you *walk* the ring outward from where you started; an arc of 3 is a build, a split across the ring is expensive | one circle, not 36 cells | needs the spoke map (#1249) final |

### Gating, adjacency, opposition (the Ring)

- **T1** (1 pt): +1 `<aspect>_aspect`. Always buyable.
- **T2** (1 pt): +1 `<aspect>_stacks_per_hit` (+2 where base is 1 and the
  aspect is weak). Buyable once an edge links it to a bought cell — gating
  is PoE adjacency from the core, the authored edges are the rules (owner,
  2026-10-17, #1652); an AND-gate is a later optional addon if play wants
  breadth forced.
- **T3** (2 pts): a signature. Needs T2 here **and** T2 on the sector partner
  (same school). Breadth before depth: three points into Poison alone never
  reach T3.
- *(Stale: Hex now holds INT beside Curse and Mark moved to DEX; see the
  `aspect_matrix.md` INT row, "Curse, Hex". The pairing below predates it.)*
- Ring order: Bleeding, Weakness | Poison, Explosive | Curse, Hex | Wither,
  Sunder | Scout, Blindness | Corruption, Greed | back to Bleeding.
- **Opposition** (six axes through the centre; no hard lock, which hurts AI
  and experimenters — instead *one T3 per axis* and taking it doubles the
  opposite's T2 cost): Poison ↔ Explosive (slow DoT vs burst) · Bleeding ↔
  Sunder (soft wounds vs hard armour) · Wither ↔ Greed (starve vs
  amplify) · Scout ↔ Blindness (reveal vs blind) · Curse ↔ Weakness (fragility
  vs damage cut) · Hex ↔ Corruption (crit-taken vs % build-up).

### Signatures (T3), one per aspect, all rule tweaks on existing rows

Bleeding: stacks are not lost while the bleeder moves · Weakness: a weakened
node halves a neighbour's damage too · Poison: a stack that would decay holds
one extra turn · Explosive: +50% blast radius, the blast leaves one Poison or
Sunder stack · Curse: death/dealloc spill reaches two hops · Hex: first
Hex landing per turn on a node counts double · Wither: the first stack already
zeroes healing, further stacks hurt · Sunder: each landing shaves 1 armor
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
  blocker health; the #1525 health rebase then stays a pure unit change.
