# Owner forks after the 2026-11-18 swarm-train (runs #1824, #1825)

Input for a swarmify / design session. Everything here is something the train
built around, picked tentatively, or could not verify — nothing below is an
owner call yet unless it says so. Compiled by the train's top session from the
leads' session reports; no item was re-verified against master by the top, and
the train kept landing all night, so **check each against current master
first**.

- Final master: `6e8ffd25`, pushed. Gate there: suite 0 failing / 7642 passed /
  1 pending / 910 scripts; `mp:e2e` green, 0 divergences.
- Closed tonight: #1799, #1800 (PR #1823), #1801–#1814, #1816, #1826–#1829,
  hub #1716.
- Run reports: `docs/handoffs/whip-report-2026-11-18.md` (run #1824),
  `docs/handoffs/whip-report-2026-11-18-2031.md` (run #1825).
- Lead ledgers (their "Needs the owner" sections are the source of this file):
  `docs/handoffs/archive/swarm-2026-11-18-{lead-a,2031-lead-a,relief-a-1,relief-a-2,relief-a-3,relief-a-4,relief-a-5,relief-a-6}.md`.
- Fable review files: `docs/handoffs/swarm-2026-11-18-relief-a-2.inbox/done/`
  (review-sim, review-dead, review-adr, review-blade, …).
- Where things stand and what to do next: "Progress and how to continue" below.

## Progress and how to continue (working doc; update it every session)

One group per session, in this order. Done groups are cut from A–I below and
listed under their "Settled" heading.

| # | Group | Items | State |
|---|---|---|---|
| 1 | Catalyst | A, B-S3, B-S5, the Catalyst leftovers in D and H | **settled 2026-11-19**, see below; ADR gate run (one record, 0096) |
| 2 | Lightning / conduct | H #1806 (a `terminal` child conducts on), H #1808 (conduct on a Frozen + Shocked node), G #1806 knobs and its two flagged behaviours | **reopened as a design talk 2026-11-20**: start at "Next session starts here" below |
| 3 | Ice | G #1813 B / C / a, G #1807 L, G #1811 (who greys a refused Ice), #1837 (a core and a Frozen node) | open |
| 4 | Fire / Burning | B-S2, G #1805 (vertex-copy spend), H "G-b retired pin", H "F4 build caveat", E #1805 | open |
| 5 | Forge / overclock / ammo | G #1812 U1–U3, G #1814 and its H item, G #1809 and its H items, G #1811 (point-split UI, wedges), H #1811 (arrow colours), G #1804 | open |
| 6 | Housekeeping (mostly no owner call) | C, the rest of D, F, I; E is the owner's own eyeball list | open |

**How a session runs** (the owner's ask, 2026-11-19): pick the next group;
write its context and game situations in plain words with real numbers
(*"the latter here also determines if code/issues aligns with my vision"*);
then one `AskUserQuestion` per situation, scored; file through one subagent;
update this doc. Practicalities learned in session 1:

- **Context: delegate first, ask early** (owner, 2026-11-20: *"the ADR
  stuff consumed like 150k tokens without us getting into anything useful
  yet … some very suboptimal decisions were made this session of not
  offloading research or mechanical work (=writing ADRs) to subagents even
  before i got my first response in"*). Session 1 reached 160k and session 2
  over 200k before the first question: session 2 read eight open issue
  bodies itself and drafted an ADR in the main thread. The main session reads
  this doc and nothing else in full. In its FIRST turn it sends, in
  parallel: one Haiku Explore for the code facts, one subagent for any ADR
  gate or ADR drafting, one for issue and comment reads (owner sentences
  verbatim). Filing goes to one subagent. First question by ~80k.
- **GitHub from a cloud session.** `gh issue view` and `mise gh-project` fail
  (GraphQL 403); `gh api repos/Koaieus/skill-tree-of-life/issues/<n>` (REST)
  and the GitHub MCP tools work. Lanes cannot be moved from there: each filed
  issue's body opens with `Intended lane:` and the owner moves it.
- **The lead ledgers and the Fable review files this doc cites are not in the
  repo** (untracked on the owner's machine). The checks below replace them.
- **Numbers for situations.** T = 2 × a node's graph degree; cap = k × T;
  k = 2 + stake level (bare ground 3). Heat, Cold and Charge past the cap
  stay (the overflow band); nothing trims them.

**What the "⚡ Settle swarm-train forks" session found** (it checked A–H
against `f8792f5b`, settled nothing, posted nothing; the owner never saw it):

- G: the landed code matches every tentative pick listed. Its one
  recommendation against the code: a `terminal` child that lands on a Shocked
  node keeps walking (`spell_resolver.gd:415`, `hops_remaining <= 0 and not
  conducted`), against `propagation_pick.gd:49-50` "never propagates on".
- C: D1, D2 and D3 are still dead on master. It held D2 and D3 back because
  #1812 and #1806 "might want the hook"; both are closed now, so that ground
  is gone.
- D: the `forge.md` passage is half stale (the barrel, fixed 2026-11-19) and
  half a tension ADR 0095's revisit-when anticipates ("each vertex carrying
  an authored innate load"); no ADR is contradicted.
- E: #1805's sandbox check cannot be done as written: no sandbox-host tab
  shows Burning, and the Terrain tab's StepTurn runs only the temperature
  flow, never a burn tick. A real level is the alternative.
- F: fire-like SVGs sit in the game-icons cache only (`lorc/small-fire`,
  `carl-olsen/flame`, `sbed/fire`, …); each needs a `mapping.txt` line and a
  bake.
- H: the blade `remove_vertex` item is a deliberate fix (`e54e963b`, pinned by
  `test_fuse_on_a_dead_vertex.gd`) and is cut from H below.

## Next session starts here — group 2 is a design talk (owner, 2026-11-20)

The owner reopened two Lightning rules, and one Fire rule with them. Ask Q1
and Q2 before anything else; #1838, #1839's wire case and the vertex spend all
hang on them. Plain words and real numbers first, then one `AskUserQuestion`
per question, scored. The facts below were checked at `5b5d6cb9c` (session 2);
re-verify only what an option turns on.

### The rules as built, in numbers

- **T** = 2 × a node's graph degree. **Shocked** = Charge > T. The cap is
  k × T (k = 3 on bare ground), and past it the overflow decays 2 per world
  turn instead of 1.
- **The arc**: any hit on a Shocked node, a copy included, sets it off. It
  reaches every node within L hops; L = 1 above T, 2 above 4T, 3 above 9T
  (`elements/edge_go_off.gd:30-36`, `ladder_exponent` 2, `max_level` 3). A
  copy that lands on another Shocked node sets that one off in the same hit,
  so a string of Shocked nodes cascades. Each node goes off at most once per
  hit (ADR 0094 §1). It pays 1 Charge per node reached and **moves** that
  Charge onto the reached node (ADR 0084 §7, `spent_charge_goes_to` = Reached
  node; Void is the knob's other value). So an arc voids nothing; only decay
  removes Charge.
- **Fire's disc** pays 1 Heat per node it reaches and **voids** it (ADR 0084
  §7: *"Burning and Frozen keep the void"*). A disc that reaches nobody pays
  nothing and is no go-off (`elements/disc_go_off.gd:15`, `:82`).
- **Conduction**: the spell's own projectile lands on its target node. If
  that node is Shocked and the spell picks next targets, the walk leaves
  without spending a hop (even at 0 hops left), and the node pays 1 Charge,
  voided (`attack/outcome/hit_gather.gd:372-379`;
  `attack/spell/spell_resolver.gd:433`; `conduct_cost` 1 on
  `elements/defs/lightning.tres:21`, `:29`). The spell's children can fan out
  to several targets there, as at any landing. Only the projectile's own
  landing conducts: an arc or a Lightning shape's reach never does. The walk
  visits each node at most once (`max_visits_per_node` 1).
- **A blade vertex** copies a primed state for one swing. Its copy pays 1 per
  node reached, voided; that spend is the only thing that stops the vertex
  going off again on a later contact of the same swing (*"a later contact
  arcs only while the copy stays > T"*, `docs/domain/elements.md` §
  Lightning; the same rule for a Burning vertex in § Fire).

**Owner history the questions revisit** (verbatim):
- Conduction: *"elec - hops -> 1D (lines)"* (2026-11-06); *"i forgot i
  designed that as a feature. it's rather powerful, not spending a hop. but
  might be just what it needs"*, then *"i agree with that lean."* (2026-11-10,
  `docs/design/elements/go-offs.md:208-210`).
- Transfer: *"knob, transfer by default"*, because *"decay is 1 per charged
  node. if it voids 4, they are gone. if it spreads them to 0 charge nodes,
  they are gone by next tick. if more charge is at play, more things can
  happen, chain effects, priming mid hit or after, all reads as *very* STATIC
  DISCHARGE i must say"* (2026-11-10, `docs/design/elements/terrain.md:217-219`).

### Worked example: a wire of four (the pass's reading of the rules, not run)

A chain X – A – B – C – D – Y; every node has degree 2 (T 4). A, B, C and D
hold Charge 6 each (Shocked, 1-hop arc); X and Y hold 0. A chaining spell's
projectile lands on A with 1 hop left.

- **The cascade, in one hit.** A arcs to X and B: it pays 2 and each gains 1.
  The copy on B sets B off; B arcs to A and C, so A takes the payload again
  but does not go off again. C goes off, then D. X, A, B, C, D and Y all take
  the payload; A, B and C take it twice. A, B, C and D each pay 2 and gain 1
  or 2: A 5, B 6, C 6, D 5, **all still Shocked**. X and Y end at 1.
  Of 24 Charge, 22 is still on the wire and none was voided.
- **Conduction on top.** A is still Shocked after the cascade (5 > 4), so
  the walk leaves A with its hop unspent; A pays 1 (5 → 4, down to T, so it
  is no longer Shocked). The spell fans out to A's neighbours; its
  wave-2 child on B sets B off again (a new hit), which sets off C and D
  again. The walk then conducts from B for free, and so on along the wire,
  while each node stays over T.
- So **one cast re-runs the whole cascade once per wave**, and the wire
  barely drains, because the arcs move Charge instead of spending it. That is
  the owner's "doubled-up" (Q1) and "can things settle" (Q2) in one picture.

### Q1. Keep conduction, or cut it?

Owner, 2026-11-20, verbatim: *"i'm kinda wondering whether conduction should
be kept, or that it makes it all too doubled-up strong. like: say a shocked
(primed) node takes a hit, and it has a string of 3 neighbors that are also
shocked. the arcs from the initially hit node will hit & set off the other 3
charged neigbors too as one big cascade (all as receivers for that *one* hit
with varying degrees of how many times each node receives the hit's
payload). do we ALSO need to let spells walk on through them at no cost?
where each walk could potentially split in N new spell hits (spell instance
can fan out at each landing point when determining next targets)"*

Options to put (the pass's, unscored until the talk):
- **Cut it.** Lightning's line identity is the arc alone (the arc's hops are
  the "1D lines"); a spell spends hops on a wire as anywhere. Falls away:
  `conduct_cost`, `HitInstance.walk_spreads` / `conducted`, the resolver's
  `not conducted` term, `PropagationConfig.mint`'s `conducts`,
  `test/unit/spell/test_shocked_conduction.gd`; **#1838 closes as moot**;
  #1839 loses its wire case (its review of the old spell movements stands).
  It reverses the owner's 2026-11-10 lean, so it needs a superseding ADR.
- **Either, not both.** On the projectile's own target, a Shocked node
  either goes off (the arc) or conducts the walk, never both in one landing.
  This keeps the wire for anyone's magic and removes the doubling, but a
  second rule now decides which one happens.
- **Keep, as built.** The doubling is the fantasy, and Q2's void rule is what
  bounds it.

Note for the talk: cutting conduction also removes the question of what
conduction costs (session 2's open item 4).

### Q2. What does a go-off pay, and where does it go? (Fire and Lightning)

Owner, 2026-11-20, verbatim: *"so for payment when goes off, i'd say: * void
AT LEAST 1, always. it's the condition that things can settle at all *
transfer 1 to each nb (lightning), or pay 1 per hit node (fire); possibly
these are to be unified into both lightning and fire pay OR they both
transfer"*

The finding to lead with: Fire already voids everything it pays, so "void at
least 1" only bites on **Lightning**, whose arc today voids nothing; that was
the owner's own 2026-11-10 pick, for chains (quote above). On the wire
example, a 1-void floor per go-off drains the wire by 4 per hit (A, B, C and
D each void 1). A Charge-6 node on T 4 then stops being Shocked after about
two hits that set it off, instead of only through decay.

Options to put (the pass's):
- **Floor of 1, elements keep their verbs.** Every go-off voids 1, then pays
  per reached node in its element's way: Lightning moves 1 per reached node
  (total cost reached + 1), Fire voids 1 per reached node (its floor is
  already met when it reaches anyone). Open within this option: does a
  go-off that reaches nobody still void its 1?
- **Both void.** Lightning's arc voids like Fire's disc: a data change
  (`spent_charge_goes_to` = Void on `lightning.tres`). Chains come only from
  Charge that landing riders bring in. Settles fastest; loses the "static
  discharge" feel the owner wanted on 2026-11-10.
- **Both move, plus a floor.** Fire's disc moves Heat onto the nodes it
  reaches (fire spreads), plus the 1-void floor on both. That is new code
  for Fire and the most heat in play (Heat also diffuses on the world turn).

The blade vertex (session 2's open item 5) belongs here. Owner, 2026-11-19:
*"Maybe vertex just doesn't spend? It's a temporary blade node right? Exists
only during the few second swing"*. Finding: with no spend, every contact of
one swing goes off at full reach. The same pick covers Fire's vertex (group
4, G #1805).

**Where the answers land.** Q1 cut / either-or and any Q2 change supersede
ADR 0084 §7 (and 0081's pay rule if Fire changes) — a subagent writes that
ADR. #1838 waits on Q1 (a comment on it says so). Then file the build issues
through one subagent.

## Settled 2026-11-19 — Catalyst (owner calls, session 1)

Each is the owner's, 2026-11-19, in an `AskUserQuestion` pass; quotes are
verbatim, "picked" names the option chosen. Issue numbers: see the table at
the end of this section.

1. **Catalyst has no side.** *"100% sideless. Virtually all Aspect statuses
   are. The sole exception i think is Scouted, which has a "for which
   team/player/entity" field (effectively its grouping key for stacks
   thereof …)"*. A defender spending an attacker's crystals is intended.
2. **A goo arrow into a Burning node paints the disc** (picked *Keep*): its
   copies carry the Catalyst rider, as copies are hits.
3. **No aspect owns "punishes a blade"** (picked *The elements cover it*): a
   struck node's primed state is the answer.
4. **The cap limits gains only** (picked): a cap that drops takes nothing
   away, and a landing on an over-cap node adds nothing and removes nothing.
   Was A.
5. **Any priming converts** (picked *Yes, any priming converts*): a threshold
   that drops under a node's count (a gate closing) converts its crystals
   like any other priming. Found in session 1 by code read
   (`terrain_settle.gd`, the crossing reads one T for before and after).
6. **Catalyst resistance goes**: *"I think catalyst resistance may best be
   removed"*. Was B-S3.
7. **A faced Dormant Core's resistance to its own status is** *"25 50 100%"*
   by size (it was 5.0 / 10.0 on a fraction stat: 500% / 1000%, every face).
8. **A cracked core carries its Catalyst**: *"If a node is hit, any checks on
   catalyst count should simply use the combined node+entity stack counts for
   it. The core will take it with it like a movable catalyst holder that will
   generally create bad shit around them (fires, shocks, frozen states)."*
   The entity's crystals count on the node the core sits on, only (picked).
   Was B-S5. Spend order, the entity row's decay clock and its look are open.
9. **The barrel, a blade vertex and the T3 signature are one design
   question**: *"Option 1 would be converting it to some kind of "catalyst
   producing" thing (not much of a 'barrel') but option 3 for reshaping "what
   does catalyst do when copied onto a blade node?" (Does it mint stacks on
   hit or does it amplify elemental stacks done iff blade node carried an
   element (which they normally dont? Or should set something up for..?) or
   does it only trigger on primed nodes minting that many new stacks?)"*; the
   signature *"Needs to be rethought along with what blade node crystals
   do/don't."*
10. **The opposition axes are re-paired**: *"Re-pair. Catalyst isn't doing
    damage nor strictly multi-target as explosive was, it amplifies any
    element (0D ice .. 2D fire)."*
11. **Asked, not answered** (group 3): *"can entity cores move through frozen
    nodes? Or nah? Or what if they sit on a node that gets frozen? Completely
    locking in the entity if its core node is frozen might be brutal, but
    making the frozen nodes impassable sounds kinda funny"*. No doc answers
    it.

Filed (lanes are intended; the board was not reachable):

| Call | Issue | Intended lane |
|---|---|---|
| 4 | #1830 | Ready |
| 5 | #1831 | Ready |
| 6 | #1832 | Ready |
| 7 | #1833 | Ready |
| 8 | #1834 | Needs design |
| 9 | #1835 | Needs design |
| 10 | #1836 | Needs design |
| 11 | #1837 | Needs design |

Calls 1–3 are recorded on #1801; #1596 and #1211 are retitled Catalyst.

**ADR gate on calls 1-11** (session 2, 2026-11-19): call 4 is
`docs/adr/0096-…` (§1 the owner's pick, §2 the tentative clamp at intake).
Call 5 needs none: ADR 0082 §5 already says *"the node primes by any route"*
(owner, 2026-11-09), so #1831 is a fix. Call 8's record is owed by the pass
that settles #1834's forks (it refines 0024 and 0066). Calls 6 and 7 are a
stat-roster call and a knob; the rest are game design or open. Noted on
#1830, #1831 and #1834.

## Group 2 — Lightning / conduct (session 2, 2026-11-19; not finished)

Checked at `5b5d6cb9c`: every claim the group makes holds. One correction:
`ElementBand.conduct_cost` defaults to 0; Lightning's two bands author 1
(`elements/defs/lightning.tres:21`, `:29`).

**Settled**

1. **The four knobs stand as pass defaults**, all editor exports:
   `ladder_exponent` 2 (the owner's L²), `max_level` 3,
   `spent_charge_goes_to` Reached node (the owner's *"knob, transfer by
   default"*, 2026-11-10), `conduct_cost` 1. Not asked.
2. **A held Frozen + Shocked node conducts nothing and pays nothing.**
   Settled from the owner's 2026-11-08 words, *"ice wins — frozen solid"* and
   *"trapped until broken"*; put to the owner as settled on 2026-11-19, no
   objection. Was H #1808. Filed #1838 (intended Ready).
3. **A dead-end child on a wire** (owner, 2026-11-19): *"2 wins in simplicity
   (one rule), 1 is also good but maybe we should instead reconsider those
   "dead end" mechanics and basically most if not all of the unique spell
   movements put onto aspect spells before the element concept was introduced
   given elements add s major inflection to hit topology/AoE"*. Option 2 was
   "the wire carries anything, as built"; option 1 was "a dead end ends the
   walk even on a Shocked node". Pass reading, tentative: as built stands
   until the review, which is #1839 (intended Needs design). Was H #1806.

**Superseded by the 2026-11-20 design talk**: the two questions left open
here (does a conduct that leads nowhere pay; does a blade vertex's copy spend)
are now part of Q1 and Q2 under "Next session starts here".

## Already settled tonight (for reference, not to re-argue)

| Call | Where |
|---|---|
| Fast-forward PR #1823 onto master ("Ff", 20:31) | landed `badc87b8` |
| A refused arrival leaves a primed node alone; same rule for a dud arrow | #1802 issuecomment-6992682229; built as F4, `cd360db5` |
| #1827: stage one decides an undecided arrow/blade head's crit | #1827 comments; built `2c413636` |
| Blade copies carried raw coefficient (B1) | fixed as a side effect of #1804; pinned by `test/unit/attack/test_blade_go_off_copy_speed.gd` |
| `SaveFile` v15, minimum v15 (pre-retag saves refused) | `2f43068c` |

## B. Sim findings from the Fable review (intended, or a defect?)

- **S2:** Burning's disc pays Heat for nodes the hit's mask skips.

Source: `review-sim` in the review folder.

## C. Dead code: delete or keep

- **D1:** `GoOff.lands_on_own_node` can no longer be false in production.
- **D2:** DiscGoOff's leftover `Power` enum, `power_source` and world plumbing.
- **D3:** `HitGather._append_reach`'s element-less path.
- (D4 removed, `e8852ca3`. D5 verdict by a drone: keep `LoadBag`, ADR 0070
  seam — confirm.)
- `GoOffResult.nodeless_cost` / `spend_at_read` were kept because a live rule
  still uses them.

## D. Docs against ADRs

- **review-adr L8:** `forge.md`'s "each vertex carrying an authored innate
  load" sits against ADR 0095 §4 (a vertex copies only a primed state) —
  which one gives.
- Stale ADR text the #1816 drone found: 0067 §2, 0075 §2, the 0060 index row
  (posted on #1816). ADRs are immutable; decide supersede vs leave.
- ADR 0094 says the batch-4 options "were not recovered"; the #1816 drone did
  recover them and posted them on #1816. They are unpicked.
- `spell-propagation.md` is over the rules-hygiene fat-doc size.

## E. Visuals nobody has looked at

Every look below was built and tested by code only.

| Issue | What to eyeball | Where |
|---|---|---|
| #1805 acc. 4 | Burning burns its holder and lights the node | sandbox host (issue was In review, then closed by trailer — confirm state) |
| #1801 | crystal look; conversion pulse tinted by dominant element; crystals vs HP-bar fade, terrain bars, fog | level |
| #1806 | the arc layer, hop count, a Shocked vertex reading as charged | Blast tab / level |
| #1807 | frost crust, Frozen vertex hue and overlay, the pop; shatter shards sized by excess, the hold ring | sandbox-host Blast tab (Ice excess slider, Ice break / Ice hold buttons, several zooms); spell playground |
| #1808 | trapped Charge on the node's bar and tooltip | level |
| #1811 | element arrow looks, ammo cards `stock/cap +gain`, shape/ride sockets and greys | level |
| #1812 AC7a/AC12 | shape-alone disc mark (code-read only, no fixture, no screenshot); range preview | sandbox |
| #1813 AC8 | sandbox check not run | sandbox |
| #1814 | "+N" overclock pip, muted look, notices; a hovered PROPAGATION node shows no pip because it mounts `footprint_ring` | level |
| #1804 | FAST/SLOW floater suffix | level |

## F. Missing art

Heat, Cold and Charge addons have no icon (`identity/defs/heat.tres` etc.);
the armed badge falls back to the plain melee one, and the ride-line badge is
parked. Two #1809 fixtures zero the element counts, which hides the gap.

## G. Delegated and tentative picks to confirm or revisit

**Made under your delegation**
- **#1804** (issuecomment-6992760004): go-off source rides the head
  (`HitInstance` overridable method), raw amount stamped in `stage_one`. Fable
  pick, recorded as tentative.
- **#1805** (issuecomment-6992629059): split into #1805 / #1828 / #1829;
  vertex-copy spend = 1 per node the combined disc reaches (you did not answer
  this sub-fork).

**Made by drones or written tentative in specs**
- **#1806** (issuecomment-6993939300): `ladder_exponent` 2, `max_level` 3,
  `spent_charge_goes_to` Reached node, `conduct_cost` 1. Conduct cost is paid
  on arrival even when the spread then picks nothing. Combined-case transfer:
  the copy's stacks beyond the node's own level are voided (not pinned).
- **#1812 U1:** per-head carrier; shape-alone mark named by band identity; a
  muted Frozen seed gives shape-alone for both elements; a break adds the shape
  into the released go-off (untested); `Element.shape_power_per_point` 5.0.
- **#1812 U2** (issuecomment-6995857469): preview shows the shape's own reach
  only (no add-up on a primed seed); a hovered preview skips the would-be
  caster; the Fire ring is not fog-gated. **U3:** shape-line wording, 0.1
  rounding.
- **#1813 B** (issuecomment-6995768230): only `LoadBag` riders scale by ×m
  (the spell's own on-hit statuses, `power_from` riders, `CleanseUse` do not);
  ×m applied once at cast, so additive hop progressions are not exactly ×m
  later; heals scale by ×m too; the cut sits on `HitInstance.hops_removed`,
  not the spec's `HitLanding`.
- **#1813 C** (issuecomment-6996050021): `FrozenAdmits.shatter_excess_per_hop_cut`
  1.0 (name and value not yours); refusal wording; several breakers' cuts
  summed in one burst (built, not pinned); only the seed head carries the cut;
  the shatter read as Ice's 0D go-off; a gain-0 concentrate row with innate > 0
  still cuts by its innate; the shape socket greys a refused Ice.
- **#1813a:** `ConcentrateUse.bonus_per_hop` 0.5; `hops_removed` returns 0 on
  0 or inf hops; a refusing row adds no tooltip line.
- **#1814:** pre-pick cap = best eligible caster's cap; muted look on the
  committed target only; aim-lock trims once at lock; AI overclocks from
  FIGHTER; `infusion_capacity_per_degree` 5; `infusion_capacity` now defaults
  to 10 instead of INF. **C** (issuecomment-6995963770): pip and muted-look
  knobs (offset/size 14, red with "!" suffix, desaturation 0.7, alpha 0.55),
  notice copy and lifetime, role tint multiplies the pip colour.
- **#1811:** who greys a refused Ice; the shape/ride point-split UI
  (unspecified in the spec); element wedges staying in the aspect chooser.
- **#1807 L** (issuecomment-6996051363): every export on `ice_break.tscn` and
  `ice_hold.tscn` is untuned; the hold cue fires on any unbroken landing on a
  Frozen node, even a plain direct hit; a cue has no generation, so a chained
  break plays at the beat's head, ahead of the blast stagger.
- **#1809:** starter counts default to 1; forge shape and ride fields.

## H. Behaviour questions the train flagged

- **#1806** issuecomment-6994269941: a `terminal` spell child still conducts on
  from a Shocked node, though terminal says it "never propagates on".
- **#1808** issuecomment-6994913730: a spell walk's conduct is not muted, so on
  a Frozen + Shocked node that holds, it pays `conduct_cost` out of the trapped
  Charge. The pair table is silent.
- **#1809** issuecomments 6994987931, 6995031923: the arrow gallery caps
  element volleys at 2; the AI turn is now reload, launch, reload, launch.
- **#1811:** element arrows fly in their status colour (Heat/Cold/Charge), not
  the element colour the spec names, so lightning and goo differ by shape only.
- **#1814** issuecomment-6995903066: a candidate with a lower raw-damage
  estimate but a bigger cap is still cut from the AI top-K because
  `cheap_estimate` ignores the fill (matters once the scorer values the fill).
- **F4 build caveat** (an estimate, unverified): deciding the gate before the
  beat's gather means two contacts of one beat both read the pre-beat state.
- **Blade:** `vertex_shielded` was removed against the #1802 body because it
  had no caller.
- **G-b** retired one go-off pin with no Burning replacement: "a copy sets the
  same node off again a generation later".

## I. Small code follow-ups left unfixed (wind-down, no new drones)

- `HitGather._shape_band` is private but called from `magic_attack_plan.gd`
  and repeated in `ReadoutLines._disc_of`: lift to a public seam such as
  `Element.shape_go_off()`.
- `elements/element.gd:24`: the `addon_scene` comment still carries an issue
  number.
- `issue-drift` misses a line range that moved because lines above it changed
  (three drones hit it independently); workaround is `git diff --numstat`. The
  tool is not fixed and no feedback was posted for it.
- Every `land` tonight failed first on "Could not find type" and passed after
  `mise run refresh` in the rebased worktree plus a second land (posted:
  discussions/1366#discussioncomment-19720948).
- `agent-cost --main` reports the shared top session, so per-lead cost columns
  in the ledgers are approximate or empty.
- Worktrees left in place, not the train's: `.worktrees/wt-lint1-rename`,
  `.worktrees/wt-lint1-shadow` (#1648 salvage), two
  `.claude/worktrees/bridge-cse_*`; possibly `wt-rv-*`, `wt-d1805`, `wt-d1826`,
  `wt-d1828` if relief-a-2's teardown missed any.
