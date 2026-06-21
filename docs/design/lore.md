# Skill Tree of Life — Lore & Narrative Design

---

## Logline

A hero fights their way through a classic adventure, levels up, spends skill points — and slowly realizes the skill tree is not a UI. It's a place. And they're trapped in it. Or rather: they've always lived there, and they're only now beginning to understand what that means.

---

## Act 0 — The Game You Think You're Playing

The player boots into what looks like a straightforward 2D action-adventure. Top-down or side-scrolling, Zelda-ish in feel. A world with enemies, a sword, a reason to fight.

- Pick up a sword. Swing it. Enemies die.
- Kill enough enemies → gain XP → level up → receive a **Skill Point**.
- A companion — a small fairy-like guide — chirps that you should *open the skill tree* and *spend it.*
- The player opens a panel. A skill tree. They click a node. A modifier applies. Stats go up.
- **The tree shudders slightly.** A single frame of wrongness. Easy to dismiss.

*This is just a game. This is normal.*

### The things you kill

The enemies of Act 0 are not menacing. They are **small, harmless, cute** — round, blinking, faintly pitiable creatures (working direction; deliberately *not* the usual slimes/goblins that read as fair game). You kill them anyway, because the game tells you to, because they give XP, because that is what the genre has always asked of you. From a Goomba's point of view, Mario is a mouth-foaming genocidal maniac. We lean into that. The player is doing exactly what every RPG protagonist does — leaving a continent of corpses behind them to make a number go up — and for the first time, something is *watching them do it and keeping count.*

The Fairy notices. The Fairy is not okay with it. (See **The Fairy.**)

### The intro beat sheet

The abstract framing above resolves into a concrete opening sequence — a small herding ritual disguised as a tutorial. The player should feel like they are playing a perfectly ordinary fetch-quest opening; every beat is doing double duty.

**Setup — the Evil Overlord.** The Fairy frames the world for the player: somewhere out there is the **Evil Overlord**, and the player has been sent into "the world" to grow stronger and one day face him. The Overlord is never seen, never described in detail, never given a face. He is a pure narrative MacGuffin — the fake antagonist that justifies every kill the player is about to make. The real antagonist is the companion telling you about him, and that fake-out is the whole point of giving him top billing.

**First fetch quest — gather plants.** The Fairy points the player to a **nearby forest**: gather plants, bring them back. Each plant is worth **1 XP**. The quest asks for roughly **10 plants** — just enough to ding the first level and earn the first skill point. The plants are the in-fiction stand-in for **Gold nodes** (the new XP-economic lifeblood, see the RGBW roster expansion note): a slow, peaceful, gathering economy. This first level-up should feel earned, calm, and entirely innocent.

**The boulder — a visible STR gate.** Somewhere on the early path is a **boulder blocking the way**, with a prompt that the player needs more **Strength** to push it aside. This is the perfect ludonarrative lever: at the exact moment the player is being asked to spend their first skill points, the world hands them a concrete reason to want more STR. Intrinsic motivation aligned with the trap. The boulder doesn't move yet. The player banks the goal: *more STR, somehow.*

**The squirrel — a taste of real XP.** During more fetch questing, a **cutesie squirrel** crosses the player's path. The game lets — invites — the player to slay it. Reward: **+20 XP** (or some ratio absurdly favorable to picking leaves). The first kill in the game, and it pays roughly twenty times what bending down for a leaf pays. The genre's open secret has just been confirmed: *living things are worth more than gathered things.* This is the Apex Heresy of the cosmos in miniature, taught to the player in the first hour as if it were a tutorial about efficient grinding.

**The Fairy protests. The player ignores.** From the squirrel onward, every kill draws a Fairy reaction — disappointed, then upset, then visibly hurt. The player ignores it. (The Fairy is *also* the only voice telling them where to go next, so brushing it off is easy.) Through this stretch, the world's affordances quietly funnel the player into a binary: **gather more leaves (slow) or hunt more innocent creatures (fast).** Both paths exist. Both work. Only one is being whispered against. The Fairy escalates each time the player chooses the fast one.

**The clearing — the engineered temptation.** The final test moment: the player needs roughly **500 more XP** to land the last STR point that would let them push the boulder. They round a corner into a sun-dappled **clearing of two dozen ultra-cute animals**, packed together, idle, ripe for the reaping. The math is rigged — finding 500 more plants would be a real grind; the clearing is two dozen one-swing kills. *The clearing was placed there.* In retrospect, the Fairy walked the player to it; the whole intro was a herding ritual. In the moment, it just looks like good fortune.

