---
name: swarmify
description: Take one GitHub issue from "has open design forks" to Ready — remove blockers, read whether the open question is "what would be fun" (design it first, game-designer hat on, with the user) or "how to build it", surface every unresolved decision, research the code and think each fork through with the user, present options scored for cleanliness with the cleanest as the default, get them to settle it, write a crisp acceptance spec, split a hub into coherent children if needed, and move it to the `Ready` column. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "make #<n> ready/swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.
---

# Swarmify

Take one issue from "has open forks" to `Ready`, in this session, with the
owner, before any worktree exists. (Design behind this file:
`docs/charters/swarmify.md` — read it only if you are changing this file.)

The output has exactly one reader: a drone doing `gh issue view <n>` and
`--comments` cold, with no chat history and a bare fence. **`Ready` means
that drone can act.** The drone's brief carries only what the issue cannot
know — fence, seams this run, tier, advisor, budget — and restates nothing.

These passes shape the whole codebase; every pick here is one a hundred
later drones will build on.

## The one rule

**Decisions are the owner's.** You surface forks and propose; the owner
chooses; you write the answer in the owner's words, dated, attributed as an
owner call. Never invent a design answer to reach `Ready`. Owner absent →
draft proposed resolutions and do **not** move the status.

## The cycle

### 1. Read the whole issue yourself, then read the room

```bash
gh issue view <n>
gh issue view <n> --comments
```

Body *and* every comment, in this session — never summarised by a subagent.
A later comment routinely corrects an earlier one. Note the labels:
`design` / `blocked` mean forks are known-open.

Then ask what is actually open: **how to build it**, or **what would be
fun**? If the second, step 2 comes before anything technical — every fork
enumerated now would be a fork on the wrong thing. If the first, skip to
step 3.

### 2. Design first, when the question is what would be fun

Game-designer hat on. **Diverge**: several candidate mechanics, each with
the player fantasy it serves, what it does to the loop, and which existing
system it leans on. Grow them from both ends — a concept looking for
gameplay, a wanted feel looking for its model — and check the stub lists
before inventing: open questions in `docs/design/*.md` and `design`-labelled
issues. Write bolder than you would for code; a reach in the designer
direction is the ask here, a safe median answer is not.

No seams, no costs, no file paths in this beat. Converge with the owner;
**the owner says when the picture is clear**. Land the conclusion durably
— `docs/design/` or a dated, owner-attributed comment on the issue — and
only then continue. Never mix the two beats in one message.

### 3. Verify claims and grep seams — one Haiku Explore

