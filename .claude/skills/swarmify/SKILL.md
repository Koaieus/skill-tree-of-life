---
name: swarmify
description: >-
  Take one GitHub issue from "has open design forks" to Ready — remove
  blockers, read whether the open question is "what would be fun" (design it
  first, game-designer hat on, with the user) or "how to build it", surface
  every unresolved decision, research the code and think each fork through
  with the user, present options scored for cleanliness with the cleanest as
  the default, get them to settle it, write a crisp acceptance spec, split a
  hub into coherent children if needed, and move it to the `Ready` column.
  This is the design gate that feeds the `swarm` skill. Use when the user says
  "swarmify #<n>", "make #<n> ready/swarmable", "settle the design on #<n>",
  or asks to prep an issue/epic for autonomous work. Run as Opus — resolving
  forks is the thinking swarm cannot do.
---

# Swarmify

Design behind every line: `docs/charters/swarmify.md`. This file is the steps.

The output has one reader: a drone doing `gh issue view <n>` and `--comments`
cold, with no chat history. **Ready means that drone can act.**

## 0. Stance — hold these for the whole pass

- **Decisions are the owner's.** You surface forks and propose; the owner
  chooses; every answer is written in the owner's words, dated, attributed as
  an owner call. Never invent a design answer to reach `Ready`.
