# Melee blade: the orthogonal split, and the work it implies

Working file for the 2026-09-08 design thread. **Spent when its decisions have
landed in #772 / #781 / #785 and the two briefs below have been dispatched.**
Delete it then — it holds no decision whose home is not an issue.

## The principle, adopted by the owner 2026-09-08

> **nodes deal damage, edges give rigidity; spikes pop vertices, bunkers break edges.**

Two blade parts, two defensive counters, each pair disjoint. Owner: *"i like that
orthogonal split, we should adopt it officially."*

Why it is worth stating as a rule rather than a preference:

- **Derived edge damage collapses a build decision.** A truss and a chain with the
  same nodes differ only in their edges. If an edge's damage derives from its
  endpoints, triangulating for rigidity *also* multiplies damage — rigidity
  double-dips, and "add a node for offence, add an edge for structure" stops being
  a real choice. This is why the answer is **no derivation**, not a gentler one.
- **Owner's lever test.** Two spiked balls on a lever deal massive damage naturally;
  the beam between them dealing massive damage *"orrrr no that makes no sense??"*
  An edge is not a blurry average of its neighbours. Allocation level makes it
  starker: a level-3 node carries +9 flat / x4.5 mult, and none of that should leak
  into the beam hanging off it.
- **Owner on the defensive half:** *"the edge between them? never really had anything
  to do with spikes"* — *"edges gained hitscan mostly just to keep bunkers from
  entering a blade then going chaos mode."*

**Precision:** "edges carry no stats" is about *stats*. The capsule's **geometry**
still derives from its endpoints — #785 trims it to the rim of each endpoint's disk,
and disk radius grows ~8px per allocation level. That is physics, not offence. Do
not over-strip it.

## Vocabulary (owner correction, 2026-09-08 — use this wording)

"Spikes depleted" means **the defence is gone and nothing pops any more.** Owner:
*"any blunting element that smashes into the spiked defender will pop UNLESS the
spikes have been removed through blunting."* So `blunting` is what an attacking
vertex spends to strip the defence, and it usually dies doing it. Never say "an edge
drains a spike" — under the split an edge is not a blunting element at all.

## Spacing luck: RESOLVED, not a concern

Owner 2026-09-08, verbatim:

> "say a blade's front sweeps past the spiked node, vertices going just around it […]
> missing the spiked defender with the top 2 corners of the `M`, the blade continues
> moving on and the 'central-bottom corner vertex' might very well hit the spiked
> defender -- popping in the process, shattering the blade in twain. lucky miss? not
> a thing. if it doesn't hit the front, it might hit a 2nd or 3rd layer of a blade.
> blades be floppy as heck, *intentionally* threading the spiked-defender needle
> would be close to impossible, players wouldn't bet on it. […] so many moving parts
> it's almost guaranteed to hit, and if not, no biggie"

This **supersedes #772's "the outcome is currently decided by spacing luck"** section
and settles #785's acceptance 2. A blade is a multi-layer floppy body; a spiked node
in its path is hit by *something*. Threading is not a strategy, so the gap is not
counterplay and not a defect — it is noise below the resolution the player acts at.

**Therefore #785 acceptance 2 is rewritten, not struck:** spacing luck for *bunkers*
(an obstacle slipping between vertices into the blade interior, then chaos) was the
real defect and is fixed by edge capsules. Spacing luck for *spikes* is a non-issue
and no longer an acceptance criterion.

## OPEN — the one question still on the owner

A fully clamped (rigid) blade rams a bunker. Vertices are discs and stick out past
the capsules trimmed to their rims, so **the contact is usually at a vertex, not an
edge.** Under "bunkers break edges", what breaks?

**Recommendation: the bunker destroys structure, never matter.** Contact at a vertex
is a collision, not a kill; the vertex survives and cannot pass. The force goes into
its incident edges, and the edge that cannot hold **fails**. So the bunker's victim
is always an edge even when the *contact* is at a vertex — contact point and failure
point need not be the same, which is what makes the split survive this case intact.

Read as gameplay: **a spike destroys matter, a bunker destroys structure.** Ram a
rigid truss into a bunker and it disassembles into a floppy chain — it keeps every
node and loses its ability to transmit force to the tip. Rigidity is the payoff and
the exposure, which is exactly the frame #772 already landed on.

Implementation note if this is chosen: the failure criterion falls out of PBD for
free. The distance-constraint residual **is** the strain — an edge whose constraint
stays violated past a threshold across the substeps (because the bunker will not let
the vertex move) is the one that fails. No new concept needed.

