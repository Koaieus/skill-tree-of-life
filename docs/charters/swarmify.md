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
children along its real seams, and moves the status. The writing half — the
spec, the split, the board tail — is the [`spec`](spec.md) skill, which the
pass invokes once the forks are settled (law 33).

Its output is read by exactly one consumer: a drone doing `gh issue view <n>`
and `--comments` cold, with no chat history and a bare fence. **The Ready
criterion is that such a drone can act.** Everything below follows from what
that reader needs and from what it costs when they do not have it.

## The cost argument

Why discovery moves upstream — implementation discovery done once at spec
time instead of by every drone and resume-leg — lives in the
[spec charter](spec.md), with the sections that carry it. What stays here is
the cost of a fork left open: a drone that meets one stalls, guesses, or
ships the wrong shape, and every consumer written against an unsettled seam
inherits it.

## Laws

Numbered so the skill can be checked against them law by law.

**The one rule**

1. **Decisions are the owner's.** Swarmify surfaces forks and proposes; the
   owner chooses; the answer is written in the owner's words, dated,
   attributed as an owner call. An agent that invents a design answer to
   reach `Ready` has defeated the purpose. The owner is present by
   definition — a `/swarmify` is a design conversation *with* them, and a
   generic "the user is not watching" harness note never makes them absent;
   only the owner saying so does. Absent for real: draft proposed
   resolutions and do **not** move the status. Two things are
   *not* inventing: writing down an answer the owner already gave in the
   issue or the prompt (law 31 — re-asking it is the failure), and
   defaulting a tunable value behind a knob (law 32 — a value is not a
   design answer). An owner's "no real forks" / "your call" delegates the
   picks: make them, attribute them as the pass's tentative calls, promote.
   The delegation covers what survives law 31's review — "no real forks" is
   itself a claim, and a genuine law-5/28 fork the review turns up is still
   asked, leading with the finding.

**Reading and verifying**

2. **RTFC is the session's own job — for the named issues, once.** The body
   *and* every comment of each issue the prompt names, in the session, never
   summarised by a subagent — a later comment routinely corrects an earlier
   one, and the summary is where that dies. Read each once; a multi-issue
   pass pays this per issue and that is fine (it is sublinear overall — the
   code reads are shared). A *related* issue — a parent, a sibling, a number
   a comment cites — is not read in full by the session: a status or title
   question is one `gh issue view <n> --json title,state,labels` line, a
   content question ("what did #N settle about X") goes into the law 3
   Explore's question list, answered as the owner's sentence verbatim with
   its comment date — never a paraphrase, so the retraction guard holds
   at one remove. This refinement is the pass's tentative call
   (2026-10-14), not an owner decision.
