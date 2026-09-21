# Swarmify — charter

The design behind `.claude/skills/swarmify/SKILL.md`. The skill is derived
from this; change the wish here, then re-derive the file. See
[README](README.md) for the protocol.

## What swarmify is for

Swarmify is the **design gate** between an issue and a drone: it takes one
issue from "has open forks" to `Ready`, in an Opus session that already holds
the design, *with the owner*, before any worktree exists. It removes
blockers, surfaces every decision a drone would otherwise have to make, gets
the owner to settle each one, writes the acceptance spec, splits a hub into
children along its real seams, and moves the status.

Its output is read by exactly one consumer: a drone doing `gh issue view <n>`
and `--comments` cold, with no chat history and a bare fence. **The Ready
criterion is that such a drone can act.** Everything below follows from what
that reader needs and from what it costs when they do not have it.

## The cost argument — why discovery moves upstream

The bulk implementation side has been tuned hard (see [drone](drone.md)),
but the thing being implemented is an issue, and *what it says shapes
everything a drone does*. The postmortem corpus below put three of four
Sonnet overruns on **spec gaps** — an undeclared seam, a bundled unit, an
interaction hidden behind an adjective — not on drone error.

The economics are lopsided. Implementation discovery — which files does this
touch, what is the seam, what shape is the new class — done in swarmify runs
**once**, at Opus rates, in a context that already holds the design. The same
discovery left to the drone costs 30–100k of orientation reads, re-sent on
**every later turn** (the integral `mise run agent-cost` measures), and
re-derived by **every resume-leg** (17 of 160 drone transcripts in the
warp-vs-drone audit were bare continuations). It also crosses the wire twice
when the orchestrator does it instead — once into the orchestrator's context,
once into the brief. On the issue it crosses once, by `gh issue view`.

So the Ready comment gains four sections that carry that discovery, and the
brief is left carrying only what the issue cannot know (fence, seams this run,
tier, advisor, budget).

## Laws

Numbered so the skill can be checked against them law by law.

**The one rule**

1. **Decisions are the owner's.** Swarmify surfaces forks and proposes; the
   owner chooses; the answer is written in the owner's words, dated,
   attributed as an owner call. An agent that invents a design answer to
   reach `Ready` has defeated the purpose. If the owner is absent, draft
   proposed resolutions and do **not** move the status.

**Reading and verifying**

2. **RTFC is the session's own job.** The issue body *and* every comment, in
   the session, never summarised by a subagent — a later comment routinely
   corrects an earlier one, and the summary is where that dies.
3. **Verification is delegated, once.** Every claim the issue makes about the
   code ("X is unbuilt", "Y has no caller", "that helper was deleted") is
   checked against `master` by one `Explore(model: haiku)` carrying the whole
   claim list, reporting verified / false / stale with a `file:line` each.
   Fact-checking is not thinking; skipping it specs work against a world two
   commits stale. A stale item closes with a doc correction, not new work.
4. **Arithmetic on pinned values.** After pinning anything numeric, compute
   what it implies at both ends of the range (level 1 and 100, one node and
   two hundred). The fix that surfaces is usually structural, and it
   surfaces from the numbers.

**Forks**

5. **A fork is anything a drone would have to decide.** Floated alternatives,
   speculative asides riding a decision, unstated acceptance, unowned
   surfaces (two plausible implementations landing on different modules means
   the *approach* is undecided), cross-issue dependencies. Enumerate them
   numbered, in prose or `AskUserQuestion` when they are clean choices.
6. **A second decision never rides a first.** Split it out — its own child,
   its own sibling, or a NOTES line — before promoting.
7. **An unsettleable fork keeps the issue in `Needs design`.** "Still blocked,
   here is why" is a valid outcome. Never promote an issue a drone will stall
   on.
8. **A dependency is recorded, not disqualifying.** Cross-issue dependencies
   go in as `gh` `--blocked-by` relations *and* in the spec prose; the
   orchestrator sequences them. Only a dependency on a decision nobody has
   made keeps an issue out of `Ready`.
9. **File ownership is a map, not a gate.** Record which paths a unit touches
   so the orchestrator can sequence; never contort the design to keep files
   disjoint, never withhold `Ready` because two issues share a file.

