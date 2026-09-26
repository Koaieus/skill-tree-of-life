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
   proposed resolutions and do **not** move the status. Two things are
   *not* inventing: writing down an answer the owner already gave in the
   issue or the prompt (law 31 — re-asking it is the failure), and
   defaulting a tunable value behind a knob (law 32 — a value is not a
   design answer). An owner's "no real forks" / "your call" delegates the
   picks: make them, attribute them as the pass's tentative calls, promote.
   The delegation covers what survives law 31's review — "no real forks" is
   itself a claim, and a genuine law-5/28 fork the review turns up is still
   asked, leading with the finding.

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

29. **Read the room: design before forks.** After reading the issue, ask
    what is actually open — *how to build it* or *what would be fun*. When
    the blocker is the second, every fork enumerated now is a fork on the
    wrong thing. Switch hats: put the game-designer hat on and **diverge**
    first — several candidate mechanics, each with the player fantasy it
    serves, what it does to the loop, and which existing system it leans on,
    grown from both ends (a concept looking for gameplay, a wanted feel
    looking for its model; `docs/design/*.md` open questions and
    `design`-labelled issues are the stub lists to check before inventing).
    Write bolder than usual — the low-temperature default is right for code
    and wrong for this beat; a reach in the designer direction is the ask.
    No seams, no costs, no file paths until the picture is clear, and
    **the owner says when it is clear** (law 1). The design conclusion lands
    durably — `docs/design/` or a dated, owner-attributed comment on the
    issue — before the cold pass starts; then forks, seams and the spec as
    usual. The two beats are never mixed in one message.

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

