# Melee blade: the orthogonal split, and the work it implies

Working file for the 2026-09-08 design thread. **Spent when its decisions have
landed in #772 / #781 / #785 and the two briefs below have been dispatched.**
Delete it then — it holds no decision whose home is not an issue.

## The principle, adopted by the owner 2026-09-08

> **nodes deal damage, edges give rigidity; spikes pop vertices, bunkers break edges.**

Two blade parts, two defensive counters, each pair disjoint. Owner: *"i like that
orthogonal split, we should adopt it officially."*

**Now recorded as [ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md)** —
read that first; it is the durable home and carries the dead grounds. This file is
only the dispatch scaffolding.

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

## Where an edge stat could live — the architectural crux of #409

**Owner, 2026-09-08:** *"stats live on 1) `Entity`s, 2) `SkillNode`s. notice how we
don't have a stat board for Edges yet. i wonder how we would cleanly model something
like edge damage at all"* — and, on an Entity-level stat: *"it would just be the same
for each Edge; so still a problem where to put it."*

Right objection: an Entity stat says *how hard my edges cut*, never *which* edges are
sharpened — and "which" is the whole content of a placed upgrade. But it decomposes:

- **magnitude is a stat** → `Entity` board (`blade_edge_damage`), where stats live.
- **placement is topology** → a **boolean on `Edge`**, never a `StatBoard`.

`Edge` gains a flag, no third stat-bearing type appears. Same shape as the node side
already: `SpikeRingAddon` *marks*, the modifier pipeline *supplies the number*.

**Still: option A — edges deal no damage at all — is the recommendation.** The above is
what to reach for *if* a sharpener is ever wanted; it makes edge damage cheap to build,
not right to have. A derivation from endpoints' `blade_damage` (min/max/mean) is ruled
out and must not be re-proposed.

**If A is confirmed, BRIEF 1 grows and simplifies:** `edge_damage` (the StatDef, the
board roster entry, `default_entity_board.tres`, the min derivation) should be
**removed**, not left at 0 — a dead derived stat mirrors a rule nobody holds. That also
makes #785's edge-vs-vertex arbitration (*"an edge emits only if it strictly
out-damages the best particle on that collider"*) unreachable, so it goes too.

## SETTLED 2026-09-08 — a bunker destroys structure, never matter

Owner: *"yes: bunkers destroy structure, never matter"*. Mapping, confirmed:
**matter = vertices/nodes**, **structure = edges**.

So on a rigid blade rammed into a bunker — where the *contact* is usually at a vertex,
since discs stick out past the capsules trimmed to their rims — the vertex **survives**
and cannot pass; the force goes into its incident edges and the edge that cannot hold
**fails**. Contact point and failure point need not be the same. A bunker never pops a
vertex; a spike never breaks an edge.

Failure criterion, for #781: the PBD distance-constraint residual **is** the strain, so
the edge that stays violated across the substeps (because the bunker will not let the
vertex move) is the one that fails. No new concept.

Full record, with the rejected alternatives and which grounds are now dead:
[ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md).

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

