---
name: swarmify
description: 'Take one GitHub issue from "has open design forks" to Ready — remove blockers, read whether the open question is "what would be fun" (design it first, game-designer hat on, with the user) or "how to build it", surface every unresolved decision, research the code and think each fork through with the user, present options scored for cleanliness with the cleanest as the default, get them to settle it, write a crisp acceptance spec, split a hub into coherent children if needed, and move it to the `Ready` column; or run a design talk with no Ready target that settles calls into docs and filed issues. Every pass closes by filing what was settled, an ADR check and an advisor review. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "swarmify next issue" or another queue selector ("next P0 from Needs design", "… + closely related"), "swarmify <topic or handoff file>", "make #<n> ready/swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.'
---

# Swarmify

The design gate between an issue and a drone: one issue goes from "has open
forks" to `Ready`, in this session, with the owner, before any worktree
exists. The reader of your output is a drone doing `gh issue view <n>` and
`--comments` cold, with no chat history and a bare fence — **the Ready
criterion is that such a drone can act.** Why each step is shaped as it is:
`docs/charters/swarmify.md`.

## 0. The one rule — decisions are the owner's

- You surface forks and propose; the owner chooses; every answer is written
  in the owner's words, dated, attributed as an owner call. Never invent a
  design answer to reach `Ready`.
- The owner is present by definition: a `/swarmify` is a design conversation
  *with* them. A generic "the user is not watching" harness note does not
  make them absent — only the owner saying so does. Absent for real: draft
  proposed resolutions on the issue and do **not** move the status.
- Two things are not inventing: writing down an answer the owner already
  gave in the issue or the prompt (step 5), and defaulting a tunable behind a
  knob (step 5).
- An owner's "no real forks" / "your call" delegates the picks: make them,
  attribute them as the pass's tentative calls, promote. The delegation
  covers what survives step 5's review — a genuine fork (step 4) or
  architectural fork (step 4) the review turns up is still asked, leading
  with the finding.
- Not implementation beyond `spec`'s stubs. Not a rubber stamp. Not a spawn:
  the thinking runs here with the owner; only the step 3 Explore, the clerk
  (inside `spec`), the close's filing subagent (step 7) and a bench (step 4)
  are delegated.
- A swarmify pass, design talk included, ignores the global context target
  until 200k and does not hand off for size before it; at 200k it finishes
  cleanly through step 7.

## 1. Resolve the target

**Issue numbers named** → they are the named issues; go to step 2.