25. **Three questions on every plan, before any code exists** — *who owns
    this fact? is this one thing pretending to be N? what does it cost per
    frame / at scale?* A unit about to read another unit's internals, a list
    of per-type cases that is one callback, a per-tick recompute that a
    stored sample makes an array read — each is a fork, and each is
    answerable from the plan sentence. The owner catches these by glancing
    at a plan; the pass must catch them without the glance.

**The Ready comment — sections**

10. **Decisions, files touched, acceptance, NOTES** — the established four:
    each resolved fork as a one-line settled fact; the paths the work lands on
    (naming any sibling that shares one); the failing test to make green or
    an exact behavioural spec; descoped asides parked for their own issue.
11. **Reading list.** 5–15 entries of `path:start-end — why`, headed by the
    master sha it was written at. "Read these, nothing else" — the successor-
    brief shape that works for retiring drones, applied at the start. Not a
    file map, not a tour: each entry names what the reader will learn there.
    Omitting what should be skipped, rather than listing it, unless a specific
    trap must be named.
12. **Seam map.** Every file the change touches, **including files that
    merely reference the thing** — a scene that instances the node, a board
    `.tres` that must gain a null-guard, a sandbox panel that lists the
    system — derived by grep in the same Haiku Explore as law 3, never by
    recall. Each entry is a whole-file entry in the drift stamp (law 15).
13. **Stubs on master before dispatch**, when the unit adds classes or
    signatures and swarmify judges the arch fork worth settling in code:
    `class_name`, method signatures, and the red test file **committed under
    `pending()`** so trunk stays green. The drone's first commit flips the
    pending to RED and confirms it ran; red-green stays the drone's. One
    `mise run refresh` on master instead of one per worktree; Sonnet's job
    becomes fill-in. Swarmify commits these itself, explicit paths, after
    `git status` — the main checkout is shared and may hold a peer's WIP.
    **A stub is a proposal.** A drone that finds the stub wrong says so on
    the issue and goes against it with a stated reason; that is leeway the
    corpus shows drones use well.
26. **Composition, written down.** A few lines of prose or a small diagram:
    which class owns which fact, what it exposes, who reads it, what is
    deleted by name. What cannot be written up concisely cannot be coded
    cleanly; a Composition that will not come out is a fork still open.

14. **Shapes and seams, not bodies.** The line is signatures, seams, reading
    list, red tests. If swarmify writes the implementation, Sonnet adds
    nothing and Opus has done the work at planning rates without isolation.
15. **The drift stamp.** The reading list and seam map sit in one fenced
    block whose first line is the master sha they were written against. That
    sha makes staleness deterministic: `mise run issue-drift -- <n>` parses
    the latest stamp on the issue, diffs `<sha>..master` with `-U0`, and
    reports every entry whose range a hunk intersects (whole-file entries
    match any hunk). Silent, exit 0, when nothing drifted; exit 0 with the
    drifted entries otherwise; exit 0 with `no stamp` on an unstamped issue —
    it is clipped onto the orchestrator's dispatch command and must never
    abort that chain. Only when it reports drift does a Haiku Explore
    re-verify. A diff is cheaper than a model. The block's exact shape is
    the contract between the skill and the task:

    ````
    ```drift-stamp <master sha, 7–40 hex>
    path/to/file.gd:120-180 — what the reader learns here
    path/to/scene.tscn — seam: instances the node
    ```
    ````

    One entry per line: `path`, optionally `:start-end`, then ` — ` and free
    text. The fence info string is the parse key; anything else in the
    comment is prose. Body and comments are scanned in order and the last
    stamp wins, so a re-swarmified issue simply posts a new one.
16. **Verify at write time.** Every reading-list `path:range` is confirmed to
    exist and to say what the entry claims (the Haiku Explore of law 3, or
    a `sed -n` of the range), or it is a stale spec with extra authority.
17. **The more, the better — by judgement, never by silence.** Any serious
    issue is decked out with every section. Omitting one is a stated call
    written on the issue: "no seams", "exploratory / docs", "few-turn patch,
    the drone finds the edits faster than we write the list". Issues promoted
    before this charter carry no stamp; `issue-drift` says so and moves on.
18. **The brief restates nothing.** If the session finds itself thinking
    "the orchestrator will explain that part", the issue is not `Ready`. Test
    before promoting: read body and `--comments` cold, as a Sonnet with no
    chat history would, and ask whether a single unsettled fork remains.