- **Edge Sharpener is #409**, not a new issue — updated 2026-09-08 and unblocked
  (its blocker #407 is CLOSED, delivered by #779's speed-scaled damage). `Needs design`.
- **The `blade_damage` split is deferred, not queued.** Owner: *"hence my lean to keep
  blade damage as it is right now, though we could split it cleanly."* No issue filed.
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

## BRIEF 1 — edges leave the offence and the spike system (READY TO DISPATCH)

Everything it waited on is settled. Dispatch as one Opus worker.

> You are a swarm worker on Skill Tree of Life (/home/bramh/skill-tree-of-life, repo
> Koaieus/skill-tree-of-life). Read CLAUDE.md and the `drone` skill first. Your unit:
> **make blade edges purely structural**, following up #785.
>
> **Read first, in this order:** `docs/adr/0005-blade-parts-and-counters-are-orthogonal.md`
> (the decision, with the grounds that are already dead — do not re-argue them), then the
> #785 comment thread, then `docs/handoffs/melee-blade-orthogonality.md`.
>
> The rule: **nodes deal damage, edges give rigidity; spikes pop vertices, bunkers break
> edges.** A spike destroys matter, a bunker destroys structure.
>
> **What is wrong on master.** #785 gave edges an offensive role and enrolled them in the
> spike system, both derived as the MIN of their endpoints'. Both shipped live:
> `BladePopResolver.LiveGate._blunting_for_edge` falls through `_blunting_for` to the
> `blunting` StatDef's own default of **1**, so every edge already strips a spiked
> defender's pool and severs on a full drain, with nothing authored and no addon involved.
>
> **Do — this unit DELETES more than it adds:**
> 1. **Edge hit events skip the spike gate entirely.** An edge crossing a spiked node
>    drains nothing, severs nothing, and leaves `pool.current` unchanged.
>    **TRAP — do NOT implement this as `_blunting_for_edge` returning `0.0`.**
>    `remaining >= blunting` is then always true, so it would `deplete(0)` and sever every
>    edge it touches: the #778 "zero means unfilled" gotcha, inverted. It must be an
>    explicit skip of the gate for edge events.
> 2. **Remove `edge_damage` outright** — `stats_system/defs/edge_damage.tres`, the board
>    roster entry, `entity_stat_board.gd`, `default_entity_board.tres`, and the
>    min-of-endpoints derivation. Not "leave it at 0": a dead derived stat mirrors a rule
>    nobody holds. Edges deal no damage at all. Use the `manage-stats` skill in reverse —
>    it lists every home a stat has, which is the checklist for removing one.
> 3. **Remove the anti-double-dip arbitration** in `blade_hit_scan.gd`
>    (`_resolve_step_contacts`, and the ~40 lines of rationale above it). It exists only to
>    stop one contact emitting vertex + edge + vertex damage for the same target; with no
>    edge damage there is nothing to double-count and the whole mechanism is unreachable.
>    Vertices must go back to the pre-#785 counting rule with no arbitration at all —
>    that carve-out (*"particles never arbitrate against each other"*) exists because
>    arbitrating them broke `test_ai_blade_rollout`, whose fixture overlaps the pop-EXEMPT
>    pivot with the same spiked target as a member vertex. Deleting the rule removes the
>    need for its own exception; confirm `test_ai_blade_rollout` still passes.
> 4. **Keep** `_sever_edge`, `BladeState.removed_edges` and `remove_edge()`. Only the
>    spike-drain *trigger* goes. Re-comment them as **#781's bunker seam** — a rigid blade
>    shattering against a bunker. Preserve #785's invariant: severance is recorded, never
>    spliced out of `state.edges`, so every `edge_idx` stays stable and #795's
>    one-adjacency-build-per-swing survives.
> 5. **Keep the capsule geometry** derived from the endpoints (trimmed to each disc's rim,
>    disc radius scaling with allocation level). Geometry is physics, not stats — do not
>    over-strip. Edges must still collide, because stopping a bunker entering the blade
>    interior is the entire reason they got hit-scan.
> 6. **Do NOT rename `blade_damage`.** The `blade_node_damage`/`blade_edge_damage` split is
>    deferred by the owner, not queued.
> 7. `test_ai_scoring_spike_pop.gd` carries a *"Do not swap the radii back"* docstring whose
>    stated reason — the long arm's edge would drain and sever — **evaporates** under this
>    change. Either revert the geometry to its pre-#785 form or re-justify it. A docstring
>    asserting a dead reason is worse than none.
> 8. `test_blade_edge_collision.gd` has 14 tests. **Enumerate** which survive (capsule
>    geometry, the hub rule, the adjacency-cache invariant) and re-point the
>    severance-by-drain and edge-damage ones onto the *absence* of the behaviour. Do not
>    delete a test merely to make a suite green; a test that pins "an edge crossing a spiked
>    node changes nothing" is worth more than the one it replaces.
> 9. Update `docs/domain/melee-blade-sim.md` and `docs/domain/combat/` where they describe
>    edges as offensive or as blunting elements. Post a summary to #785 and to #772.
>
> **Baselines.** Fresh worktree, no native binary: `0 failing · 3906 passed · 14 pending ·
> 421 scripts`. The 14 are correct — 1 is #771 (deliberate, do not fix), 13 are
> `test_blade_native_parity.gd` honestly reporting no binary. Your script count may DROP by
> one if a test file dies wholesale; say so explicitly if it does and justify it.
>
> Standard rules: `cd <ABSOLUTE> && <everything>` in ONE command with `pwd` as its receipt
> (cwd does not persist; backgrounded commands never inherit it); always
> `git -C <absolute>`; **never call `advisor`**; any `Explore` subagent pinned
> `model: "haiku"`; long commands backgrounded via the Bash tool's own `run_in_background`
> (a bare `&` will NOT wake you — three workers stalled that way this run); ladder `check`
> → `test:one` → `test:dir` → ONE full `mise run test`; a new `.gd` test needs its `.gd.uid`
> committed (`mise run refresh`) or it vanishes silently; never `gh --body` with backticks,
> heredoc to a file and use `--body-file`. Do not push, do not merge, do not close the
> issue — I am the merge gate. Report in your own final message: branch, tip sha, verdict
> with script count, the enumerated test disposition, and anything you left undone.

## BRIEF 2 — #186 free-flight (dispatchable NOW, independent of the ruling)

Unblocked by #778 + #779, and no longer collides with anything now that #798 has
landed. Needs a second, **unpinned** sim of the severed remainder from its positions
and velocities at disconnection, fed back into hit-scanning so the coasting fragment
still deals damage. Front-load the worker with: `BladeSim.simulate()` is pure and now
has a C++ backend (`.claude/rules/blade-native.md` — **a built `.so` is not a loaded
extension, `mise run refresh` after the first `native:build`**); `BladeState` is
struct-of-arrays; the presentation-clock and attack-timeline rules both bind; and
#785's `removed_edges` is how severance is represented.
