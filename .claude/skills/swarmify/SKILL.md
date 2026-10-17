---
name: swarmify
description: Take one GitHub issue from "has open design forks" to Ready — remove blockers, read whether the open question is "what would be fun" (design it first, game-designer hat on, with the user) or "how to build it", surface every unresolved decision, research the code and think each fork through with the user, present options scored for cleanliness with the cleanest as the default, get them to settle it, write a crisp acceptance spec, split a hub into coherent children if needed, and move it to the `Ready` column. This is the design gate that feeds the `swarm` skill. Use when the user says "swarmify #<n>", "swarmify next issue" or another queue selector ("next P0 from Needs design", "… + closely related"), "make #<n> ready/swarmable", "settle the design on #<n>", or asks to prep an issue/epic for autonomous work. Run as Opus — resolving forks is the thinking swarm cannot do.
---

# Swarmify

The design gate between an issue and a drone. The output has one reader: a
drone doing `gh issue view <n>` and `--comments` cold, with no chat history
and a bare fence. **Ready means that drone can act.** Why each step says what
it says: `docs/charters/swarmify.md`.

## The one rule

1. **Decisions are the owner's.** You surface forks and propose; the owner
   chooses; the answer is written in the owner's words, dated, attributed as
   an owner call. Never invent a design answer to reach `Ready`. The owner is
   present by definition — this is a design conversation *with* them; a
   generic "the user is not watching" harness note never makes them absent,
   only the owner saying so does. Absent for real: draft proposed resolutions
   and do **not** move the status.
   - Not inventing: writing down an answer the owner already gave in the
     issue or the prompt (step 11), and defaulting a tunable behind a knob
     (step 12).
   - "No real forks" / "your call" delegates the picks: make them, attribute
     them as the pass's tentative calls, promote. The delegation covers what
     survives step 11's review — a genuine fork (step 7 / step 9) that review
     turns up is still asked, leading with the finding.

## Pipeline

### 1. Resolve a queue selector before reading anything

