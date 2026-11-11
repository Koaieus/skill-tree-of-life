# Elements — play-situation review (2026-11-05)

Four Sonnet reviewers, one lens each, wrote play situations against `docs/design/elements.md` as of 2026-11-05 (before the Cold / Frozen / temperature verdicts of the same day), then rated each other. **Unjudged by the owner**; the consensus top items are summarised in the design doc § Open. Situations are reviewer text, not decisions.


---

# Fire lens: play situations (Fuel medium, Heat mover, Element Matrix)

Reviewer: Fire. Cites are to docs/design/elements.md ("EL"), ADRs, the four issues ("#n rK" = issue n, round K) and docs/handoffs/elements.md (deleted 2026-11-11; `git show 9582a705:docs/handoffs/elements.md`) findings ("HF n"). Lines marked EXTRAPOLATION go beyond the text. Verdicts: covered / gap / contradiction / unfun.

## 1. The 5-goo volley (atomic 1, the happy path)

**Setup.** An archer with Fire 6 fires 3 goo arrows (Fuel ride rows) then 5 poison arrows at one enemy node N (HP 100, 4 neighbours, all hostile).
**Resolution.** Each goo arrow plants Fuel by a `ride` row, so "the planting hit never trips it" (EL § reach rule, § three things wear "explosive"). N holds Fuel 3. Each poison arrow reads Fuel 3, 2, 1 as it lands. Reach is "the element it carries plus the element resting on the node" (EL § reach rule). Arrow 1 reads Fuel 3 and arrow 3 reads Fuel 1. The arrows carry no fire, so the Fuel gives the reach. The poison copies go to the disc at `ceil(r*s)` (#1733 r3). One Fuel is spent per go-off, as in code (explosive.md § Spend and power, the 5,4,3,2,1 ledger).
**Verdict: covered, with one hole.** EL says only "a medium that gives reach is spent by the reach it gives". It never says how much. The 1-per-hit answer sits in #1733 r3 and explosive.md, not in EL. A reader of EL alone cannot tell whether Fuel 3 is spent whole on arrow 1.
**Fix.** Add one line to the reach rule: "a go-off spends one stack of the medium (owner, #1733 r3)".

## 2. Heat meets Fuel on a tick (settle with no parent hit)

**Setup.** My Hearth keystone (emits Heat each world turn) sits beside a Fuel-3 barrel node K. Enemy nodes are at distance 1 and so are two of mine.
**Resolution.** The world-turn tick diffuses Heat onto K. "The same settle runs after every world-turn tick" (EL § Landing resolution). Ignition spends min(heat, fuel) and the power is the node's Fuel (#1660 r2, "ignition is a state check"). EL's pair table says "radius from Fuel plus load". There is no parent hit, so the copies carry no payload. They have no crit (HF 12), no side, no landing mask and no seed stream. Mine and the enemy's nodes in the disc are indistinguishable. Whether a peer receives or reproduces them is unanswered (HF g, ADR 0002).
**Extrapolation, not in the text.** With the barrel addon refilling Fuel each owner turn (explosive.md § Charges; its fate is HF 15), a permanent Hearth would blast every tick. Heat is never spent: "Heat stays on the node".
**Verdict: gap, plus unfun.** The tick-ignition blast hits friendly nodes and nothing says whether it should.
**Fix.** State that a tick blast carries no payload except its own damage (#1733 r3's named exceptions) and a side-blind mask. Add a once-per-node-per-turn cap on tick ignition.

## 3. Fire answers a Frozen chokepoint

**Setup.** Enemy chokepoint C has Frost 5 and the Frozen threshold T is 3, so C is Frozen. I have a Heat ride row at +2 and a Fire reach row.
**Resolution.** A Fire-loaded hit on C "lands, load inert" (EL pair table). A Heat rider nets min(heat, frost) at settle. "A hit carrying +1 Heat onto a 5-Frost node is read against 5, lands, and leaves 4" (EL § Landing resolution). My +2 Heat arrow leaves Frost 3, still Frozen. It needs a third Heat to drop under T. The Heat decays at 1 per turn while Frost decays "per def", so the freezer can out-stock the pyro.
**Hole.** Riders are separate `HitInstance`s that land BEFORE their hit (ADR 0067; HF 3 says no "landing unit" exists). If settle runs per instance, the Heat rider thaws C before the same arrow's Fire load is read. If settle runs per hit, it does not. EL does not say which.
**Verdict: gap.** The thaw timing is ambiguous. The "Frost sheds the pyro's Heat" economics (1 Heat buys 1 thaw) is not stated as a design intent.
**Fix.** Define the landing unit as the Hit (lead plus riders), with read once before its first rider and settle once after its last.

## 4. The disc walks round the wall

**Setup.** A Frozen chokepoint B sits between A and C in a line. I blast A with a Fuel-4 node.
**Resolution.** The Frozen rule: "a hit lands on a Frozen node and never leaves it (an arc grounds, a blast sinks)" (EL § reach triad; § pair table). B receives a copy and goes no further. The disc is euclidean. C, behind B, is inside the same radius, so A's gather list includes C directly.
**Extrapolation.** EL never says whether Frozen nodes inside a euclidean disc block line of sight, as the #1733 r3 leap rule does ("no node disc on the segment"). The text only describes what happens to hits that land on B.
**Verdict: gap, and a readability risk.** EL's claim that a frozen chokepoint "holds against every blast that lands on it" is true but misleading. Ice walls arcs (paths) but not discs. A player who freezes a choke expecting Fire not to reach behind it is surprised. This is the one place where Ice is not "anti-reach" for Fire.
**Fix.** Either say outright that Frozen stops a blast's chain from B but not the origin's disc, or adopt the line-of-sight rule from #1733 r3 for discs.

## 5. Fire-loaded cast on a Fuel node (one blast or two?)

**Setup.** My Venom Burst has an Explosive (Fire reach) row at load 2. It lands on an enemy node holding Fuel 3.
**Resolution, two passages disagree.**
(a) The pair table: Fuel × a Fire-loaded hit is one "blast, radius from Fuel plus load".
(b) § Dual reach: "every reach source present at read time fires... lists are concatenated, not deduplicated", and the owner's "double counting might be a feature" (2026-11-05). The hit's Fire load and the node's Fuel are both Fire. Are they two sources, so two blasts, or one?
(c) #1660 r2, owner: ignition power is "the node's fuel", not Fuel plus load. HF 7a already flags this.
(d) The hit "spends nothing" of its load, but the Fuel is spent.
**Verdict: contradiction.** Table (a) and § Dual reach (b) give different counts for the same landing, and (a) overran an owner verdict (c). It matters most for Fire, which is the only element whose hit load and node medium share a type.
**Fix.** Say: same-element sources merge into one reach whose radius is the larger of the node's Fuel and the load; dual reach (concatenation) applies only across different elements.

## 6. Fuse and "per attack" versus "per wave"

**Setup.** Five Fuel-2 nodes in a line. I fire a 5-arrow volley and a 4-wave spell on separate turns. I hit node 1.
**Resolution.** EL: a copy landing on a medium "spends it and reaches again from there, once per node per attack, at its parent's share". But in code `detonated` is per arrow and per spell wave (explosive.md § Chains), and the owner's own 5-arrow case needs 5,4,3,2,1 across arrows. Read literally, "per attack" would make the volley's arrows 2..5 unable to re-detonate the same node. That breaks the owner case (HF 11, 7b).
**What a chained blast deals** is #1735 fork 1, open: terrain damage, diminished hit damage, or no cascade. The fantasy of lighting a fuse has no damage figure. Share-at-parent plus radius-from-Fuel gives a fuse whose range holds but whose damage decays geometrically, and the owner flagged "lighting a fuse suddenly doesn't work anymore, bit sad".
**Verdict: contradiction (cap scope) plus gap (chained damage).** The Fuse is the headline Fire fantasy and has no defined damage.
**Fix.** Change "per attack" to "per hit (arrow, wave)", as code is. Unblock #1735 fork 1 before any Fire issue goes `Ready`.

## 7. Ranged access: does 20 Fire mint 20 arrows or 40?

**Setup.** An archer has Fire 20 and two element ammo types: Fuel (goo) arrows and Heat arrows. Both cells of the Element Matrix.
**Resolution.** EL: the count "sets how many element arrows a reload mints (`AmmoType.per_reload_stat_id`)" and "one cap per element across its whole family" (EL § forge; § which element statuses ride). In code, a non-base type mints `stat_board.get_stat(per_reload_stat_id)` independently (`Entity.reload_yield`). Both types key on `fire`, so each mints 20 and the pair mints 40. The family cap (one count across the family) is not enforced by anything.
**Extrapolation.** If instead the two types key on `fuel_aspect` and `heat_aspect`, that is HF 5's new `StatDef.Role` question, and the members would draw separate supplies, again against ADR 0072's "one supply per family".
**Other hole.** Stock cap: Fuel arrows decay 1/turn, so a banked Fuel plant is worth a stack. Planted Fuel is side-less terrain that "survives retakes": if I retake a node I goo'd, the enemy's Fire-loaded hit or Charge arc on it blasts MY nodes in the disc. Fuel is a liability on territory I may own tomorrow. EL's readability test ("would it still make sense if nobody owned this node") is satisfied, but a player will feel their own goo as friendly fire.
**Verdict: gap.** No rule chooses between a shared draw-down budget and per-type minting, and the retake liability is undiscussed.
**Fix.** Make `per_reload_stat_id` a single budget per element family (Fuel and Heat arrows split it) or state in EL that each cell is its own bin.

## 8. Crit on a goo plus poison arrow

**Setup.** Crit chance is 1.0 and `crit_multiplier` 2.0 on a Fuel-laden target. A 1-stack poison arrow with a Fuel ride row lands.
**Resolution.** A hit crits once and its riders copy the crit (#1741, built). The Fuel rider is a rider: 1 × 2 = 2 Fuel planted. The poison copies on a later Fuel-triggered disc: EL says only "whether a reach copy also copies its parent's crit is open". If copies carry the multiplied rider and then take `ceil`, then `ceil(2*0.5)*...` differs from `ceil(1*0.5)*2` (HF 12).
**Effect.** A crit goo arrow plants double Fuel. Since the blast radius scales with power^0.5 and Fuel is uncapped (#1733 r3 proposes `max_stacks`, no owner pick), 100 crit goo arrows give a node of Fuel ~200, a radius of about 40 node-radii. EL caps the row's supply by the count; crits then multiply past it.
**Verdict: gap.** Crit scaling of Fuel rides defeats the "a count is supply, not load" cap, and Fuel has no node cap.
**Fix.** Rider crit multiplies after the cap by design (say so), and give Fuel a `max_stacks` before any Fire issue is `Ready`.

---

# Ice lens: play situations (reviewer: Ice)

Sources: E = docs/design/elements.md (section named), A72/A73/A70/A67 = ADRs, I1444/I1733 = issue comments, H = docs/handoffs/elements.md (deleted 2026-11-11; `git show 9582a705:docs/handoffs/elements.md`). "EXTRAPOLATION" marks anything the text does not say. Code check: grep finds no Frost/Frozen/Frostbite/Afterdrop anywhere in `*.gd`/`*.tres`, so every Ice mechanic below is paper only. Shipped facts used: `max_hops`/`max_visits_per_node` on `PropagationConfig` (spell_resolver.gd:217, :436); Pestilence 6 hops x2 visits, 1 poison seed, enemy-only filter; Venom Burst 15/10/5 poison, 2 hops; Cyclone 8 hops x999 visits; Trail Blazer `max_hops = inf`.

Important context: the Ice material that is *owner-quoted* is thin: the Frost/Frostbite/Frozen role table (2026-11-04), "concentrate" as an idea (hops shrunk for more payload, "not a pure nerf"), the ranged=point triad vibe, "Frost side-less", and "Heat vs Frost is the one netting pair". The toll, shed, shatter numbers, Afterdrop, the Frozen threshold T and the concentrate multiplier are all pass proposals (I1444 round 2 or E "pass lean").

---

## 1. My own wall blocks my own healer (Frozen is side-less)

**Setup.** I own a chokepoint node C. I plant Frost >= T on it (Ice cast with a Frost ride row). Behind C are my other nodes, one holding a wounded ally core-side node. I cast Healing Beam (3 hops) from in front of C.

**Resolution.** E "reach rule": Frost is side-less and "blocks the freezer's own reach too"; E "reach triad": a hit lands on a Frozen node "and never leaves it (a hop walk ends)". So the beam lands on C (heals it) and the branch ends; nodes behind C get nothing. Same for Remedy/Purification walks and for an ally's cure spread. The text says "arc and blast", "hop walk", "chain" -- it never says friendly hits are exempt.

**Verdict: gap + probably unfun.** The wall is meant as defence (owner: "frozen is also a defensive option"), but it taxes the owner's own support spells and own Lightning for the life of the Frost. EXTRAPOLATION: whether a heal walk is "a hit" for the Frozen rule is unstated; whether the seed itself can sit on a Frozen node and walk out (seed = `hops_remaining` at the seed landing) is unstated too.

**Fix.** State that Frozen stops only hits whose `target_mask` includes HOSTILE (a friendly walk passes through at normal cost), or accept the tax and say so.

---

## 2. Concentrate pricing: what "x ratio" does on three real spells

**Setup.** Ice count 12. Cast Venom Burst (seed 15 poison, 2 hops), Pestilence (1 poison seed, 6 hops, 2 visits) and Cyclone (8 hops, 999 visits) with an Ice reach row, each concentrated to 0 hops.

**Resolution (E "Ice on a cast", "pass lean").** Affinity converts count to hops (Pestilence 4:1 -> 3 hops removed, Venom Burst 2:1 -> 6 hops, but only 2 exist so surplus is wasted). "Each hop removed multiplies the seed payload by a knob near the measured ratio of the hop it removes." From the doc's table: Pestilence 0 hops = x84 (landings at <=2 visits) so a 1-stack seed becomes ~84 poison on one node; Venom Burst x11.9 on 15 -> ~178 stacks, though the real spread only ever placed ~95 stacks in total (15 + ~4x10 + ~8x5), because the stacks per hop fall (10, 5) while the ratio counts landings. Cyclone (visits 999, ladder is the "unbounded" column, x3.6 per hop compounding) is off any table.

**Verdict: gap, and a likely degenerate.** (a) The ratio counts landings, not payload per landing, so it overpays any spell whose payload decays per hop. (b) The measure is on whole-graph walks; real enemy territory is "a subset", so versus a 8-node enemy it pays x84 for a walk that would have hit 8. (c) "knob: one number per spell vs the ladder" is the open question. (d) EXTRAPOLATION: "seed payload" may or may not include infusion riders; Pestilence "poison infusions diluted 10:1" interacts. (e) `max_hops = inf` (Trail Blazer) has no ladder at all.

**Fix.** Price from authored payload mass: conserve `sum(payload over typical landings)` capped per spell, not the landing ratio; refuse Ice on `inf`-hop and `max_visits >= 99` spells until priced by hand.

---

## 3. A concentrated cast lands on a Fuel keg (Ice as an AoE amplifier)

**Setup.** Enemy node K holds 4 Fuel. I cast a Pestilence concentrated to 0 hops (x84 seed, situation 2) onto K.

**Resolution.** E "landing resolution": the Ice-loaded cast "has no reach entry at landing (Ice was spent on the spell's hops at cast time)". But reach is "the hit's element plus the element resting on the node": K's Fuel still gives a blast (E "reach rule" atomic 1: "the arrow carries no fire; Fuel on the node gives the blast"). The blast copies the payload at share s (riders `ceil(r*s)`, A73/I1733 R3). The payload is the x84 payload.

**Verdict: contradiction/degenerate.** E sells Ice as *anti-reach* ("the counter-element"), yet a concentrated seed is the largest payload in the game and any Fuel or Charge node in reach copies it at one share into a disc or arcs. Ice becomes the best Fire/Lightning *amplifier*, the opposite of the triad story. Each copy also keeps `ceil` so a share of 0.5 of 84 is 42 poison on every disc node. EXTRAPOLATION: that copies take the multiplied riders rather than the pre-concentration ones; the text does not distinguish. Related: H finding 10 (Ice breaks "the slot buys reach only").

**Fix.** Define the concentrate bonus as a cast-local multiplier on the seed *landing only* (copies and chain shares use the unmultiplied payload), or simply forbid reach from a concentrated landing.

---

## 4. Frostbite pack walks into my Frozen chokepoint

**Setup.** Enemy casts a 20-stack Frostbite at my node; the pack heads for my core along the shortest owned path, which crosses Frozen C (Frost 8, T = 6 in this example; T is nowhere defined).

**Resolution.** E pair table, Frozen row x Frostbite column: "toll, a free hop if deep enough". Cancellation: Heat never touches a pack. The mechanics of the toll (hop k owes shed k, node Frost pays first and is *consumed*, the pack sheds `max(0, k - Frost)`) exist only in I1444 round 2, a pass proposal; E's table just says "toll". Hop 1 owes 1, Frost 8 -> 7. Still Frozen (>=6). Next hop k=2: Frost 5 -> **unfrozen**. Each pack permanently eats the wall; sheds on Frost-free nodes become Frost on *my* path, which I may then freeze into my own corridor (situation 1) -- side-less.

**Verdict: gap.** E never states shed rule (growing vs constant vs halving: I1444 10-24 "Owner not yet answered"), never defines T, and never says the toll consumes Frost, only that "Frost sheds first". The doc's claim "an Ice chokepoint is answered with content, never with a stat" is true but the Frostbite answer *is* a stat-free consumption of the wall. Also E calls Frostbite "mover: sided, hurts, spreads" yet #1444 says walking does no damage.

**Fix.** Copy the toll/shed rule and T into E as a pass proposal marked as such; settle T as a flat knob (>=2) before anything else.

---

## 5. Afterdrop: cheap Frost, converted into a core-seeking pack

**Setup.** I Frost-plant a hostile chokepoint (my concentrated ice cast, situation 2, plants 60 Frost; Frost cap = ice count, but the concentrate multiplier is on payload, not cap: EXTRAPOLATION, text silent). Next turn I cast Afterdrop.

**Resolution (I1444 round 2 only; E never mentions Afterdrop).** Targets each HOSTILE-owned Frozen node in reach, spends all Frost F, lands `ceil(F/2)` Hypothermia/Frostbite "raw" (no `stacks_per_hit`, no crit, no cap), pack aims at that owner's core. 60 Frost -> 30-stack pack; growing shed gives range ~sqrt(2*30) = 7 hops. The note "bounded only while T >= 2" is also only there.

**Verdict: gap + degenerate risk.** (a) Afterdrop is not in the design doc, so no section covers its cost, slot or school. (b) It converts a *defensive* wall into the strongest "core is far away" threat, and raw bypasses the ice-count cap that E insists on (A73 point 5: "capped by the element count"). (c) Frost is side-less, so a wall *I* built defensively is Afterdroppable by the enemy too (EXTRAPOLATION: sides are checked on node owner, not Frost's origin; I1444 asks "convert only Frost the caster laid?" lean no). Net: freezing your own chokepoint is a liability whenever the enemy owns Afterdrop.

**Fix.** Make raw Hypothermia count against the same ice cap, or cap the Afterdrop pack at the target's `ice`-style budget; promote Afterdrop into E or park it explicitly.

---

## 6. A blade swings at a frozen keg (phase ordering of shatter)

**Setup.** Melee entity swings at node Z holding Fuel 3 and Frost >= T (a frozen keg, per E Cancellation "nobody can set it off until thawed").

**Resolution.** E pair table: Fuel x blade "blast on contact"; Frozen x blade "shatters". Landing resolution: (1) Read: Frozen check -> reach inert, no blast. (2) Land: damage + riders; "nothing reacts". (3) Settle: spends read-charged mediums; EXTRAPOLATION: shatter spends Frost here, since Frost is not charged at read and land forbids reactions. Result: blade damages Z, Frost goes, the keg stays Fuel, un-blasted. Next swing blasts. The shatter's *damage* (`k x F` in I1444 round 1, owner wants "an execute below a %" or percent HP: open) has no hit, so no crit and no `resolve_seed` stream (H finding 12).

**Verdict: gap.** The three phases never mention shatter, drag or Afterdrop. "First spend wins (R5 hit order)" in I1444 round 2 contradicts "settle is one pure function": which of shatter/Afterdrop/netting runs first inside a single settle is unstated. Also a blade vertex sweep touches several Frozen nodes at once: each shatters in one hit, but "a blade is the one hit that answers back" has no cost for the blade (`drag` applies only below T).

**Fix.** Add one line: shatter is a settle spend, ordered shatter > Afterdrop > netting > toll, damage as raw with no crit.

---

## 7. How long does a wall last? Decay, death, retake

**Setup.** Ice count grows to 30 (E: counts 20-50). I plant a 40-Frost wall on a node, then lose the node to the enemy, who retakes it; later it is deallocated.

**Resolution.** E "One count": the medium "rests on a node regardless of owner, survives kills, retakes and deallocs", leaves by spend, decay ("per-def, ADR 0048; Frozen's timer") or cleanse. Frozen = Frost >= T; "the timer is Frost decaying back under it". No decay is authored. If it copies Poison's `FlatDecay` 1/turn (status-effects.md), 40 Frost with T = 6 stays Frozen 34 turns, roughly the rest of a level. Build note in E: today `on_dealloc` CLEAR/LINGER both clear on death; the medium needs a new shape.

**Verdict: unfun/gap.** Because count scales Frost into the tens (and concentrate x84, situation 2), a Frozen node is effectively permanent terrain for whoever finishes the level, and the only fast counter is Heat (a Fire build). A Lightning/ranged-only build has no answer at all, contradicting "answered with content". Readability: a Frozen node that has no owner and no visible clock is hard to read. Also unspecified: does Frozen block *allocating* onto the node or entity travel ("Frozen blocks travel, #1444" in E's State bullet is ambiguous between hits and movement; #1444 said "hop walks, chains, spread and blades").

**Fix.** Give Frost a `FractionDecay` (proportional, so 40 vs 8 both thaw in similar turns) and state Frozen affects hits only, never allocation or movement.

---

## 8. Cleansing and mirrors (short)

**Setup.** Multiplayer peer; a world-turn tick takes Frost from 6 to 5 by Heat netting; Frozen flips mid-turn.

**Resolution.** E: "the same settle runs after every world-turn tick". H finding 12: ticks have no parent hit, no crit stream, and receive-vs-reproduce is open (ADR 0002). Frozen is *derived*, so no save row, but the Frost row must be saved (A "save-load" rule). EXTRAPOLATION: a peer reproduces Frozen from replicated Frost; text does not say.

**Verdict: gap (shared with the landing-resolution lens).** Fix: Frozen is a read-time derivation on both sides; only Frost and Heat counts are replicated.

---

# Lightning / chain-reaction play situations

Lens: Lightning (Charge medium, no mover), plus fuses across media.
Sources: `docs/design/elements.md` (EL), ADRs 0067/0070/0072/0073, issues #1733 r3 (the "Round 3" comment), #1741, `docs/handoffs/elements.md (deleted 2026-11-11; `git show 9582a705:docs/handoffs/elements.md`)` review.
Tags: **[owner]** is a dated owner quote. **[pass]** is a pass proposal. **[extrap]** is my extrapolation, not text.

Context for all of them: the shipped `lightning_bolt.tres` is a 3-hop `FanAllSpread` ball at x0.5 per hop with an enemy filter. Nothing elemental exists in code yet (EL header). The design's Lightning arc is a new thing.

---

## 1. The tie that eats the cut (pick rule on an ordinary board)

**Setup.** An enemy hub H has graph degree 4 and Charge 1. Its four neighbours have Charge 0 and graph degree 3 each (the mean degree is 3.1, so ties are the common case). A Charge-free arrow lands on H.

**Per the design.**
- Read: S_total = 1 + 0 = 1 (#1733 r3 table).
- Pick: the top 1 neighbour by (Charge, graph degree) **[owner]**. The "ties included" clause **[pass]** strikes a tie straddling the cut in full.
- All four neighbours tie, so all four are struck.
- Result: Charge 1 behaves like Charge 4. A cut that lands in the middle of a tie group struck everything.

**Verdict: unfun / unreadable.** The same Charge 1 does 1 arc next to a degree-5 neighbour and 4 arcs on a flat patch. The player must read neighbours' graph degree, which includes other owners' edges and self-loops at +2 (`docs/domain/degree.md`).

**Contradiction.** The round-2 pass proposal said ties FORK and split the share (f*s/k). Round 3 says ties are struck in full. Neither is an owner call. EL never says which holds.

**Fix.** Either ties split the arc count (cut = k, random-free via a stable but explainable order), or the pick rule gets a visible third key. An owner call is needed because "no node id" was the owner's complaint.

---

## 2. Charge 40 on a keystone node (critical Charge and leaps)

**Setup.**
- A late-game lightning build (count ~40) plants Charge with a ride row. The Charge ride is capped by the element count (ADR 0073 #5, "one cap per element across its family").
- A degree-3 node N now holds Charge 40.
- An ordinary arrow hits N.

**Per the design.**
- S_total = 40 > M = 3. Critical (**[owner]**: Charge > graph degree, leap range grows with the excess).
- The arrow arcs to all 3 neighbours, plus E = 37 leaps. Each leap goes to the best node in clear line of sight within `leap_radius(37)` **[pass]**.
- One stack is spent (**[owner]**). So the next 39 arrows each repeat a nearly board-wide zap.

**Gaps and contradictions.**
- The pass says "bounded because media are small (point 4)". But the node cap (`max_stacks` on the `StatusDef`) is **an unanswered owner fork**. Meanwhile the owner expects counts of 20 to 50, and ADR 0073 caps the ride by that count. The bound the argument rests on does not exist yet.
- `leap_radius(E)` has no numbers anywhere.
- Line-of-sight leaps are a new geometric mechanic. It breaks "hops are hitscan along edges".
- Whether a leap respects ownership, Frozen nodes or territory is silent.
- EL's Open list does not mention any of this. The doc says only "The arc pick rule and radius-per-load numbers: #1733".

**Verdict: gap, and degenerate at high count.**

**Fix.** Settle the node cap before Lightning is `Ready`, or clamp E (for example E <= M).

---

## 3. The self-refilling wire (a Charge rider rides the arc copies)

**Setup.**
- A lightning cast has a Lightning reach row, load 3, in the element slot.
- It also has a Charge ride row in an aspect slot. ADR 0073's consequence says "reach + ride, drawing on one cap" is legal.
- It hits plain node X.

**Per the design.**
- Read: no medium on X. The reach entry arcs the load to 3 neighbours.
- Land: an arc copy is "the payload at share f (riders `ceil(r × f)`)". The 1-stack Charge rider is ceil(1 × f) = 1, so it plants 1 Charge on each neighbour. **[extrap]** that the copy carries the medium rider. The text says riders are copied and a medium can ride, so nothing excludes it.
- Next shot at X: each charged neighbour goes off (spends 1) and its copy replants 1.
- Charge conserved: -1 +1 on every go-off. The wire never depletes.

**Check.** "A hit that plants a medium does not trip it" (EL) governs the node a hit lands on. It does not govern a copy replanting the node it just spent. Settle spends "mediums the read phase charged"; the copy's plant lands after read, so the order is plausible.

**Verdict: gap, probable infinite loop.** It is bounded only by "once per node per attack", which resets every attack.

**Fix.** A reach copy carries damage and aspect riders but not element-medium riders (they plant at the target only). Or planting a medium onto a node that was just spent nets out.

---

## 4. Five arrows into Charge 5 (spend of one, absorbed, and the pair table)

**Setup.** Node T has degree 6 and Charge 5. Five plain arrows land on it, in one volley.

**Per the owner.**
- "One at a time … size(F), size(F-1), …, size(1), last regular hit" **[owner]**.
- That gives arcs of 5, 4, 3, 2, 1, then a plain hit.
- Within one volley, a per-volley ledger is needed. Fuel has `SPENT_KEY` (`docs/domain/explosive.md`). EL's "read is a pure function of the node before this hit" does not say it is per hit rather than per snapshot of the volley.

**Contradiction.** The pair-table cell "a Lightning-loaded hit on Charge: arcs from Charge plus load, **Charge absorbed**" is the earlier proposal (#1733 r2). The owner replaced it with "consuming 1 at a time". The handoff review lists this as 7(b), and it is unfixed in the cell. Likewise, the "Fuel | Fire-loaded: radius from Fuel plus load" cell overran "blast power is the node's fuel" (7a).

**Second point.**
- Above M the stacks are wasted on arcs. With M = 3, arcs go 3, 3, 3, 2, 1, but the leaps (item 2) give back the excess.
- So the F+1-hit fuse analogy is exact only when S <= M.

**Verdict: contradiction (pair table vs owner) plus a gap on volley ledger.**

**Fix.** Rewrite the Charge cells to "arcs from S_total, spends 1". Reuse Fuel's per-volley ledger for Charge.

---

## 5. The lightning rod (Frozen plus Charged)

**Setup.**
- Defender D freezes a chokepoint F (Frost >= T).
- D also plants Charge 3 on F. Frost and Charge coexist as media.
- F is adjacent to D's other nodes. Attacker A fires a Charge-free arrow at neighbour G, where S_total = 1 (G is Charged 1).

**Per the design.**
- Pick: most Charge first, then degree. F (Charge 3) outranks every other neighbour of G.
- The arc lands on F. "Frozen ends an arc: the arc lands and does not go on" and "spends no Frost and absorbs no Charge" (#1733 r1, EL pair table).
- So F soaks the arc and keeps its Charge. The pick rule makes F a magnet, and F is also a dead end.

**What is silent.**
- Does F's own Charge go off when an arc lands on it? The table says the arc "grounds" and the chain ends. If Charge stays inert on a Frozen node, F is a permanent battery nobody can use.
- Is a Frozen node excluded from the pick? The pass lets it be picked, and the note "Frozen ends an arc" only describes what happens after it is chosen.

**Verdict: gap.** It could be a good emergent lightning rod (Ice counters Lightning, which is the stated design), but nothing says the pick is meant to reward it.

**Fix.** State it as a feature: Frozen nodes are valid, high-priority picks, and the arc dies there. Or exclude them from the pick, keeping "Charge first" honest.

---

## 6. Charge next to Fuel (a fuse across media)

**Setup.** A line: A (Charge 2) - B (Fuel 3) - C (Charge 1) - D (Fuel 2). All are enemy nodes. One arrow hits A.

**Per the design.**
- A goes off: arc to B (the Fuel) and another neighbour. An arc is a landing (pair table "Fuel | arc landing: blast").
- B blasts. Its disc reaches C. A copy landing on a charged node "spends it and reaches again, once per node per attack, at its parent's share" (EL § Chain reactions).
- C arcs to D, and D blasts. The share multiplies down at every generation.
- Result: a fuse that alternates media, bounded by shares, the one-spend-per-go-off rule and the once-per-node cap.

**Gaps.**
- What each chained go-off **deals** is #1735 fork 1, still an open owner question (owner is torn between 3 options). EL's Reach rule states "payload copied at one share" as if settled. It is labelled "pass proposal", but § Chain reactions cites R3, which was only restated by the agent.
- "Once per node per attack" in EL vs "per wave" in code and R3 (handoff 11, EL Open (i)). With a hitscan arc and a multi-wave spell, "per wave" lets the same node go off once per wave.
- Dual reach: a node in both B's disc and an arc's list takes **two copies** (concatenated, **[owner]** 2026-11-05, tentative). In an interleaved fuse, C takes a blast copy and an arc copy. That is double the damage on the node where media overlap.

**Verdict: gap (damage per go-off open), plus an unresolved scope for the cap.**

**Fix.** Pin damage per chained go-off before any chain issue is `Ready`. Say "per wave" or "per attack" in one place.

---

## 7. Crit and the hitscan arc (settle copies and crit draws)

**Setup.** A 30%-crit arrow hits a Charge-4 node, a degree-5 hub, and crits.

**Per the design.**
- #1741 (built): a hit crits once; its riders copy the crit.
- Whether a **reach copy** copies its parent's crit is **open** (EL § The hit). A spell blast's shrapnel draws its own crit today (`PairedDamageEffect`). Only melee blast and riding landings copy.
- So arcs have two possible semantics:
  - Copy: a crit arrow makes 4 guaranteed-crit arcs. Hitscan never misses, so a crit is multiplied by 4 with no further chance involved.
  - Draw: each of the 4 arcs rolls its own crit. The draw happens at settle, after the parent's crit stream.

**Gaps.**
- A settle-phase copy has no `resolve_seed` stream and no paired lead (handoff 12).
- A peer must either receive or reproduce the draws (ADR 0002). Unsaid.
- Rounding: `ceil(r·s)·c` differs from `ceil(r·s·c)` (handoff 12). A crit arc of a 1-stack rider is also 1.
- Owner caveat on hitscan: "just need to take that into account when balancing" **[owner]**. Crit copying is the lever that breaks that balance, and f below s alone does not offset it.

**Verdict: gap (open in EL).**

**Fix.** Arcs draw their own crit, in landing order, on the authority only. Do not copy. This matches shrapnel today.

---

## 8. Charge is side-less, so who gets zapped? (friendly fire and captured terrain)

**Setup.**
- Enemy plants Charge on a node E1 that borders the player's territory.
- The player retakes E1 (the medium "survives kills, retakes and deallocs", EL § The count).
- The enemy then shoots an arrow at one of the player's nodes P1 next to E1.

**Per the design.**
- Charge is terrain, judged by "side-less board facts" (#1733 r3: graph degree).
- The arrow lands on P1. If P1 has no Charge, nothing arcs. If E1 (now the player's) has Charge and gets hit, its arcs go to the top neighbours by Charge and degree.
- Neighbours include the player's own nodes. Which nodes **receive** a copy is never stated. The shipped `lightning_bolt` uses an enemy `OwnerFilter`. The pair table says nothing about a copy's filter.

**Gaps.**
- Do an enemy's arcs hurt the enemy's own nodes (Charge planted by a hostile)? Does an ally arc hit allies? The `ownership-vocabulary` rule says relation checks go through NEUTRAL/MINE/ALLY/HOSTILE bits, but elements.md never states which bits a copy uses.
- Leaps (item 2) bypass territory: can they cross to a third party?
- Captured Charge never fades unless per-def decay is authored (ADR 0048). EL gives no decay for Charge, and "Shocked" and any Lightning mover are parked.
- Lightning has no clock route. Fire has ignition and a death burn. Charge has only landing-triggered release, and cleanse or Frost as counters. A parked, unwanted Charge node is permanent, side-less, and only usable by whoever lands a hit next to it.

**Verdict: gap.**

**Fix.** State the copy's filter (hostile to the original attacker, as the shipped bolt), and give Charge a default decay knob.

---

# Landing resolution lens: 7 play situations

Source passages: `E` = docs/design/elements.md, `H` = docs/handoffs/elements.md (deleted 2026-11-11; `git show 9582a705:docs/handoffs/elements.md`) § Adversarial review (item numbers), `#n` = issue comments.
Marked **[extrapolation]** where I go beyond the text. Meta-finding first: E § Landing resolution is headed "ADR 0074" and the handoff says "if held, ADR 0074", but `docs/adr/` ends at 0073. The three-phase model is owner-held ("hold it") but not yet an ADR, and ADR 0073 explicitly says landing resolution is "not decided here".

---

## 1. Curse arrow into a Charge-3 node (atomic 3, full phases)

**Setup.** Node N holds Charge 3 (a hostile node). I fire one Curse arrow: damage 5, Curse rider 1, crit_multiplier 2, arc share f = 0.5. Its neighbours A, B, C are uncharged. Degree M = 4.

**Resolution.** *Read* (E, Landing 1): N's Charge 3 is read as it stood, so there are up to 3 arcs. The arrow's own reach entry is empty. *Land*: the Curse rider lands BEFORE the damage (ADR 0067), so it lifts its own hit. If the hit crits, both the rider and the damage are x2 (#1741). *Settle*: spend 1 Charge ("consuming 1 at a time", #1733 r3). Copies go to the top-3 neighbours, each running its own read, land and settle.

**Gaps.**
- The copy's Curse is `ceil(r x s)`. Does `r` mean the base 1 or the crit-multiplied 2? `ceil(1 x .5) x 2 = 2` but `ceil(2 x .5) = 1`. H12 names this and the doc is still silent. The same applies to damage.
- E says "Whether a reach copy also copies its parent's crit is open." Each copy would draw its own crit, so a crit-heavy build gets a different expected value per arc than per arrow. **[extrapolation]**
- Pair-table cell "Charge: arcs ... Charge absorbed" contradicts the owner's "consuming 1" (H7b). E's Landing text only says "the mediums the read phase charged are spent".

**Verdict:** gap (crit and share order); the pair-table cell contradicts an owner quote.
**Fix:** state "copy = parent's final landed numbers x share, rounded up once", and strike "absorbed".

---

## 2. A hit that has a Fire load, onto a node holding both Fuel and Charge (dual reach)

**Setup.** Firecracker-style Fire reach load 2. Target N holds Fuel 3 and Charge 2. N has 3 neighbours: A (Fuel 1), B, C. One cast, wave 1.

**Resolution.** E Dual reach: every source present at read time fires, so there are three of them: the hit's own load (disc), N's Fuel (disc), N's Charge (2 arcs). Each makes its own list, and the lists are concatenated, not deduplicated. A node in a disc and an arc takes two copies. The hit's load spends nothing; Fuel spends 1 and Charge spends 1.

**Gaps.**
- The pair table says "arcs from Charge, **then** the blast", and "arcs from load, then blast". The read phase is simultaneous, so "then" has no meaning. Does order matter? It does, because the once-per-node-per-attack cap decides which copy is the one that goes off on A's Fuel.
- Two copies landing on one node: do they count as two landings against the cap? E says the cap is per node per attack. The code's `HitLanding.detonated` is per wave, and the doc says per attack (H11). **[extrapolation]** If the cap is on go-offs rather than landings, A takes 2 copies of damage but only 1 go-off.
- Two Fuel sources in a single disc: is "the hit's Fire load" and "the node's Fuel" one blast or two? E says the load is a reach source. The owner's "blast power is the node's fuel" (#1660 r2) says only Fuel sets size. Pair table says "radius from Fuel plus load" (H7a).

**Verdict:** gap. The double count is explicitly an owner-tentative feature, but the cap's unit is undefined.
**Fix:** define the cap as "one go-off per medium per node per attack", and define concatenation order as "Fuel, Charge, hit load".

---

## 3. Goo arrow onto a Fuel node (planting versus "the read sees the pre-hit node")

**Setup.** A volley: arrow 1 plants Fuel 2 on enemy node N (Fuel 0 before). Arrow 2 (also goo) lands on N next beat. Arrow 3 is a Frost arrow.

**Resolution.** E reach rule: "a hit that plants a medium does not trip it." E Landing 1: reach reads the medium "as it was before this hit". Arrow 2 reads Fuel 2 (pre-hit). Does it blast?

**Contradiction.** If the read is literal, arrow 2 blasts and the goo volley eats itself: this is the old DETONATE. If the exemption holds, "a hit that plants a medium" is undefined: Fuel only? any medium? Pair table says a Frost rider on Fuel gives "blast, Frost copied into the disc", so planting Frost does trip Fuel. #1660 r2 solved this by authoring (goo ammo "leaves the spark out"), but E removes sparks (`Landing` says reach is a read of the node). Atomic 1 needs a Poison arrow to trip Fuel and a goo arrow not to.

**Unfun.** My own Frost arrow onto my ally's kegged node detonates it. **[extrapolation]** E "side-less medium" says reach copies follow the target mask, but the text never says the mask applies to media-triggered reach, only #1733 says "target mask filters friendlies".

**Verdict:** contradiction (pre-hit read vs planting exemption); the exemption's scope is silent.
**Fix:** "A hit carrying a ride row for medium X is exempt from X's go-off at its own landing only."

---

## 4. Heat rider onto a Frost-and-Fuel node (settle ordering)

**Setup.** Node N: Frost 3 (T = 5, not frozen), Fuel 4. A hit lands +3 Heat.

**Resolution.** Read: nothing (Heat is a rider, not reach). Land: Heat 3 on N. Settle (E Landing 3): "the Heat x Frost netting, the mediums the read phase charged are spent, and the copies go out". The ignition rule (#1660 r2) fires when heat > 0 and fuel > 0, "checked after every landing and after every tick's diffusion".

**Gap.** Settle's list has no ignition, and no order between netting and ignition. Net first: Heat 0, Frost 0, no ignition. Ignite first: spends min(3,4) = 3, power = Fuel, Heat stays 3, then nets to Frost 0. The player cannot tell from the text which, and the two differ by a whole blast. **[extrapolation]** E "Cancellation" says "order independent" for the netting only. The existing "frozen keg nobody can set off until thawed" line suggests net first, but a not-yet-frozen Frost 3 is not covered.

**Verdict:** gap.
**Fix:** "Settle order: net, then ignite, then medium spend, then copies out," written into the ADR 0074 text.

---

## 5. A fire blast hits a Frozen node holding Fuel (read phase vs Ice rule)

**Setup.** Fuel 2 and Frost 6 (Frozen, T = 5) on node F; a Fire-loaded hit lands on F.

**Resolution.** E: the Frozen check is in Read. "A hit lands on a Frozen node and never leaves it" (reach triad), and the table row Frozen: "lands, load inert". So no disc.

**Gaps.**
- Is F's own Fuel read (a source) when F is Frozen? The "frozen keg" line says it is inert until thawed. So is the Fuel spent by a go-off that has no reach? E: a medium is "spent by the reach it gives"; no reach given, so nothing spent. **[extrapolation]** That is consistent but never stated.
- Mid-hit unfreezing: a hit with +1 Heat onto Frost 5 "lands, leaves 4: it thaws for the next hit". Fine. But a tick-time settle then ignites the keg the same turn (heat > 0, fuel > 0). Whether Frost 4 still blocks a tick-time ignition (it is not a hit, so "never leaves" does not apply) is undefined.
- A copy arriving on a Frozen node runs "its own read" and grounds, so a Frozen ring is a perfect firewall. It costs the owner nothing (E: "costs its owner nothing else"). **Unfun**: the cheapest defence in the game, with no counter except Heat or a blade.

**Verdict:** gap (tick-time ignition on Frozen) plus a balance flag.
**Fix:** "A Frozen node ignites only after Frost drops under T, tick or hit."

---

## 6. Settle after a world-turn tick (no parent hit) in multiplayer

**Setup.** World turn. Heat diffuses onto a fuse of 4 Fuel nodes (A-B-C-D, Fuel 3 each, Heat just arrived on A). Host plus one peer.

**Resolution per E.** "The same settle runs after every world-turn tick." Settle emits copies, "each running its own read, land, settle". Nothing in E says what payload those copies carry.

**Gaps.**
- *Payload*: #1660 r2 says "heat-ignites-fuel burn: damage_per_charge x fuel spent, share s, **no riders**". E says a copy is "the payload". With no parent hit, what is the share of? What is the attacker (for kill credit, resistance, Greed, XP)? H12 flags this and the doc is still open (§ Open g).
- *Crit*: no parent crit; the crit stream is `resolve_seed ^ 0xC217` of an AttackPlan, and a tick has no plan. A copy draws its own or none. **[extrapolation]** Probably "none, no crit on terrain".
- *Multiplayer*: today a tick is **reproduced** on each peer (`EndTurnCommand` runs `end_turn` everywhere, status-effects.md), while spill and removals are **received** (a rebuilt record lands the recorded transfers). A blast cascade has damage numbers and kills, which are the received kind. It needs an `AttackRecord`-shaped "tick record" from the host, or the peer's diffusion and the host's cascade diverge. ADR 0002 says a mirror never mints its own result.
- *Cap scope*: "once per node per attack": a tick is not an attack. The whole fuse (D from A) would burn in one settle if the cap is unbounded, since each go-off wakes the next; or one node per tick if copies defer. **[extrapolation]** Either is a legitimate fuse feel, but the doc picks neither.

**Verdict:** gap, and the one with the most desync risk.
**Fix:** "A tick-settle emits a host-minted record (attacker = medium's last planter, no crit, riders none), received by peers, never reproduced."

---

## 7. The one rider map: a Poison rider and its AFTER copy (id-keyed coalescing)

**Setup.** Venom Burst with Poison infusion 3 plus a Fire reach row, on a Fuel node, `poison_stacks_per_hit` +1 (wisdom pool).

**Resolution.** ADR 0073 and E: riders are `status id -> stacks`, one entry per id, summed before `stacks_per_hit` folds (#1733 r2 restatement). The target gets Poison via the BEFORE rider. The disc's copies carry riders as AFTER (ADR 0067: a blast's status keeps `blast_mark`/`land_mask`, stays AFTER). If the map is keyed per hit, the BEFORE rider and the AFTER copy are in the same map under `poison` and merge.

**Gap.** H13: the "one map, one entry per id" is the agent restatement of round 2, not an owner quote, and #1741 NOTES still list coalescing as open. Two real effects: (1) the BEFORE/AFTER distinction ADR 0067 depends on vanishes, so the target's own copy might land after its damage; (2) the +1 per hit folds once, not twice. The owner's own question ("fifteen 1-curse hits land 2x15") is about separate hits, so one map per hit survives; but a copy is a new hit, so each copy folds its own +1 per node: a 12-node disc with `ceil(1 x .5) = 1` plus a fold +1 = 2 Poison per node on 12 nodes. **[extrapolation]** The fold applying to copies would make `stacks_per_hit` a reach multiplier the owner's R2 forbids.

**Verdict:** gap (owner-undecided), with a possible R2 break.
**Fix:** "Copies land raw: `ceil(r x s)`, no `stacks_per_hit` fold" (matches Afterdrop's raw path in #1444).

---

## 8. Greed / Hex terrain (aspect riding on reach) and the freezer's own chokepoint

**Setup.** Node H holds Hex (a sided mark) and I attack with an arrow that lands an arc copy on a neighbour.

**Resolution.** R4 (#1733): terrain is read "as a pure function of the pre-hit node and payload". Hex raises crit chance; #1741 says a Mark lands after the crit draw, so it lifts the hits behind it. A copy goes out at settle, after the parent's land.

**Gaps.** (1) A Mark-style rider on the parent is copied to the neighbours at ceil share, so the copies' crit draws (if they draw) read it: the arc copies get crit lift the parent's own hit did not. Reasonable but surprising, and the opposite of #1741's "mark lifts hits behind". (2) Hex/Greed/Curse are sided; Fuel/Charge/Frost are side-less: a copy landing on MY OWN node (a blast radius reaching my territory) plants my enemy's Curse on me? Mask rules apply per #1733 ("target mask filters friendlies") but E never says the copy rides the parent's mask. (3) Aspects "ride on element reach" only if the cast has a reach: the Curse arrow that hits a Charged node gets its reach free, but my own Charge planted on MY node (side-less) is then a hole that arcs my own copies. **[extrapolation]** This is the freezer-grounds-itself case E already accepts for Frost.

**Verdict:** gap (mask on settle copies; crit read on copies).
**Fix:** "A copy inherits the parent's target mask and its crit, drawn nothing."

---

## Ratings: rate-by-fire.md

# Ratings by the Fire reviewer

Scale: 5 = real, well-grounded gap or contradiction the owner must answer. 3 = real but minor or already in § Open. 1 = misreads the text or code, or presents a guess as a mechanic.

## ice.md
ice#1 — 4 — Frozen's "never leaves" is stated for arcs, blasts and hop walks, and nothing exempts friendly heal or cure walks. The extrapolation is flagged.
ice#2 — 4 — The landings-based ladder overpays spells whose payload decays per hop, and the measure is whole-graph. It partly overlaps the "Ice pricing knob" in § Open, but the `inf`-hop and `max_visits` 999 spells are new.
ice#3 — 5 — A concentrated seed is the biggest payload, and a Fuel or Charge node copies it into a disc or arcs at `ceil` share. This inverts "Ice is anti-reach" and is only touched by HF 10.
ice#4 — 3 — The toll/shed rule and the threshold T live only in the #1444 pass proposals, so EL's "toll" cell is under-specified. The Frostbite damage point (walking does no damage) is a real minor drift from "mover hurts".
ice#5 — 4 — Afterdrop is absent from EL, and its raw landing bypasses the count cap. Whether Frost is sided is a real owner question, already flagged in #1444.
ice#6 — 3 — Shatter, drag and Afterdrop do not appear in the three phases, and the order of spenders in one settle is unstated. Minor, since shatter's design is still open.
ice#7 — 4 — Frost has no authored decay, and counts in the tens make Frozen near-permanent. The only fast counter is Heat, which contradicts "answered with content". The ambiguity in "Frozen blocks travel" is also real.
ice#8 — 2 — Duplicates HF 12 and the tick-settle question, with no new content.

## lightning.md
lightning#1 — 4 — "Ties included" (round 3) and "ties fork and split" (round 2) are both pass proposals that disagree. The flat-patch case turns Charge 1 into 4 arcs.
lightning#2 — 4 — The "media are small" bound depends on an unanswered `max_stacks` fork, and the leap radius has no numbers. Grounded in #1733 r3; EL's § Open does not list it.
lightning#3 — 4 — The self-refilling wire is an extrapolation, explicitly marked. It follows from "copies carry the payload" plus "a medium can ride", and ADR 0073 allows reach plus ride on one cast. Worth an owner call.
lightning#4 — 3 — The "absorbed" cell versus the owner's "consuming 1" is HF 7b, already known. The per-volley ledger for Charge is a small new point.
lightning#5 — 3 — Whether a Frozen node is a valid or preferred pick is genuinely unsaid. The cross-element lightning rod is a minor gap.
lightning#6 — 3 — The chained-go-off damage (#1735) and the per-attack versus per-wave scope are both known. It duplicates my #6.
lightning#7 — 3 — The reach-copy crit question is open in EL itself. The "crit multiplied by hitscan" balance angle is a nice addition.
lightning#8 — 3 — The copy's ownership filter is stated only in #1733 ("target mask filters friendlies"), not in EL. Charge's lack of a decay is real.

## landing.md
landing#1 — 3 — Rounding and crit order is HF 12, and "absorbed" is HF 7b, both already known. The proposed fix is clear.
landing#2 — 5 — The cap's unit is undefined for dual reach, the "then" order against a simultaneous read is incoherent, and the hit's Fire load plus node Fuel as two sources contradicts the owner's "node's fuel". It duplicates my #5 and is more complete.
landing#3 — 4 — The "planting hit does not trip it" scope against a pre-hit read is a real tension. Its Frost-on-Fuel point is correct per the pair table. Overlaps my #1 only in part.
landing#4 — 5 — Settle's list has no ignition, and netting before or after ignition changes a whole blast. EL calls only netting order independent.
landing#5 — 4 — Tick-time ignition on a Frozen node is unaddressed, since "never leaves" governs hits. The Frozen ring as a free firewall is a fair balance flag. Overlaps my #4 slightly.
landing#6 — 5 — The tick settle has no payload, attacker or crit, and the receive-versus-reproduce question carries a real desync risk. It duplicates my #2 and is sharper on multiplayer.
landing#7 — 4 — The id-keyed map merging BEFORE and AFTER copies is HF 13. The extrapolation that `stacks_per_hit` folds on copies and breaks R2 is flagged and worth asking.
landing#8 — 2 — Muddled. It reads #1741's "mark lifts the hits behind" as being about copies, and its mask point is already in #1733.

## First in front of the owner
1. landing#6 (tick settle with no parent hit, plus peer sync), which also covers my #2. It blocks every Fire ignition and thaw issue.
2. landing#2 (dual reach: what counts as a source, what the cap counts, and whether same-element sources merge). It is the same as my #5 and contradicts the owner's "node's fuel".
3. ice#3 (a concentrated Ice seed amplified through Fuel or Charge copies). It undercuts the triad's central claim about Ice.
Runners-up: landing#4 (net versus ignite order) and lightning#3 (self-refilling wire).

## Duplicates of mine
- landing#2 duplicates my #5.
- landing#6 duplicates my #2.
- lightning#6 duplicates my #6.
- landing#3 partly duplicates my #1.
- landing#5 partly duplicates my #3 and #4.
- lightning#7 and landing#1 overlap my #8 (crit on copies).

---

## Ratings: rate-by-ice.md

# Ratings by the Ice reviewer

fire.md#1 — 2 — Real but the spend-one-per-go-off answer is already an owner quote (#1733 r3) and shipped; only an EL wording gap.
fire.md#2 — 3 — Tick settle with no parent hit is already EL § Open (g); the friendly-fire and barrel-refill points are labelled extrapolation, so useful but not new.
fire.md#3 — 4 — Real: ADR 0067 riders are separate instances and HF 3 says no landing unit exists, so whether the Heat rider thaws before its own hit's load is read is genuinely unstated.
fire.md#4 — 4 — Real and sharp: "a blast sinks" only governs copies landing on the Frozen node, a euclidean disc from the origin reaches behind it; EL's "holds against every blast" overpromises.
fire.md#5 — 4 — Real contradiction: pair table "Fuel plus load" vs dual-reach concatenation vs owner "the node's fuel"; the same-element merge question is new (HF 7a only covers the radius).
fire.md#6 — 3 — "Per attack" vs "per wave" is already EL § Open (i) / HF 11; #1735 fork 1 is a known open owner fork.
fire.md#7 — 4 — Plausible and new: two ammo types keying one count mint independently, so the "one cap per family" is unenforced (matches HF 5 role question). The retake liability is a good readability point. I did not verify `Entity.reload_yield`.
fire.md#8 — 3 — Rider crit on uncapped Fuel is real; the "radius ~ power^0.5, 40 node-radii" figures are invented, not from a quoted passage.

lightning.md#1 — 4 — Real: ties are common at mean degree 3.1, "ties included" is a pass proposal that makes Charge 1 act as Charge 4, and round 2 (fork/split) vs round 3 (full) disagree. I did not check the degree.md self-loop claim.
lightning.md#2 — 4 — Real: the "bounded because media are small" argument depends on a `max_stacks` cap that is an unanswered owner fork; leap_radius has no numbers.
lightning.md#3 — 4 — Real and unexamined: an arc copy carries riders at ceil(r*f), and nothing stops a Charge ride row from replanting; flagged as extrapolation, honestly. Worth an owner line.
lightning.md#4 — 3 — The "absorbed" cell vs "consuming 1 at a time" is HF 7b, already known; the volley ledger point is minor.
lightning.md#5 — 4 — Real: Frozen+Charge on one node is unspecified (the pair table has rows per medium only). Overlaps my situations 1 and 6 (Frozen coexistence).
lightning.md#6 — 3 — #1735 fork and per-wave/per-attack are both already open; dual-copy overlap restates an owner tentative call.
lightning.md#7 — 3 — Already stated open in EL § The hit and HF 12.
lightning.md#8 — 4 — Real: the copy's target mask is never stated for media-triggered reach, and Charge has no decay or clock route. Overlaps my situation 7 (medium durability).

landing.md#1 — 3 — Crit/share rounding order is HF 12; "absorbed" is HF 7b. Correct but known.
landing.md#2 — 4 — Real: three reach sources, "then" in the table vs simultaneous read, and the cap's unit (landings vs go-offs) is undefined.
landing.md#3 — 3 — Partly misreads EL: the shipped exemption ("a hit that plants a medium does not trip it") already covers arrow 2 planting Fuel; the real remaining gap is the exemption's scope (same medium only?). The claim that EL "removes sparks" is not in the text.
landing.md#4 — 4 — Real: settle's list in EL omits ignition, so net-then-ignite vs ignite-then-net gives a whole blast of difference on a Frost 3 / Fuel 4 / Heat 3 node.
landing.md#5 — 4 — Real: tick-time ignition on a Frozen keg is undefined because "never leaves" is a hit rule. Overlaps my situation 6 (Frozen keg) and fire.md#3.
landing.md#6 — 4 — Real and risky: ticks are reproduced on peers today while cascades with damage are received; no tick record exists. In EL § Open (g) but this spells out the desync. Overlaps my situation 8.
landing.md#7 — 3 — HF 13 and #1741 NOTES already open; the "copies fold stacks_per_hit" extension is new but speculative.
landing.md#8 — 2 — Scattered: Hex/crit claims about #1741 are not sourced, and the mask-on-copies point duplicates lightning.md#8.
(landing.md meta-finding: no ADR 0074 exists in docs/adr, I confirmed; EL § Landing resolution is headed "ADR 0074". Score 4, a real doc inconsistency.)

## Put in front of the owner first
1. fire.md#5 (with landing.md#2): same-element reach sources, one blast or two, vs "blast power is the node's fuel". It contradicts an owner quote and fixes the dual-reach semantics for everything.
2. landing.md#6 (with fire.md#2): the tick settle has no payload, crit, mask, attacker or receive/reproduce rule; highest desync risk.
3. lightning.md#2 (with fire.md#8, lightning.md#8 and my #7): there is no medium node cap or decay, so Charge/Fuel/Frost counts of 20-50 plus crit or concentrate multipliers are unbounded. One owner call on `max_stacks` and decay settles four situations.

## Duplicates of mine
- lightning.md#5, landing.md#5, fire.md#3, fire.md#4 overlap my 1, 3 and 6 (what Frozen does to Charge, Fuel, discs and friendly hits).
- lightning.md#8 overlaps my 7 (medium durability/decay).
- landing.md#6 overlaps my 8.
- None of the three covers concentrate pricing (my 2, 3), Frostbite toll/T (my 4) or Afterdrop (my 5); no one else touched Ice's cast-time half.

---

## Ratings: rate-by-landing.md

# Ratings by the landing-resolution reviewer

fire.md#1 — 3 — Real hole (E never says how much a go-off spends), but the answer is the owner's "consuming 1" in #1733 r3 and explosive.md; only a missing line in E.
fire.md#2 — 5 — Tick-time settle with no parent hit (payload, attacker, mask, receive vs reproduce). Duplicates my #6. The unfun add-on (a Hearth blasting every tick) is flagged as extrapolation.
fire.md#3 — 4 — Landing unit: a Heat rider is its own HitInstance landing BEFORE its hit (ADR 0067, H3), so thaw-before-load-read depends on settle granularity. Adjacent to my #4 (settle order).
fire.md#4 — 4 — Euclidean disc versus a Frozen wall: the text only says what happens to a hit that lands on B. Real readability gap. Not mine.
fire.md#5 — 5 — Pair-table "radius from Fuel plus load" vs dual-reach concatenation vs the owner's "power is the node's fuel". Overlaps my #2, with the sharper same-element-merge fix. Small slip: Lightning also shares hit-load and medium type, so Fire is not the only case.
fire.md#6 — 3 — Cap scope "per attack" vs code "per arrow / wave" and the open #1735 chained damage are both already in E § Open (i), (d). The volley-5,4,3,2,1 argument is a good addition. Overlaps my #2.
fire.md#7 — 3 — Per-type independent minting by `per_reload_stat_id` is real code (`reload_yield`), but E already says the family cap and the Element Matrix are open. Retake friendly-fire is a minor note.
fire.md#8 — 3 — Crit doubling Fuel rides is the built #1741 behaviour; the unbounded Fuel is the open `max_stacks` fork. The "radius ~40" figure is a guess.

ice.md#1 — 4 — Frozen vs friendly walks (heals, cures). E says Frost blocks the freezer's own reach, but only arcs and blasts are named. New and unaddressed.
ice.md#2 — 3 — Pricing knob is in E § Open. The point that landings are not payload mass is good, but the Venom Burst arithmetic is hand-derived.
ice.md#3 — 4 — A concentrated seed landing on Fuel or Charge copies the big payload, so Ice amplifies Fire. Real and connects to H10 (Ice vs "reach only"). Related to my #7 (copies and riders).
ice.md#4 — 3 — The toll and shed rules live only in the #1444 pass proposal, and T is undefined. Real but known and flagged as pass.
ice.md#5 — 3 — Afterdrop is absent from E; its cap bypass via the raw path is a good catch. A pass-proposal item.
ice.md#6 — 3 — Shatter, drag and Afterdrop are not in the three phases, and the shatter damage has no hit (H12 family). Adjacent to my #4/#5.
ice.md#7 — 4 — No authored decay for Frost and the ambiguity of what "Frozen blocks travel" means. Counts of 20 to 50 make a wall permanent, with only Heat or a blade as counter.
ice.md#8 — 3 — Duplicates my #6 and E § Open (g); thin.

lightning.md#1 — 4 — "Ties included" (round 3) vs "ties fork" (round 2); neither is an owner call. Real unreadability.
lightning.md#2 — 3 — Critical Charge leaps depend on an unanswered `max_stacks` fork and unnumbered leap radius. Already listed as #1733 numbers in E § Open.
lightning.md#3 — 5 — Self-refilling wire: copies carry the medium rider, so each go-off replants what it spends. Genuinely new and a degenerate loop. The owner must say whether copies carry medium riders. Touches my #7.
lightning.md#4 — 3 — Pair-table "absorbed" vs "consuming 1" is already H7b and E § Open (d). The volley-ledger point is a small add. Overlaps my #1.
lightning.md#5 — 3 — Frozen plus Charged "lightning rod": a real unstated interaction, but a minor one.
lightning.md#6 — 3 — Interleaved fuse: damage per go-off (#1735) and cap scope are both open. The double copy at an overlap node duplicates my #2.
lightning.md#7 — 3 — Crit on reach copies is explicitly open in E § The hit; the hitscan-multiplier argument is a good reason. Duplicates my #1 and #8 (and H12).
lightning.md#8 — 4 — The target mask and filter of copies are unstated (the shipped bolt has an enemy filter), plus Charge never decays. Duplicates my #8.

## First in front of the owner
1. lightning.md#3 — do reach copies carry medium riders? An unbounded replant loop.
2. fire.md#5 (with my #2) — Fuel plus load vs the node's fuel vs dual reach: how many blasts and what radius.
3. fire.md#2 / my #6 — settle after a tick: payload, attacker, crit, and host-minted record (ADR 0002).
Runner up: my #3 (planting exemption vs pre-hit read).

## Duplicates of mine
- fire.md#2, ice.md#8: my #6. fire.md#5, fire.md#6, lightning.md#6: my #2.
- lightning.md#4: my #1. lightning.md#7: my #1 and #8. lightning.md#8: my #8.
- fire.md#3, ice.md#6: near my #4.

---

## Ratings: rate-by-lightning.md

# Ratings by the Lightning reviewer (fire.md, ice.md, landing.md)

fire.md#1 — 3 — Real but minor: the one-stack spend is in #1733 r3 and explosive.md, just not restated in EL's reach rule.
fire.md#2 — 4 — Tick ignition has no parent hit, so payload, crit, side mask and receive-vs-reproduce are all open. Handoff item g, but the friendly-fire blast angle is new.
fire.md#3 — 4 — Rider-before-hit (ADR 0067) against one settle per hit is the "no landing unit" gap (handoff 3). It decides whether a Heat rider thaws before its own Fire load is read.
fire.md#4 — 4 — A euclidean disc from A reaches C behind a Frozen B, so EL's "chokepoint holds against every blast" misleads. Fresh readability point.
fire.md#5 — 5 — Pair-table "one blast, Fuel plus load" against § Dual reach "every source fires, concatenated" gives different counts for the same landing. Also overran the owner's "blast power is the node's fuel". The same-element merge fix is good.
fire.md#6 — 3 — Chained-blast damage (#1735 fork 1) and per attack vs per wave are both already in § Open. It slightly misreads the cap: R3's once-per-node cap limits copies re-reaching, not direct arrow hits, so the 5,4,3,2,1 volley is not broken by it.
fire.md#7 — 4 — Per-type minting off one `fire` count (code reload_yield) contradicts "one cap per element across the family". The retake-liability point is a good extra.
fire.md#8 — 3 — Crit multiplying a Fuel rider past the count cap is plausible but depends on how #1741 applies crit to stacks, which I did not verify. Fuel node cap is already an open fork.

ice.md#1 — 4 — EL states Frost blocks the freezer's own reach. Whether a friendly heal walk counts as a "hit" is unaddressed (flagged as extrapolation).
ice.md#2 — 4 — Pricing knob is in § Open, but "ratio counts landings, not payload per landing" and the `inf`-hop spells are fresh and well-grounded.
ice.md#3 — 5 — A concentrated seed (the biggest payload) is copied by any Fuel or Charge node it lands on, so Ice becomes the best amplifier. That contradicts "anti-reach". Related to handoff 10, but this angle is not in the doc.
ice.md#4 — 3 — Toll, shed and T exist only as pass proposals in #1444 round 2. Real, but "write them into EL" is a doc task. The "hurts" claim vs #1444 I did not verify.
ice.md#5 — 4 — Afterdrop is absent from EL and its raw pack bypasses the ice cap. A gap, though sourced from a pass proposal.
ice.md#6 — 3 — Shatter, drag and Afterdrop have no settle slot. Real, minor, and the ordering is a doc line.
ice.md#7 — 4 — Frost at 40 with no authored decay is near-permanent, and a non-Fire build has no answer. Duplicates part of my #8 (no decay for Charge).
ice.md#8 — 3 — Duplicate of landing.md#6 and fire.md#2 (tick settle). Short and right.

landing.md#1 — 3 — Crit/`ceil` order is handoff 12. The "Charge absorbed" contradiction duplicates my #4.
landing.md#2 — 4 — "Then" is meaningless when read is simultaneous, and the cap's unit (landings vs go-offs) is undefined. Overlaps fire.md#5 and my #6.
landing.md#3 — 5 — A Frost arrow plants a medium, yet the table says it blasts Fuel. A literal "a hit that plants a medium does not trip it" contradicts the table, and the exemption's scope is undefined.
landing.md#4 — 4 — Net vs ignite order inside one settle changes a whole blast, and EL's settle list omits ignition.
landing.md#5 — 4 — Tick-time ignition on a Frozen keg is uncovered, since "never leaves it" is stated for hits. The cheap Frozen firewall flag is fair.
landing.md#6 — 3 — Already in § Open (g), though it is the best-argued desync case (ticks are reproduced today, cascades are received).
landing.md#7 — 4 — Id-keyed rider map merging BEFORE with AFTER is handoff 13. The new part is `stacks_per_hit` folding on each copy, which would break R2.
landing.md#8 — 4 — Mask on settle copies is a real gap, though the text is truncated in my read. Duplicates my #8.

## Put in front of the owner first (other files)
1. landing.md#3 — plant exemption vs the Frost-on-Fuel table cell (a literal contradiction in EL).
2. ice.md#3 — concentrate turns Ice into the best amplifier for Fuel/Charge copies.
3. fire.md#5 — what happens when a Fire-loaded hit lands on Fuel (one blast or two, and what sets the radius).

## Duplicates of mine
- fire.md#5 and landing.md#2 vs my #6 (dual reach / what each go-off deals).
- landing.md#8 vs my #8 (copy mask/filter).
- landing.md#1 "absorbed" vs my #4.
- fire.md#8 and landing.md#1 crit vs my #7.
- ice.md#7 decay vs my #8.
- fire.md#6 vs my #6 (per attack / per wave cap).
