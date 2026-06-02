# Metagame & Meta-Progression — Skill Tree of Life
*Working doc · v0.1.0 · New document.*
*Scope: the hub between runs, the meta skill tree, the run-as-allocation economy, permanent progression and unlocks, class selection, and the metagame as the outermost — and ultimately escapable — vertex of the fractal. Cross-refs: `lore_v0_4_0.md` (narrative framing, the Fairy, Graph Theology), `combat_system_design` (in-run mechanics), `core_classes` (what the unlocks unlock).*

---

## What the Metagame Is

The metagame is **not a second game.** It is a hub — the between-runs space in the lineage of Enter the Gungeon's Breach, Hades' House, the FTL hangar. A small place you return to, configure from, and leave. Gazillions of roguelikes have one. Ours has a twist: the hub is also a cell, and the only door out is *down* — into a run.

Two things live in the metagame, and they are different:

1. **The hub** — a navigable physical space (a house, a garden, a basement; TBD). Rooms and features that unlock gradually. This is where you *configure* the next dive.
2. **The meta skill tree** — the progression spine. Allocating a node here is how you start a run, and completing that run is how the allocation commits. This is where permanent power and unlocks come from.

The hub is the room. The meta skill tree is the menu on the wall of that room. They are introduced together but they do separate jobs.

---

## The Hub

### A locked space

The player can walk around and do things, but the space is bounded and there is, pointedly, **nothing to progress toward inside it.** The design justifies this the way every hub does — locked doors, a crate too heavy to move, a corridor that "isn't ready yet." The intended feeling in Act 0 is mundane: *this is just the menu screen of a normal RPG, lightly dressed up.* The player should not yet suspect the room is a cell.

### Rooms unlock gradually

Classic hub expansion. Meta-progression opens new rooms and features over many runs — a forge, a wardrobe, a map table, whatever the fiction wants — each a small function that tweaks how runs behave. Almost nothing in the hub is *gameplay*; it is configuration with a face on it.

### Gated by meta-stats (diegetic gating)

Hub exploration is gated behind meta-progression in physical terms, not menu terms. The canonical example: **a crate blocks a door, and you need 20 STR to push it.** Reaching 20 STR means clearing far enough up the meta skill tree to have banked that much permanent Strength. The gate is real, it is legible, and it ties hub expansion to the only activity available — diving and surviving. You unlock the building by getting stronger in the only place strength is earned: inside.

### Class selection as a room

Choosing the core class an entity enters a run with is a hub feature, not a menu dropdown. The working physicalization: **a helmet you put on before you allocate.** You don't *select* the Bulwark; you don't pick from a list — you walk to the rack and wear the head you'll be wearing in the world. Meta-tree nodes unlock the available heads; the hub is where you equip one. (Direction open: helmet, mask, mantle, or some other worn artifact — pick whatever best fits the final art.)

### "Does the outside even exist?"

The player will inevitably wonder, during run 1, what is happening *out here* in the metagame while they are *in there*. We answer by refusing to answer, and by messing with them: you dive as a level-1 nobody clutching a stick, and you come back wearing dragon-warrior plate. Time seems to have passed. Events seem to have happened. There is no outside-gameplay behind any of it — it is pure uncanny fluff, deliberately unexplained, seeding the game's central *what is even real* unease without spending a word on exposition.

### The hub is itself a vertex

The quiet horror, planted early and paid off late: **the hub has Tethers too.** They are in plain view, disguised — a doorframe, a light fixture, the seams of the room — the same way Act 0's tree-shudder was in plain view and dismissible. The metagame is not the safe outer frame the player assumes. It is simply the outermost *known* vertex of the fractal, and like every vertex, it is bounded by edges that anchor it to something above. See **The Way Out**, below.

---

## The Meta Skill Tree

### Allocation is the dive

The defining mechanic: **allocating a node on the meta skill tree is what crashes you into a run.** You reach for a skill point, you place it — and the world breaks (Act 1 → Act 2). The node you tried to allocate *is* the run you fall into.

### Commit-on-completion

The allocation does not finish when you place it. It finishes when you **survive everything inside it.**