Collect every claim the issue makes about the code ("X is unbuilt", "Y has
no caller", "that helper was deleted") and every thing the change touches.
Dispatch **one** `Agent(subagent_type: "Explore", model: "haiku")` carrying:

- the whole claim list → report verified / false / stale, a `file:line` each;
- the seam grep → every file that references the thing (scenes instancing
  the node, `.tres` boards needing a null-guard, sandbox panels listing the
  system), never from recall;
- each reading-list `path:range` you intend to cite → confirm it exists and
  says what the entry will claim.

A stale claim closes with a doc correction, not new work. This is the only
delegation in the pass; the thinking stays here.

### 4. Do the arithmetic

After pinning anything numeric, compute what it implies at both ends of the
range (level 1 and level 100, one node and two hundred). The fix that
surfaces is usually structural, and it surfaces from the numbers.

### 5. Enumerate every open fork

A fork is anything a drone would have to *decide*:

- **Floated alternatives** — "…or some other way", "maybe X, maybe Y".
- **Speculative asides riding a decision** — a second decision never rides a
  first: split it out (own child, own sibling, or a NOTES line) before
  promoting.
- **Unstated acceptance** — no failing test, no exact spec.
- **Unowned surfaces** — two plausible implementations landing on different
  modules means the *approach* is undecided.
- **A fact read from the wrong owner** — the unit that shows the symptom is
  about to read another unit's internals (a director walking a blade's
  vertices, a panel writing a controller's private request). Ask *who owns
  this fact?* and make the owner expose it (a marker, a signal, a stored
  sample) — that is the fork, and it is answered from the plan, not the diff.
- **N things that are one** — a list of per-type cases, a rebuild-on-every-
  signal, a discrete two-step where one continuously-recomputed target
  would do. Ask *is this one callback / one deferred flag / one value?*
- **Per-frame and at-scale cost** — anything recomputed in `_process`, per
  tick, or per entity that a sim, a stored sample, or a once-per-frame
  dedupe would make an array read. Ask it for both ends of the range (step 4).
- **An architectural seam** — two classes doing one job, a stage doing
  another's work, a mirror of logic that already exists. Settled in this
  pass, refactor-first, with the delay cost said out loud — never parked in
  a design issue. An unsettled seam leaks into every consumer written
  against it.
- **Cross-issue dependencies** — recorded as `--blocked-by` relations *and*
  in the spec prose (step 8), never disqualifying; the orchestrator
  sequences them. Only a dependency on a decision nobody has made keeps an
  issue out of `Ready`.

List them numbered — `AskUserQuestion` for clean choices, prose for the rest.

### 6. Score the options, cleanest first

Each option carries one scorecard line in this fixed axis order, then one
sentence of what it buys and one of what it costs — the line *replaces* the
prose that would argue the ranking:

```
clean ★★★★☆ · smell: none · perf ★★★★★ · blast ●●○○○ (4 files, 1 sys) · taste ★★★☆☆
```

- **clean** — separation, one owner per fact, SOLID, no mirror of existing
  logic. Composition as a plural array (`composes: Array[...]`), never a
  singular parent link or inheritance vocabulary; one implementation over
  swappable state, never two implementations of one contract; graph
  vocabulary exact (`docs/domain/graph-vocabulary.md`).
- **smell** — `none`, or the smell in three words (reads another unit's
  internals, N cases that are one callback, parallel copy).
- **perf** — per-frame / at-scale cost, from step 4's arithmetic.
- **blast** — files and subsystems touched, tests to re-point. Informational
  only: it never demotes an option or moves the Recommended tag.
- **taste** — both senses: slick code is slick, and the pick reads like
  this codebase would have made it. A tiebreaker after the others, never
  before.

Say it when every option scores the same on `clean` — the fork is then about
something else.

**Cleanest is not biggest.** The problem has a shape its solution fits —
look for it in this order: a duplicated fact to collapse into one owner,
then an existing path to route through, then a composition whose union
yields the behaviour; a new system or resource hierarchy comes last and
rarely pays this way. The tell that the shape is found is that something
else **falls out for free** — a special case that disappears, a test that
writes itself, a sibling that closes. Name it in the option's "buys"
sentence, gameplay consequences alongside codebase ones; a pick where
nothing falls out gets a second look.

### 7. Settle each fork with the owner

**The cleanest option is the default.** "A, sorta clean" against "B, hella
clean but more work" is B; `(Recommended)` sits on the cleanest option unless
you state a reason it should not, and the clean option's cost is said out
loud, never used as the tiebreaker. The owner still sees every option and
still chooses — the default moves, the choice does not. An "Other" answer
that redirects the premise is a normal outcome, not a failed question.

Every fork gets a pinned answer in the owner's words. An unsettleable fork
(needs a spike, needs another issue) keeps the issue in `Needs design`:
"still blocked, here is why" is a valid outcome. Never promote an issue a
drone will stall on.

File ownership is a map, not a gate: record which paths a unit touches so
the orchestrator can sequence; never contort the design to keep files
disjoint, never withhold `Ready` because two issues share a file.

### 8. Write the Ready comment

Post a comment (or edit the body) headed `## Acceptance spec`:

`````markdown
## Acceptance spec

**Decisions** (owner, <date>)
- <each resolved fork as one line of settled fact, in the owner's words>

**Composition**
<how the pieces compose — a few lines of prose or a small diagram: which unit
owns which fact, what it exposes, who reads it, what dies>

**Files touched**
- <path> — <what lands here; name any sibling issue sharing it>

**Acceptance**
1. <the failing test to make green, or an exact behavioural spec>

**NOTES**
- <descoped asides, each parked for its own issue; never riding this unit>

**Stubs on master** — <commit sha> · <class_name / signatures added> · <test file under `pending()`>

```drift-stamp <master sha, 7–40 hex>
path/to/file.gd:120-180 — what the reader learns here
path/to/scene.tscn — seam: instances the node
```
`````

- **Decisions** — one line per resolved fork, dated, attributed to the owner.
- **Composition** — the proposed shape, concise: which class owns which
  fact, what it exposes (marker, signal, accessor), who reads it, which path
  is deleted by name. Prose or a small diagram, whichever gets the idea
  across. If it cannot be written up cleanly in a few lines it cannot be
  coded cleanly either — that is a fork still open, go back to step 5.
- **Files touched** — the paths the work lands on; name any sibling that
  shares one, and which issue.
- **Acceptance** — the failing test to make green or an exact behavioural
  spec. A characterization pin ("this test still passes") enumerates the
  surviving assertions and says whether the test may be re-pointed.
- **NOTES** — descoped asides, parked for their own issue.
- **Reading list** (inside the stamp) — 5–15 entries of `path:start-end —
  why`, "read these, nothing else". Not a file map, not a tour: each entry
  names what the reader learns there. Omit what should be skipped rather
  than listing it, unless a specific trap must be named. Every range is
  verified at write time (step 3, or `sed -n 'a,bp'`).
- **Seam map** (inside the stamp) — every file the change touches, including
  files that merely reference the thing, from step 3's grep; one whole-file
  entry each (`path — seam: <why>`).
- **Stubs on master** — when the unit adds classes or signatures and the
  arch fork is worth settling in code: `class_name`, method signatures, and
  the red test file committed **under `pending()`** so trunk stays green.
  `git status` first (the main checkout is shared), `git add` explicit
  paths, one `mise run refresh` on master. The drone's first commit flips
  the pending to RED. A stub is a proposal: a drone that finds it wrong
  says so on the issue and goes against it with a stated reason.
- **The drift stamp** — one fenced block, info string `drift-stamp <sha>`
  where `<sha>` is the master sha the entries were written against; one
  entry per line: `path`, optionally `:start-end`, then ` — ` and free text.
  That shape is a parse contract (`mise run issue-drift` consumes it); the
  info string is the key, anything else in the comment is prose. The last
  stamp on the issue wins, so a re-swarmified issue simply posts a new one.

**Shapes and seams, not bodies.** Signatures, seams, reading list, red
tests — never the implementation.

**Every section, on any serious issue.** Omitting one is a *written* call on
the issue — "no seams", "exploratory / docs", "few-turn patch, the drone
finds the edits faster than we write the list" — never silence.

**Test before promoting:** read body and `--comments` cold, as a Sonnet with
no chat history would. If you think "the orchestrator will explain that
part", or a single unsettled fork remains, it is not `Ready`.

### 9. If it is a hub, decompose into Ready children

A hub (sub-issues > 0, or too big for one unit) is never `Ready` itself — its
children are. **A parent never carries work**: on split, *all* of the hub's
work moves into children, the hub's own defect included as "child 0". The hub
keeps the problem statement, the decisions and the DAG; never set its status
by hand — `land` and `hygiene --fix` derive it.

- Every child is drone-sized: one subsystem, a handful of files, one test file
  — under ~150k drone context. More than three subsystems or more than five
  tests is a split, along state / wiring / consumer seams, now. Prefer more
  small children with native `blocked-by` over one fat one.
- Split along the seam the design has: one decision, one unit. Where that
  is also a file boundary, say so; where it is not, split anyway and record
  the overlap. A unit describing three or more deliverables is split before
  dispatch.
- A follow-up not required for the hub to be done is a sibling linking back,
  never a child.
- Shared-file work every child touches (one `.tres`, a registry append) is
  the orchestrator's pre-step in the main checkout, not parcelled out.
- Each child gets its own full `## Acceptance spec` (step 8).

```bash
gh issue create --parent <n> --title "…" --body-file <file>
mise gh-project -- status <child> ready                # or needs-design if it still forks
```

Record cross-issue dependencies as relations *and* in the spec prose:

```bash
gh issue create --blocked-by <n1>,<n2> --title "…" --body-file <file>
gh issue edit <child> --add-blocked-by <blocker>
```

### 10. Promote

`Ready` is the admission ticket; the status move is the whole act, and the
labels and milestone go in the same breath:

```bash
mise gh-project -- status <n> ready
mise gh-project -- label <n> rm design
mise gh-project -- label <n> rm blocked       # if it was
mise gh-project -- milestone <n> <m>          # Ready without one is a hygiene violation
mise gh-project -- hygiene                    # must stay clean
```

## What swarmify is NOT

- **Not implementation** beyond step 8's stubs.
- **Not a rubber stamp** — an issue with an unsettleable fork stays in
  `Needs design`.
- **Not a spawn** — the thinking runs here, with the owner; only step 3's
  lookup is delegated.
