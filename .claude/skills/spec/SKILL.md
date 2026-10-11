---
name: spec
description: Write a GitHub issue a cold drone can act on, then file it — the `## Acceptance spec` (decisions, knobs, composition, files touched, acceptance, NOTES, reading list + seam map in a drift stamp, stubs), a too-big issue or hub split into drone-sized children, and the board tail (post, create, relate, status, milestone) handed to one Haiku `clerk` as a plain-prose work order. Use whenever you file, split or rewrite an issue meant for implementation — at the end of a /swarmify pass, when a swarm / relief / warp lead files a follow-up or splits a unit, or when asked to "spec this", "write it up as an issue", "file a Ready issue for X". Headless-safe: it never asks; an issue with an unsettled design fork is filed to `Needs design` with the forks laid out, never `Ready`.
---

# Spec

Write the issue a drone implements, and get it onto the board. (Design
behind this file: `docs/charters/spec.md` — read it only if you are changing
this file.)

The reader is a drone doing `gh issue view <n>` and `--comments` cold, with
no chat history and a bare fence. **`Ready` means that drone can act.** Its
brief carries only what the issue cannot know — fence, seams this run, tier,
advisor, budget — and restates nothing.

## The fence

**You write what was decided; you never decide a design fork.** A fork is
anything that would move a file, a class, or an owner-of-fact. Each one has
an answer — from the owner in a `/swarmify` pass, or already stated on the
issue — or the issue does not go `Ready`. You may settle alone: a fact you
verified in the code, and a knob (a number on something that exists),
defaulted and marked tentative.

**No owner to ask** (a lead, a relief, a background session): never
`AskUserQuestion`, never wait. An issue with an open fork goes to
`Needs design` as a written menu: the title names the fork, the problem in
two lines, each fork numbered and restated, each option described by what it
*is*, your recommendation marked as your tentative pick. A fork-free issue,
sized and stamped, may go `Ready`.

## 1. Write the Acceptance spec

To a file in your scratchpad, headed `## Acceptance spec`:

`````markdown
## Acceptance spec

**Decisions** (owner, <date>)
- <each resolved fork as one line of settled fact, in the owner's words>
- <a stated decision from the body/prompt: the quoted sentence, then "— reviewed, taken as settled">

**Knobs** (tentative defaults — easy to change)
- `<OwningClass>.<export_name>` = <default> — <what it tunes; editor feedback: setter redraw / sandbox tab>

**Composition**
<which unit owns which fact, what it exposes, who reads it, what dies>

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

- **Decisions** — one line per fork, dated, attributed. A decision stated
  before the pass quotes the sentence; a delegated pick is marked tentative.
- **Knobs** — every defaulted tunable: exported property, default, editor
  feedback. Omit the section when there are none.
- **Composition** — prose or a small diagram, a few lines. If it will not
  come out concisely, a fork is still open: stop, and it is `Needs design`.
- **Files touched** — the paths the work lands on; name any sibling sharing
  one.
- **Acceptance** — the failing test or exact behaviour. A characterization
  pin ("this test still passes") lists the surviving assertions and says
  whether the test may be re-pointed.
- **NOTES** — descoped asides, parked.
- **Reading list** (inside the stamp) — 5–15 `path:start-end — why`, "read
  these, nothing else". Each entry names what the reader learns there; not a
  file map, not a tour. Verify every range in one batch — the Explore
  that checks the claims and greps the seams, not a `sed` per range.
- **Seam map** (inside the stamp) — every file the change touches,
  including files that merely reference the thing (a scene instancing the
  node, a `.tres` needing a null-guard), from a grep, never recall. One
  whole-file entry each: `path — seam: <why>`. It is where the drone
  starts, not a fence it may not leave.
- **The drift stamp** — one fenced block, info string `drift-stamp <sha>`
  with the master sha the entries were checked at; one entry per line:
  `path`, optional `:start-end`, ` — `, free text. `mise run issue-drift`
  parses it; the last stamp on an issue wins. Every `docs/design/*` path the
  spec cites is an entry with a line range. A path a sibling will create is
  never an entry — name the sibling in prose and stamp an existing neighbour
  (the `.tres` the new file inherits).
- **Stubs on master** — when the unit adds classes or signatures and the
  shape is worth settling in code, and only from the main checkout (never a
  drone): `class_name`, signatures, the red test **under `pending()`**. One
  `mise run refresh`, `git status` (the checkout is shared), `git add`
  explicit paths, commit — then cut the stamp at that commit's sha, since
  the stub moved the lines. A stub is a proposal; a drone that finds it
  wrong says so and goes against it.

**Shapes and seams, not bodies** — never the implementation. **Every
section on a serious issue**; an omission is a written call ("no seams",
"exploratory / docs", "few-turn patch, the drone finds the edits faster than
we write the list"), never silence.

**Read it cold before promoting**, as a Sonnet with no chat history. If you
think "the orchestrator will explain that part", it is not `Ready`.

## 2. Split what is too big

A hub (has sub-issues, or too big for one unit) is never `Ready`; its
children are. **A parent never carries work**: all of it moves into
children, the hub's own defect as "child 0". The hub keeps the problem, the
decisions and the DAG; its status is derived, never set.

- **Drone-sized**: one subsystem, a handful of files, one test file, one or
  two deliverables, under ~150k drone context. More than three subsystems,
  five tests, or three deliverables is a split along state / wiring /
  consumer seams. Prefer more small children with native `blocked-by`.
- **One decision, one unit.** Where that is not a file boundary, split anyway
  and record the overlap.
- **Bed before siblings.** Three or more siblings sharing a recipe: what
  will drone two copy from drone one? A shared pattern not yet in code gets a
  bed unit the siblings are blocked on (a part only if two or more siblings
  use it), and a column of siblings gets a retrospective unit after it. A
  recipe that is already data plus a roster line needs no bed.
- A follow-up the hub does not need is a **sibling** linking back, never a
  child.
- Shared-file work every child touches (one `.tres`, a registry append) is
  the orchestrator's pre-step in the main checkout.
- Each child gets its own full Acceptance spec as its own body file. Name a
  sibling not yet filed by handle — `#{wiring}` — and the clerk substitutes
  the number. Never `@wiring` (a live mention; the gh shim refuses it).

## 3. Hand the board to the clerk

`Ready` is status, `design` / `blocked` labels dropped, and a milestone, in
one breath. The milestone is a default — the live one
(`mise gh-project -- roadmap`) or the parent's — never a question.

Write a work order next to the spec files: plain sentences, one line or
short paragraph per issue, saying what should be true afterwards. Declare
each new issue's handle where you create it. For example:

```
Milestone 3 for everything unless a line says otherwise.

#1130: post 1130-spec.md as a comment; drop the design and blocked labels. It is a hub — leave its status.
New issue {state} "Status tick: sparse schedule": under #1130, body state.md, label ui, Ready.
New issue {wiring} "Status tick: wiring": under #1130, body wiring.md, blocked by {state}, Ready.
#1128: move it under #1130.
#1119: clear its blockers, milestone 4, Needs design.
Check the drift stamps on {state} and {wiring}. Run refresh. Then hygiene.
```

Then spawn **one** `Agent(subagent_type: "clerk", prompt: "<work order path>")`.
It knows the commands and the traps; you state intent. Its report is one line
per issue: handle each `SKIPPED` / `FAILED` yourself (a corrected order and a
second clerk, or the one call by hand). A re-parent line gives the old
parent's open-child count — at zero, `land` / `hygiene --fix` will close
that hub; say so to whoever you report to.