37. **A queue selector resolves to the pick before anything is read.** The
   prompt may name a selector instead of numbers — "next issue", "next P0 from
   Needs design", "next … + closely related". Resolve it with one `mise
   gh-project -- next [<lane>] [--prio P0[,P1…]] [--not N,M…] --claim` (lane
   `needs-design` unless the selector names another): it prints the first issue
   in the board's own order — priority, then issue number — and moves it to `In
   design`, the pass's claim, so a second pass cannot take it. Its line is taken
   as printed, never re-sorted or re-ranked by reasoning about which issue
   matters more; "— no match" → say so and stop, never widen the lane or the
   filter unasked (the pass's tentative call, 2026-10-17, not an owner
   decision). Priority and size are **board fields**, printed as `[P0/S]` —
   never labels, so `gh issue list --label P0` finds nothing and is never the
   probe (`docs/domain/issue-workflow.md`, *The board*). The order is: resolve
   and claim the pick → the pick gets its law 2 read → `mise gh-project --
   related <n>` and a title scan of `mise gh-project -- list <lane>` → one
   opening message → the owner confirms → the confirmed riders get their law 2
   read, each claimed with `mise gh-project -- status <n> in-design`. "Closely
   related" is a candidate list, not a pick, and a judgement `related` does not
   make: an issue sharing the pick's parent, a sub-issue, a blocked-by /
   blocking link, or a sibling on the same surface (same subsystem, same swing
   or feature) found from the lane's titles; an issue that merely shares a
   keyword is not related. Candidates get the law 2 related-issue treatment (a
   title line, never a full read) until the owner confirms them. The opening
   message (law 34) names the issue the selector resolved to and why — lane,
   priority, number ("first P0 in Needs design: #N") — and lists each candidate
   with one line on why it is related; the owner confirms which ride along. The
   named issues of law 2 are the pick plus the confirmed riders. A pass that
   ends without promoting a claimed issue moves it back with `mise gh-project --
   status <n> nd` and names it under `Not done` (law 35); promotion to `Ready`
   is the release otherwise. Why: the owner wants to one-shot a pass from the
   queue, agents probing for priority by label stall on "P0 is not a label"
   before they find the board, and the claim is the owner's call (2026-10-17)
   for one shared selector every skill uses, so two passes never design the same
   issue.
3. **The Explore orients and verifies; the session confirms and thinks.**
   One `Explore(model: haiku)`, dispatched always once the question is *how
   to build it* — straight away when there is no design beat, after the
   design beat converges (law 29) when there is; a pass with none is the
   shape that reads the tree itself. It carries three lists: the orientation
   questions ("what does `X` look like", "where is `Y` wired", "what does
   `Z`'s contract say", "what did #N settle"), the claim list (every claim
   the issue makes about the code — "X is unbuilt", "Y has no caller",
   "that helper was deleted" — reported verified / false / stale with a
   `file:line` each, against `master`), and the seam grep. Its return is
   shaped, not capped: `file:line` facts, one-line answers, and for a
   related-issue question the owner's sentence verbatim with its date; never
   excerpts of code. Reading-list ranges are verified at spec time by
   `spec`, not here. Fact-checking is not thinking; skipping it specs work against
   a world two commits stale. A stale item closes with a doc correction,
   not new work. The thinking stays in the session.
   The brief, verbatim:

   ```
   Explore(model: haiku) — read-only, against master. Return shaped facts, not excerpts.

   ORIENTATION — one-line answer each, with file:line:
     - what does `X` look like
     - where is `Y` wired
     - what does `Z`'s contract say
     - what did #N settle about W  → the owner's sentence VERBATIM with its comment date

   CLAIMS — the issue says each of these about the code; report each as
   verified / false / stale, with a file:line:
     - "X is unbuilt"
     - "Y has no caller"
     - "that helper was deleted"

   SEAM GREP — every caller / consumer / test of: <symbols, signals, scenes>.

   Return: file:line facts, one-line answers, verbatim owner quotes with dates.
   Never code excerpts. Reading-list ranges are not your job.
   ```
36. **The session's own reads are ranged and confirm-only.** During research —
   from the moment the question is how to build it until a fork is
   presented — the session opens a file only to confirm a contract it has
   already named from the Explore's answer — a ranged `sed -n` of the lines
   that carry it, never a whole source file, never a `head -200`, never a
   review or design doc end to end. Bash reads bypass every line cap the
   Read tool has, and no hook clamps them; the discipline is the law. What
   the session wants to *know* goes in the Explore's question list; what it
   must *see* to reason it reads, bounded.
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
   The converse: a `Backlog` issue named in `/swarmify` is already picked up —
   it goes straight to its landing lane, never via a `Needs design` hop, and
   the move earns no comment. Owner, 2026-09-28: *"swarmifying a backlog
   issue implicitly moves it to needs design; sometimes agents comment on it.
   it's just: if it is to be swarmified we *are* picking it up"*.
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

**Writing it down — moved to `spec`**

10–23, 26, 27. *Moved to the [spec charter](spec.md) on 2026-10-11* — the
    Acceptance spec sections, reading list, seam map, stubs, drift stamp,
    write-time verification, the cold-drone test, hub splitting and sizing,
    promotion. Spec carries them as its laws 4–21, each tagged with its old
    number here, and their corpus rows moved with them.

24. **Not implementation** beyond spec's stubs. **Not a rubber stamp.**
    **Not a spawn** — the thinking runs in the session with the owner; only
    law 3's lookup and the clerk are delegated.

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
    never used as the tiebreaker; the options are a prompt to think aloud, not a strict menu, so the
    scorecard must survive an "Other" answer (a redirected premise, a
    synthesised option) and score that too; and the owner still sees every option
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
    having listened. The same goes for a confirm-everything closer
    ("OK?", "does that hold?", "settle both?") on picks already made: state
    them and move on; the owner redirects when they disagree.

32. **A knob is defaulted, not asked.** A tunable — a size, a timing, a
    ratio, a threshold, a count — where any sensible value ships
    and the owner tunes it by feel later, is not a fork. The discriminator:
    **if changing it would move a file, a class, or an owner-of-fact, it is
    a fork (law 5); if it changes a number on something that already
    exists, it is a knob.** "Is there a cap?" is a fork; "what is the cap?"
    is a knob. A number the owner already stated is still a knob — their
    value is the default, exported all the same. For a knob, the pass picks a sensible default (law 4's
    arithmetic at both ends), records it in the Ready comment's Knobs section as a tentative pass
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
    timing and feel tunables those leave to an `@export`. The mechanics —
    shared with drones and every session writing a `.gd` — live in
    `docs/domain/tunables.md`; this law is only swarmify's half: default in
    the spec, don't ask.
    The board has one knob of its own: the **milestone** defaults to the
    live one (`mise gh-project -- roadmap`) or the parent's, stated in the
    Ready comment, never asked.

**Talking to an owner who has not read the issue**

34. **The owner's context is the prompt, not the issue.** A pass opened
    with `/swarmify #1234` usually means the owner has read the issue's
    title and nothing more — sometimes not even that. The issue body and
    comments are the pass's reading, not the owner's: it may have been
    written by an agent, weeks ago, against a design the owner no longer
    holds in mind. So everything the pass shows the owner stands on its
    own. Open with two or three lines of what the issue is and why it
    exists, before the first fork. Every fork restates its problem in a
    line; every option is described by what it *is*, never by the issue's
    label for it — "option B from the body", "the A/B/C split", "the
    approach in the second comment" each assume a read that did not happen.
    Terms the issue coined (a handle, a nickname for a mechanism, a
    sibling's number) are glossed in a few words or dropped. This is the
    asking-side twin of law 31: law 31 says what the owner *wrote* is an
    answer; law 34 says what the owner did *not* write is not something
    they know — an option the issue enumerates is still news to them, and
    a question that leans on it is answered blind or bounced back. The
    test is the cold-drone test (spec law 4) turned around: read the message
    as someone who has seen only the title.

**Handing off the tail**

33. **Spec time loads `spec`.** Once every fork is settled, the pass
    invokes the `spec` skill, which writes the Acceptance spec, splits a hub
    and hands the board tail to a clerk (its laws 1–22). Loaded at that step
    and not before: the spec half was 42% of this file and sat unused through
    ~64% of a pass's calls (2026-10-10 scan), and a separate skill gives
    sessions with no owner a format to file by without claiming law 1. Writing
    the spec stays in this session — it is the compressed thinking — and the
    Composition that will not come out sends the pass back to the forks.

35. **The pass ends with the session report** (`docs/domain/session-report.md`),
    `Landed` carrying the swarmify columns — issue, lane after the pass
    (`Ready` is the goal), the decision direction or fork settled in a
    clause, what is left (stubs, children, a fork kept) — and `Not done`
    naming every issue that stayed in `Needs design` and why. The last
    message of the pass is this report, never a pasted brief or
    walkthrough. Owner,
    2026-10-09: *"the most important outcome is which issue, what status
    (`Ready` being the ideal), short decision direction or fork settled, or
    stubs left."* Mined 2026-10-09: swarmify's last long message was often a
    pasted brief or walkthrough, not a closing report, so the owner had to
    ask what actually moved.

## Frontmatter

`name: swarmify`. `description:`, verbatim:

> Take one GitHub issue from "has open design forks" to Ready — remove blockers, read whether the open question is "what would be fun" (design it first, game-designer hat on, with the user) or "how to build it", surface every unresolved decision, research the code and think each fork through with the user, present options scored for cleanliness with the cleanest as the default, get them to settle it, write a crisp acceptance spec, split a hub into coherent children if needed, and move it to the `Ready` column. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "swarmify next issue" or another queue selector ("next P0 from Needs design", "… + closely related"), "make #<n> ready/swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.

## Incident corpus

Each law traces to at least one of these. Kept here so the skill does not
have to carry them.

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-17 | owner | "i feel like i should be able to oneshot this like 'next issue from needs design queue ordered by prio then by issue number; and if any closely related pick those up too'" and "(as in '/swarmify next issue …' + gotcha/guidance of how to find by P0 (agents often struggle then find 'P0 is not a label, ah'))". The Needs-design head that day was #256 (blade visuals) followed by aspect "× Addon" issues whose titles mention "blade" — keyword siblings, not related | 37 |
| 2026-10-17 | owner, via AskUserQuestion | asked that the selector work for every skill that picks issues (warp, relay, swarm, triage), not just swarmify; settled SHAPE = "Board cmd" — a shared `gh-project next` + `gh-project related`, no new skill — and CLAIM = "In design lane", a board column between Needs design and Ready | 37 |
| 2026-10-14 | owner; scan `.claude/skills/swarmify/corpus/2026-10-14-research-cost-scan.md` (133 sessions) | owner: swarmify sessions "should upgrade their initial research … a Fable … exploring codebase rapidly bloating context possibly reading stuff they dont need", asked what to read, what to delegate, how many explorers and what return size. Scan: the research phase is 73% of a session's tool-result bytes (median 62k chars, max 195k); the session's own `cat`/`sed` reads are the largest bucket (3.0M total), issue reads second (2.1M), Explore returns smallest by 7x (0.4M, ~3.4k/agent). The two heaviest passes cat'ed whole source files and a whole review doc that the resulting specs never cite; one ran no Explore at all; 45 of 133 did not. Owner picked: Explore orients + session confirms, no Explore cap, "just a shape" | 3, 36 |
| 2026-10-14 | same scan, `bebb84f4` (#1381/#1383/#1489) | the max issue-read case (70k chars, 13 `gh issue` calls) read its three named issues once; the rest was six *related* issues' comment tails and a nine-issue status loop. Multi-issue cost is sublinear (median 58k → 76k → 93k chars for 1 / 2–3 / 4+ issues) because code reads are shared. Owner deferred ("what does advisor say? i'm leaning 1 but comments could get *long* right?"); the pass's tentative call: keep full in-session reads of the named issues (the observed ceiling is 17k tokens, half a heavy pass's own cats) and route related issues through the Explore with a verbatim quote-back | 2 |
| 2026-10-11 | owner, after the 2026-10-10 scan (`docs/corpus/2026-10-10-swarmify-spec-weight-headless-clerk.md`) | asked whether the spec-writing half should be its own skill, loaded at spec time and usable by sessions with no owner; "I want literally all of these enhancements and fixes you propose, I'm sold" | 33 |
| 2026-10-10 | #1524 | a generic autonomous-mode harness note ("the user is not watching in real time") made the pass treat the owner as absent: it posted the design options as a comment and ended the turn instead of asking. Owner: "swarmify is a speccing slash design session WITH the user. I AM THE OWNER … we must talk them through and make decisions right here right now" | 1 |
| 2026-10-08 | owner, `/swarmify` prompt | "owner often has only read the title of an issue if e.g. user starts a session with \"/swarmify #1234\", and sometimes not even the title. So if e.g. an issue mentions an A B C don't assume the user knows these options, stuff like that" | 34 |
| 2026-08-02 | #332 / #165 hubs | reading two comment threads in-session caught a comment retracting an earlier one's central claim; the same pass burned ~8 calls on pure lookup (is #322 closed, is #339 filed, does `keystone_placement.gd` carry `node_scene`) — the last exposed #330 sitting in `Ready` with an open fork in its body | 2, 3 |
| 2026-09-11 | #847 | a publish-a-Release pre-step lived in a post-review comment and rewrote acceptance 7 — fine, because it was on the issue, dated, the owner's | 1, 18 |
| 2026-09-16 | #928 → #930/#931 | the camera 2-step was fixed inside the director by reading the blade's `state.pivot_index`, `get_node_visuals()` and a vertex's alpha; the test had to poke those to move the goalpost. The owner caught it from a glimpse of the plan — "opportunity: decouple the director from what it follows by letting the (alive) melee blade provide some %Marker2D" — and the sim storing its own centroid. Seven such redirects in seven days (#889, #900, #910/#917, #927, #928, #930, #931), all answerable from the plan, none from the diff | 25, 26 |
| 2026-09-26 | #1125 → #1126 | told "`/swarmify` this, i assume no real forks", the pass picked `MIN_SEGMENT_PX := 12` and `DIAGONAL_SHARE := 0.5` itself, marked them tentative on the issue, and told the owner "they're easy to change". Owner: "that's excellent. leaving design knobs while not harking over details, just put sensible defaults and enable enough DX that tweaking them is easy in the godot editor. most often an exported variable, ideally with instant editor view feedback (if it's a visual thing)". The picks shipped as `const`s on `TraceRouter` — easy in code, not in the editor; the DX half is what law 32 adds | 1, 32 |
| 2026-09-26 | owner, status-fx sandbox tab (#1114) | the prompt asked for every status effect with controls and the tooltip panels always on; the session (a `/warp`, `6f05643b…`) asked how the always-on tooltips should show and what "single node with vision range" meant — narrower than remembered, but stated intent framed as open. Owner: "like seriously asking me this? but then again, rather they ask than silently head in the wrong direction … [an agent] should just better report on what's good, if the idea is clean, and if it clearly is (like a mini internal review) then just write that out" | 31 |
| 2026-09-26 | transcript scan (59 swarmify sessions, 32 in depth, 251 questions; `.claude/skills/swarmify/corpus/2026-09-26-reask-scan.md`) | most questions code-grounded; re-asks a minority, in three shapes — numeric magnitudes deferred inside a range the owner stated, confirm-everything closers ("OK?", "Settle both?"), and a milestone question in nearly every session. Legit asks (a review finding, an arithmetic hole, a bug in the issue's own fix) are the overcorrection guard | 31, 32 |
| 2026-09-10 | #764 / #849 | Recommended parking an architectural fork in a design issue; owner overrode — settle now, refactor-first hub with three children. | 28 |
| 2026-09-22 | owner | "read the room for when an issue is more about designing before serving forks … put your Epic Game Designer hat on and when the picture becomes clear, then we talk code plans, forks to settle, with the cold hard specs and technical seam maps … sometimes crank up the LLM temperature" | 29 |
| 2026-09-22 | owner | "when a fork can be settled with 'this option A which is sorta clean' and 'this option B which is hella clean but costs more work' then that's gonna be a B in 99% of cases … This project for a solo dev grew this big yet stayed so maintainable due to our aggressive combating of tech debt … you wouldn't know how much stuff landed by drones that used plumbing that was already there just because what could've been deferred as YAGNI instead was implemented on the spot"; asked for a stars ranking on cleanliness plus blast radius ("which we take to the chin every time"), effectiveness, good practices, lack of smell, perf, style secondary — "swarmify is often a lot of reading and thinking in which i could use all help i can get" | 30 |
| 2026-09-22 | transcript scan (318 sessions, 681 `AskUserQuestion` pairs; `.claude/skills/swarmify/corpus/2026-09-22-askq-scan.md`) | 106 pairs turned on a clean-vs-cheap axis; owner picked cleaner 49 vs cheaper 33 (~1.5:1), even within `/swarmify` runs. Where the agent's `(Recommended)` tag and the owner's pick disagreed on that axis, the owner pushed toward *more* work 9 times and toward less 5 — the tag was under-recommending cleanliness. Sonnet-labelled, directional not exact. Two side patterns: perf ("how many nodes, how fast") is the real tiebreaker at least as often as cleanliness; and the owner routinely answers a menu by redirecting the premise or synthesising a new option — options are a prompt to think aloud, not a strict menu, so a scorecard must survive an "Other" answer | 30 |
| 2026-09-22 | owner | "100% and we don't need to go overboard. Usually the problem at hand has a certain shape of solution that works best, add a signal? Add a system? Add a bespoke resource and or set of subclasses? A shared shape? Just be on the lookout … these swarmify sessions basically shape the entire codebase.. so they bear some weight. Or i love it when we discuss and then agent mentions something along the lines of '… and then XYZ *falls out* for free' like those nifty picks are often just style and clean architecture high fiving" | 30 |
| 2026-09-22 | transcript scan (318 sessions, 227 regex hits, 75 genuine "falls out for free" moments; `.claude/skills/swarmify/corpus/2026-09-22-fallsout-scan.md`) | enabler: single-owner-of-fact 31, shared-shape-reuse 17, composition-array 8, data-driven 4, resource+subclasses 1, new system 1 — free-riding comes from deleting a duplicate representation or routing through what exists, almost never from adding abstraction. What fell out: feature-for-free 21, consumer-simplifies 19, special-case-removed 12. Three "free" claims were false or a smell ("self-loop-blind for free" asserted in four places incl. flavour text; "bulk grows for free with level" as the defect); Cyclone's parity detector was free, unauthored, and later cut. 58 of 75 in swarmify passes. Steady rate, no trend | 30 |

## What the skill must not contain

- Any row of the table above, any issue number, any date.
- Anything `spec` carries — the Acceptance spec template, the split rules,
  the clerk work order. The skill names the step and invokes `spec`.
- Worked examples and "why this is a rule" paragraphs. Each law states the
  next action; the charter holds the why.
- Restatements of the board rules (`docs/domain/issue-workflow.md`) beyond the
  commands the pass runs.

## Corpus scans

Transcript scans behind a law live in `.claude/skills/swarmify/corpus/` —
a dated report plus the labelled rows, so a count can be re-checked rather
than trusted. The skill never reads them. New scans go to `docs/corpus/`
via the `archivist` agent; these stay where this charter cites them.

## Open follow-ups

- `swarm` wants the same charter treatment: 1171 lines, still frames opencode
  as the primary harness though the repo has no opencode config, and its
  dispatch section should say `Agent(subagent_type: "drone", model: <tier>)`.
- Whether the Haiku Explore of law 3 and the seam grep (spec law 9) should be one
  dispatch or two is a per-pass call; one is cheaper, two lets the seam grep
  start before the claims are listed. Since law 3 now also carries the
  orientation questions, a second dispatch for the seam grep is the likelier
  split when it is split at all.
- A `PreToolUse` hook that clamps a Bash `cat`/`sed -n` to N lines would make
  law 36 mechanical; none exists (2026-10-14). `/update-config` scope, owner
  has not asked.