- Place the point → crash → run begins.
- Complete the run (the final Breakout) → you surface back in the hub → the allocation **commits.** Its modifier is now permanently yours; the node is "cleared."
- **Die in the run → the allocation does not commit.** The node stays pending. The fractal is permanent; your attempt was not. Try the dive again.

This is the same compression logic as an in-run Breakout, one layer up: a completed run bakes its essence into your persistent self, exactly as a cleared level bakes into your next starting node. The metagame is the fractal's top floor playing by the fractal's own rules.

### The intro sequence (scripted)

The opening is authored, not yet governed by the steady-state economy. The Fairy railroads you through spending your first points (this is the tutorial, and it is also how you are led to the slaughter — see `lore_v0_4_0.md`):

| # | Node shows | On allocation |
|---|---|---|
| 1 | `+10 STR` | allocates fine |
| 2 | `+10 DEX` | allocates fine |
| 3 | `+10 INT` | allocates fine |
| 4 | (e.g. `+1 armor`) | **crashes — Run 1 begins** |

Nodes 1–3 set up your basic attributes and teach the click. They are tutorial freebies. The fourth is the fatal one. **The first three already count:** you enter Run 1 with 10 STR, 10 DEX, and 10 INT live as starting modifiers on your core, because you allocated them and allocations bless the core. Basic attribute kit: done, and done by *you*, via a skill tree. (See `combat_system_design` for why base-10 attributes are the anchor scale.)

### The steady-state economy

After the intro, the rule is clean:

> **Allocatable meta points = runs completed + 1.**

The `+1` is always the **pending dive** — the one uncommitted node waiting to crash you into your next run. Every other allocated node is a *cleared* node, earned by a survived run.

Worked example, with the tree drawn linear-then-branching for clarity:

```
1. +10 STR
2. +10 DEX
3. +10 INT
4. +1 armor                    ← crashes; commits on clearing Run 1
   ├─ 5. +10 STR | unlocks <ClassA> Core
   ├─ 6. +10 INT | unlocks <ClassB> Core
   └─ 7. +10 DEX | unlocks <feature>
```

- After Run 1 clears, node 4's `+1 armor` takes effect on every subsequent run start.
- Node 5 is now reachable. Allocate it → crash → Run 2. Clearing Run 2 commits `+10 STR` **and** unlocks ClassA's core for use in the hub's helmet rack.
- And so on. Each branch node is one run's worth of progression, gated behind actually living through that run.

### Re-allocation: tweaking your meta build

Once nodes are cleared, the player should be able to **deallocate and re-spend** on the meta tree to tune their permanent loadout — the Path-of-Exile refund, applied to the meta layer. Cleared points are flexible; you are not locked into the first build you stumbled into.

Two real questions this opens (see Open Questions):
- **Does deallocating an unlock node (5–7) re-lock its unlock?** A node that reads `+10 STR | unlocks ClassA` — if you pull the point, do you lose access to ClassA? (Yes / no / the stat refunds but the unlock is permanent once earned — leaning toward the last, so unlocks are *milestones* and stats are *fluid*.)
- **Does re-allocating a cleared node re-trigger its run?** Probably not — clearing it once paid the toll, and re-spending should be instant. But there's a darker option where every placement, even a re-placement, drops you back in. Flag, don't lock.

---

## Meta-Progression Content

What meta nodes actually grant, two kinds, often on the same node:

- **Permanent stat carry (the rogueli*te* part).** `+10 STR`, `+1 armor`, `+2 core health`, etc., applied to the core at the start of every run. Yes, this makes the game a rogueli*te* rather than a pure roguelike. That's fine and intended — the metagame is where the run-over-run growth lives, and the growth is *blessed*: every point is one you chose, on a skill tree, the way you've been choosing them since the title screen.
- **Unlocks.** Core classes, hub rooms/features, possibly field themes or in-run options. Expressed as a second clause on a node: `+10 STR | unlocks <X>`.

Source of stat values: in part hand-authored, in part **compressed run-essence** — a cleared run can fold a fragment of what it was into the meta node it completed, the same way an in-run level folds into your starting node at Breakout. This keeps us from having to hand-design an endless ladder of `+N` perks; the runs themselves seed some of the ceiling.

