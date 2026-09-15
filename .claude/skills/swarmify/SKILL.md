---
name: swarmify
description: Take one GitHub issue from "has open design forks" to Ready — remove blockers, surface every unresolved decision, research the code and think each fork through with the user from both the technical and gameplay side, get them to settle it, write a crisp acceptance spec, split a hub into coherent children if needed, and move it to the `Ready` column. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "make #<n> ready/swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.
---

# Swarmify

Take one issue from "has open forks" to `Ready`, in this session, with the
owner, before any worktree exists. (Design behind this file:
`docs/charters/swarmify.md` — read it only if you are changing this file.)

The output has exactly one reader: a drone doing `gh issue view <n>` and
`--comments` cold, with no chat history and a bare fence. **`Ready` means
that drone can act.** The drone's brief carries only what the issue cannot
know — fence, seams this run, tier, advisor, budget — and restates nothing.

## The one rule

**Decisions are the owner's.** You surface forks and propose; the owner
chooses; you write the answer in the owner's words, dated, attributed as an
owner call. Never invent a design answer to reach `Ready`. Owner absent →
draft proposed resolutions and do **not** move the status.

## The cycle

### 1. Read the whole issue yourself

```bash
gh issue view <n>
gh issue view <n> --comments
```

Body *and* every comment, in this session — never summarised by a subagent.
A later comment routinely corrects an earlier one. Note the labels:
`design` / `blocked` mean forks are known-open.

### 2. Verify claims and grep seams — one Haiku Explore

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

### 3. Do the arithmetic

After pinning anything numeric, compute what it implies at both ends of the
range (level 1 and level 100, one node and two hundred). The fix that
surfaces is usually structural, and it surfaces from the numbers.

### 4. Enumerate every open fork

A fork is anything a drone would have to *decide*:

- **Floated alternatives** — "…or some other way", "maybe X, maybe Y".
- **Speculative asides riding a decision** — a second decision never rides a
  first: split it out (own child, own sibling, or a NOTES line) before
  promoting.
- **Unstated acceptance** — no failing test, no exact spec.
- **Unowned surfaces** — two plausible implementations landing on different
  modules means the *approach* is undecided.
- **Cross-issue dependencies** — recorded, not disqualifying (step 6).

List them numbered — `AskUserQuestion` for clean choices, prose for the rest.

### 5. Settle each fork with the owner

Every fork gets a pinned answer in the owner's words. An unsettleable fork
(needs a spike, needs another issue) keeps the issue in `Needs design`:
"still blocked, here is why" is a valid outcome. Never promote an issue a
drone will stall on.

File ownership is a map, not a gate: record which paths a unit touches so
the orchestrator can sequence; never contort the design to keep files
disjoint, never withhold `Ready` because two issues share a file.

### 6. Write the Ready comment

Post a comment (or edit the body) headed `## Acceptance spec`:

`````markdown
## Acceptance spec

**Decisions** (owner, <date>)
- <each resolved fork as one line of settled fact, in the owner's words>

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
- **Files touched** — the paths the work lands on; name any sibling that
  shares one, and which issue.
- **Acceptance** — the failing test to make green or an exact behavioural
  spec.
- **NOTES** — descoped asides, parked for their own issue.
- **Reading list** (inside the stamp) — 5–15 entries of `path:start-end —
  why`, "read these, nothing else". Not a file map, not a tour: each entry
  names what the reader learns there. Omit what should be skipped rather
  than listing it, unless a specific trap must be named. Every range is
  verified at write time (step 2, or `sed -n 'a,bp'`).
- **Seam map** (inside the stamp) — every file the change touches, including
  files that merely reference the thing, from step 2's grep; one whole-file
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

### 7. If it is a hub, decompose into Ready children

A hub (sub-issues > 0, or too big for one unit) is never `Ready` itself — its
children are. **A parent never carries work**: on split, *all* of the hub's
work moves into children, the hub's own defect included as "child 0". The hub
keeps the problem statement, the decisions and the DAG; never set its status
by hand — `land` and `hygiene --fix` derive it.

- Split along the seam the design has: one decision, one unit. Where that
  is also a file boundary, say so; where it is not, split anyway and record
  the overlap. A unit describing three or more deliverables is split before
  dispatch.
- A follow-up not required for the hub to be done is a sibling linking back,
  never a child.
- Shared-file work every child touches (one `.tres`, a registry append) is
  the orchestrator's pre-step in the main checkout, not parcelled out.
- Each child gets its own full `## Acceptance spec` (step 6).

```bash
gh issue create --parent <n> --title "…" --body-file <file>
mise gh-project -- status <child> ready                # or needs-design if it still forks
```

Record cross-issue dependencies as relations *and* in the spec prose:

```bash
gh issue create --blocked-by <n1>,<n2> --title "…" --body-file <file>
gh issue edit <child> --add-blocked-by <blocker>
```

### 8. Promote

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

- **Not implementation** beyond step 6's stubs.
- **Not a rubber stamp** — an issue with an unsettleable fork stays in
  `Needs design`.
- **Not a spawn** — the thinking runs here, with the owner; only step 2's
  lookup is delegated.