**Hubs**

19. **A parent never carries work.** On split, *all* of the hub's work moves
    into children — including the hub's own defect, as "child 0". The hub
    keeps the problem statement, the decisions, the DAG. Its status is never
    set by hand; `land` and `hygiene --fix` derive it.
20. **Split along the seam the design has**, one decision one unit; where
    that is also a file boundary, say so; where it is not, split anyway and
    record the overlap. **A unit describing three or more deliverables is
    split before dispatch**, not left for a drone to self-split.
21. **A follow-up not required for the hub to be done is a sibling**, linking
    back, never a child.
22. **Shared-file work every child touches** (one `.tres`, a registry append)
    is the orchestrator's pre-step in the main checkout, not parcelled out.

**Promotion**

23. **`Ready` is the admission ticket**: status move, `design`/`blocked`
    labels dropped in the same breath, a milestone set (Ready without one is
    a hygiene violation), then `hygiene` kept clean — the board is the
    queue; there is no separate decisions-queue issue to update.

**What swarmify is not**

24. **Not implementation** beyond law 13's stubs. **Not a rubber stamp.**
    **Not a spawn** — the thinking runs in the session with the owner; only
    law 3's lookup is delegated.

27. **Every child is drone-sized.** Roughly one subsystem, a handful of
    files, one test file — finished under ~150k drone context. Size by
    files × subsystems × tests before promoting; a unit touching more than
    three subsystems or needing more than five tests is split along its
    state / wiring / consumer seams *at swarmify time*, never after it
    stalls. Prefer more small children with native `blocked-by` over one fat
    one. A drone is reused only for a tiny follow-up ("add this class" → "use
    that class"); one that just did a 200k run has no room left.

28. **An architectural fork is settled in the pass, not parked.** Two classes
    doing one job, a stage doing another's work, a mirror of logic that
    already exists — present it as seams with options and costs and get it
    settled now; refactor-first ordering is the default, and the delay cost is
    said out loud. Owner, 2026-09-10, overriding a recommendation to park the
    "is Step stealing propagation's role" question in a design issue so a
    tooltip could go Ready: *"settle now, may become a hub or large refactor.
    paramount is: cleanliness, clean arch, good separation, SOLID, you know
    the stuff that makes you go 'wow yeah duh' if the split is so correct that
    it's almost boring."* An unsettled seam leaks into every consumer written
    against it. The owner's stated taste, for shaping the options:
    - **Composition as a plural array**, never a singular parent link or
      inheritance vocabulary — #279 shipped `@export var inherits: CoreClass`
      as its own spec pinned and was reopened (*"composition over inheritance,
      then literally a drone decides to add 'inherits'? if it were an
      'extends' array though"*); `composes: Array[...]` is the settled shape
      (`extends` is a GDScript keyword). A singular chain forces independent
      batches into an arbitrary nesting order; the stat pipeline stacks
      modifiers natively, so "weaker" is a negative modifier, never a replace
      rule.
    - **No parallel mirrors of logic** — before proposing an accessor or
      substrate layer, enumerate what the existing class already answers
      (*"the SkillNode answers all these (owner_of / hp_of / local_value /
      apply_damage / die), so we'd end up implementing the same logic 3
      times"*). One implementation over swappable state beats two
      implementations of one contract; parallel copies drift silently and the
      drift surfaces as gameplay divergence between the live and the
      AI/preview path.
    - **Graph vocabulary is exact** — see `docs/domain/graph-vocabulary.md`.

## Incident corpus

Each law traces to at least one of these. Kept here so the skill does not
have to carry them.

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-08-02 | #332 / #165 hubs | reading two comment threads in-session caught a comment retracting an earlier one's central claim; the same pass burned ~8 calls on pure lookup (is #322 closed, is #339 filed, does `keystone_placement.gd` carry `node_scene`) — the last exposed #330 sitting in `Ready` with an open fork in its body | 2, 3 |
| 2026-08-02 | label collapse | the `swarmable` label retired; `Ready` became the queue; a `design` label left on a `Ready` issue is the drift the collapse was meant to end | 23 |
| 2026-09-11 | #847 | a publish-a-Release pre-step lived in a post-review comment and rewrote acceptance 7 — fine, because it was on the issue, dated, the owner's | 1, 18 |
| 2026-09-11 | #857 | the Ready criterion stated: a drone given only the number, its comments and a fence can act | 18 |
| 2026-09-14 | #879 status-tick | four sub-units (sparse tick, clear-on-dealloc, resync, docs) bundled in one brief; +29% calls, Sage exchanges over cap; the drone "sound throughout" — bundling was the cost | 20 |
| 2026-09-14 | #888 tempo-pool | the fence omitted `scenes/dev_sandbox.tscn` / `melee_sandbox_graph.tscn`, which the new pool touched; found mid-flight, +69% calls and a review round-trip | 12 |
| 2026-09-14 | #878 status-hit | an `AttackRecord`/crit-draw interaction hidden behind "shadow-safe", surfaced only in Sage review; +34% | 11, 16 |
| 2026-09-14 | #766 mana-rework | the one in-budget Sonnet unit: single mechanism, narrow fence, 75 calls | 14, 20 |
| 2026-09-14 | #872 status-def | the cheapest unit by every measure was the tightest-fenced foundation with nothing upstream to reconcile against | 13 |
| 2026-09-15 | hubs (#729/#901) | "hub that is also a bug" vs "hub that is only a container" kept tripping agents and `hygiene`; owner chose "a parent never carries work" | 19, 21 |
| 2026-09-15 | warp-vs-drone audit | 17/160 drone transcripts open with a bare "continue"; per-file parity with warp, the tax is coordination and fragmentation — every resume-leg re-derives orientation the issue could have carried | cost argument, 11 |
| 2026-09-15 | #902, owner | "the more the better; every section met is a happier / more effective drone … some issues have little to no seams, or no reading list because they're exploratory / docs, or small patch jobs … any *serious* issue should ideally be decked out best we can. stubs too — depends on the issue / judgment. a wrong attempt at a stub needs the drone to realize and go against it, which often happens (drones make excellent value judgement calls)" | 13, 17 |
| 2026-09-16 | #928 → #930/#931 | the camera 2-step was fixed inside the director by reading the blade's `state.pivot_index`, `get_node_visuals()` and a vertex's alpha; the test had to poke those to move the goalpost. The owner caught it from a glimpse of the plan — "opportunity: decouple the director from what it follows by letting the (alive) melee blade provide some %Marker2D" — and the sim storing its own centroid. Seven such redirects in seven days (#889, #900, #910/#917, #927, #928, #930, #931), all answerable from the plan, none from the diff | 25, 26 |
| 2026-09-17 | owner | "if you can't write it up cleanly (potentially concise, get the idea across) you won't be able to code it up cleanly either" — the Composition section | 26 |
| 2026-09-15 | #902, owner | stub shape: stubs + `pending()` test on master, so trunk stays green and red-green stays the drone's first commit; drift range-aware and exit 0 always; charter written in the pass, three children | 13, 15 |

## What the skill must not contain

- Any row of the table above, any issue number, any date.
- The cost argument. The skill says "reading list", "seam map", "stubs",
  "drift stamp" as instructions with the template; why they pay is here.
- Worked examples and "why this is a rule" paragraphs. Each law states the
  next action; the charter holds the why.
- Restatements of the board rules (`docs/domain/issue-workflow.md`) beyond the
  commands the pass runs.

## Open follow-ups

- `swarm` wants the same charter treatment: 1171 lines, still frames opencode
  as the primary harness though the repo has no opencode config, and its
  dispatch section should say `Agent(subagent_type: "drone", model: <tier>)`.
- Whether the Haiku Explore of law 3 and the seam grep of law 12 should be one
  dispatch or two is a per-pass call; one is cheaper, two lets the seam grep
  start before the claims are listed.

| 2026-09-10 | #764 / #849 | Recommended parking an architectural fork in a design issue; owner overrode — settle now, refactor-first hub with three children. | 28 |
| 2026-09-14 | last 2–3 swarms | Drones hitting 300k+ on oversized units; a "plumbing" issue spanning five subsystems was the shape that did it. #872 → #872/#878/#879 is the split that worked. | 27 |
| 2026-08-24 | #573 | "`test_meta_routing_parity.gd` still passes unmodified" was unsatisfiable — the deletion half of the same issue removed `class_name`s the test cast to, so it stopped *parsing*. A characterization pin enumerates the surviving assertions and says the test may be re-pointed; then asks whether there is anything to re-point onto yet. | 10 |