- **The owner is present by definition.** A `/swarmify` is a design
  conversation *with* them. A generic harness note ("the user is not
  watching") never makes them absent; only the owner saying so does. Absent
  for real: draft proposed resolutions on the issue and do **not** move the
  status.
- Two things are *not* inventing: writing down an answer the owner already
  gave in the issue or the prompt (step 2 — re-asking it is the failure), and
  defaulting a tunable behind a knob (step 7 — a value is not a design
  answer).
- An owner's "no real forks" / "your call" delegates the picks: make them,
  attribute them as the pass's tentative calls, promote. The delegation
  covers what survives step 2's review — "no real forks" is itself a claim,
  and a genuine fork the review turns up is still asked, leading with the
  finding.
- **Not implementation** beyond `spec`'s stubs. **Not a rubber stamp.**
  **Not a spawn** — the thinking runs in this session with the owner; only
  step 4's Explore and `spec`'s clerk are delegated.

## 1. Read the named issues yourself

- For each issue the prompt names: read the body **and every comment**, in
  this session, once. Never through a subagent summary — a later comment
  routinely corrects an earlier one. A multi-issue pass pays this per issue.
- A *related* issue (parent, sibling, a number a comment cites) is not read
  in full:
  - status or title question → one line:
    `gh issue view <n> --json title,state,labels`
  - content question ("what did #N settle about X") → goes on the Explore's
    question list (step 4), answered as the owner's sentence **verbatim with
    its comment date**, never a paraphrase.

## 2. Bin every owner sentence on the first read

Every shape the owner put in the issue body, a comment, or the `/swarmify`
prompt — however rough — is an owner decision, not a note to re-confirm.
Sort each owner sentence into exactly one bin:

| Bin | Goes to |
|---|---|
| **stated decision** | mini internal review (below), then written back as settled |
| **claim about the code** | the Explore's claim list (step 4) |
| **tunable** | a knob (step 7) |
| **genuinely open** | a fork (step 6) |

**Mini internal review** of a stated decision: verified against the code,
consistent with the owner's other sentences, the arithmetic of step 6 holds,
the three questions of step 6 pass. If it passes, write it back as settled,
quoting the source sentence, with one line of why it is sound — "you asked
for X; that is clean because Y — taken as settled" — and **never echo it
back as a question**. It becomes an ask only when the review *finds
something*: a contradiction, a stale premise, a smell, a cheaper-and-cleaner
shape the owner would want to hear about. That ask leads with the finding.

## 3. Read the room — design before forks

Ask what is actually open: **how to build it** or **what would be fun**.

If the blocker is *what would be fun*, every fork enumerated now is a fork
on the wrong thing. Switch hats:

- Put the game-designer hat on and **diverge** first — several candidate
  mechanics, each with the player fantasy it serves, what it does to the
  loop, and which existing system it leans on.
- Grow them from both ends: a concept looking for gameplay, a wanted feel
  looking for its model. Check the stub lists before inventing —
  `docs/design/*.md` open questions and `design`-labelled issues.
- Write bolder than usual: the low-temperature default is right for code and
  wrong for this beat.
- **No seams, no costs, no file paths until the picture is clear, and the
  owner says when it is clear.**
- Land the design conclusion durably — `docs/design/` or a dated,
  owner-attributed comment on the issue — *before* the cold pass starts.
- The two beats are never mixed in one message.

Then continue with step 4 as usual.

## 4. Dispatch the Explore, then confirm with ranged reads

Dispatch **one** `Explore(model: haiku)` — straight away when there is no
design beat, after step 3 converges when there is. A pass with none is the
shape that reads the tree itself. Fact-checking is not thinking; skipping it
specs work against a world two commits stale.

The brief carries three lists and a return shape:

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

- A **stale** claim closes with a doc correction, not new work.
- Reading-list ranges are verified at spec time by `spec`, not here.
- **The thinking stays in the session.** The Explore orients and verifies;
  you confirm and think.

**Your own reads are ranged and confirm-only.** From here until a fork is
presented, open a file only to confirm a contract you have already named
from the Explore's answer — a ranged `sed -n 'A,Bp'` of the lines that
carry it. Never a whole source file, never a `head -200`, never a review or
design doc end to end. Bash reads bypass every line cap; the discipline is
the step. What you want to *know* goes on the Explore's question list; what
you must *see* to reason, you read bounded.

## 5. Open to the owner as someone who has seen only the title

The owner's context is the prompt, not the issue. Assume they have read the
title and nothing more.

- Open with two or three lines of what the issue is and why it exists,
  before the first fork.
- Every fork restates its problem in a line.
- Every option is described by what it *is*, never by the issue's label for
  it — no "option B from the body", "the A/B/C split", "the approach in the
  second comment".
- Terms the issue coined (a handle, a nickname, a sibling's number) are
  glossed in a few words or dropped.
- Test: read your message as someone who has seen only the title.

## 6. Enumerate and settle the forks

**A fork is anything a drone would have to decide**: floated alternatives,
speculative asides riding a decision, unstated acceptance, unowned surfaces
(two plausible implementations landing on different modules means the
*approach* is undecided), cross-issue dependencies. Enumerate them numbered,
in prose or `AskUserQuestion` when they are clean choices.

**Three questions on every plan, before any code exists:**

1. *Who owns this fact?* — a unit about to read another unit's internals.
2. *Is this one thing pretending to be N?* — a list of per-type cases that is
   one callback.
3. *What does it cost per frame / at scale?* — a per-tick recompute that a
   stored sample makes an array read.

Each is a fork, answerable from the plan sentence; catch them without the
owner's glance.

**Arithmetic on pinned values.** After pinning anything numeric, compute what
it implies at both ends of the range (level 1 and 100, one node and two
hundred). The fix that surfaces is usually structural.

**An architectural fork is settled in the pass, not parked.** Two classes
doing one job, a stage doing another's work, a mirror of logic that already
exists — present it as seams with options and costs and get it settled now.
Refactor-first ordering is the default; the delay cost is said out loud. An
unsettled seam leaks into every consumer written against it. Shape the
options to the house taste:

- **Composition as a plural array** — `composes: Array[...]`, never a
  singular parent link or inheritance vocabulary (`extends` is a GDScript
  keyword). A singular chain forces independent batches into an arbitrary
  nesting order; the stat pipeline stacks modifiers natively, so "weaker" is
  a negative modifier, never a replace rule.
- **No parallel mirrors of logic** — before proposing an accessor or
  substrate layer, enumerate what the existing class already answers. One
  implementation over swappable state beats two implementations of one
  contract; parallel copies drift and the drift surfaces as gameplay
  divergence between the live and the AI/preview path.
- **Graph vocabulary is exact** — `docs/domain/graph-vocabulary.md`.

**The cleanest option is the default, and every option is scored.** "A,
sorta clean" against "B, hella clean but more work" is B in 99% of cases.
The `(Recommended)` tag sits on the cleanest option unless a stated reason
moves it; the cost of the clean option is said out loud, never used as the
tiebreaker; the owner still sees every option. Each option carries one
scorecard line, fixed axis order, cleanest option listed first:

```
clean ★★★★☆ · smell: none · perf ★★★★★ · blast ●●○○○ (4 files, 1 sys) · taste ★★★☆☆
```

- **clean** — separation, single owner of each fact, SOLID, no mirror of
  existing logic (the taste list above is the rubric).
- **smell** — `none`, or the smell named in three words (reads another
  unit's internals, N cases that are one callback, parallel copy).
- **perf** — per-frame / at-scale cost from the arithmetic above.
- **blast** — files and subsystems touched, tests to re-point.
  **Informational only**: never demotes an option or moves the tag.
- **taste** — slick code is slick, and the pick reads like this codebase
  would have made it. Tiebreaker after the others.

Then one sentence of what the option buys and one of what it costs. Equal
cleanliness across the board is worth saying — the fork is about something
else. The scorecard *replaces* the prose that argued the ranking; it does
not join it. A scorecard must survive an "Other" answer — options are a
prompt to think aloud, not a strict menu.

"Cleanest" is not "most": look for the shape the problem fits — a signal, a
system, a bespoke resource with subclasses, a shared shape already in the
tree — not the largest refactor. Look first, in this order:

1. a **duplicated fact to collapse** into one owner (a status derived instead
   of set, a delta stored instead of an absolute, a gate read once);
2. an **existing path to route through** (the same builder, material,
   command channel);
3. a **composition** whose union produces the behaviour;
4. only then a new system or resource hierarchy.

The tell the shape is found: something *falls out for free* — a consumer
that no longer needs a special case, a test that writes itself, a sibling
issue that closes. Name it when it happens; a pick where nothing falls out
is worth a second look. A free thing is a fact, not a verdict: it has
gameplay consequences too, and the designer hat names both.

**A second decision never rides a first.** Split it out — its own child, its
own sibling, or a NOTES line — before promoting.

**State picks, do not re-confirm them.** No confirm-everything closer
("OK?", "does that hold?", "settle both?") on picks already made; state them
and move on. The owner redirects when they disagree.

## 7. Default the knobs — never ask them

A tunable — a size, a timing, a ratio, a threshold, a count — where any
sensible value ships and the owner tunes by feel later, is not a fork.

**Discriminator:** if changing it would move a file, a class, or an
owner-of-fact, it is a fork (step 6); if it changes a number on something
that already exists, it is a knob. "Is there a cap?" is a fork; "what is the
cap?" is a knob. A number the owner already stated is still a knob — their
value is the default, exported all the same.

For each knob:

- Pick a sensible default (arithmetic at both ends of the range).
- Record it in the Ready comment's **Knobs** section as a tentative pass
  pick — not an owner call — and say it is easy to change.
- **Specify the DX that makes it easy**: an `@export` (`@export_range` when
  bounded) on the `@tool` node or `.tres` that owns the value, never a
  `const` buried in a script; for a visual knob, instant editor feedback — a
  setter that redraws in the editor, or a live sandbox-host tab.
- The acceptance names the knob and its default; tests assert the behaviour
  the knob parameterises (ratios, invariants, a sweep), never the literal
  default, so retuning never reds a test.
- The knob's *home* follows the house rule for its kind: a stat rate is a
  modifier's `value`, then a stat (`docs/domain/stat-knobs-and-bins.md`); a
  glow is a named tier, never a hand-picked HDR float
  (`docs/domain/hdr-color.md`); per-instance shader variation rides
  `modulate`/`INSTANCE_CUSTOM`, never a per-node uniform
  (`docs/domain/rendering-performance.md`). The mechanics live in
  `docs/domain/tunables.md`; this step is only "default in the spec, don't
  ask".

The board's one knob: the **milestone** defaults to the live one
(`mise gh-project -- roadmap`) or the parent's, stated in the Ready comment,
never asked.

## 8. Decide the lane

- **An unsettleable fork keeps the issue in `Needs design`.** "Still blocked,
  here is why" is a valid outcome. Never promote an issue a drone will stall
  on.
- A `Backlog` issue named in `/swarmify` is already picked up: it goes
  straight to its landing lane, never via a `Needs design` hop, and the move
  earns no comment.
- **A dependency is recorded, not disqualifying.** Cross-issue dependencies
  go in as `gh` `--blocked-by` relations *and* in the spec prose; the
  orchestrator sequences them. Only a dependency on a decision nobody has
  made keeps an issue out of `Ready`.
- **File ownership is a map, not a gate.** Record which paths a unit touches
  so the orchestrator can sequence; never contort the design to keep files
  disjoint, never withhold `Ready` because two issues share a file.

## 9. Spec time — invoke `spec`

Once every fork is settled, invoke the `spec` skill. Loaded at this step and
not before. It writes the Acceptance spec, splits a hub into children along
its real seams, and hands the board tail (comment, children, relations,
status, milestone) to a clerk. Writing the spec stays in this session — it
is the compressed thinking — and a Composition that will not come out sends
you back to step 6.

## 10. Close with the session report

End the pass with the session report (`docs/domain/session-report.md`):

- `Landed` carries the swarmify columns — issue, lane after the pass
  (`Ready` is the goal), the decision direction or fork settled in a clause,
  what is left (stubs, children, a fork kept).
- `Not done` names every issue that stayed in `Needs design` and why.

The last message of the pass is this report, never a pasted brief or
walkthrough.