There are two outcomes the design needs to accept:
- The player **resists** and goes hunting for 500 leaves the slow way. The Fairy is touched. The trap still springs eventually — the curse is on the whole metagame tree (see The Fairy → *The crash is the Fairy's doing*), not contingent on this one swing — but the lore-canonical first run is the one where the player gives in. We design for the canonical path; the resistant path is a quiet branch that ends the same way, slightly later.
- The player **swings**, claims fucktons of XP in one minute of play, and walks out of the clearing carrying the skill point that buys the last STR.

**The curse, mid-syllable.** That clearing-fueled allocation **does it** for the Fairy. The companion finally snaps — *"AAH FUUUCK"* — which reads in the moment as the only profanity it has ever used, a small character break, almost endearing. (Optional: a single subliminal frame in the speech bubble where the glyphs aren't Latin.) It is, of course, **literally the curse being cast** — the player is parsing English; the Fairy is speaking Old Tongue, and *fuuuck* is the verb. As the player commits the allocation — the one bought with two dozen lives — the casting completes. The screen breaks.

This is the **fatal allocation** referenced in Act 1: not an arbitrary fourth click, but the one purchased with mass murder, on the skill point the Fairy walked the player into earning. The crime and the sentence land in the same frame.

---

## Act 1 — Something is Off

The player keeps playing through the early fetch loop. More plants, more squirrels, more skill points. The Fairy keeps insisting they open the tree and allocate. They do.

**The tree resists.** Not dramatically — a visual stutter, a sound that doesn't quite belong, a moment where the camera feels like it hiccupped. The kind of thing you'd chalk up to a bug and post on the game's Discord. Each kill-fueled allocation hiccups a little harder than each plant-fueled one, though the player is unlikely to notice the correlation on a first pass.

Then the clearing happens (see *The intro beat sheet*). The Fairy snaps *"AAH FUUUCK"*, the player allocates the skill point bought with two dozen lives, and the game **breaks**. Hard. Visually catastrophic — the kind of "crash" that looks deliberate in retrospect but feels real in the moment. Screen artifacts, audio distortion, a freeze.

Then: a reboot sequence. Loading bars. The game "comes back."

---

## Act 2 — Inside

The skill tree panel opens.

Except it doesn't close.

The player is no longer *looking at* the skill tree. They are *in* it. The nodes are structures. The edges between them are traversable paths. What was a UI overlay is now the world.

The entity's Core rests at their starting node — the one they've been inhabiting since the game began, the "Starter Skill." They can see the nodes they've allocated glowing with their color. The unallocated nodes are dark, cold, distant.

There is no "Close Panel" button. There is no menu. There is no going back to the adventure game.

*This is the game.*

---

## The Fairy

Act 0 has a companion in the lineage of Navi and Fi: a small fairy-like guide who helps you, talks at you, gets in your way, and is always, exhaustingly there. It is endearing and it is wrong.

### Uncanny, on the same dial as the tree-shudder

The Fairy reads as a normal helper companion that is *subliminally* off. A childlike appearance that is somehow also too old. A voice that doesn't quite sync to the face. An earnestness that tries a little too hard to be trusted; a warmth that doesn't fully reach the eyes. Crucially, the uncanniness sits on the **same dial as the tree-shudder** — noticeable in retrospect, dismissible in the moment. Act 0 must stay genuinely normal (see Tone Notes), so the Fairy is a companion players *feel* something faintly wrong about and then shrug off. Its clumsiness is real and important: it is too clumsy to be a god, which is exactly why no one suspects what it serves.

### The judgment

The Fairy is born to love and to be loved — but it serves the universe's biggest edge lord of all (see **Graph Theology**), and love in that service comes barbed. Watching the player cut down harmless creature after harmless creature for XP, the Fairy has a moment of clarity and **decides not to support the hero it was sent to support.** It tallies the kills — the cute things, all of them — and, projecting forward along the only trajectory an RPG protagonist ever has, everything up to and including God Himself — and concludes the player is not the hero. The player is the **antichrist**: an engine of severance wearing a hero's sprite.

The punishment is likely already underway rather than pre-emptive. We are not running Minority Report on the player — they have *already done the deeds.* The continent of corpses is real. If anything, the curse fits a spirit already doomed; the crime and the sentence may not arrive in a clean order, and we leave that ambiguous (see Open Questions).

### The crash is the Fairy's doing

The Fairy single-handedly caused the skill-tree crash — it is the agent behind Act 1's break — and the means of punishment is **infinite regression:** lock the antichrist inside the fractal, falling forever, every escape only a deeper floor. The railroading of Act 0 (*spend your point! open the tree! just one more!*) was the Fairy walking the player to the trap, including the fatal allocation that triggers the crash. We sell it as a tutorial lesson and as *just how the Fairy is* — ✨helpful like that✨ — and the player is meant to carry a real grudge once they understand. The Fairy pushed the button.

**The curse is on the whole meta tree, not just one node.** The Fairy didn't curse a single allocation — it cursed the player's entire metagame skill tree. *Every uncleared node is a fresh trap:* reaching for any of them crashes you into a run, and the curse only lifts from a node once you survive what's inside it. This is the in-fiction reason a second run (and a third, and a fourth) exists at all — the curse is still there, waiting on every node you haven't cleared yet. The fourth node was simply the *first* trap to spring because it was the first one the Fairy steered you to allocate. Clearing the whole tree is clearing the whole curse — which is also what eventually lets you reach the metagame Breakout (see `metagame.md`, The Way Out).

### The Fairy and the Tethers

Does the Fairy comment on the Tethers — approve or recoil when you destroy them? It *should*, and the tension is rich either way: as a servant of the Lord of Edge, watching you sever sacred bonds should appall it — yet each Breakout is also a step toward the escape it secretly needs. So its commentary on Tether-cutting is split against itself: theological horror laced with reluctant complicity. Whether the player can *read* that contradiction early (a tell for the late betrayal) is a writing decision. **Does it even understand its own curse?** Open — and a good lever. A Fairy that fully grasps the regression it spun is a calculating jailer; a Fairy that only half-understands the mechanism it invoked (and is as surprised as you are by the rules of the prison it's now stuck in) is more tragic, more clumsy, and more *itself.* Leaning toward the latter, unresolved (see Open Questions).

### Caught in its own curse

The Fairy is too clumsy by half: in cursing the player to the regression, it **trapped itself inside with them.** This is why it keeps helping — its escape is bound to yours. It needs you to break out *completely* (see `metagame.md`, The Way Out), which is also the one act that proves its judgment of you correct. Helping you and being right about you are the same motion, and it hates that.

### Herald, not god

The Fairy is a **herald and servant of the Lord of Edge — not the Lord Himself.** This keeps the Apex Entity's identity ambiguous (the god you climb toward may or may not be the Fairy's master) and keeps the Fairy fallible: it makes mistakes, it gets caught, it is in over its head.

### The betrayal(s)

The Fairy's **first and largest betrayal is already on the table:** it cursed you — crashed you into infinite regression — under the cover of being your helpful guide. Everything since has been a being that damned you still chirping encouragement in your ear. That alone is a complete betrayal arc, and it lands when the player understands what the crash *was* and who caused it.

**Is there a second betrayal?** Open question, and we should decide deliberately rather than pile on twists for their own sake. Options on the table:
- *No second twist.* The reveal that the cheerful companion is your jailer is enough; a second betrayal risks diluting it.
- *A reversal, not a second betrayal.* Late game, the Fairy's interests and yours fully converge (it must escape too) and it has to *come clean* and genuinely help — the "betrayal" inverts into reluctant alliance. The emotional turn is forgiveness/partnership, not a second knife.
- *A deeper twist held in reserve* (only if it earns itself): e.g. the Fairy isn't merely a herald that overreached but something closer to the Lord of Edge's instrument by design, and its "moment of clarity" was scripture, not conscience. High risk; only if it strengthens the ending rather than complicating it.

Recommendation: commit to the first betrayal as *the* betrayal, and treat the endgame turn as a **reversal into uneasy alliance** rather than a second stab.

---

## Graph Theology — the Lord of Edge

This universe is, literally and at every scale, a graph. So its religion is **graph theology** — graph *theory* with a single substitution, `r → log`, and not by accident: in a world that *is* a graph, the mathematics and the scripture are the same text. Graph theology is canon, and it is played dead straight. No winking.

### Connection is divine

Its central tenet: **without edge we are but isolated vertices; edge unites us all.** That which *connects* is holy. The Lord of Edge — the unseen god of this graph — is the principle of connection itself, and the cosmos He presides over is held together by edges that are, in the most literal sense, sacred bonds.

It follows that **severance is heresy.** Cutting an edge is a sin against the Lord of Edge. And the player's entire mode of progress is severance: every Breakout severs all of a level's Tethers (and a Tether is an edge — see The Field), so **ascension is serial edge-genocide.** You climb by cutting yourself free, over and over. The player is a heretic by the very act of progressing. This is why the Fairy's "antichrist" verdict is not hyperbole — in this theology, the player is precisely an anti-divine force: an unmaker of edges in a cosmos that worships them.

### "All edge, no point"

The faithful's condemnation of severance-for-its-own-sake — edgy behavior with nothing to anchor it — is **"all edge, no point."** It lands as a triple: an edge with no endpoints is a degenerate, meaningless object (no vertices = nothing); *point* is the vertex; and *point* is purpose. It is what graph theology says about anyone who only cuts and never connects, and it is a standing warning to the kind of entity that fights *with* edges (see the Edgelord, `core_classes`): sever without anchoring and you are nothing the universe values.

This doctrine has a literal in-game embodiment: the **`coolness`** attribute (a rare, procgen-sprinkled color carrying *no mechanical effect whatsoever* — pure style, tallied only at the end credits). It is the purest "all edge, no point" — flair with nothing structural beneath it. Winning a run on a coolness-maxed build is therefore the **cardinal aesthetic heresy**, the most flamboyant possible way to be all edge and no point — and the Fairy, herald of the biggest edgelord alive, should have *opinions* about a champion who conquered the cosmos on style alone. (Roughly the joke-CHA of the attribute set.)

### The Ophanim

The Lord of Edge's angelic order takes the form of **rings.** A ring (a cycle) is the purest expression of connection — redundant, 2-edge-connected, no loose ends, no single seam to cut. Biblical angels were sometimes drawn as wheels within wheels: the **Ophanim.** A ring is also, in graph terms, genuinely hard to dismantle — *OP*. We are putting the OP in **OP**hanim, and we mean it. The Ophanim are the divine made structural: connection so total it cannot be severed.

The Apex Entity's signature form is an Ophanim ring (see The Final Ascent). Whether the Apex *is* the Lord of Edge or merely His greatest angel is left ambiguous.

### Self-loops — connection with no other

A **self-loop** is an edge connecting a vertex to itself. It is the graph theology's most quietly troubling object.

An ordinary edge unites *two* distinct things — that distinctness is why connection is holy. The Lord of Edge's love is relational, outward. A self-loop has the form of connection but only one endpoint; it is a vertex that turned entirely inward, became its own neighbor, achieved total self-reference. Whether this is sacred or damned is genuinely contested within graph theology:

**The traditionalists** read self-loops as a category of heresy adjacent to severance — not *cutting* connection but *refusing* it. A vertex with only a self-loop has technically retained its edge while abandoning every other vertex. "All edge, no point" was coined for cutters, but some theologians extend it here: the self-looped vertex has a point (itself), but an edge that serves no other. Connection that connects nothing is not connection; it is a posture. The Lord of Edge, they argue, did not intend edges as self-flattery.

**The contemplatives** hold the opposite view sharply. A self-loop is *perfect self-knowledge* — a vertex that has become its own neighbor, that contains itself as a relationship. In certain strands of graph mysticism, the fully self-knowing vertex is *nearer* to the divine than any ordinary hub, because it has internalized the very principle of edge. The Lord of Edge is the principle of connection; a vertex that connects to itself has, in some sense, become that principle locally. A small god of one.

The Lord of Edge's official position, if He has one, is not on record. Self-loops appear to predate any entity in the field. The cosmos made them; perhaps the Lord does not always explain Himself. Or perhaps He does not know what to make of them either.

**Mechanically, self-loops are rare.** They arise in the field as anomalies — scars, relics, perhaps sites of ancient compression or forgotten entities that fed on themselves. Finding one means finding something that graph theology cannot agree is good or bad. A node that has become its own neighbor is: a glass-cannon wizard station, a resonance chamber for incoming spells, and an object the faithful will argue about for as long as anything believes. See Self-Loops section for full mechanics.

---

## The Field — How a Level is Structured

Each level of the game takes place on a **bounded circular field** of nodes. The boundary is visible — not as an invisible wall, but as a distinct outer ring. The field is finite. You can see its edge.

Built into the boundary at roughly even intervals are **1 to 4 Structures** — inward protrusions, distinct in appearance from ordinary nodes. Working name: the **Tethers** (alt: *Conduits*). At first the player has no idea what they are. They look like indents pushed inward from outside the wall, like something is bolted or moored *through* the boundary — bridges, cabling, anchored cords disappearing into a place you can't see. They are not immediately reachable from the starting position. Reaching them requires expanding across the field, fighting for territory, building toward the edge.

The Tethers can be attacked. They can be destroyed. Destroying all of them triggers the **Breakout.**

### What the Tethers actually are (the quiet reveal)

The player is meant to *wonder* about the Tethers before the truth lands at Breakout: **a Tether is an edge** — one of the connections that joins the entire field, considered as a single skill node, to its neighbors *one level up*. You are a ball inside a graph vertex. The edges leaving that vertex have to terminate *somewhere* on your inner sky — and a Tether is where one is fastened in. The "protrusion" is the anchor; the cord runs out through the wall to a neighbor you cannot see from in here.

This gives the boundary structure an exact meaning rather than a decorative one, and it sets up a clean numeric foreshadow:

**Tether count = this vertex's degree, one level up.** A 1-Tether level is a leaf node in the parent graph; a 4-Tether level is a well-connected hub. So the number of Tethers can quietly telegraph difficulty and the shape of what's above: more connections, more that depends on you, a harder level. (Exact terminology — Tether / Conduit / something else — and the precise visual of an "edge seen from inside a vertex" still want a dedicated art pass.)

### The level's boss — a Tether's defensive reaction

There is **no boss on the field at the start.** The boss is *triggered.*

When the player first **damages a Tether**, the Tether reacts defensively: an allocation animation fires, a mass of nodes is claimed around the boundary, and a guardian entity resolves into being — *there's* the boss. Mechanically this needs no special boss system: a boss is simply an entity that has allocated a *lot* (everything gets stronger as it owns more nodes), so the "spawn" is just a sudden, large allocation.

Narratively, graph theology now gives this teeth. Damaging a Tether is the first cut of an edge — the opening move of heresy. The guardian is **the Lord of Edge's immune response:** the cosmos defending its own sacred seams against an unmaker. Poke the bond that holds the world together and you wake what guards it.

**Guardian-form progression.** Early guardians are deliberately *not* rings — irregular, single-node-thick, easy to dismantle topologically — so new players meet a power-check, not a topology puzzle. As the player climbs, guardians escalate toward the ring: the first **Ophanim** the player faces is a relatively doable **single-thick ring** (one node thick — a closed cycle, so it demands two cuts rather than one, the first taste of "you can't just snipe a cut vertex here"). The thick, multi-row Ophanim is reserved for the very top — the Apex itself (see The Final Ascent). So the boss bestiary runs: irregular thin guardians → single-thick Ophanim → multi-thick Apex Ophanim, teaching ring-topology counterplay by degrees.

### The Breakout

The level does not end the instant the last Tether falls. **The Breakout condition is: all Tethers destroyed AND the level's guardian boss defeated.** (The boss is triggered the moment you first damage a Tether — see above — so by the time the last Tether is gone you are usually mid-fight with the guardian anyway. Both must be done.)

When both conditions are met, a short **grace period** of `X` turns begins (working value TBD). During grace:
- No XP is gained (the level is effectively over; this isn't bonus farming time).
- The player can make **final adjustments to their constellation shape** before the compression locks in.

The grace exists because stat carry-forward is computed from **the nodes you own at Breakout time**, and a player who just finished clawing through a boss and breaking Tethers is often left in a contorted, suboptimal shape. Grace lets them tidy up — reallocate into the form they actually want to compress — without being long enough to let them freely re-sculpt into any arbitrary build. Short enough to matter, not so short that the rest/loot phase starts from a bad hand. (Calibrate `X` in playtesting.)

When grace ends, the revelation fires.

The camera pulls back. The **entire field** — your constellation, all enemy constellations, the edges between every node, the wall itself — **collapses inward.** Everything compresses into a single point.

**Your entire level becomes one Skill Node.**

This is graph-literal: destroying every Tether is **severing every edge that joined your vertex to the graph above.** An isolated vertex has nowhere left to belong, so it collapses into itself — and that collapsed point is your new starting node. Clearing a level *is* cutting the node you live inside free from its parents. (And, in the eyes of the Lord of Edge, it is also the most complete heresy available short of escaping the metagame entirely.)

All internal topology dissolves in this compression — the individual nodes, the edges between them, any self-loops. What carries forward is stat and modifier; the shape of what was is lost, becoming the substance of what comes next.

The camera continues pulling back. A new field resolves around you. Larger. The node you just became is your starting node for the next level. Other nodes surround it — some familiar in structure, some stranger, some clearly belonging to entities that got here before you did.

You are bigger now. Denser. Your starting node is powerful because an entire level's worth of effort is baked into it. The surrounding nodes are correspondingly stronger. The field is wider. The Tethers are further away. The enemies are more complex.

**Level 2 begins.**

### Re-edging the new starter node (a necessary detail)

Your freshly-formed starting node arrives **with no edges** — you just spent the whole level severing the ones it had (that's what destroying Tethers *was*). A node with zero edges is an isolated vertex with nowhere to go; if the next level booted with your starter still edgeless, the game would **softlock** on turn one.

So between Breakout and the start of the next level, some edges are **restored** to your new starting node — connecting it into the new field. This is a **partly random process,** and it fits the cosmology to frame it as part of the Lord of Edge's **immune response:** the cosmos re-knitting a vertex it cannot allow to remain detached, re-binding the heretic back into the web whether they like it or not. (Invariant: at least one edge must always be restored, or the run dead-ends — never zero.) How many edges, to which neighbors, and whether the player has any influence over it are open (see Open Questions).

### What Carries Forward

When the Breakout compresses your constellation:
- Your **core absorbs a portion** of your final stats — becoming the seed of your new, more powerful entity.
- The absorbed nodes' modifiers fuse into the new starting node's inherent bonus list — visible as fixed modifiers on the node, not spendable-away.
- **Loot nodes** collected during the level may be selectively absorbed: the player picks N of them to carry forward, the rest dissolve.
- Enemy entities that were still alive when the Breakout triggered also compress, becoming neutral hostile nodes on the new field — pre-allocated to a new, stronger enemy entity.

What is lost: the shape of your constellation. The individual nodes as distinct places. The journey becomes the substrate for the destination.

---

## The Fractal — Depth Unknown

Each level is one layer of a fractal. Your starting node at level 2 *is* your level-1 field. Your starting node at level 3 *is* your level-2 field. All the way up — or down, depending on how you orient it. The Tethers make this concrete: every level you inhabit is a vertex, and its Tethers are that vertex's edges to the level above.

The intro crash didn't drop you into a skill tree. It dropped you into **a specific depth** of the fractal. You don't know which one. You don't know how deep the tree goes in the direction you came from. You don't know what's at the top.

The game never tells you your depth explicitly. But the further you climb, the more the structures around you feel ancient — like the nodes you're navigating were themselves once entire worlds, their history compressed into a single point by whoever was here before you.

**This is the central mystery:** not "what is the tree," but "how far in are you, and is there a way out?"

And there is a layer *above* the levels: the **Metagame** — the hub you return to between runs — is itself a vertex of this same fractal, with its own disguised Tethers and its own possible Breakout. The way out, if there is one, runs through there. See `metagame.md`.

---

## The Roguelike Loop

The game is structured as a roguelike with meta-progression through fractal ascension. (Because meta-progression carries permanent stats forward, it is technically a rogueli*te* — that's intended; see `metagame.md`.)

### Within a Level
- Begin at your starting node (the Breakout-compressed previous level, or a seed node on run start).
- Expand your constellation by allocating nodes, fighting enemy entities for territory.
- Collect loot, build a synergistic constellation configuration.
- Reach the Tethers at the boundary; strike one and beat the guardian it summons.
- Destroy the Tethers → trigger Breakout → carry forward what you keep.

### Between Levels (Rest State)
After Breakout but before the next level fully resolves, there is a brief **rest phase:**
- Inspect what your new starting node inherited.
- Choose which loot nodes to absorb (permanent) vs. discard.
- See what the new field looks like before fully engaging.
- Possibly: a trade — spend some of what you preserved to re-roll the new field's layout or enemy composition.

### Between Runs (the Metagame)
A *completed run* (clearing the Apex, the final in-run Breakout) surfaces the player back in the **Metagame hub**, where permanent progression lives and the next dive is configured. This is a distinct, higher layer from the per-level rest state. Full mechanics: `metagame.md`.

### Scaling
Each level is harder: wider field, more enemy entities, stronger base node stats on everything, more Tethers (up to 4), Tethers placed further from center. But the player is also compounding: their starting node is richer, their core stronger.

The risk-reward loop is positional and temporal simultaneously: **where you are on the field is also what your build is.** A strong outer position gives you access to better nodes but exposes your flanks. Retreating inward is safer but stunts growth.

### Run Failure
If your core is destroyed, the run ends. No Breakout. No carry-forward at the level layer, and — at the meta layer — the pending allocation does not commit. The fractal is permanent; your attempt is not.

Roguelikes work through the cycle of: fight to a rest area → upgrade → enter next stage → more powerful, more dangerous. This game's version of that cycle is: fight to the Tethers → Breakout → rest phase → next level. The "stage" and the "skill tree" are not separate things. They are the same thing. Fighting for territory IS building your character IS clearing the stage.

---

## Node Types — The RGBW System

Nodes on the field are color-coded by type. The four types form the core design vocabulary:

| Color | Attribute | Attack Type | Notes |
|---|---|---|---|
| **R** (Red) | Strength | Melee | Close-range. High damage, short reach. Beats Blue. |
| **G** (Green) | Dexterity | Ranged | Long-range. Euclidean targeting. Precise, lower raw damage. Beats Red. |
| **B** (Blue) | Intelligence | Graph-magic / Spells | Propagates along edges. Hop-based. Bypasses geometry. Beats Green. |
| **W** (White) | — | — | The lifeblood: XP/turn → skill-point income, plus general passive bonuses. |

**Triangle (R › B › G › R):** Brute force closes on wizards, wizards outrange archers, archers kite bruisers. Lives primarily in emergent per-color resist stats — a Red-heavy entity naturally builds resist_b through its node choices, not because the engine mandates it. See combat doc.

White nodes are the **economic lifeblood:** their XP/turn becomes skill points, the currency of all expansion and recovery. They grant no combat identity — a constellation heavy in W is resource-rich but toothless, and precisely for that reason, White nodes are the objectives entities fight over like resource patches in a strategy game.

**Mixed builds** are rewarded by the tree structure itself: high-value interior nodes often combine colors (e.g. a Red/Blue node grants STR + INT bonuses), representing natural synergy points worth fighting for.

**Topology is your loadout.** Beyond color, a node's *graph position* determines what it can do offensively and how well it defends — leaves fire ranged, hubs cast magic, dense adjacency melees. Durability now lives in a dedicated attribute (CON), not in degree. This is the spine of the combat redesign; see `combat_system.md`.

> **Roster expansion (newer intent, not yet fully back-propagated through this doc).** The RGBW four has grown to **six colors:** R/STR (melee), G/DEX (ranged), B/INT (magic) — and three rarer utility colors: **White/CON** (durability), **Gold/WIS** (XP/growth — *the new economic lifeblood*), **Purple/PER** (vision/sensing). The old "White = XP economy" role moves to **Gold**; White becomes durability. Where this doc still says "White nodes" for the economy, read **Gold**. Mechanics: `combat_system.md`. A purely cosmetic, non-mechanical **coolness** attribute also exists (see "All edge, no point"). Procgen **clusters like-colors into biome-like regions** — Red territory, Blue territory — so the battlefield reads as a map of warring colors; node color is *content* (which attribute a node carries), deliberately **not** an adjacency-coloring (the planar 4-color theorem is a red herring noted against).

---

## The Core

The **core** is the nucleus of a tree entity. It is not just a stat container — it is the entity's self, the thing that cannot be lost. It is also the answer to the foundational question *"two entities sharing one skill tree, fighting — how does that work in a way that's interesting and intuitive?"*

Mechanically:
- The core occupies exactly one node at all times. That node is called the **core node.**
- Losing the core node = death. Other nodes can be lost (damage, territory taken) and recovered (healing, reallocation). The core node cannot be freely surrendered.
- **An entity is a connected subgraph, and the core is what keeps it one thing.** When an attack kills a cut vertex and splits the constellation, the piece containing the core remains the entity; any orphaned piece becomes an island (see Islands) and dissolves immediately. The core is why a cut entity doesn't split into two new beings — there is only one nucleus.

Movement (two distinct kinds):
- **Core relocation** — the core hops along *owned* edges, from one owned node to an adjacent owned node. Each hop costs movement. The core cannot hop to an unallocated node; it cannot leave the constellation.
- **Constellation reshaping ("apparent movement")** — nodes are mostly stationary, so an entity changes its *shape* by deallocating in one place and reallocating in another, exactly like a Path of Exile player refunding passives to spend them in a new direction. The allocation frontier reaches somewhere new; the body has effectively moved without anything physically sliding. Gated by a per-turn deallocation budget.

Structurally:
- The core **radiates stats** outward. Nodes near the core (within range — by hops or euclidean radius, per the core's class) receive a bonus — a warmth gradient that falls off with distance.
- This aura is the reason the core can't simply hide. You *could* tuck your core onto a far, safe filament and become hard to kill — but then your fighting nodes get no aura and underperform. The aura is the carrot that pulls the core toward the front. Different core classes shape this differently (see Core Classes) — and that shaping is most of where class identity lives.
- The core is a **component** that can be upgraded. Core class parameters include: aura range, aura falloff curve, base health bonus to the core node, deallocation budget, and more. These upgrades persist across Breakouts as part of the core's carry-forward.

---

## Core Classes

Stat weights and one aura rule define a class. The core class is the single most important architectural choice an entity makes — it shapes the whole constellation's tactical identity. Full entries live in `core_classes.md`.

### The Ninja
High deallocation budget. Massive aura buff to nodes close to the core. Steep penalty to nodes far from the core. Small `skill_points_max` — can't sprawl. Hit-and-run warfare. Every turn is a shape.

### The Hive
Multiple isolated sub-constellations, each anchored by a **Lifelink** proxy core (see Addons). Multiplicative penalty to all node stats if any sub-graph exceeds N nodes, forcing pods to stay small and spread. The real core hides deep in one pod. An economic sprawler with inherently fragile pieces.

### The Edgelord
The entity that fights *with* edges rather than against them — master of the very topology the combat redesign runs on. Adds edges (safe by construction — only increasing connectivity, so it can never strand a region), closes rings, builds hubs, collapses hop-distance, and is the natural wielder of **Bleeding Edge** — the edge-severing move — which it can use without committing the unreachable-region heresy, because it can re-add what it cuts. The convert who uses the Lord of Edge's own tools — and is *still* damned the instant it Breaks Out. High complexity, and likely **the final core class to unlock.** The Edgelord is also the most plausible *creator* of self-loops — if any entity can add an edge from a node to itself, it is this one. Full entry in `core_classes.md`.

---

## SP Reservation — Wounds on the Tree

When a node is lost in combat, its freed skill point does not return cleanly. It becomes a **Reservation** — a wound in the entity's capacity that cannot be filled until healed.

In world terms: the entity's constellation has been forcibly torn. The lost node's connection to the core was not gracefully severed — it was ripped. That damage propagates inward, locking off a portion of the entity's available energy. The entity *remembers* what it lost, and the memory costs it. A `health_per_turn` flow heals these wounds, restoring capacity 1:1 — but until then, the entity cannot re-expand into the space left by its lost nodes even if it has nowhere else to go.

This creates a **suppression mechanic:** sustained node damage shrinks the enemy's effective options in real time. An entity that loses three nodes in a single turn is not just smaller — it's crippled, its reallocation budget collapsed to near zero. Healing is the only way back.

---

## Magic & Spells — the Blue Design Space

Magic is not a generic "ranged attack that goes further." It is **graph-theory made into a weapon.**

Each spell defines its own targeting mechanism, expressed in terms of the graph: hops from source, forks at junctions, propagation through specific node types, relay through edges. INT scales the spell's potency — damage, propagation depth, fork count, propagation distance — but the spell's *shape* is inherent to it.

A **lightning spell** forks. It follows all available edges simultaneously from the source, and the player has to reason about the graph's branching structure to predict what it hits. But forking is only one primitive among many. The Blue design space is meant to hold *dozens* of spells, each a different graph-math behavior fit to a different situation — greedy walks, degree-reactive chains, allocation-boundary targeting. See `combat_system.md` for the full taxonomy.

Crucially, **a node's degree gates and boosts magic:** weak spells can be cast from low-degree nodes, while the heaviest spells require high-degree **hubs**, as if a node draws power from its allocated neighbors. Hunting and holding the finest casting hubs becomes a Blue-build quest in itself. Degree is counted over the entity's own (owned) subgraph by default; certain rare or drain-flavored spells may instead count *any* incident neighbor, owned or not. **Self-loops add degree** and are of acute interest to Blue builds chasing casting tiers. See `combat_system.md` for mechanics.

This is a design space to open carefully and incrementally — too many spell types creates incomprehensible states; too few and Blue is just a better ranged attack. The guiding principle: every spell should feel like it *is* something that happens in a graph, not something that happens *to* a graph.

---

## The Core — Extraction and Uprooting

The core is not a passive nucleus. It has active capabilities — things only the core can do, limited by a charge economy earned through play.

### The build continuity problem

Movement on the tree does not dissolve your constellation. When the core hops between owned nodes, all other nodes stay allocated. The practical tension is narrower: if an exceptional node exists far from your current constellation, reaching it requires bridging through mediocre nodes to get there — diluting your build in the process. These abilities address that tension without removing it.

### Extraction

The core sits on a node and draws modifiers out of it, binding them directly to the core entity rather than to any position on the tree. The affected node loses those modifiers and becomes ordinary. The extracted modifiers travel with the core always — they cannot be deallocated, because they are no longer attached to any node.

Rules:
- The core must occupy the target node (hop to it first if needed, which costs movement).
- Costs 1 extraction charge.
- Extracts up to 2 modifiers of the player's choice from the node's modifier list.
- The node is not destroyed — it stays on the graph, just diminished.
- Extracted modifiers apply immediately and persist for the rest of the run.

Extracted modifiers are displayed in a dedicated "Core Mods" panel, visually distinct from the board of node-granted stats.

**Extraction and Proliferation are inverses.** Extraction (and loot's STEAL) pulls power **field → core** — *consolidate, make permanent and portable*. **Proliferation** pushes it back **core → field ×N** — remove a modifier the core holds and spread N copies across a cluster you must then fight to hold (*multiply, expose*). One pulls in, one pushes out. Crucially, proliferated copies carry an **intrinsic, owner-independent taint** that cannot be extracted or re-proliferated *by anyone* — even an enemy who captures one can only use it in place (a PoE-Mirror lineage). This is load-bearing: it breaks the otherwise infinite extract → proliferate → extract loop, so field→core paths stay rare and gated. See `combat_system.md` — Proliferation.

### Uprooting (status: class specialty — not a core-universal)

A more aggressive idea: the core rips a node entirely out of the graph — severing its edges, lifting the whole thing (type, modifiers, addons) — and holds it as a **seed** to replant elsewhere.

**The problem with making this a universal core power:** uprooting severs *all* of the target node's edges. If the core uproots a node from *its own* constellation, it tears out the very edges that held that node to the entity — and if the core itself is uprooting from where it sits, that is **graph-suicide:** the core orphans itself. Even uprooting an interior owned node risks islanding everything past it. As a freely-available core verb it mostly hands the player a way to accidentally dismember themselves.

So Uprooting is **demoted** from the core's universal kit. It survives, if at all, as a **class specialty** — something a topology-savvy class (the Edgelord is the obvious candidate, since it can re-add edges and therefore clean up after itself) can wield deliberately, with full knowledge of the connectivity cost. It also remains a viable *enemy-facing* weapon (uprooting a critical cut vertex out of an opponent's path), just not a casual self-targeting one.

**For build portability — moving a great node's power to where you want it — the intended tool is the Tech Seed, not Uprooting.** Tech Seeds already give core-bound, position-free modifiers without any edge surgery. That is the clean, safe portability path; see `skill_node_addons.md`.

Rules (if it ships, as a specialty):
- Costs charges (3, or 1 if the node is already player-owned).
- Edges are severed on uprooting — subject to the absolute softlock invariant (the board must never become permanently unreachable) and to the self-islanding risk above.
- The seed is held until planted (one at a time); planting is a normal allocation (1 SP to connect). Contents fully restored.

### Charge economy

**Base mechanic:** one charge earned per enemy core destroyed.
**Cap:** default maximum of 3 charges held at once. Charges beyond the cap are lost.
**Scalable via stat:** `core_charge_capacity` is a stat on the entity's board. Rare nodes can increase the cap.
**Design intent:** charges are earned through aggression. A passive player who avoids combat gets few charges. The charge cap prevents indefinite hoarding — use them or lose them when the next kill comes in.

---

## Constellation Geometry — Tendrils, Islands, and Rings

The shape of a player's constellation is not just aesthetic. It has tactical consequences that reward different playstyles.

### Compact vs. extended constellations

A **compact constellation** (dense cluster around the core) is defensible. Few exposed edges. Hard to sever. The core is deep inside and difficult to reach. But compact play means the player is likely not reaching the best nodes in the field — those are typically toward the periphery.

An **extended constellation** (long tendrils reaching out to high-value nodes at the edge) has access to better nodes but is structurally fragile. A single cut vertex cut by an enemy severs everything past it. The core may be exposed. The trade-off is power vs. survivability.

Both are valid. Some core classes and rare nodes actively reward extended geometry — bonuses that scale with the length of the longest path, or with the number of leaf nodes. A tendril-specialist build leans into the risk. (And under the combat redesign, leaves are now firing ports — extended geometry is literally where your ranged guns live; see `combat_system.md`.)

### Rings are strong (and that's graph theory, not a buff)

A **cycle** — a constellation that closes a loop — is **2-edge-connected:** there is no single edge whose removal islands anything off it. To sever a chunk of a ring an attacker must make *two* cuts, and since edge-cutting is meant to be rare and gated, rings are genuinely, mathematically hard to dismantle. Looping a tendril back to close a cycle around the core is a real defensive technique that falls straight out of the graph being a literal graph. (It is also why the final boss is a ring — the Ophanim — see The Final Ascent, and why the Lord of Edge's angels take that shape.)

**The same truth arms the melee blade (tensegrity resonance).** Under the phantom-blade model, a melee weapon *is* a swung copy of your topology, and its rigidity is a physical consequence of **triangulation** — a braced cycle holds its posture and delivers a full, wide "face" of damage, while a floppy hoop shears and deflates. So the structural fact that makes a ring an uncuttable *angel* is the same fact that makes a triangulated cycle a devastating *cleaver*: connection-made-rigid is holy **and** sharp. The Ophanim are not just hard to cut — were one to *swing*, it would land with the weight of every redundant edge in it. Graph theology and the swing kinematics are, again, the same text. (See `combat_system.md` — Tensegrity.)

### Islands

An **island** is a sub-graph of owned nodes with no path back to the core. Islands cannot persist. **Default: when an island is created, it dissolves immediately.** All its nodes become unallocated; SP Reservation fires for each.

There is no default grace period. The grace is an upgrade, not a right.

**Lifeline** (see Addons): grants nodes within N hops a 1-turn reprieve if severed into an island, enabling a last-resort race to reconnect before dissolution. Countered by the attacker immediately occupying the cut vertex that caused the island.

**Lifelink** (see Addons): a proxy core — a node that sustains an island indefinitely. The island lives as long as the Lifelink does. Very rare. Mid-to-late game only.

Islands created by Uprooting follow the same immediate-death rule.

---

## Node Components — The Addon System

Nodes support **attachable components** (addons) that modify behavior beyond base stat modifiers — an ECS layer on top of the base node type. Key addons: **Armor Ring** (damage resistance), **Reinforcement** (HP), **Buffer** (melee charging), **Winch** (euclidean pull force), **Lifeline** (island grace period), **Lifelink** (proxy core). See `skill_node_addons.md` for the full system including node specializations and Tech Seeds.

**Designer rule:** addons change *how a node behaves on the tree*, not what stats it grants.

---

## Death, Loot, and the Kill Economy

### When an enemy core dies

1. **XP reward:** The killing attacker receives XP proportional to the dead entity's level, converting to skill points through the normal pipeline.

2. **BLITZ (Predator only):** If the Predator had at least one node adjacent to at least one of the dying entity's nodes at the moment of the kill, it may immediately **steal one adjacent enemy-owned node** — direct transfer, no SP cost. If it BLITZes the core node itself (the Relic Node), loot resolution triggers immediately with a bonus. (Universal kill reward is XP + a DAP bonus; see `combat_system.md`.)

3. **Relic Node:** The dead core's node becomes a **Relic Node** — fused with the dead entity's core modifiers, sitting on the board indefinitely (provisional). All remaining enemy-owned nodes become neutral immediately — not destroyed, available to allocate.

### Reaching the loot

To trigger loot resolution, the player must **allocate the Relic Node.** The path to it usually runs through former-enemy neutral territory — chasing the loot naturally means claiming land. They are the same decision.

### The STEAL / PROLIFERATE tension

STEAL is portable power. PROLIFERATE is multiplied-but-fixed power. A roaming, aggressive build wants STEAL; a territorial anchor build wants PROLIFERATE. Neither is always dominant. The first loot window teaches this tension. Playtime is over. Pick one.

Full loot pool rules, pick count, and staining mechanics are in `combat_system.md`.

---

## The Final Ascent — Fighting God

The fractal does not ascend forever in an undifferentiated gradient. There is a top.

At some level — the exact depth TBD, discovered rather than announced — the structure changes. The field is vast. There are no Tethers to break. There is one other entity on the field. It is enormous. Its constellation spans most of the field. Its core glows differently.

This is the **Apex Entity:** the tree's original occupant, the thing that was here before any player ever loaded the game, the being whose presence shaped the fractal. In a JRPG it would be God. In this game it's that — whatever entity built or became the tree and has been watching every run, every Breakout, every level. Whether it *is* the Lord of Edge or His greatest angel is left ambiguous — and that ambiguity is preserved precisely because the Fairy is only His herald, not Him.

### The Ophanim — a ring you cannot cut

The Apex's signature form is an Ophanim **ring** of allocated nodes encircling the whole field — and not the thin, single-row ring a level guardian spawns as. The Apex is a **thick** ring: several concentric rows, redundant everywhere, parallel paths through every arc. The 2-edge-connectivity that makes any cycle hard to sever is multiplied; there is no single seam, no two cuts that drop an arm. You cannot dismantle it topologically. You grind it, arc by arc, the long way around. We are putting the OP in **OP**hanim, and we mean it.

You wanted to take out God. Here, fight His angels. Oh — you didn't want that? You just wanted to swing a sword? Tough. You're fighting God anyway. That was always what leveling up was. That was always what the Fairy saw coming.

The final level is not about reaching the Tethers. There are none. It is about dismantling the Apex Entity's constellation, reaching its core, and ending it — or absorbing it.

**Every run ends here.** The Apex Ophanim is the capstone of a *run*, not only of the whole game: clearing it is the final in-run Breakout that surfaces the player back in the metagame and commits the meta-allocation that crashed them in (see `metagame.md`). So the first run already culminates in an Apex fight. Subsequent runs face a **tougher Apex** — scaled by accumulated meta-progression, and/or by a player-selectable **heat / ascension modifier** in the roguelike tradition (Hades' Heat, StreetPass-difficulty knobs), letting players dial the challenge up for greater reward. The *truly* final confrontation — the one that ends the game rather than a run — is the **metagame Breakout**, a distinct endgame the player must earn their way to; see the note below and `metagame.md`, The Way Out.

What happens after is unwritten. Possibilities:
- You Breakout one final time and the camera keeps pulling back — the game world itself is revealed as one node in something even larger.
- The Apex Entity's core fuses with yours. A stats screen. A seed for the next run that carries a fragment of what the Apex was.
- The tree collapses. The adventure game boots up. The sword is in your hand. But the skill tree panel, when you open it — is different.

Note the open thread between this in-run summit and the **metagame Breakout** (`metagame.md`, The Way Out): are these the same top reached two ways, or two different escapes? Unresolved.

---

## Level Design — Field Themes

Every level takes place on a bounded circular field, but the *feel* of that field is not fixed. Each level runs a theme — a structural and visual identity borrowed from the long tradition of skill trees and talent systems. The circular boundary is always present; what fills it varies. Themes determine edge density, node type distribution, field width vs. depth, edge directionality, palette, and Tether placement/count. (Because topology now determines offense and defense, themes also carry an *offensive identity:* dense webs favor magic hubs, sparse maps favor ranged tendrils — see `combat_system.md`.)

**The Classic Talent Tree.** Tiered columns, wider at the top, narrowing down. Edges point downward — branching decisions, converging payoffs. Tall and narrow. Convergence points make natural hubs.

**The Tech Tree Strip.** Wide, shallow, directed — a march from one end to the other. Tethers at the far end. Rare; breaks the circular feel hardest.

**The Web.** Dense, interconnected, near-directionless. Every node 3–5 edges. Rewards compact builds; a mage's paradise (hubs everywhere).

**The Constellation Map.** Sparse. Long edges. Few nodes. Tendril builds excel here — and so do snipers, since leaves reach the valuable outer nodes.

**The Spiral.** Nodes along a tightening spiral with lateral shortcuts. Core starts outer, best nodes at center, Tethers distributed along the path. Enemies expand outward from the inside — an inversion of the normal risk geometry.

**The Cluster Web.** Dense sub-clusters joined by narrow bridges — a graph of galaxies. Bridge nodes (cut vertices) are choke points by design. Each cluster has a distinct color identity.

### The Final Boss Level — The Grand Passive Tree

The Apex Entity's level is a homage to Path of Exile's passive skill tree. Massive, dense, multiple cluster regions radiating from a center, long bridges between regions.

**Winks to PoE:** filler `+10 to an Attribute of your choosing` nodes; Notable-style named nodes ("Iron Fortress," "Whispers of Doom"); Keystone-style nodes that change a rule for their owner; Jewel sockets that accept a modifier seed affecting nodes within N hops; the dark/gold/amber palette. The final level has no Tethers — the win condition is the Apex's core. This is the only level where Breakout is not the exit.

---

## Themes

**The skill tree as a place, not a menu.** Most games treat the skill tree as a layer on top of the game. Here it is revealed to be the substrate beneath it. The "adventure game" intro was the layer.

**Allocation as colonization.** Spending skill points was claiming territory. Owned nodes are warm, lit, alive; unowned ones are hostile or inert. Expanding your tree is literal expansion into unknown space.

**Allocation as heresy.** And — under graph theology — every Breakout severs the edges that bind your world to the one above. To progress is to cut. The player is an unmaker of edges in a cosmos that worships connection. The Fairy was not wrong.

**The entity on the tree.** The player's character did not get left behind in the adventure game. They *are* on the tree — they always were. The sword, the enemies, the world: projections of what the tree-entity was simulating. Leveling up was the entity growing. The skill tree opening was the entity becoming aware of itself.

**Other entities.** NPCs, enemies — they have their own nodes, allocations, colors. The turn-based structure (initiative, ticking, turn order) is the natural rhythm of entities on a shared tree negotiating who acts next.

**Compression as growth.** Everything you lose at Breakout became the substrate beneath your Core. You don't lose your run when a level ends. You *become* it.

---

## Tone Notes

- Act 0 should feel **genuinely normal.** No winks to camera. No ironic distance. The player should feel like they accidentally loaded a Zelda clone — and the Fairy should feel like a normal, if faintly off, companion.
- The cute enemies should read as **fair game in the moment** (it's an RPG; of course you kill the little things for XP) and quietly **uncomfortable in hindsight** once the Fairy's judgment lands.
- The "crash" should feel **real enough to be alarming** — "oh no the game crashed," not "oh no my GPU died."
- Act 2 should shift to **quiet dread** rather than horror. The tree is beautiful. The player's nodes glow warmly. Like waking up somewhere unfamiliar that is somehow also home.
- The graph theology should be played **straight** — strange, never ironic, the way the Ophanim pun is meant *and* meant seriously.
- The fractal reveal should feel **vertiginous, not cheap** — awe, like a map fitting inside one square of a larger map.
- The final boss should feel **earned and enormous.** By the time the player reaches the Apex they should feel genuinely powerful — and still outmatched.

---

## Tone Reference: The JRPG Ending

This game earns a JRPG-style finale. The Apex Entity is not ironic. It is the natural conclusion of a world where everything is a skill tree and scale goes all the way up. The player should feel like they've been ascending toward something real. The final confrontation is not "and then you fight god" as a joke — it is "and then you fight god" as a payoff.

---

## Open Narrative Questions

1. **What is the tree?** A simulation? A being? A prison? A garden? Intentionally ambiguous — the player's interpretation should be valid. (Graph theology now offers one in-world answer: it is the body of a cosmos held together by sacred edges. That answer is a *faith*, not necessarily the truth.)

2. **Who built it / who is the Apex?** Is the Apex the Lord of Edge Himself, or His greatest Ophanim? Deliberately unresolved; the Fairy being only a herald protects this ambiguity.

3. **The party.** If the intro implies a party of fighters, where are they on the tree? Other entities to find? Competitors for nodes?

4. **The enemies from Act 0.** They existed in the simulation. Do they exist on the tree? Were the cute things you slaughtered the same *kind* of thing you now are?

5. **Going down.** The fractal ascends through Breakouts — does it also go down? Can a node be pried open and fought inside?

6. **The Fairy across runs.** Resolved that the Fairy is the crash-agent, the antichrist-judge, a herald (not god), self-trapped in the curse, and carries a late betrayal. *Open:* does it ride along every dive, narrate from the hub "outside," go quiet as betrayal nears, or not even know it is imprisoned? And what *is* the betrayal?

7. **Curse vs. crime order.** Is the player cursed *because* they killed the innocents, or were they already cursed (the metagame already a prison) and the killing merely fit a doomed spirit? Leaning ambiguous — both readings should hold.

8. **Can you win on the first run?** With meta-progression now canon (rogueli*te*), runs are individually winnable and the metagame supplies persistence. *Open:* is reaching the Apex possible cold, or does it require meta-carry? See `metagame.md`.

9. **The metagame Breakout vs. the Apex.** Two possible "tops" — the in-run god-fight and the escape from the hub-prison. Same summit reached two ways, or two distinct escapes? Unresolved.

10. **Tether terminology and visualization.** Tether / Conduit / something else, and the exact look of "an edge seen from inside a vertex." Also: the disguised Tethers of the metagame hub.

11. **Self-loop origin.** How do self-loops arise in play — rare field property, Edgelord power, Tech Seed fruit, Blue unlock, rare event? And can they be destroyed/targeted directly?

---

## Visual Language

| Element | In Act 0 (adventure game) | In Act 2 (tree world) |
|---|---|---|
| The player | A sprite with a sword | A glowing entity anchored to a node |
| The Fairy | A small, faintly-uncanny companion sprite | (TBD — does it manifest on the tree, or only speak?) |
| The cute enemies | Small harmless creatures you kill for XP | (TBD — neutral/hostile nodes? the same kind of thing you are?) |
| Skill tree panel | A UI overlay | The entire world |
| Allocated node | A lit icon in the panel | A warm, inhabited structure |
| Unallocated node | A dark icon in the panel | A cold, silent landmark |
| Edges / connections | Lines in the UI | Traversable paths — and, theologically, sacred bonds |
| Red node | A fire skill icon | A red-glowing melee power structure |
| Green node | A speed skill icon | A green-glowing precision outpost (leaves = firing ports) |
| Blue node | A magic skill icon | A blue-glowing magic conduit (hubs = the great casters) |
| White node | An XP/utility icon | A bright neutral structure, XP-granting |
| Self-loop | N/A | A small recursive arc on a node; rare; marks a glass-cannon wizard station and a resonance point for propagating spells |
| The core | Not visible | The warmest point in the constellation |
| Tether | N/A | An inward protrusion / anchored cord — an edge of this vertex, seen from inside |
| Breakout trigger | N/A | All Tethers severed + boss dead; the entire field collapses inward into a single node |
| Relic Node | A dropped item | A fused enemy node glowing with foreign color; the dead core's last position |
| Cut vertex | N/A | A load-bearing junction whose loss islands everything past it |
| The Lord of Edge | N/A | Unseen. Present in the sacredness of every edge; embodied, perhaps, by the Apex |
| The Ophanim | N/A | Rings — angels of pure connection; the Apex's thick, uncuttable form |
| The metagame hub | A title/menu screen, lightly dressed | A small locked space with disguised Tethers of its own |