30. **The cleanest option is the default, and every option is scored.**
    When a fork resolves to "A, sorta clean" against "B, hella clean but
    more work", B is the answer in 99% of cases — the codebase grew this
    large for a solo owner and stayed maintainable by taking the cleanest
    path every time, refactor size notwithstanding, and later drones land
    work fluently on plumbing that was built on the spot instead of deferred
    as YAGNI. So: the `(Recommended)` tag sits on the cleanest option unless
    a stated reason moves it; the cost of the clean option is said out loud,
    never used as the tiebreaker; and the owner still sees every option
    (law 1 — the default changes, the choice does not). To make the choice
    cheap to read, each option carries one **scorecard line** with a fixed
    axis order, cleanest option first:

    ```
    clean ★★★★☆ · smell: none · perf ★★★★★ · blast ●●○○○ (4 files, 1 sys) · taste ★★★☆☆
    ```

    - **clean** — separation, single owner of each fact, SOLID, no mirror of
      existing logic (the law-28 taste list is the rubric).
    - **smell** — `none`, or the smell named in three words (reads another
      unit's internals, N cases that are one callback, parallel copy).
    - **perf** — per-frame / at-scale cost from law 4's arithmetic.
    - **blast** — files and subsystems touched, tests to re-point.
      **Informational only**: it never demotes an option or moves the
      Recommended tag; the owner takes it to the chin every time.
    - **taste** — both senses: slick code is slick, and the pick reads
      like this codebase would have made it (the law-28 taste list, the
      house idioms). A tiebreaker after the others.

    Then one sentence of what the option buys and one of what it costs.
    Equal cleanliness across the board is worth saying — it means the fork
    is about something else. A scorecard is a compression of reading, not an
    addition to it; the prose that used to argue the ranking is replaced by
    the line, not joined by it.

    "Cleanest" is not "most": the problem at hand has a shape its solution
    fits best — a signal, a system, a bespoke resource with subclasses, a
    shared shape already in the tree — and the pass is on the lookout for
    that shape, not for the largest refactor. The tell that it has been
    found is that something else *falls out for free* — a consumer that no
    longer needs a special case, a test that writes itself, a sibling issue
    that closes. Name it when it happens; a pick where nothing falls out is
    worth a second look. Swarmify sessions shape the whole codebase, so this
    is where the weight sits. Where to look first, in the order the corpus
    ranks them: a **duplicated fact to collapse** into one owner (a status
    derived instead of set, a delta stored instead of an absolute, a gate
    read once), then an **existing path to route through** (the same
    builder, material, command channel), then a **composition** whose union
    produces the behaviour — and only after those a new system or resource
    hierarchy, which almost never yields one. A free thing is a fact, not a
    verdict: it has gameplay consequences as well as codebase ones, and the
    designer hat names both (an emergent mechanic nobody authored is a
    free thing that later got killed for exactly that).

**Honouring what the owner already said**

31. **The owner's input is already an answer.** Every shape the owner put
    in the issue body, a comment, or the `/swarmify` prompt — however
    rough, however scribbled — is an owner decision, not a note to be
    re-confirmed. On the first read, sort each owner sentence into one bin:
    **stated decision**, **claim about the code** (→ law 3), **tunable**
    (→ law 32), or **genuinely open** (→ law 5). A stated decision gets a
    **mini internal review** — verified against the code, consistent with
    the owner's other sentences, law 4's arithmetic holds, law 25's three
    questions pass. If it passes, write it back as settled, quoting the
    source sentence, with one line of why it is sound ("you asked for X;
    that is clean because Y — taken as settled") — and **never echo it back
    as a question**. It becomes an ask only when the review *finds
    something*: a contradiction, a stale premise, a smell, a cheaper-and-
    cleaner shape the owner would want to hear about. That ask leads with
    what the review found. The owner would rather be asked than watch a
    silent wrong turn, so the guard is "review, then settle", never "never
    ask" — but a question whose best answer is the owner's own sentence
    read back is a round-trip bought for nothing, and it reads as not
    having listened.

32. **A knob is defaulted, not asked.** A tunable — a size, a timing, a
    ratio, a threshold, a count — where any sensible value ships
    and the owner tunes it by feel later, is not a fork. The discriminator:
    **if changing it would move a file, a class, or an owner-of-fact, it is
    a fork (law 5); if it changes a number on something that already
    exists, it is a knob.** "Is there a cap?" is a fork; "what is the cap?"
    is a knob. A number the owner already stated is still a knob — their
    value is the default, exported all the same. For a knob, the pass picks a sensible default (law 4's
    arithmetic at both ends), records it in Decisions as a tentative pass
    pick — not an owner call — and says it is easy to change. It also
    **specifies the DX that makes it easy**, since that is what "easy to
    change" means: an `@export` (with `@export_range` when bounded) on the
    `@tool` node or `.tres` that owns the value, never a `const` buried in
    a script, and for a visual knob, instant editor feedback — a setter
    that redraws in the editor, or a live sandbox-host tab. The acceptance
    names the knob and its default; tests assert the behaviour the knob
    parameterises (ratios, invariants, a sweep), not the literal default,
    so retuning never reds a test. A knob's *home* follows the house rule
    for its kind: a stat rate is a modifier's `value`, then a stat
    (`docs/domain/stat-knobs-and-bins.md`); a glow is a named tier, never a
    hand-picked HDR float (`hdr-color.md`); per-instance shader variation
    rides `modulate`/`INSTANCE_CUSTOM`, never a per-node uniform
    (`rendering-performance.md`). This law covers the layout, visual,
    timing and feel tunables those leave to an `@export`.

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
| 2026-09-26 | #1125 → #1126 | told "`/swarmify` this, i assume no real forks", the pass picked `MIN_SEGMENT_PX := 12` and `DIAGONAL_SHARE := 0.5` itself, marked them tentative on the issue, and told the owner "they're easy to change". Owner: "that's excellent. leaving design knobs while not harking over details, just put sensible defaults and enable enough DX that tweaking them is easy in the godot editor. most often an exported variable, ideally with instant editor view feedback (if it's a visual thing)". The picks shipped as `const`s on `TraceRouter` — easy in code, not in the editor; the DX half is what law 32 adds | 1, 32 |
| 2026-09-26 | owner, status-fx sandbox tab (#1114) | the prompt asked for every status effect represented with controls and specific existing tooltip panels always visible; the pass asked "should the panels be visible", "do you want to reuse the existing panels", "do you want all status effects" — "like seriously asking me this? but then again, rather they ask than silently head in the wrong direction". Owner: an agent "should just better report on what's good, if the idea is clean, and if it clearly is (like a mini internal review) then just write that out" | 31 |
| 2026-09-10 | #764 / #849 | Recommended parking an architectural fork in a design issue; owner overrode — settle now, refactor-first hub with three children. | 28 |
| 2026-09-14 | last 2–3 swarms | Drones hitting 300k+ on oversized units; a "plumbing" issue spanning five subsystems was the shape that did it. #872 → #872/#878/#879 is the split that worked. | 27 |
| 2026-08-24 | #573 | "`test_meta_routing_parity.gd` still passes unmodified" was unsatisfiable — the deletion half of the same issue removed `class_name`s the test cast to, so it stopped *parsing*. A characterization pin enumerates the surviving assertions and says the test may be re-pointed; then asks whether there is anything to re-point onto yet. | 10 |
| 2026-09-22 | owner | "read the room for when an issue is more about designing before serving forks … put your Epic Game Designer hat on and when the picture becomes clear, then we talk code plans, forks to settle, with the cold hard specs and technical seam maps … sometimes crank up the LLM temperature" | 29 |
| 2026-09-22 | owner | "when a fork can be settled with 'this option A which is sorta clean' and 'this option B which is hella clean but costs more work' then that's gonna be a B in 99% of cases … This project for a solo dev grew this big yet stayed so maintainable due to our aggressive combating of tech debt … you wouldn't know how much stuff landed by drones that used plumbing that was already there just because what could've been deferred as YAGNI instead was implemented on the spot"; asked for a stars ranking on cleanliness plus blast radius ("which we take to the chin every time"), effectiveness, good practices, lack of smell, perf, style secondary — "swarmify is often a lot of reading and thinking in which i could use all help i can get" | 30 |
| 2026-09-22 | transcript scan (318 sessions, 681 `AskUserQuestion` pairs; `.claude/skills/swarmify/corpus/2026-09-22-askq-scan.md`) | 106 pairs turned on a clean-vs-cheap axis; owner picked cleaner 49 vs cheaper 33 (~1.5:1), even within `/swarmify` runs. Where the agent's `(Recommended)` tag and the owner's pick disagreed on that axis, the owner pushed toward *more* work 9 times and toward less 5 — the tag was under-recommending cleanliness. Sonnet-labelled, directional not exact. Two side patterns: perf ("how many nodes, how fast") is the real tiebreaker at least as often as cleanliness; and the owner routinely answers a menu by redirecting the premise or synthesising a new option — options are a prompt to think aloud, not a strict menu, so a scorecard must survive an "Other" answer | 30 |
| 2026-09-22 | owner | "100% and we don't need to go overboard. Usually the problem at hand has a certain shape of solution that works best, add a signal? Add a system? Add a bespoke resource and or set of subclasses? A shared shape? Just be on the lookout … these swarmify sessions basically shape the entire codebase.. so they bear some weight. Or i love it when we discuss and then agent mentions something along the lines of '… and then XYZ *falls out* for free' like those nifty picks are often just style and clean architecture high fiving" | 30 |
| 2026-09-22 | transcript scan (318 sessions, 227 regex hits, 75 genuine "falls out for free" moments; `.claude/skills/swarmify/corpus/2026-09-22-fallsout-scan.md`) | enabler: single-owner-of-fact 31, shared-shape-reuse 17, composition-array 8, data-driven 4, resource+subclasses 1, new system 1 — free-riding comes from deleting a duplicate representation or routing through what exists, almost never from adding abstraction. What fell out: feature-for-free 21, consumer-simplifies 19, special-case-removed 12. Three "free" claims were false or a smell ("self-loop-blind for free" asserted in four places incl. flavour text; "bulk grows for free with level" as the defect); Cyclone's parity detector was free, unauthored, and later cut. 58 of 75 in swarmify passes. Steady rate, no trend | 30 |

## What the skill must not contain

- Any row of the table above, any issue number, any date.
- The cost argument. The skill says "reading list", "seam map", "stubs",
  "drift stamp" as instructions with the template; why they pay is here.
- Worked examples and "why this is a rule" paragraphs. Each law states the
  next action; the charter holds the why.
- Restatements of the board rules (`docs/domain/issue-workflow.md`) beyond the
  commands the pass runs.

## Corpus scans

Transcript scans behind a law live in `.claude/skills/swarmify/corpus/` —
a dated report plus the labelled rows, so a count can be re-checked rather
than trusted. The skill never reads them.

## Open follow-ups

- `swarm` wants the same charter treatment: 1171 lines, still frames opencode
  as the primary harness though the repo has no opencode config, and its
  dispatch section should say `Agent(subagent_type: "drone", model: <tier>)`.
- Whether the Haiku Explore of law 3 and the seam grep of law 12 should be one
  dispatch or two is a per-pass call; one is cheaper, two lets the seam grep
  start before the claims are listed.