**A queue selector** ("next issue", "next P0 from Needs design", "next … +
closely related") → resolve it before anything is read:

```
mise gh-project -- next [<lane>] [--prio P0[,P1…]] [--not N,M…] --claim
```

lane `needs-design` unless the selector names another. It prints the first
issue in the board's own order (priority, then issue number) as `[P0/S]
…` and moves it to `In design` — the pass's claim. Take its line as printed,
never re-sorted or re-ranked by which issue seems to matter more. `— no
match` → say so and stop; never widen the lane or the filter unasked.
Priority and size are board fields, never labels: `gh issue list --label P0`
finds nothing and is never the probe (`docs/domain/issue-workflow.md`, *The
board*). Then, in order:

1. the pick gets its step 2 read;
2. `mise gh-project -- related <n>` plus a title scan of
   `mise gh-project -- list <lane>` build the candidate list — an issue
   sharing the pick's parent, a sub-issue, a blocked-by / blocking link, or
   a sibling on the same surface (same subsystem, same swing or feature); a
   shared keyword is not related. Candidates get only the related-issue
   treatment of step 2 (a title line) until confirmed;
3. one opening message (step 6 rules) names the issue the selector resolved
   to and why — lane, priority, number ("first P0 in Needs design: #N") —
   and lists each candidate with one line on why it is related;
4. the owner confirms which ride along;
5. each confirmed rider gets its step 2 read and is claimed with
   `mise gh-project -- status <n> designing`.

The named issues are the pick plus the confirmed riders. A claimed issue the
pass does not promote goes back with `mise gh-project -- status <n> nd` and
is named under `Not done` in the report (step 8).

**A topic, a hub, or a handoff file** with no `Ready` target → a design-talk
run (step 7a). A handoff file named in the prompt is read in full and
checked before the pass begins: each claim it makes about the code and each
issue it names is verified against the code and the board, and a correction
is said in the first message.

**A `Backlog` issue** named here is already picked up: it goes straight to
its landing lane, never via a `Needs design` hop, and the move earns no
comment.

**"Needs a design pass"** means the `Needs design` lane. Never `Intake`.

## 2. Read the named issues — yourself, once

- Read the body **and every comment** of each named issue, in this session,
  never summarised by a subagent; a later comment routinely corrects an
  earlier one. Read each once; a multi-issue pass pays this per issue.
- A *related* issue (a parent, a sibling, a number a comment cites) is never
  read in full here: a status or title question is one
  `gh issue view <n> --json title,state,labels`; a content question ("what
  did #N settle about X") goes into the step 3 Explore's question list,
  answered as the owner's sentence verbatim with its comment date — never a
  paraphrase.
- On the first read, sort each owner sentence into one bin: **stated
  decision** (→ step 5), **claim about the code** (→ step 3 claim list),
  **tunable** (→ step 5 knobs), or **genuinely open** (→ step 4).

## 3. Read the room, then orient

**Which question is open — *how to build it* or *what would be fun*?**

- *What would be fun* → the design beat first. Put the game-designer hat on
  and **diverge**: several candidate mechanics, each with the player fantasy
  it serves, what it does to the loop, and which existing system it leans
  on, grown from both ends (a concept looking for gameplay, a wanted feel
  looking for its model). Check the stub lists before inventing:
  `docs/design/*.md` open questions and `design`-labelled issues. Write
  bolder than usual — a reach in the designer direction is the ask. No
  seams, no costs, no file paths until the picture is clear, and **the owner
  says when it is clear**. Land the conclusion durably — `docs/design/` or a
  dated, owner-attributed comment on the issue — before the cold pass
  starts. Never mix the design beat and the fork beat in one message.
  Prose, not `AskUserQuestion`, for this beat.
- *How to build it* → dispatch the Explore now (straight away when there is
  no design beat; after the design beat converges when there is). One
  `Explore(model: haiku)`, three lists, shaped return. The brief, verbatim:

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

  The claim list is every claim the issue makes about the code, checked
  against `master`. A stale item closes with a doc correction, not new work.
  Reading-list ranges are verified later by `spec`, not here. The thinking
  stays in this session.

**Your own reads are ranged and confirm-only.** From here until a fork is
presented, open a file only to confirm a contract you have already named
from the Explore's answer — a ranged `sed -n` of the lines that carry it,
never a whole source file, never a `head -200`, never a review or design doc
end to end. What you want to *know* goes in the Explore's question list; what
you must *see* to reason you read, bounded.

**Arithmetic on pinned values.** After pinning anything numeric, compute
what it implies at both ends of the range (level 1 and 100, one node and
two hundred). The structural fix surfaces from the numbers.

## 4. Enumerate the forks

- **A fork is anything a drone would have to decide**: floated
  alternatives, speculative asides riding a decision, unstated acceptance,
  unowned surfaces (two plausible implementations landing on different
  modules means the *approach* is undecided), cross-issue dependencies.
  Number them.
- **Three questions on every plan, before any code exists**: who owns this
  fact? is this one thing pretending to be N? what does it cost per frame /
  at scale? A unit reading another unit's internals, a list of per-type
  cases that is one callback, a per-tick recompute that a stored sample makes
  an array read — each is a fork, answerable from the plan sentence.
- **An architectural fork is settled in the pass, never parked** — two
  classes doing one job, a stage doing another's work, a mirror of logic
  that already exists. Present it as seams with options and costs and settle
  it now; refactor-first ordering is the default, and the delay cost is said
  out loud. The house taste for shaping the options:
  - composition as a plural array — `composes: Array[...]` — never a
    singular parent link or inheritance vocabulary; the stat pipeline stacks
    modifiers natively, so "weaker" is a negative modifier, never a replace
    rule;
  - no parallel mirrors of logic — before proposing an accessor or substrate
    layer, enumerate what the existing class already answers; one
    implementation over swappable state beats two implementations of one
    contract;
  - graph vocabulary is exact — `docs/domain/graph-vocabulary.md`.
- **A second decision never rides a first.** Split it out — its own child,
  its own sibling, or a NOTES line — before promoting.
- **A dependency is recorded, not disqualifying**: cross-issue dependencies
  go in as `--blocked-by` relations *and* in the spec prose; the orchestrator
  sequences them. Only a dependency on a decision nobody has made keeps an
  issue out of `Ready`.
- **File ownership is a map, not a gate**: record which paths a unit
  touches; never contort the design to keep files disjoint, never withhold
  `Ready` because two issues share a file.
- **A perf number is measured or marked an estimate.** Never quote an
  inferred floor. When a fork's ranking turns on a number nobody measured at
  the range that matters, a subagent bench runs before the
  `AskUserQuestion`, not after.

## 5. Settle what the owner already said; default the knobs

- **The owner's input is already an answer.** Every shape the owner put in
  the issue body, a comment, or the prompt — however rough — is a decision,
  not a note to re-confirm. Each stated decision gets a **mini internal
  review**: verified against the code (step 3 claims), consistent with the
  owner's other sentences, step 3's arithmetic holds, step 4's three
  questions pass. If it passes, write it back as settled, quoting the source
  sentence, with one line of why it is sound ("you asked for X; that is
  clean because Y — taken as settled") — **never echo it back as a
  question**. It becomes an ask only when the review *finds something* — a
  contradiction, a stale premise, a smell, a cheaper-and-cleaner shape — and
  that ask leads with the finding. No confirm-everything closers ("OK?",
  "settle both?") on picks already made: state them and move on.
- **A knob is defaulted, not asked.** A tunable — a size, a timing, a
  ratio, a threshold, a count — where any sensible value ships and the owner
  tunes it by feel later is not a fork. The discriminator: if changing it
  would move a file, a class, or an owner-of-fact, it is a fork; if it
  changes a number on something that already exists, it is a knob. "Is there
  a cap?" is a fork; "what is the cap?" is a knob. A number the owner stated
  is still a knob — their value is the default, exported all the same. For
  each knob: pick a sensible default (arithmetic at both ends), record it in
  the Ready comment's Knobs section as a tentative pass pick — not an owner
  call — say it is easy to change, and **specify the DX that makes it
  easy**: an `@export` (`@export_range` when bounded) on the `@tool` node or
  `.tres` that owns the value, never a `const` buried in a script; for a
  visual knob, instant editor feedback (a setter that redraws in the editor,
  or a live sandbox-host tab). The acceptance names the knob and its
  default; tests assert the behaviour the knob parameterises (ratios,
  invariants, a sweep), not the literal default. A knob's *home* follows the
  house rule for its kind: a stat rate is a modifier's `value`, then a stat
  (`docs/domain/stat-knobs-and-bins.md`); a glow is a named tier, never a
  hand-picked HDR float (`hdr-color.md`); per-instance shader variation
  rides `modulate`/`INSTANCE_CUSTOM`, never a per-node uniform
  (`rendering-performance.md`). The mechanics live in
  `docs/domain/tunables.md`; this skill's half is: default in the spec,
  don't ask.
- The **milestone** is a knob of the board: default to the live one
  (`mise gh-project -- roadmap`) or the parent's, state it in the Ready
  comment, never ask.

## 6. Present the remaining forks — scored, restated, rapid-fire

- **The owner's context is the prompt, not the issue.** Assume they have
  read the title and nothing more. Open with two or three lines of what the
  issue is and why it exists, before the first fork. Every fork restates its
  problem in a line; every option is described by what it *is*, never by the
  issue's label for it ("option B from the body", "the A/B/C split" assume
  a read that did not happen). Terms the issue coined are glossed in a few
  words or dropped. Test: read the message as someone who has seen only the
  title.
- **The cleanest option is the default, and every option is scored.**
  "A, sorta clean" against "B, hella clean but more work" → B. The
  `(Recommended)` tag sits on the cleanest option unless a stated reason
  moves it; the cost of the clean option is said out loud, never used as the
  tiebreaker; the owner still sees every option. Options are a prompt to
  think aloud, not a strict menu — the scorecard must survive an "Other"
  answer (a redirected premise, a synthesised option) and score that too.
  Each option carries one **scorecard line**, fixed axis order, cleanest
  option first:

  ```
  clean ★★★★☆ · smell: none · perf ★★★★★ · blast ●●○○○ (4 files, 1 sys) · taste ★★★☆☆
  ```

  - **clean** — separation, single owner of each fact, SOLID, no mirror of
    existing logic (the step 4 taste list is the rubric);
  - **smell** — `none`, or the smell in three words (reads another unit's
    internals, N cases that are one callback, parallel copy);
  - **perf** — per-frame / at-scale cost from step 3's arithmetic;
  - **blast** — files and subsystems touched, tests to re-point.
    Informational only: it never demotes an option or moves the Recommended
    tag;
  - **taste** — slick code, and the pick reads like this codebase would have
    made it. A tiebreaker after the others.

  Then one sentence of what the option buys and one of what it costs. The
  line replaces the prose that argued the ranking; it does not join it.
  Equal cleanliness across the board is worth saying — the fork is about
  something else.
- "Cleanest" is not "most": look for the shape the problem fits — a signal,
  a system, a bespoke resource with subclasses, a shared shape already in
  the tree — not the largest refactor. Look first for a **duplicated fact
  to collapse** into one owner (a status derived instead of set, a delta
  stored instead of an absolute, a gate read once), then an **existing path
  to route through** (the same builder, material, command channel), then a
  **composition** whose union produces the behaviour — and only after those
  a new system or resource hierarchy. The tell that the shape is found is
  that something *falls out for free* — a consumer that no longer needs a
  special case, a test that writes itself, a sibling issue that closes. Name
  it when it happens; a pick where nothing falls out gets a second look. A
  free thing is a fact, not a verdict: name its gameplay consequences as
  well as its codebase ones.
- **Forks reach the owner through `AskUserQuestion`, rapid-fire**: up to
  four questions per call, one call after another until the forks are
  settled, each question carrying its scorecard and its restatement. Never a
  numbered prose list the owner answers by typing. Prose only for the design
  beat (step 3) and for a fork whose options do not fit four choices.
- **An unsettleable fork keeps the issue in `Needs design`.** "Still
  blocked, here is why" is a valid outcome; never promote an issue a drone
  will stall on.

## 7. Spec, then close

**Spec time loads `spec`.** Once every fork is settled, invoke the `spec`
skill: it writes the Acceptance spec, splits a hub into children and hands
the board tail to a clerk. Load it at this step and not before. Writing the
spec stays in this session — it is the compressed thinking — and a
Composition that will not come out sends the pass back to step 4.

**7a. A design-talk run** — a topic, a hub or a handoff file, no `Ready`
target: no code is touched, the commits are docs (`docs/design/`, the issue,
ADRs), and the outcome is settled calls and filed issues, not a lane move.
Steps 0, 3 (design beat), 5 and 6 bind it as they bind any pass; it closes
through 7b; its report (step 8) names what was settled and filed in place of
a lane move.

**7b. Every pass closes the same way, before its report.** In order:

- (a) each call settled in the conversation is written down as the owner's
  dated words in its home — the issue, `docs/design/` (step 0);
- (b) each settled item not yet on the board is filed as its own issue
  through `spec`, at the lane and priority the owner names; none named →
  one `AskUserQuestion`, `Needs design` as the recommended lane. When there
  are several, the bodies and docs are written by one subagent briefed from
  this session's context;
- (c) each settled call is put through the `adr` skill's gate — invoke
  `adr`; an ADR is written by that skill, never by hand;
- (d) one `advisor` call reviews what the pass settled and filed;
- (e) the report (step 8).

When the work continues in a fresh session, invoke `handoff` for the resume
half; the report's last line is the one-line resume prompt it gives.

## 8. End with the session report

The last message of the pass is the session report
(`docs/domain/session-report.md`), never a pasted brief or walkthrough:

- `Landed` carries the swarmify columns — issue, lane after the pass
  (`Ready` is the goal), the decision direction or fork settled in a
  clause, what is left (stubs, children, a fork kept);
- `Not done` names every issue that stayed in `Needs design` and why,
  including any claimed pick or rider returned with
  `mise gh-project -- status <n> nd`;
- for a design-talk run, what was settled and filed in place of a lane
  move;
- last line: the resume prompt, when there is one.
