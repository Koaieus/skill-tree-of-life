---
status: exploring
---

# The final level — the Apex's inner tree

The last level of every run is not a rolled field. The penultimate Breakout
drops the player *into* a core, and the level is that core's inner tree —
authored, PoE-passive-tree-like, with the Apex holding its immovable centre.
Killing the Apex is the run's exit. This doc is how that becomes a fightable
level and a boss with a character: what is settled, what it reuses from the
inner ring (#1651), and the candidates for everything the owner left open.
The cosmology it pays off — the node axis and the core axis — is
[`nesting_cosmology.md`](nesting_cosmology.md). Tracked on #1670 (Needs
design).

Nothing below the owner quotes is decided; candidates are marked, and the
owner says when a fork closes.

## 1. Owner calls

**Settled (owner, 2026-10-17): the final level is a core's inner tree.**
*"You breakout of the core the last one. Or the level right before is? With
then entering a core's inner tree from apparently one of the nodes in there,
so the next level is an ordered unit not procgen, and you must defeat the
central entity in there - what in your own inner tree would've been the
central immovable starter position. Killing that one exits you and boots you
back into the metagame, possibly with a reward related to the boss you killed
and or extended by reward that was put on the level beforehand (e.g. a
metagame skill allocation, is permanent starting stat, the allocation happens
when you complete the run it offers)."*

So: the penultimate level's Breakout does not condense into a starter node —
it drops you into a core, entering its inner tree at one of its nodes. The
final level is authored, not rolled. Its centre — the immovable spot your own
core holds in your ring — is the Apex. The exit is that kill, not a Breakout;
it boots you to the metagame with a boss-related reward and/or the
meta-allocation the run offered, committed on completion (`metagame.md` →
*Commit-on-completion*).

**What falls out for free (owner, 2026-10-17):** *"boss damage scaling, boss
aspect specialization. It'd be a real inner tree, but the keystones may be
specific to that boss (their coreclass) so giving bosses unique abilities and
characters through bespoke keystones (as one would for a coreclass specific
inner skill tree) is doable. And two: bosses can have a subtype, correlated to
coreclass or not, expressed by what Aspects the sections they hold within the
inner tree"*.