Alternatives, so the choice is real:

- **B — the bunker pops the contacting vertex.** Simplest, most readable hit feedback,
  but bunkers then do both jobs and the orthogonality is gone the day it is adopted.
- **C — shed one incident edge per contact** until the blade is floppy enough to flow
  around the bunker. The discrete version of the recommendation; more legible per-hit,
  needs a rule for *which* incident edge (most-strained is the natural pick, which
  collapses it back into the recommendation).

Sub-question either way: does a bunker ever pop a vertex? Recommendation says **no** —
vertices die only to spikes, full stop.

## Work this implies

### DAG as of 2026-09-08 17:40

master `cf50b73` (local; **push held** — `16f794a docs(focus)` beneath it is not the
swarm's commit). Suite: fresh worktree, no native binary `0 failing · 3906 · 14
pending · 421 scripts`; main checkout with binary built + `mise run refresh`
`0 failing · 3919 · 1 pending · 421`.

| issue | state |
|---|---|
| #778 #790 #795 #798 | merged, closed |
| #779 | merged, **open** — third test parked on #771, closing is an owner call |
| #785 | merged, **in-review** — awaiting BRIEF 1 below |
| #797 | merged, **in-review** — premise dissolved, see below |
| #186 | Ready, unblocked, no longer conflicts with anything |
| #771 | Ready — popped swing scores 3.0 when true EV is 0.0 |
| #780 #781 #782 | blocked on #785's ruling; #781 additionally on the bunker question |

Not in the DAG yet, to be filed:

- **Edge Sharpener Addon** (`Needs design`) — the only thing that ever raises an
  edge's `edge_damage` above 0. Park this on it: a *sharpened* edge cuts but still
  does not interact with spikes, so it sweeps over a spiked node unharmed. That makes
  sharpened edges **the anti-spike weapon** — plausibly the intended counter (spike
  investment answered by a different investment), plausibly a hole. Decide deliberately.
- **`blade_damage` → `blade_node_damage` / `blade_edge_damage`** (`Ready`) — an owner
  leaning, deliberately NOT folded into BRIEF 1. `edge_damage` is already 0 by default,
  so the substance is a broad mechanical rename across StatDefs, #779's speed curve,
  fixtures, procgen pools and localization. Queuing it in front of #780/#781/#782 is
  rebase debt for all three.
- **Analytic narrow phase for `BladeHitScan`** — #785 measured ~21600 physics queries
  per resolve at 100 vertices / 197 edges. Deliberately not done there: it would make
  the module encode target geometry.

### #797 changed what the perf conversation is about

There is no 2.4 s of deliberation. An AI turn on the 4-node fixture is **4979 ms wall,
32.8 ms of compute** (46.5 ms forced-GDScript); **654 of 707 frames are parked on the
presentation clock**, swing playback alone 80% of the wall. Within one resolve:
solver 4%, `BladeHitScan` 22%, and the outcome build+apply pass — DamageInstance loop,
`OutcomeSchedule.compile`, `CritRoll.decide_all`, `OutcomeApplier.apply` — **71%**.
#798 bought 0.3% of the turn.

Caveat stated on the issue: master moved, so the AI now *attacks* on that fixture
where at `ce9256c` it submitted `end_turn` only, and ~4 s of the 5 s is playback the
original measurement never had. Whether an NPC should pay full swing playback and
per-allocation reveal beats is a **pacing** decision, not a perf bug. Time-slicing
stays off the table — owner, 2026-09-08: the playtest laptop *"reached maybe 20-30fps
on average"*, so an AI turn has no idle budget to slice into.

## BRIEF 1 — edges leave the spike system (dispatch once the ruling lands)

> You are a swarm worker on Skill Tree of Life (/home/bramh/skill-tree-of-life, repo
> Koaieus/skill-tree-of-life). Read CLAUDE.md and the `drone` skill first. Your unit:
> **make blade edges orthogonal to spikes**, following up #785.
>
> **The rule, adopted by the owner 2026-09-08:** *nodes deal damage, edges give
> rigidity; spikes pop vertices, bunkers break edges.* Two blade parts, two defensive
> counters, each pair disjoint. Read the #785 comment thread and
> `docs/handoffs/melee-blade-orthogonality.md` before touching code.
>
> **What is wrong on master.** `BladePopResolver.LiveGate._blunting_for_edge` returns
> the MIN of the two endpoints' `blunting`, and `_blunting_for` falls back to the
> `blunting` StatDef's own default of **1** for any unfilled slot. So every blade edge
> already strips a spiked defender's pool and severs on a full drain, with nothing
> authored and no addon involved. Owner's own math: a 10-node blade goes from ~10 spike
> interactions to ~19, a truss more. Worse than a rate change — on a chain, severing
> edge *k* disconnects everything past *k*, so it also doubles the attacker's failure
> surface while halving the defender's pool life.
>
> **Do:**
> 1. Edge hit events **skip the spike gate entirely**. An edge crossing a spiked node
>    drains nothing, severs nothing, and leaves `pool.current` unchanged.
>    **TRAP — do NOT implement this as `_blunting_for_edge` returning `0.0`.**
>    `remaining >= blunting` is then always true, so it would `deplete(0)` and sever
>    every edge it touches: the #778 "zero means unfilled" gotcha, inverted. It must be
>    an explicit skip of the gate for edge events.
> 2. **Keep** `_sever_edge`, `BladeState.removed_edges` and `remove_edge()`. Only the
>    spike-drain *trigger* goes. Re-comment them as **#781's bunker seam** — a rigid
>    blade shattering against a bunker — which is what they are for under the split.
>    Preserve the invariant #785 pinned: severance is recorded, never spliced out of
>    `state.edges`, so every `edge_idx` stays stable and #795's one-adjacency-build-
>    per-swing survives.
> 3. Leave `edge_damage` exactly as it is: min-of-endpoints, default **0**. It is only
>    ever raised by the future Edge Sharpener Addon. Do NOT rename `blade_damage`.
> 4. Keep the capsule **geometry** derived from the endpoints (trimmed to each disk's
>    rim, disk radius scaling with allocation level). Geometry is physics, not stats.
> 5. `test_ai_scoring_spike_pop.gd` carries a "Do not swap the radii back" docstring
>    whose stated reason — *the long arm's edge would drain and sever* — **evaporates**
>    under this change. Either revert the geometry to its pre-#785 form or re-justify
>    it. A docstring asserting a dead reason is worse than none.
> 6. `test_blade_edge_collision.gd` has 14 tests. **Enumerate** which survive (capsule
>    geometry, the hub rule, `edge_damage` min, the adjacency-cache invariant) and
>    re-point the severance-by-drain ones onto the *absence* of the behaviour. Do not
>    delete a test to make a suite green.
> 7. Update `docs/domain/melee-blade-sim.md` and the #772 thread's model.
>
> **Baselines.** Fresh worktree, no native binary: `0 failing · 3906 passed · 14
> pending · 421 scripts`. The 14 are correct — 1 is #771 (deliberate, do not fix), 13
> are `test_blade_native_parity.gd` honestly reporting no binary. Gate on 0 failing and
> script count ≥ 421.
>
> Standard rules: `cd <ABSOLUTE> && <everything>` in ONE command with `pwd` as its
> receipt (cwd does not persist; backgrounded commands never inherit it); always
> `git -C <absolute>`; **never call `advisor`**; any `Explore` subagent pinned
> `model: "haiku"`; long commands backgrounded via the Bash tool's own
> `run_in_background` (a bare `&` will NOT wake you — three workers stalled that way);
> ladder `check` → `test:one` → `test:dir` → ONE full `mise run test`; a new `.gd` test
> needs its `.gd.uid` committed (`mise run refresh`) or it vanishes silently; never
> `gh --body` with backticks, heredoc to a file and use `--body-file`. Do not push, do
> not merge, do not close the issue — I am the merge gate. Report in your own final
> message: branch, tip sha, verdict with script count, the enumerated test disposition,
> and anything you left undone.

## BRIEF 2 — #186 free-flight (dispatchable NOW, independent of the ruling)

Unblocked by #778 + #779, and no longer collides with anything now that #798 has
landed. Needs a second, **unpinned** sim of the severed remainder from its positions
and velocities at disconnection, fed back into hit-scanning so the coasting fragment
still deals damage. Front-load the worker with: `BladeSim.simulate()` is pure and now
has a C++ backend (`.claude/rules/blade-native.md` — **a built `.so` is not a loaded
extension, `mise run refresh` after the first `native:build`**); `BladeState` is
struct-of-arrays; the presentation-clock and attack-timeline rules both bind; and
#785's `removed_edges` is how severance is represented.
