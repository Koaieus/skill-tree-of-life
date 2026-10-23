# Charter — charter

The design behind `.claude/skills/charter/SKILL.md`. The skill is derived
from this; change the wish here, then re-derive the file — through the
skill itself. See [README](README.md) for the protocol this skill enforces.

## What the skill is for

The one way to change a skill (`.claude/skills/<name>/SKILL.md`) or an
agent (`.claude/agents/<name>.md`). Until now the protocol in the README
was a convention every session re-read and applied by hand: edit the
charter, re-derive the file, remember the fold pass, remember the replies.
Two things kept going wrong. The file got patched directly with the fresh
lesson and the charter went stale — the exact drift the split exists to
prevent. And the re-derivation was done by the session that had just
edited the charter, at that session's largest context, carrying the issue
thread, the transcripts and the owner's reasoning — everything the file
must *not* contain — so the "derived" file kept absorbing history. Owner,
2026-10-14: *"after writing out charter, one advisor pass. And the actual
skill (re)writes would ideally be done by a Fable (sub)agent. Actually we
should have a skill for that maybe?"*

The skill is a pipeline with one input (a wish, or the charter's feedback
board) and one output (a commit holding the charter and its derived file,
plus the board's posts answered). It writes no design; it moves a wish into
laws and laws into instructions. A pass may name several charters
(`/charter swarm spec clerk`): each is edited and gets its own builder, but
the advisor reads them once, together, and one commit holds them all.
Owner, 2026-10-23: *"it should accept more than 1 skill to update, call
advisor just once. still 1 fable write per touched skill, though for small
skills Opus may be enough"*.

Charters collaborate: a swarm law is read by the drone, a clerk law by
every skill that hands it an order. Such a law lives in one charter — its
owner — and every other charter that relies on it marks it **foreign** and
points at it, so a change is made once and every reader is found by grep
(laws 13–14). Owner, 2026-10-23: *"some charter laws would be foreign, or
live on other charters. and should be marked as such. so they live in 1
place, while keeping charters to their own mostly, while collaborating
aspects are kept in sync. any referenced law ofc may be read by the
writer. and must be updated/kept in sync when laws change or get
superseded"*.

## The cost model

**The derivation runs in a fresh context on purpose.** The session that
edits a charter has read the board, the incident, the thread with the owner
— tens of thousands of tokens of exactly the material the instruction file
must leave out. A derivation subagent briefed with nothing but the charter
path reads ~10–20k (charter + README) and *cannot* leak what it never
saw. That is cheaper than the editing session doing one more turn, and it
is the only way to prove the charter is complete: if the file cannot be
built from the charter alone, the charter is missing something, and the
pipeline finds out now instead of at the next rewrite.

**Fable derives.** The instruction file is read and obeyed on every run of
that skill or agent; a sloppier derivation is paid on every one of those
runs, forever, where a stronger model is paid once per change. The advisor
pass on the charter is one call for the same reason: a law written badly
is derived faithfully into a bad instruction — and one call for a
multi-charter pass, not one per charter: the advisor sees the whole
transcript either way, and the laws that cross charters are exactly what a
per-charter call would miss. A small charter (law 5's size line) derives on
Opus: what the builder needs is a fresh context, and a short file gives
Fable's extra capability little to do.

**The derive is bounded, or it researches.** Fable is about twice Opus per
token, so the derive's price is its reads. With an open brief the four
derives of 2026-10-15 ran 8–18 tool calls, peaked at 72–101k and priced at
1.2–1.7M sonnet-units each — 5.8M for two charter commits, against 16M for
the whole next night's train of 21 issues — because each builder, missing
an exact verb, grepped the tool for it and called the advisor twice. A
builder that reads two files and writes its targets is a handful of tool
calls; the charter carries every exact line the file needs (*Briefs and
orders, verbatim*), and what it lacks comes back as a gap, which is the
charter-completeness proof the fresh context exists to give. The first
bounded derive (`/charter charter`, 2026-10-17) ran 9 calls in two
dispatches at 540k sonnet-units. The bound has two openings, both priced:
the text of each foreign law the charter cites (a few lines per law), and
one Sonnet Explore whose answer is capped at about 5k tokens, for context
the charter cannot carry — what a named tool or file is for, how a sibling
skill is shaped. Owner, 2026-10-23: *"it should allow fable writers to use
1 Sonnet explore agent with a max 5k response. besides the skill and
charter fi[l]es. to allow a limited contextual grounding"*. An exact
string the Explore turns up is reported as grounded and lifted into the
charter by the lead, so the next derive no longer needs it and the
completeness proof survives.

**Replies are a clerk's.** Answering folded posts is `feedback -- reply`
per post, verdict text already written — pure tool calls, a Haiku
[clerk](clerk.md) with the order inline (*Foreign laws*).

## Laws

1. **One door.** Every change to a `.claude/skills/<name>/SKILL.md` or a
   `.claude/agents/<name>.md` goes through this skill: the charter changes
   first, the file is derived from it. A session that finds itself patching
   an instruction file directly stops and runs this skill instead; a diff
   that touches a file and not its charter is the bug. *Why:* two paths to
   change a file is how the charter goes stale, and a stale charter means
   the next rewrite re-learns every lesson it dropped
   (`.claude/rules/charters.md`).
2. **A charter names what it builds and carries everything the build
   needs.** Its first paragraph lists the derived file or files (a charter
   may build more than one: `swarm-train.md` builds the `swarm-train` skill
   and the `swarm-lead` agent; `adr.md` builds the `adr` skill and the
   `adr-librarian` agent). It carries a *Frontmatter* section — the
   `description` with its trigger phrases, and for an agent the `model` and
   `tools` — or states them in its laws. A charter missing any of this
   gets it added in the same pass, lifted from the current file, before
   anything is derived; that lift, law 12's, and law 9's first charter,
   are the only times a current file is read into a charter. *Why:* law 5 derives from the charter alone, and the
   frontmatter is what makes a skill fire at all — a derivation that has to
   guess the triggers, or read the old file for them, is not from the
   charter alone.
3. **Two inputs, same pass.** A *wish* — the owner's words, verbatim and
   dated, or a lesson from a session — becomes a law (with its why), a row
   in the incident corpus, an entry under *Revisit when*, or a fork noted
   there as open. The *board* — `mise run feedback -- unanswered <charter>`
   — is folded the same way, every post becoming one of those or a
   rejection, with a row in the charter's *Fold digest* (date · kind → what
   it became); the lead keeps each post's comment id and verdict text for
   law 8. A post that belongs to another charter is moved with
   `feedback -- post --verbatim <other> <file>`, not folded here. A pass
   may carry both a wish and the board; it reads the board every time, so
   a wish never lands on top of an unfolded post. `unanswered` failing
   (Discussions not set up, the GraphQL hour spent) does not stop the
   pass: it continues on the wish and the failure goes under `Not done`.
   *Why:* the board is where
   `--bg` sessions leave what they learned (README → *Feedback boards*);
   a charter revised without reading it folds the owner's wish and loses
   the field report. In a multi-charter pass, laws 3–4 and 12's first read
   run for every named charter before anything is derived.
4. **One advisor pass for the whole pass, after editing and before
   deriving.** One call however many charters the pass names, after every
   charter is edited. Each point is applied to its charter or declined, the
   declined ones named in the commit body. One pass, not a loop. *Why:* the
   derivation is faithful by construction (law 5), so the charter is the
   last place a bad law can be caught cheaply; a second pass is the editing
   session re-arguing with itself at full context; a call per charter pays
   the same transcript again and sees no more of it.
5. **Derivation is one fresh subagent per touched charter, bounded.** One
   `general-purpose` subagent per charter the pass edited, with a `name`
   (law 6 sends gaps back to it) and `run_in_background: false`, writes
   every file that charter builds — a skill and its agent in one context,
   the charter paid once. A multi-charter pass spawns its builders in one
   message, so they run side by side. **Tier:** `model: "fable"`; a
   *small* charter — under about 200 lines, building one file of under
   about 150 — may take `model: "opus"`, the lead's call, named in the
   report. Its brief is the *derive brief* below, verbatim, with only the
   paths and the foreign-law lines filled: no summary of what
   changed, no diff, no paste of the old file. **Reads:** the charter —
   with `sed -n` in ranges of about 250 lines from its first call — and the
   short README whole; the text of each law the charter's *Foreign laws*
   section cites (law 13), from the owning charter by a `sed -n` range or
   a `grep -n -A` on its number; and at most **one** `Explore` subagent
   with `model: "sonnet"`, its prompt asking for an answer under about 5k
   tokens, for context the charter does not carry — never about the
   target file itself or an earlier derive of it. Nothing else: not the
   current file, not another skill or agent file, no command beyond those
   reads, a `mkdir` and its writes; no advisor; about eight tool calls. An
   exact string the file needs — a command line, a verb, a path, a brief,
   an order or report shape — that the charter does not give is never
   invented: the builder writes `<gap: law N — what is missing>` in its
   place, or, when the Explore found it verbatim, uses it and lists it as
   `grounded: law N — <string> — <source>`; both go in its handback.
   Owner, 2026-10-14: *"the actual skill (re)writes would ideally be done
   by a Fable (sub)agent"*; the Opus line and the Explore are the owner's,
   2026-10-23 (*What the skill is for*, *The derive is bounded*). *Why:*
   the cost model — a context that never saw the history cannot leak it,
   and a file that cannot be rebuilt from its charter proves the charter
   incomplete; a builder that researches freely hides that proof and pays
   for it (*The derive is bounded*), so the one Explore is capped, kept
   off the target — a summary of the old file is the proxy read the fresh
   context exists to prevent — and what it grounds is lifted (law 6). The lead's law-6 check is the review, so
   an advisor inside the derive only forwards the builder's whole context
   to buy a second one. The range read is because the budget guard refuses
   a whole-file Read past 400 lines, and grepping for symbols — its advice
   — is wrong for the one job whose input is the whole file.
6. **The lead checks the build law by law, and fixes gaps through the
   builder.** Every numbered law has its line in the file; the file cites
   the charter once; it holds no date, no issue number, no owner quote, no
   "was:" — the mechanical half is a grep for `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]`
   and `#[0-9]{3,}` that finds only template placeholders; a quote or a
   reasoning-behind is caught by the law-by-law read; a grep for `<gap: law`
   finds every gap the builder marked (a template placeholder aside). A gap is closed in the charter at its
   law, then sent back to the same subagent by `SendMessage` naming the law
   and the charter lines to re-read; never hand-patched. A law the subagent
   cannot place is a law written unclearly — fix the charter and re-derive.
   Each `grounded:` line is lifted into the charter at its law before the
   commit; the file already holds the string, so no re-derive is needed.
   *Why:* a hand patch is the file drifting from its charter on the very
   pass meant to align them; an unlifted grounding is a gap the next
   builder pays the Explore for again.
7. **`mise run rules-hygiene` adds no violation, then one commit holds
   every charter and derived file of the pass.** `docs(skill): <name> —
   <what moved>` (`docs(agent):` for an agent; several names joined with
   `, ` for a multi-charter pass), the README index in the same commit when
   a charter is new. A charter and its file never commit apart. *Why:*
   `folded in <sha>` names one commit, a history where the charter and the
   file move separately is a history where they can be read as
   disagreeing, and a foreign law changed in one charter and re-pointed in
   another (law 14) is one change.
8. **The folded posts are answered after the commit, by one Haiku clerk
   with an inline order.** A `clerk` subagent, `model: "haiku"`, the
   *clerk order* below as its whole prompt. Per post: its comment id and the verdict,
   `folded in <sha>: <law or digest row>` or `rejected: <why>`; the clerk
   runs `feedback -- reply --resolve` and reports one line per post; the
   lead checks every post the pass folded or rejected has a line, and
   lists one that does not under `Not done`. A multi-charter pass sends
   one clerk, the order carrying one block per board. *Why:* unanswered is
   unprocessed (README): a post folded but not replied is folded again
   next pass.
9. **A file with no charter gets its first one in the same pass.** The
   charter is the one whose first paragraph names the file — usually
   `docs/charters/<name>.md`, but an agent may be built by a skill's
   charter, so the README index is checked before concluding there is
   none. `handoff`, `manage-stats` and `pickup` have none today; any file found
   without one is treated the same: the skill writes
   `docs/charters/<name>.md` from the file's own imperatives — each
   must/never becomes a numbered law with the why the file or the rule it
   points at gives, plus *What it is for*, a cost model, *Frontmatter*,
   *Revisit when*, and an empty corpus — adds it to the README index, then
   applies the wish and derives. The skill never patches a charterless
   file. *Why:* the README's exemption ("a checklist carries no laws")
   held only while nobody wanted the checklist changed; a change request
   is a law candidate by definition, and an exemption is the second door
   law 1 closes.
10. **Scope is the charters, their files, the README, and the foreign
    lines law 14 updates.** The README's protocol bullets are this skill's
    laws in prose and move with them; its index moves when a charter is
    new. A rule, a doc, a mise task or a code
    change the wish implies is named in the report, not made here; `.claude/rules/charters.md` is a rule and
    follows `writing-rules.md`. The charter of this skill is changed the
    same way as any other — through the skill. *Why:* a pass that also
    edits rules is a pass whose commit no longer reads as "the charter
    moved"; and a skill that exempts itself is law 1's second door again.
11. **The report is the session-report shape** (`docs/domain/session-report.md`):
    `Landed` holds the sha and the laws that moved; `Not done` the posts
    not answered, the advisor points declined, a failed `unanswered`, and
    each rule, doc, mise or code change the wish implies (law 10);
    `Needs the owner` a fork the wish opened and did not close. *Why:* the
    owner reads it on a phone, after the fact.
12. **The lead reads the loss list twice: the current file before the
    derive, the diff before the commit, every pass.** Before deriving, the
    lead reads the current file and confirms every
    imperative line — each must and never, each command, brief and order
    — has its law; one that has none is lifted into the charter at the law
    it belongs to. On a pass after a clean one this finds nothing, at the
    price of one read of a file the lead is about to replace. Before the commit, every pass, the lead reads
    `git diff` of each derived file as a loss list: each removed
    instruction is a law that moved on purpose, or a gap closed as law 6
    closes one — lifted into the charter, the builder sent the lines to
    re-read — never re-added by hand. *Why:* a builder from the charter
    alone drops exactly what the charter lacks and invents what it leaves
    implicit; caught before the derive it costs a lift, caught after the
    commit it cost the swarm fold a discarded Fable build, a second commit
    and a three-turn derive (2026-10-17).
13. **A law lives in one charter; every other reader marks it foreign.**
    The charter whose skill or agent *does* the thing owns the law — the
    clerk owns how a work order is shaped, swarm owns how a drone is
    briefed. A charter that relies on another's law does not restate it as
    one of its own numbered laws: it lists it in its `## Foreign laws`
    section, one line each, in exactly this form —
    `- [<owner>](<owner>.md) law <N> — <what this skill does with it>` —
    and its own laws cite it in that same `[<owner>](<owner>.md) law <N>`
    form. It keeps only its own side: what it hands over, what it expects
    back. A law found duplicated across two charters is merged into the
    one that does the thing, the other's copy turned into its foreign
    line, in the pass that finds it. The builder may read every law listed
    there (law 5) and states in the file only what this skill does with
    it. *Why:* a law written twice drifts in one copy; the fixed form is
    what lets law 14 find every reader by grep.
14. **A changed law takes its readers with it.** Before the advisor pass,
    for each law the pass changed, superseded, retired or renumbered, the
    lead greps `docs/charters/` for `(<name>.md) law` and reads the hits
    for <N> (a citation may name a range, `laws 13–14`), plus the
    charter's bare name near `law`, for a reference older than law 13. Each
    reader's foreign line and citing laws are updated in this pass; a
    reader whose derived file states what the law changed joins the pass
    as a touched charter (law 5). Law numbers are stable: a law is never
    renumbered or deleted — it stays, reading `retired — <why>` or
    `superseded by law <M>`, and new laws append — so a stale reference
    still lands on a law that says where it went. *Why:* a foreign mark
    that is never followed back is a second copy with extra steps; and a
    reference that lands silently on a different law is worse than none.
15. **A small pass patches; anything else rebuilds.** A charter whose file
    exists is *patched* when the pass moved about three laws or fewer
    (changed, added, retired) and changed no existing brief, order, report
    shape or step order — a new law with a new brief of its own is still
    additive. Everything else is a full rebuild (law 5): a first charter
    (law 9), a law-12 first read that lifted anything, a structural
    change, a patch that fails the law-6 check, or the owner asking for
    one. The patch builder is one fresh subagent per charter, as in law 5
    — a `name`, `run_in_background: false`, the same foreign-law reads and
    the one capped Explore — but `model: "opus"` (Fable when a moved law
    is subtle, the lead's call) and the *patch brief* below: it reads the
    charter, the README and the **current file**, and edits only the lines
    that carry the listed laws, every other line left byte for byte. The
    brief lists the moved laws by number and nothing more — no summary of
    the change, no diff. The lead's law-6 check runs on the moved laws, the
    mechanical greps on the whole file, and law 12's diff read confirms the
    diff stays inside the moved laws; the report names which mode each
    charter took. Owner, 2026-10-23: *"i wonder if full rewrites are always
    needed or that fable could do an additive one. might depend on the
    blast radius / scope of the change?"*, choosing *patch when small*.
    *Why:* a full rebuild re-proves every law, but the unmoved ones were
    proven at the last rebuild, and its price is a Fable context plus
    wording churn in laws nobody touched; the leak guard matters less here
    because the file the patcher reads was itself built clean. Structural
    changes rebuild because a patch cannot tell whether a moved step order
    left an older line wrong.

## Frontmatter

- `name: charter`
- `description`: revise one or more skill or agent files through their
  charters — edit each charter (a wish, or fold its feedback board with
  `mise run feedback -- unanswered <charter>`), keep foreign laws in sync
  across charters, one advisor pass for the whole pass, one fresh Fable
  (or, for a small charter, Opus) subagent per touched charter re-derives
  its files from the charter alone — or, for a pass that moves only a few
  laws, an Opus subagent patches just those laws' lines — rules-hygiene, one commit, the folded
  posts answered through a Haiku clerk. Use when the user says "revise a
  skill", "update the charter", "fold the feedback board", "re-derive
  <skill>", "change the <agent> agent", "/charter <name> [<name>…]", or
  when a session is about to patch a `SKILL.md` or an agent file
  directly.

## Briefs and orders, verbatim

The skill file carries these three texts exactly, placeholders in angle
brackets.

**Derive brief** (law 5) — the bracketed alternative for a charter that
builds more than one file, the agent clause when one target is an agent:

```
Repo: <absolute repo path> (a shared checkout; do not commit, do not run
git write commands).

Write the file `<absolute target path>` [or: the files `<path 1>` and
`<path 2>`] (create the directory if it does not exist) from the charter
at `<absolute charter path>`, following the protocol in
`<absolute README path>`.

Read the charter with `sed -n 'a,bp'` in ranges of about 250 lines, from
your first call (a whole-file Read of a long file is refused), and the
README with one Read. You may also read, and only these: the text of each
foreign law below, from its owning charter, with a `sed -n` range or
`grep -n -A` on its number —
<the charter's *Foreign laws* lines, or "none">
— and you may spawn at most ONE `Explore` subagent with `model: "sonnet"`,
its prompt ending "Answer in under 5k tokens.", for context the charter
does not carry (what a named tool or file is for, how a sibling skill is
shaped) — never about the target file itself or an earlier version of
it. Open no other file — not the current version of the target, not any
other skill or agent file. Run no command but those reads, a `mkdir`
and your writes. Do not call advisor. Budget: about eight tool calls.

A string the file must state exactly — a command line, a verb, a path, a
brief, an order or a report shape — that the charter does not give is
never invented. If your Explore found it verbatim, use it and list
`grounded: law N — <string> — <source>` in your handback; otherwise write
`<gap: law N — what is missing>` in its place and list it. The lead
closes gaps in the charter and sends you the lines to re-read.

Of a foreign law, the file states only what this skill does with it, never
the owning skill's side.

The file's frontmatter is `name:` and `description:` as the charter's
*Frontmatter* section states them. [Agent: and `model:` and `tools:` as
the charter states them.] The body is steps only — the pipeline a fresh
session follows, with the exact briefs and orders it uses, taken from the
charter — with one one-line pointer to the charter and nothing the
charter's *What the skill file must not contain* section forbids (no
dates, issue numbers, owner quotes, or reasoning-behind). Every numbered
law in the charter must be recognisable as a step or a line in the file.

When done, report each path, the gap list (or "no gaps") and the
grounded list (or "none") via SubagentHandback.
```

**Patch brief** (law 15) — the same alternatives as the derive brief:

```
Repo: <absolute repo path> (a shared checkout; do not commit, do not run
git write commands).

Patch the file `<absolute target path>` [or: the files `<path 1>` and
`<path 2>`] so it carries laws <N, M, …> of the charter at
`<absolute charter path>` as they now read, following the protocol in
`<absolute README path>`.

Read the charter with `sed -n 'a,bp'` in ranges of about 250 lines, from
your first call (a whole-file Read of a long file is refused), the README
with one Read, and the current target file (`sed -n` ranges past 400
lines). You may also read, and only
these: the text of each foreign law below, from its owning charter, with
a `sed -n` range or `grep -n -A` on its number —
<the charter's *Foreign laws* lines, or "none">
— and you may spawn at most ONE `Explore` subagent with `model: "sonnet"`,
its prompt ending "Answer in under 5k tokens.", for context the charter
does not carry — never about the target file. Open no other file. Run no
command but those reads and your edits. Do not call advisor. Budget:
about eight tool calls.

Edit only the lines that carry the listed laws — add, change or remove
them — and the frontmatter if the charter's *Frontmatter* section no
longer matches it. Leave every other line byte for byte. A listed law
whose change reaches lines that carry an unlisted law is not patched:
say so in your handback and stop.

A string the file must state exactly that the charter does not give is
never invented. If your Explore found it verbatim, use it and list
`grounded: law N — <string> — <source>`; otherwise write
`<gap: law N — what is missing>` in its place and list it. Nothing the
charter's *What the skill file must not contain* section forbids.

When done, report each path, the laws patched, the gap list (or "no
gaps") and the grounded list (or "none") via SubagentHandback.
```

**Clerk order** (law 8) — one block per board for a multi-charter pass:

```
Reply to and resolve each feedback post below. For each: write the
verdict text to a file, run
`mise run feedback -- reply --resolve <comment-id> <file>`, and report one
line per post (comment id, verdict, done or the error).

`<charter>` board:
- <comment-id>: folded in <sha>: <law N | digest row: <date · kind → what>>
- <comment-id>: rejected: <why>
```

## Foreign laws

- [clerk](clerk.md) law 11 — law 8 hands the clerk a fold order of replies
  only, one line per post.
- [clerk](clerk.md) law 12 — law 8 writes the order inline as the clerk's
  whole spawn prompt.

## What the skill file must not contain

The owner's quote, the reasoning behind the fresh-context derivation, the
names of the charterless files beyond the rule that covers them, this
charter's history, the cost figures. It carries the steps, the derive brief, the patch brief
and the clerk order, verbatim.

## Revisit when

- Patches accumulate: a file patched many passes in a row reads as
  layers, or a full rebuild after a patch run moves wording in laws no
  pass touched — then law 15 gains a rebuild every Nth pass. The size line
  (about three laws) is a tentative pick, revisable on any patch that
  disagrees with it.
- **The derive's tier — closed 2026-10-23, revisit on data.** Owner,
  2026-10-14: *"the actual skill (re)writes would ideally be done by a
  Fable (sub)agent"*; 2026-10-17: *"…went to town on researching the fuck
  out of what they were rewriting which is uhm.. COSTLY"*; 2026-10-23:
  *"still 1 fable write per touched skill, though for small skills Opus
  may be enough"* — Fable by default, Opus for a small charter (law 5).
  Reopen if Opus derives of small charters routinely fail the law-6
  check (back to Fable for all), or if Fable derives under the bounded
  brief stop landing near the first probe's 540k (Opus for all, option 2
  of the old fork). The size line (~200-line charter, ~150-line file) is
  a tentative pick, revisable on any derive that disagrees with it.
- The budget guard gains an exemption for `docs/charters/` — the derive
  brief's range-read line becomes optional.
- Derives routinely hand back gaps — the charters are thin on exact
  lines, and a pass that lifts each skill's commands into its charter
  pays off before the next derive.
- The advisor pass routinely returns nothing — drop it to on-request.
- Builders routinely spend their Explore, or hand back `grounded:` lines
  — the charters are thin on context, and a lift pass on the worst ones
  pays before the next derive. Builders never spend it — drop it.
- The charters' ad-hoc cross-references (`swarm law 4`, `(its law 11)`)
  predate law 13 — a sweep that converts them to the fixed form and
  fills each charter's *Foreign laws* section makes law 14's grep exact;
  until then it also greps the bare charter name.
- Every charterless file has its charter — law 9 collapses to "a file
  with no charter is a bug".
- A charter is edited by a `/handoff` sweep without this skill — handoff's
  sweep should spawn this skill's steps instead of carrying its own copy.

## Fold digest

| Date | Kind | Became |
|---|---|---|
| 2026-10-17 | law-candidate (derive cost) | law 5 bounded brief — two files in, gaps handed back, no advisor, ~six calls (a); one builder per charter (c); cost-model paragraph; tier fork (b) open under *Revisit when*; one-law patch (d) stays there |
| 2026-10-17 | gotcha (Read guard) | law 5 and the derive brief: the charter read with `sed -n` in ranges from the first call; guard exemption under *Revisit when* |
| 2026-10-17 | probe (first bounded derive: 9 calls, 2 dispatches, 70k peak, 540k) | cost-model paragraph (*The derive is bounded*); the tier fork's revisit trigger |
| 2026-10-17 | gotcha (swarm rebuild lost six lines) | law 12: the current file read against the laws before every derive (the post asked first passes only; widened on the advisor pass), the diff read as a loss list before every commit |

## Incident corpus

| date | source | finding | laws |
|---|---|---|---|
| 2026-10-14 | owner, this charter's birth | the protocol lived in the README and in every session's memory of it; files were patched with lessons and re-derived by the session holding the history they must omit | 1, 5 |
| 2026-10-15 | `mise run agent-cost`, derives a06730d2 / ae1fd716 / a9f29b0e / aa109524 (swarmify, swarm-train, swarm, swarm-lead) | 8–18 tool calls, 72–101k peak, 1.2–1.7M sonnet-units each; builders grepped `mise.toml`, the ledger task, session-report.md, the drone charter, ran `whip --help` for thirteen verbs, each called advisor twice; swarm-train's charter fed two derives | 5 |
| 2026-10-15 | derive ae1fd716 | the budget guard refused the whole-file Read of a 498-line charter; the builder re-read it with `sed -n` in five ranges — one refused turn | 5 |
| 2026-10-17 | owner | *"…went to town on researching the fuck out of what they were rewriting which is uhm.. COSTLY"* | 5, tier fork |
| 2026-10-17 | `/charter swarm`, commits b786bea + f542946 | the first rebuild from the charter alone dropped six instructions the old file had and the charter lacked, invented two shapes it left implicit; found by a reverse check after the first commit; two commits, a three-turn derive (~87k, 97k, 113k) | 12 |
| 2026-10-23 | owner | several charters per pass, one advisor call, one builder per touched charter, Opus for a small one; one capped Sonnet Explore for the builder; foreign laws marked and kept in sync — the last salvaged in part from a sibling repo's port of this protocol (*Stays in sync with* sections, stable law numbers) | 3–5, 7, 8, 13, 14 |
| 2026-10-23 | owner | an additive patch derive for a small pass (about three laws, no structural change), Opus by default; a full rebuild otherwise — closes the *Revisit when* item on wording churn | 15 |