### Magnitude and scale

Meta stat grants live at the same base-10 scale as everything else (see `combat_system_design`). `+10` to an attribute is a *full baseline's worth* — strong, legible, and deliberately large at this scale so a meta upgrade feels like an upgrade. How meta-granted stats scale against in-run-granted stats (do they stack flat? is there diminishing return so meta-carry doesn't trivialize early runs?) is open and tied to the broader stat-scaling question (linear vs. steeper).

---

## Mask-Off — Recommended Resolution

The metagame tree masquerades, in Act 0, as a perfectly ordinary RPG skill tree. The "mask off" is when the player learns it never was one. Recommended handling, balancing drama against honesty:

- **Keep the early nodes' faces intact.** `+10 STR` stays `+10 STR`, stays permanent, stays blessed. We do **not** retroactively lie about the player's innocent first choices — the horror was always *beneath* the tree, not *in* what the player picked. The naive early acts were real and remain real.
- **Stage the reveal on the deeper tree.** After Run 1, fog lifts on nodes that were always there but unreachable, and the early nodes quietly grow a second line (`+10 STR | …unlocks ———`). The mask comes off the tree *as a whole* — the worlds were always under there — without betraying the first skill point.

This re-lands the Act 0 → Act 2 rug-pull one layer up, and it means the player's first instinct (*these are just stat boosts, right?*) was true at face value and catastrophically incomplete underneath. Both at once.

(Minor: even within the intro, node 4 revealing different mods than it first showed is a small, fair surprise — nobody takes offense at a hub node turning out to do a bit more than its tooltip teased.)

---

## The Way Out — the Metagame as Prison

The Fairy cursed the player to **infinite regression** (see `lore_v0_4_0.md`). The metagame is what that curse looks like from the inside: a cozy little hub you return to between runs, that you cannot leave except by diving into another run, forever. The comfort is the cage. Always another point to allocate, always another world to fall into, always another floor below this one.

But the fractal has a top, and a top has Tethers. The hub's disguised Tethers are the seams of the prison. The far end of the meta skill tree holds the unlock that lets the player **attempt a Breakout of the metagame itself** — sever the hub's own edges, the ultimate act of severance, the heresy to end all heresies in a universe that worships connection. This is the *complete* breakout: not climbing one more level inside the cell, but cutting the cell loose from whatever contains *it*.

It is exactly the thing the Fairy both needs (it is trapped in here too) and dreads (it is the act that proves you are what it judged you to be). Escaping the metagame and being the antichrist are, in the end, the same motion.

What's actually on the far side is unwritten — see `lore_v0_4_0.md`'s Final Ascent and the open questions there.

---

## Open Questions

1. **Intro bootstrap.** Exactly how many scripted free points before the fatal allocation (3 attribute nodes is the current sketch). Does the count teach everything it needs to?
2. **Un-unlock on deallocation.** Pulling a point from an `unlocks <X>` node — does X re-lock? Leaning: stat refunds, unlock stays earned. Confirm.
3. **Re-allocation re-trigger.** Does re-spending a cleared node re-run it? Leaning: no, instant. Hold the darker "always re-dive" option in reserve.
4. **Meta vs. in-run stat scaling.** Do meta-carried stats stack flat with in-run gains? Any diminishing return so meta-carry doesn't trivialize early levels of a later run? Tied to the global linear/steeper scaling question in `combat_system_design`.
5. **Run-essence compression.** What, concretely, does a cleared run fold into its meta node beyond authored values? How much of the meta ceiling is hand-built vs. earned?
6. **The hub's physical identity.** House / garden / basement / something stranger. Drives the disguised-Tether art.
7. **The worn artifact for class selection.** Helmet, mask, mantle, other.
8. **The metagame Breakout.** What the final unlock actually does, what's on the far side of the hub's Tethers, and how this reconciles with the Apex Entity / Final Ascent (the in-run god-fight) — are these the same summit reached two ways, or two different tops?
9. **The Fairy's presence across runs.** Does it ride along every run, wait in the hub and narrate from "outside," or change behavior as the betrayal approaches? See `lore_v0_4_0.md`.
