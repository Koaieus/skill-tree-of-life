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
- A parallel session, "⚡ Settle swarm-train forks"
  (`session_01Jiczcx3oXtUEXBU9snkRQt`), was started at 00:14 on sections A–H
  below. It reported having checked all eight and was waiting on answers for G
  and E. It wrote no `settled:` note to the whip ledger and sent the top no
  message, so **assume nothing in A–H is settled unless an issue comment from
  that session says so** — read its transcript or the issue comments first.

## Progress and how to continue (working doc; update it every session)

One group per session, in this order. Done groups are cut from A–I below and
listed under their "Settled" heading.

| # | Group | Items | State |
|---|---|---|---|
| 1 | Catalyst | A, B-S3, B-S5, the Catalyst leftovers in D and H | **settled 2026-11-19**, see below |
| 2 | Lightning / conduct | H #1806 (a `terminal` child conducts on), H #1808 (conduct on a Frozen + Shocked node), G #1806 knobs and its two flagged behaviours | open |
| 3 | Ice | G #1813 B / C / a, G #1807 L, G #1811 (who greys a refused Ice), the core-on-a-Frozen-node issue filed 2026-11-19 | open |
| 4 | Fire / Burning | B-S2, G #1805 (vertex-copy spend), H "G-b retired pin", H "F4 build caveat", E #1805 | open |
| 5 | Forge / overclock / ammo | G #1812 U1–U3, G #1814 and its H item, G #1809 and its H items, G #1811 (point-split UI, wedges), H #1811 (arrow colours), G #1804 | open |
| 6 | Housekeeping (mostly no owner call) | C, the rest of D, F, I; E is the owner's own eyeball list | open |

**How a session runs** (the owner's ask, 2026-11-19): pick the next group;
write its context and game situations in plain words with real numbers
(*"the latter here also determines if code/issues aligns with my vision"*);
then one `AskUserQuestion` per situation, scored; file through one subagent;
update this doc. Practicalities learned in session 1:

- **Context.** The skill, rules and one closed issue body put session 1 at
  160k before the first question. Do not read a closed issue's body in full;
  ask the Haiku Explore for the owner's sentences. Start asking by ~180k.
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
| 4 | _filled by the filing pass_ | Ready |
| 5 | | Ready |
| 6 | | Ready |
| 7 | | Ready |
| 8 | | Needs design |
| 9 | | Needs design |
| 10 | | Needs design |
| 11 | | Needs design |

## Already settled tonight (for reference, not to re-argue)

| Call | Where |
|---|---|
| Fast-forward PR #1823 onto master ("Ff", 20:31) | landed `badc87b8` |
| A refused arrival leaves a primed node alone; same rule for a dud arrow | #1802 issuecomment-6992682229; built as F4, `cd360db5` |
| #1827: stage one decides an undecided arrow/blade head's crit | #1827 comments; built `2c413636` |
| Blade copies carried raw coefficient (B1) | fixed as a side effect of #1804; pinned by `test/unit/attack/test_blade_go_off_copy_speed.gd` |
| `SaveFile` v15, minimum v15 (pre-retag saves refused) | `2f43068c` |

## A. Catalyst over its cap

When a gate flip or a stake extract lowers the cap, nothing re-trims the row,
so the authority can hold an over-cap row. Re-trim on the drop, or keep? Note
fixer rv-S4 (`320381ce`) made snapshot restore keep the row as sent, with no
cap trim, so a re-trim rule has to agree with that. The "re-trim order" was
also parked by relief-a-5.

## B. Sim findings from the Fable review (intended, or a defect?)

- **S2:** Burning's disc pays Heat for nodes the hit's mask skips.
- **S3:** `catalyst_resistance` below 100% has no effect.
- **S5:** Catalyst on a cracked core's entity host ticks per holder turn and
  never converts.

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

- **review-adr L8:** a `docs/design` forge.md passage sits against ADR 0095 §4
  — which one gives.
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
- **Blade:** `BladeState.remove_vertex` now marks every edge on a popped vertex
  removed, so `SwingResolve._fire_fuse` no longer pops / `severed_at`s an edge
  whose vertex died earlier — pinned by a test, intent unconfirmed.
  `vertex_shielded` was removed against the #1802 body because it had no
  caller.
- **G-b** retired one go-off pin with no Burning replacement: "a copy sets the
  same node off again a generation later".
- **Design leftovers:** the anti-blade face has no home (aspect_matrix is
  annotated); Catalyst's inner-tree T3 signature is "open"; whether the
  Poison/Catalyst opposition axis still holds; #1596 and #1211 still carry
  Explosive titles.

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