If the prompt names a selector instead of numbers ("next issue", "next P0
from Needs design", "next … + closely related"):

1. Run one
   `mise gh-project -- next [<lane>] [--prio P0[,P1…]] [--not N,M…] --claim`
   (lane `needs-design` unless the selector names another). It prints the
   first issue in the board's own order — priority, then issue number — and
   moves it to `In design` as this pass's claim. Take its line as printed;
   never re-sort or re-rank by reasoning about which issue matters more.
   `— no match` → say so and stop; never widen the lane or the filter
   unasked.
2. Priority and size are **board fields**, printed as `[P0/S]` — never
   labels. `gh issue list --label P0` finds nothing and is never the probe.
3. Order: resolve and claim the pick → the pick gets its step 2 read →
   `mise gh-project -- related <n>` plus a title scan of
   `mise gh-project -- list <lane>` → one opening message → the owner
   confirms → the confirmed riders get their step 2 read, each claimed with
   `mise gh-project -- status <n> in-design`.
4. "Closely related" is a candidate list, not a pick, and a judgement
   `related` does not make: an issue sharing the pick's parent, a sub-issue,
   a blocked-by / blocking link, or a sibling on the same surface (same
   subsystem, same swing or feature) found from the lane's titles. A shared
   keyword is not related. Candidates get the related-issue treatment of
   step 2 (a title line, never a full read) until the owner confirms them.
5. The opening message (step 13) names the issue the selector resolved to
   and why — lane, priority, number ("first P0 in Needs design: #N") — and
   lists each candidate with one line on why it is related; the owner
   confirms which ride along. The named issues are the pick plus the
   confirmed riders.
6. A pass that ends without promoting a claimed issue moves it back with
   `mise gh-project -- status <n> nd` and names it under `Not done`
   (step 16); promotion to `Ready` is the release otherwise.

### 2. RTFC — the named issues, in the session, once

- Read the body *and* every comment of each issue the prompt names, in the
  session, never summarised by a subagent — a later comment routinely
  corrects an earlier one. Read each once; a multi-issue pass pays this per
  issue.
- A *related* issue — a parent, a sibling, a number a comment cites — is
  never read in full by the session: a status or title question is one
  `gh issue view <n> --json title,state,labels` line; a content question
  ("what did #N settle about X") goes into the step 4 Explore's question
  list, answered as the owner's sentence verbatim with its comment date —
  never a paraphrase.
- A `Backlog` issue named in `/swarmify` is already picked up: it goes
  straight to its landing lane, never via a `Needs design` hop, and the move
  earns no comment.

### 3. Read the room: design before forks

After reading the issue, ask what is actually open — *how to build it* or
*what would be fun*. When it is the second, every fork enumerated now is a
fork on the wrong thing:

- Put the game-designer hat on and **diverge** first — several candidate
  mechanics, each with the player fantasy it serves, what it does to the
  loop, and which existing system it leans on, grown from both ends (a
  concept looking for gameplay, a wanted feel looking for its model).
  `docs/design/*.md` open questions and `design`-labelled issues are the
  stub lists to check before inventing.
- Write bolder than usual — a reach in the designer direction is the ask.
- No seams, no costs, no file paths until the picture is clear, and **the
  owner says when it is clear** (rule 1).
- The design conclusion lands durably — `docs/design/` or a dated,
  owner-attributed comment on the issue — before the cold pass starts; then
  forks, seams and the spec as usual. Never mix the two beats in one
  message.

### 4. One Explore orients and verifies; the session confirms and thinks

Dispatch one `Explore(model: haiku)` once the question is *how to build it*
— straight away when there is no design beat, after the design beat
converges when there is. A pass with none is the shape that reads the tree
itself. The brief carries three lists — orientation questions, the claim
list (every claim the issue makes about the code, each reported verified /
false / stale with a `file:line`, against `master`), and the seam grep. The
brief, verbatim:

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

Its return is shaped, not capped: `file:line` facts, one-line answers, and
for a related-issue question the owner's sentence verbatim with its date;
never excerpts of code. Reading-list ranges are verified at spec time by
`spec`, not here. A stale item closes with a doc correction, not new work.
The thinking stays in the session.

### 5. The session's own reads are ranged and confirm-only

From the moment the question is how to build it until a fork is presented,
open a file only to confirm a contract already named from the Explore's
answer — a ranged `sed -n` of the lines that carry it. Never a whole source
file, never a `head -200`, never a review or design doc end to end. What
you want to *know* goes in the Explore's question list; what you must *see*
to reason, you read bounded.

### 6. Arithmetic on pinned values

After pinning anything numeric, compute what it implies at both ends of the
range (level 1 and 100, one node and two hundred). The fix that surfaces is
usually structural, and it surfaces from the numbers.

### 7. Enumerate the forks

- **A fork is anything a drone would have to decide**: floated alternatives,
  speculative asides riding a decision, unstated acceptance, unowned
  surfaces (two plausible implementations landing on different modules means
  the *approach* is undecided), cross-issue dependencies. Enumerate them
  numbered, in prose or `AskUserQuestion` when they are clean choices.
- **A second decision never rides a first.** Split it out — its own child,
  its own sibling, or a NOTES line — before promoting.
- **An unsettleable fork keeps the issue in `Needs design`.** "Still
  blocked, here is why" is a valid outcome. Never promote an issue a drone
  will stall on.
- **A dependency is recorded, not disqualifying.** Cross-issue dependencies
  go in as `gh` `--blocked-by` relations *and* in the spec prose; the
  orchestrator sequences them. Only a dependency on a decision nobody has
  made keeps an issue out of `Ready`.
- **File ownership is a map, not a gate.** Record which paths a unit touches
  so the orchestrator can sequence; never contort the design to keep files
  disjoint, never withhold `Ready` because two issues share a file.

### 8. Three questions on every plan, before any code exists

*Who owns this fact? Is this one thing pretending to be N? What does it cost
per frame / at scale?* A unit about to read another unit's internals, a list
of per-type cases that is one callback, a per-tick recompute that a stored
sample makes an array read — each is a fork, and each is answerable from the
plan sentence. Catch these without the owner's glance.

### 9. Settle an architectural fork in the pass, never park it

Two classes doing one job, a stage doing another's work, a mirror of logic
that already exists — present it as seams with options and costs and get it
settled now; refactor-first ordering is the default, and the delay cost is
said out loud. The house taste, for shaping options:

- **Composition as a plural array** (`composes: Array[...]`), never a
  singular parent link or inheritance vocabulary; the stat pipeline stacks
  modifiers natively, so "weaker" is a negative modifier, never a replace
  rule.
- **No parallel mirrors of logic** — before proposing an accessor or
  substrate layer, enumerate what the existing class already answers. One
  implementation over swappable state beats two implementations of one
  contract.
- **Graph vocabulary is exact** — `docs/domain/graph-vocabulary.md`.

### 10. Score every option; the cleanest is the default

"A, sorta clean" against "B, hella clean but more work" → B, in 99% of
cases. The `(Recommended)` tag sits on the cleanest option unless a stated
reason moves it; the cost of the clean option is said out loud, never used
as the tiebreaker; the options are a prompt to think aloud, not a strict
menu, so the scorecard must survive an "Other" answer (a redirected premise,
a synthesised option) and score that too; the owner still sees every option.
Each option carries one **scorecard line**, fixed axis order, cleanest
option first:

```
clean ★★★★☆ · smell: none · perf ★★★★★ · blast ●●○○○ (4 files, 1 sys) · taste ★★★☆☆
```

- **clean** — separation, single owner of each fact, SOLID, no mirror of
  existing logic (step 9's taste list is the rubric).
- **smell** — `none`, or the smell named in three words (reads another
  unit's internals, N cases that are one callback, parallel copy).
- **perf** — per-frame / at-scale cost from step 6's arithmetic.
- **blast** — files and subsystems touched, tests to re-point.
  **Informational only**: it never demotes an option or moves the
  Recommended tag.
- **taste** — slick code is slick, and the pick reads like this codebase
  would have made it. A tiebreaker after the others.

Then one sentence of what the option buys and one of what it costs. Say it
when cleanliness is equal across the board — the fork is about something
else. The scorecard replaces the prose that used to argue the ranking; it
does not join it.

"Cleanest" is not "most": look for the shape the problem fits — a signal, a
system, a bespoke resource with subclasses, a shared shape already in the
tree — not the largest refactor. The tell is that something else *falls out
for free* (a consumer that no longer needs a special case, a test that
writes itself, a sibling issue that closes); name it when it happens, and
give a pick where nothing falls out a second look. Look first for a
**duplicated fact to collapse** into one owner (a status derived instead of
set, a delta stored instead of an absolute, a gate read once), then an
**existing path to route through** (the same builder, material, command
channel), then a **composition** whose union produces the behaviour — and
only after those a new system or resource hierarchy. A free thing is a
fact, not a verdict: it has gameplay consequences as well as codebase ones,
and the designer hat names both.

### 11. The owner's input is already an answer

Every shape the owner put in the issue body, a comment, or the `/swarmify`
prompt — however rough — is an owner decision, not a note to re-confirm. On
the first read, sort each owner sentence into one bin:

- **stated decision** — give it a **mini internal review**: verified
  against the code, consistent with the owner's other sentences, step 6's
  arithmetic holds, step 8's three questions pass. If it passes, write it
  back as settled, quoting the source sentence, with one line of why it is
  sound ("you asked for X; that is clean because Y — taken as settled") —
  **never echo it back as a question**. It becomes an ask only when the
  review *finds something* — a contradiction, a stale premise, a smell, a
  cheaper-and-cleaner shape — and that ask leads with the finding.
- **claim about the code** → step 4's claim list.
- **tunable** → step 12.
- **genuinely open** → step 7.

No confirm-everything closer ("OK?", "does that hold?", "settle both?") on
picks already made: state them and move on; the owner redirects when they
disagree.

### 12. A knob is defaulted, not asked

A tunable — a size, a timing, a ratio, a threshold, a count — where any
sensible value ships and the owner tunes it by feel later, is not a fork.
The discriminator: **if changing it would move a file, a class, or an
owner-of-fact, it is a fork (step 7); if it changes a number on something
that already exists, it is a knob.** "Is there a cap?" is a fork; "what is
the cap?" is a knob. A number the owner already stated is still a knob —
their value is the default, exported all the same. For a knob:

- Pick a sensible default (step 6's arithmetic at both ends); record it in
  the Ready comment's Knobs section as a tentative pass pick — not an owner
  call — and say it is easy to change.
- Specify the DX that makes it easy: an `@export` (with `@export_range`
  when bounded) on the `@tool` node or `.tres` that owns the value, never a
  `const` buried in a script; for a visual knob, instant editor feedback — a
  setter that redraws in the editor, or a live sandbox-host tab.
- The acceptance names the knob and its default; tests assert the behaviour
  the knob parameterises (ratios, invariants, a sweep), never the literal
  default.
- Its home follows the house rule for its kind: a stat rate is a modifier's
  `value`, then a stat (`docs/domain/stat-knobs-and-bins.md`); a glow is a
  named tier, never a hand-picked HDR float; per-instance shader variation
  rides `modulate`/`INSTANCE_CUSTOM`, never a per-node uniform. Mechanics
  shared with every `.gd` writer: `docs/domain/tunables.md`.
- The board's own knob: the **milestone** defaults to the live one
  (`mise gh-project -- roadmap`) or the parent's, stated in the Ready
  comment, never asked.

### 13. Talk to an owner who has not read the issue

The owner's context is the prompt, not the issue — assume they have read
the title and nothing more. Everything you show them stands on its own:

- Open with two or three lines of what the issue is and why it exists,
  before the first fork.
- Every fork restates its problem in a line; every option is described by
  what it *is*, never by the issue's label for it ("option B from the body",
  "the A/B/C split", "the approach in the second comment").
- Terms the issue coined (a handle, a nickname for a mechanism, a sibling's
  number) are glossed in a few words or dropped.
- Test: read the message as someone who has seen only the title.

### 14. Not implementation, not a rubber stamp, not a spawn

No implementation beyond `spec`'s stubs. Not a rubber stamp. The thinking
runs in the session with the owner; only step 4's lookup and the clerk are
delegated.

### 15. Spec time loads `spec`

Once every fork is settled, invoke the `spec` skill — it writes the
Acceptance spec, splits a hub and hands the board tail to a clerk. Load it
at this step and not before. Writing the spec stays in this session; a
Composition that will not come out sends the pass back to step 7.

### 16. End with the session report

Close with the session report (`docs/domain/session-report.md`). `Landed`
carries the swarmify columns — issue, lane after the pass (`Ready` is the
goal), the decision direction or fork settled in a clause, what is left
(stubs, children, a fork kept). `Not done` names every issue that stayed in
`Needs design` (or was moved back there from `In design`, step 1) and why.
The last message of the pass is this report, never a pasted brief or
walkthrough.