**The ring shape this inherits (owner, 2026-10-17, #1652):** *"a hand
authored scene with nodes and edges and node content readily composed. (and
keystone position too; can later be swapped out for others e.g. coreclass
specific keystones if we so want)"*; *"think more like \"PoE passive tree\"
than \"a simple ring\""*; *"Graph but visuals and background and core visuals
differ, core cant move etc, dealloc pts for those is a separate resource"*
(#1669); *"we can start small like not go too ham, can always expand the
inner tree's scene"*.

## 2. What #1651 builds that this reuses

#1651 is Ready, not built; this is what it is specced to build
(`inner_tree_and_stake_economy.md` §2, #1651's acceptance spec):

- **An authored Graph scene** of the board's own SkillNodes and Edges
  (`entity/ring/aspect_ring.tscn`): a centre `Core`, six sectors (one per
  school) × two aspects, each sector T1 → T2 → a keystone cell. A cell's
  content is a `RingCellAddon` (aspect, sector, tier, cost, grant).
- **Adjacency gating** — a cell is buyable iff an edge links it to the centre
  or to a cell this entity bought. The authored edges are the rules.
- **`RingTable`** — the scene sampled once into rules, the instance freed; the
  UI instances it again for display.
- **A per-CoreClass ring** is a noted later export on `RingSystem.ring_scene`
  — the same swap that gives a boss its bespoke keystones.

The gap the final level has to cross: the ring is *sampled and freed* — rules
only, never a live board. The final level needs the same kind of authored
scene **as a live board** that entities stand on and fight across. The
precedent for an authored board exists: `scenes/dev_sandbox.tscn` is a
hand-authored, fully baked level. So the final level is a level scene whose
Graph is authored, not a procgen roll — the inner-tree *shape rules*
(sectors, tiers, an inert centre, its own background) on a board-sized Graph.

## 3. Entering: the penultimate Breakout

Every other Breakout condenses the field into a starter node (the node axis).
This one falls *in* along the core axis. What has to differ:

- **No starter node to re-edge.** The player arrives on the Apex tree's entry
  node, so `lore.md` → *Re-edging the new starter node* does not run.
- **Carry-forward still happens** — the compression is the player's reward
  for the penultimate level. Where it lands is open (Q-carry).
- **The camera beat** — pull back as always, then dive
  (`nesting_cosmology.md` §4, rung 5).

## 4. The level

**Shape (candidate).** The Apex tree is a scaled-up inner tree: the Apex's
core at the centre, six aspect sectors radiating out as clusters, notables and
keystones on the authored spots, long bridges between sectors — the PoE winks
`lore.md` sketched (filler `+10 to an Attribute of your choosing` nodes;
Notable-style named nodes, "Iron Fortress," "Whispers of Doom"; Keystone-style
nodes that change a rule for their owner; Jewel sockets that accept a modifier
seed affecting nodes within N hops; the dark/gold/amber palette). No Tethers.

**Entry (candidates).** The owner: *"entering a core's inner tree from
apparently one of the nodes in there"*.

| candidate | fantasy | loop effect |
|---|---|---|
| **Rim entry** — a fixed outer node, grind inward | the long march to God | the whole level is approach; the thick band is between you and the centre |
| **Sector entry** — the entry is in the sector the player's dominant aspect matches | the tree recognises you | the opening is in friendly terrain; a run's build choices pick the route in |
| **Random rim node per run** | the static tree, a rolled door | replays differ without breaking the "never rerolls" tell |

**The Ophanim band (candidate reconciliation).** `lore.md` → *The Final
Ascent* draws the Apex as a thick ring encircling the field; this level puts
it at the centre. Both hold if **the band is the Apex's own bought cells** —
its constellation is its spent inner tree, a dense multi-row ring of claimed
T1/T2/keystone cells around the inert centre, seen from the rim as the wall
you grind. The thickness is how much of its tree it holds.

## 5. The Apex as an inner-tree entity

The owner's line is that a boss *"would be a real inner tree"*. Read
literally, the Apex's state on its own level is its ring state:

- **Its core** sits on the centre and cannot move (*"core cant move"*,
  #1669) — the one entity on the board that fights from a pinned core.
- **Its constellation** is the cells it holds. Damaging them is the
  arc-by-arc grind.
- **Its character** is its keystones — a bespoke set per boss / CoreClass, the
  swap #1651 leaves room for. A keystone is a rule change, so a boss's unique
  ability is authored where the player's class keystones will be.
- **Its subtype** is which aspect sectors it holds (owner: *"expressed by what
  Aspects the sections they hold"*) — a Rot Apex holds Poison/Explosive deep,
  a Hexer holds Curse/Hex (*stale pairing: see the `aspect_matrix.md` INT row, "Curse, Hex"*); correlated with its CoreClass or not.

**How its ring is filled (candidates).**

| candidate | gives | costs |
|---|---|---|
| **Authored per boss** — the spent set is part of the boss def | full control of each boss's character | one authored set per boss; no variety per run |
| **#1651's AI spender, run ahead** — give the Apex N points and let the deterministic buyer spend | free variety from one rule; sync needs only the spent set | the character is whatever the rule picks |
| **Mix** — authored keystones, sectors bought by rule from an authored aspect bias | character from keystones, subtype from bias, little authoring | two sources of truth to tune |

**Does it keep buying?** Candidate: the Apex earns ring points during the
fight (or as cells are lost), so a slow fight hardens it — a clock. Candidate:
static, so the fight is a pure grind against a fixed wall.

**Bosses below the Apex (candidate).** The same model fits level guardians:
a guardian's sectors are its subtype and its keystones its trick, on an
ordinary field. The guardian-form progression (`lore.md` → *The level's
boss*) then escalates in *how much tree* a guardian holds, not only its
topology — and teaches the sector vocabulary before the Apex uses it.

## 6. Scaling

The owner lists boss damage scaling as free: the ring is points, so scaling is
how many points the Apex has spent. Candidate knobs, any of which fit
`lore.md` → *Every run ends here* (a tougher Apex per run, by meta-progression
and/or a heat modifier):

- **Points spent** — deeper sectors, more keystones; scales offense *and*
  wall thickness together.
- **Base stats** on the Apex's core (the existing "everything gets stronger as
  it owns more" lever).
- **Heat opens sectors** — each heat tier pre-buys one more sector; a high-heat
  Apex holds aspects opposed to the player's.

## 7. The exit and the reward

The kill boots the player to the metagame and commits the run's pending
meta-allocation (`metagame.md` → *Commit-on-completion*). The owner adds a
reward *"related to the boss you killed and or extended by reward that was put
on the level beforehand"*. Candidates, each with what it does to the loop:

| candidate | fantasy | loop effect |
|---|---|---|
| **The boss's keystone as a meta unlock** | you took its trick | unlocks feed the meta tree's `unlocks <X>` clause; boss variety becomes a collection |
| **Its CoreClass unlocked** (the hub's class room) | you can be what you killed | ties boss roster to class roster; one more reason to vary bosses |
| **A fragment of its core** — a starting modifier next run | `lore.md`'s "the Apex's core fuses with yours" | meta stat carry; risks stacking with `metagame.md` Q4 |
| **The level's posted reward only** — the reward shown before the dive | you chose the stakes | the meta tree already does this; the boss adds nothing of its own |

## 8. Open questions

1. **Whose core (Q-whose).** Is the Apex's core a node on the penultimate
   field — visible, perhaps its guardian's — so the penultimate level
   telegraphs the final one? Or does the Breakout pick a core the player
   never saw? The first makes the dive a choice-shaped beat; the second keeps
   it a shock.
2. **Q-carry: where does the penultimate compression land** with no starter
   node — on the entry node, on the player's core register, or skipped (the
   dive *is* the reward)?
3. **Q-reuse: one scene or two.** Is the Apex tree a larger `aspect_ring.tscn`
   (same cells, more of them, the player's ring as its literal inner band —
   strongest foreshadowing, `nesting_cosmology.md` Q1) or a separate authored
   Graph sharing only the shape rules?
4. **Player core mobility.** The ring's centre is pinned (#1669); is the
   player's core normal inside someone else's tree, or also constrained?
5. **Does the player's own ring work here?** Buying cells in your ring while
   standing in the Apex's — candidate: yes, unchanged; candidate: the two
   trees interact (taking an Apex cell of an aspect you hold grants more).
6. **Can the player claim Apex cells?** Allocating a held cell after
   damaging it is the normal board verb; whether that also takes its *grant*
   (a stolen keystone mid-fight) is a big fantasy and a balance risk.
7. **Ring state: authored, AI-spent, or mix** (§5), and whether it keeps
   buying during the fight.
8. **Reward shape** (§7) and how it squares with `metagame.md` Q4 (meta vs
   in-run stat scaling).
9. **Same tree every run?** The "never rerolls" tell says yes; replay variety
   says the bosses rotate. Candidate: one tree, a rotating boss at its centre
   (keystones and held sectors change, the shape does not).
10. **The Apex vs the metagame Breakout** — same summit or two tops — stays
    `lore.md` Q9 / `metagame.md` Q8; not resolved here.
