# Spec — charter

The design behind `.claude/skills/spec/SKILL.md`. The skill is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol.

## What spec is for

Spec is the **writing half** of the design gate: it turns an issue whose
decisions are already made into one a drone can act on cold — the
`## Acceptance spec`, a hub's split into drone-sized children, and the board
tail handed to a [clerk](clerk.md). It never settles a design fork; that is
[swarmify](swarmify.md)'s job, with the owner.

It was split out of swarmify (owner, 2026-10-11: *"I want literally all of
these enhancements and fixes you propose, I'm sold. Spec needs a suitable
description so agents can use it also outside of skills prescribing it
too"*) for two reasons, both measured in the 2026-10-10 scan
(`docs/corpus/2026-10-10-swarmify-spec-weight-headless-clerk.md`):

- **Weight.** The spec half was 42% of swarmify's file (~2.3k tokens). Spec
  drafting begins at median call 24 of 38, ~132k context; the half sat unused
  through ~64% of calls, and 14 of 101 passes never wrote a spec at all.
  Loaded at step 8, the fork conversation carries only the fork machinery.
  The token saving is small against the context; the gain is a conversation
  not sharing attention with format rules it cannot use yet.
- **Legitimacy.** Swarmify's first law is that the owner is present. Headless
  sessions file issues often — 25 swarm, 11 relief, 5 warp sessions and ~11
  subagents in the window — and always as plain bodies: no spec, no stamp.
  They coped well (parking forks in `Needs design` "for a `/swarmify`
  session"), but had nowhere to learn the format without running a skill
  whose first law they could not meet. Spec has no owner law, only law 1's
  fence.

## The cost argument — why discovery moves upstream

The thing a drone implements is an issue, and *what it says shapes
everything the drone does*. The 2026-09-14 postmortem put three of four
Sonnet overruns on **spec gaps** — an undeclared seam, a bundled unit, an
interaction hidden behind an adjective — not on drone error.

Implementation discovery — which files this touches, what the seam is, what
shape the new class has — done at spec time runs **once**, in a context that
already holds the design. Left to the drone it costs 30–100k of orientation
reads, re-sent on **every later turn** (`mise run agent-cost` measures the
integral), and re-derived by **every resume-leg** (17 of 160 drone
transcripts in the warp-vs-drone audit were bare continuations). Done by the
orchestrator instead, it crosses the wire twice — into the orchestrator,
then into the brief. On the issue it crosses once, by `gh issue view`. Owner,
2026-09-21, on per-issue cost falling to ~5.5% of a window: *"due to updated
swarmify mostly (better specs, map and seams provided, a lot less research
needed to be done by implementer drones the first 40 tool calls etc)"*.

## Laws

Laws marked *(sw N)* moved here from swarmify's law N on 2026-10-11; the
corpus rows citing them moved with them.

**The fence**

1. **Spec writes what was decided; it never decides a design fork.** A fork
   (anything that would move a file, a class, or an owner-of-fact) has an
   answer from the owner — in a swarmify pass, or already stated on the issue
   — or the issue does not go `Ready`. What spec may settle alone: a fact
   verified against the code, and a knob (a number on something that
   exists), defaulted and marked tentative. This fence is what lets a caller
   with no owner use the skill at all.
2. **No owner, no question.** A headless caller never calls
   `AskUserQuestion` and never waits for an answer. An issue it files with an
   open fork goes to `Needs design`: title naming the fork, the problem in two
   lines, each fork numbered and restated, each option described by what it
   *is*, the caller's recommendation marked as its tentative pick — the
   swarmify pass then starts from a written menu. The corpus shape that
   worked: *"Every decision below is the owner's, for a `/swarmify` session;
   each fork carries scored options and a recommendation, nothing is settled
   here."* A headless issue with no fork, sized and stamped, may go `Ready`.
3. **Who loads it.** Swarmify invokes it at its spec step; any session that
   files or rewrites an issue meant for implementation loads it by its
   description — a swarm lead's follow-up, a relief, a warp, an ad-hoc
   session. Drones have no `Skill` tool and report `NOTES` instead; their
   lead files. The description names those callers and the fence, so a
   caller outside any skill that prescribes it still finds it.

**The one reader**

4. **A cold drone can act** *(sw 18)*. The reader does `gh issue view <n>`
   and `--comments` with no chat history and a bare fence. Test before
   promoting: read body and comments cold as that drone, and ask whether a
   single unsettled fork remains or whether "the orchestrator will explain
   that part". The brief carries only what the issue cannot know.

**The Acceptance spec — sections**

5. **Decisions, files touched, acceptance, NOTES** *(sw 10)* — each resolved
   fork as a one-line settled fact in the owner's words, dated (a delegated
   pick marked tentative); the paths the work lands on, naming any sibling
   that shares one; the failing test to make green or an exact behavioural
   spec; descoped asides parked for their own issue. A characterization pin
   ("this test still passes") enumerates the surviving assertions and says
   whether the test may be re-pointed.
6. **Knobs** — every tunable the pass defaulted: the exported property, its
   default, and how it gives editor feedback. The rules for making a knob
   easy are swarmify's law 32; spec only writes the section.
7. **Composition, written down** *(sw 26)*. Which class owns which fact, what
   it exposes, who reads it, what dies by name — a few lines or a small
   diagram. What will not come out concisely is a fork still open (law 1).
8. **Reading list** *(sw 11)*. 5–15 entries of `path:start-end — why`. "Read
   these, nothing else". Not a file map, not a tour: each entry names what
   the reader learns there.
9. **Seam map** *(sw 12)*. Every file the change touches, **including files
   that merely reference the thing** — a scene that instances the node, a
   board `.tres` that needs a null-guard — from a grep, never by recall.
   Whole-file entries. **A starting map, not a fence**: 71% of drones'
   edits to existing source landed in the stamp and 16 of 34 drones went
   outside it, rightly ("an eighth copy the spec missed"). The skill never
   tells a drone it may not leave the map.
10. **Stubs on master** *(sw 13)*, when the unit adds classes or signatures
    and the arch shape is worth settling in code: `class_name`, signatures,
    and the red test **under `pending()`** so trunk stays green; one
    `mise run refresh`, `git status`, explicit paths. Only a session working
    in the main checkout writes them; a drone never. **A stub is a
    proposal**: a drone that finds it wrong says so on the issue and goes
    against it.
11. **Shapes and seams, not bodies** *(sw 14)*. If the spec writes the
    implementation, the drone adds nothing and the work was done at planning
    rates without isolation.
12. **The drift stamp** *(sw 15)*. Reading list and seam map sit in one
    fenced block whose info string is `drift-stamp <master sha>`. `mise run
    issue-drift -- <n>` parses the latest stamp, diffs `<sha>..master` with
    `-U0`, and reports every entry whose range a hunk intersects (whole-file
    entries match any hunk) — always exit 0, since it is clipped onto the
    dispatch command. A diff is cheaper than a model; only reported drift
    earns a re-verify. One entry per line: `path`, optional `:start-end`,
    ` — `, free text; the last stamp on the issue wins.
    **A cited design doc is a stamp entry**, with a line range — a design
    doc may be rewritten any day, and a cited doc outside the stamp lets that
    rewrite reach the drone silently as spec. **A path a sibling will create
    is never an entry** (it does not exist at the stamp's sha; `issue-drift`
    cannot diff it): name the sibling in prose and stamp an existing
    neighbour, e.g. the `.tres` the new file inherits from.
13. **Verify at write time, in one batch** *(sw 16)*. Every `path:range`
    is confirmed to exist and say what the entry claims, or it is a stale
    spec with extra authority — but in the one Explore that already does the
    claim check and seam grep, not by a `sed -n` per range (median 11 range
    seds per pass on top of an Explore, roughly a third of a pass's calls,
    2026-10-11 scan). **The stamp is cut after any stub commit**, its sha
    that commit's: a stub shifts the lines the ranges were read from (six
    entries across two issues pointed at the wrong functions, caught by Sage
    before dispatch).
14. **The more, the better — by judgement, never by silence** *(sw 17)*. A
    serious issue carries every section; an omission is a written call on
    the issue ("no seams", "exploratory / docs", "few-turn patch, the drone
    finds the edits faster than we write the list").

**Splitting**

15. **A parent never carries work** *(sw 19)*. On split, all the hub's work
    moves into children, its own defect as "child 0". The hub keeps the
    problem, the decisions, the DAG; its status is derived by `land` and
    `hygiene --fix`, never set.
16. **Every child is drone-sized** *(sw 27)*: one subsystem, a handful of
    files, one test file, one or two deliverables, under ~150k drone
    context. More than three subsystems, five tests, or three deliverables
    is a split along state / wiring / consumer seams, now. Prefer more small
    children with native `blocked-by`.
17. **Split along the seam the design has** *(sw 20)*, one decision one
    unit; where it is not a file boundary, split anyway and record the
    overlap.
18. **A follow-up not required for the hub is a sibling** *(sw 21)*, linking
    back, never a child.
19. **Shared-file work every child touches** *(sw 22)* is the orchestrator's
    pre-step in the main checkout, not parcelled out.
20. **Bed before siblings.** When three or more siblings share a recipe,
    answer "what will drone two and three copy from drone one?" before
    promoting. A shared pattern not yet in code gets a **bed unit** the
    siblings are blocked on, built from a demand table of the siblings'
    specs (a part goes in only if two or more use it); a column of siblings
    also gets a **retrospective** unit after it, harvesting what the units
    added. Where the recipe is already a bed (data plus a roster line), no
    bed unit. Owner, 2026-10-07: *"after 1 or 2 are implemented, some
    roadblocks may have been resolved, gotchas encountered, plumbing
    specific to arrow types or delivery added … the third would ideally end
    up on a readily made bed"*, and *"kits are the way to go"*.

**Promotion and the tail**

21. **`Ready` is the admission ticket** *(sw 23)*: status, `design` /
    `blocked` labels dropped, a milestone — in one breath. The milestone is
    a default (the live one or the parent's), never a question.
22. **The tail goes to one clerk** *(sw 33)*. Spec files plus a short prose
    work order; one `Agent(subagent_type: "clerk")`; the caller reads the
    one-line-per-issue report and handles each `SKIPPED` / `FAILED` itself.
    The work order is plain sentences, not a grammar (clerk law 2): the
    2026-10-10 scan found the orchestrator opening `clerk.md` to learn keys
    in 25 of 54 sessions, and the format's two gaps (re-parent, clearing
    blockers) were each a new keyword where a sentence would have done.
    The one convention kept is the sibling **handle**: a body file names a
    sibling not yet filed as `#{name}`, declared in the work order, and the
    clerk substitutes the number — never `@name`, a live mention.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-11 | owner | split request and the "suitable description" ask, quoted above | 3 |
| 2026-10-10 | corpus scan (101 passes; `docs/corpus/2026-10-10-swarmify-spec-weight-headless-clerk.md`) | weight and headless-filing numbers above; headless leads parked forks in `Needs design` (0ad13edc: "an open question for a `/swarmify` pass with you"); a warp filed #1114 straight to In progress with "a plan and an acceptance section, but that isn't a real acceptance spec" | 1, 2, 3 |
| 2026-10-11 | drift-stamp scan (78 stamping passes, 203 lead-side drift runs, 358 drones, 09-15→10-10; `docs/corpus/2026-10-11-drift-stamp-value.md`) | verdict *slim*: drones read the reading list (69% of stamp paths touched within 15 calls of the view); the sha check redirected leads a handful of times and was mostly the run's own landings; seam map a start not a fence; the cost was per-range verification. Clerk `no stamp` fired on every `Needs design` child as noise | 9, 12, 13 |
| 2026-09-22 | 65f779bf | a stub commit shifted lines after the ranges were read; six entries pointed at the wrong functions — "would have actively misled a drone" | 13 |
| 2026-10-07 | drone afb0fab3 | the fork-menu shape for an owner-less issue, quoted in law 2 | 2 |
| 2026-10-07 | arrow pass (d359f7ce) | nine bespoke-look siblings promoted in parallel, each told to copy poison's shape; six shed trail particles, seven leave a lingering impact — fixed after the fact by bed unit #1474 and retrospective #1475 | 20 |
| 2026-10-04 | #1410 (bc56e8dd) | stamped `identity/defs`, which sibling #1404 creates; the clerk flagged it `missing-at-stamp` | 12 |
| 2026-09-30 | #1222 | `Ready` with ≥4 deliverables, one opus unit, 4.21M priced (23% of the run), did not land in budget | 16 |
| 2026-09-17 | owner | "if you can't write it up cleanly (potentially concise, get the idea across) you won't be able to code it up cleanly either" | 7 |
| 2026-09-15 | #902, owner | "the more the better … some issues have little to no seams, or no reading list because they're exploratory / docs, or small patch jobs … stubs too — depends on the issue / judgment. a wrong attempt at a stub needs the drone to realize and go against it, which often happens"; stubs under `pending()`, drift range-aware and exit 0 | 10, 12, 14 |
| 2026-09-15 | hubs (#729/#901) | "hub that is also a bug" vs "hub that is only a container" kept tripping agents and `hygiene`; owner chose "a parent never carries work" | 15, 18 |
| 2026-09-15 | warp-vs-drone audit | 17/160 drone transcripts open with a bare "continue"; every resume-leg re-derives orientation the issue could have carried | cost argument, 8 |
| 2026-09-14 | #879 status-tick | four sub-units bundled in one brief; +29% calls; the drone "sound throughout" — bundling was the cost | 17 |
| 2026-09-14 | #888 tempo-pool | the fence omitted two scenes the new pool touched; found mid-flight, +69% calls | 9 |
| 2026-09-14 | #878 status-hit | an `AttackRecord`/crit-draw interaction hidden behind "shadow-safe", surfaced only in review; +34% | 8, 13 |
| 2026-09-14 | #766 mana-rework | the one in-budget Sonnet unit: single mechanism, narrow fence, 75 calls | 11, 17 |
| 2026-09-14 | #872 status-def | the cheapest unit: the tightest-fenced foundation with nothing upstream to reconcile | 10 |
| 2026-09-14 | last 2–3 swarms | drones past 300k on oversized units; #872 → #872/#878/#879 is the split that worked | 16 |
| 2026-09-11 | #857 | the Ready criterion stated: a drone given only the number, its comments and a fence can act | 4 |
| 2026-08-24 | #573 | "still passes unmodified" was unsatisfiable — the same issue deleted `class_name`s the test cast to | 5 |
| 2026-08-02 | label collapse | `swarmable` retired; `Ready` became the queue; a `design` label on a `Ready` issue is the drift the collapse ended | 21 |

## Fold digest

| Date | Kind | Became |
|---|---|---|
| 2026-10-04 | gotcha (bc56e8dd, swarmify board) | law 12: a path a sibling creates is never a stamp entry |
| 2026-10-07 | law-candidate (d359f7ce, swarmify board, two posts) | law 20: bed unit before siblings, retrospective after a column. Not folded: a recipe-delta line in every Acceptance (lives in `docs/design/aspect_matrix.md`, too domain-specific for every spec) and a swarm-lead dispatch guard (swarm's charter, not this one) — left for the owner |

## What the skill must not contain

- Any row above, any issue number, any date, the cost argument.
- How to settle a fork, score options, or talk to the owner — swarmify's.
- The clerk's `gh` traps — the clerk's.
- Restatements of `docs/domain/issue-workflow.md` beyond what the caller does.
