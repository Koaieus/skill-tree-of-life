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
laws and laws into instructions.

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
is derived faithfully into a bad instruction. Whether the tier must be
Fable is an open fork (*Revisit when*).

**The derive is bounded, or it researches.** Fable is about twice Opus per
token, so the derive's price is its reads. With an open brief the four
derives of 2026-10-15 ran 8–18 tool calls, peaked at 72–101k and priced at
1.2–1.7M sonnet-units each — 5.8M for two charter commits, against 16M for
the whole next night's train of 21 issues — because each builder, missing
an exact verb, grepped the tool for it and called the advisor twice. A
builder that reads two files and writes its targets is a handful of tool
calls; the charter carries every exact line the file needs (*Briefs and
orders, verbatim*), and what it lacks comes back as a gap, which is the
charter-completeness proof the fresh context exists to give.

**Replies are a clerk's.** Answering folded posts is `feedback -- reply`
per post, verdict text already written — pure tool calls, a Haiku
[clerk](clerk.md) (its law 11) with the order inline (its law 12).

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
   the field report.
4. **One advisor pass on the charter, after editing and before deriving.**
   Each point is applied to the charter or declined, the declined ones
   named in the commit body. One pass, not a loop. *Why:* the derivation
   is faithful by construction (law 5), so the charter is the last place a
   bad law can be caught cheaply; a second pass is the editing session
   re-arguing with itself at full context.
5. **Derivation is one fresh Fable subagent per charter, bounded to two
   files in and its targets out.** One `general-purpose` subagent with
   `model: "fable"`, a `name` (law 6 sends gaps back to it) and
   `run_in_background: false` writes every file the charter builds — a
   skill and its agent in one context, the charter paid once. Its brief is
   the *derive brief* below, verbatim, with only the paths filled: no
   summary of what changed, no diff, no paste of the old file. The builder
   reads exactly the charter and the README — the charter with `sed -n` in
   ranges of about 250 lines from its first call, the short README whole —
   opens no other file
   (the current file included), runs no command beyond those reads, a
   `mkdir` and its writes, calls no advisor, and spends about six tool
   calls. An exact string the file needs — a command line, a verb, a path,
   a brief, an order or report shape — that the charter does not give is
   never looked up and never invented: the builder writes
   `<gap: law N — what is missing>` in its place and lists it in its
   handback. Owner, 2026-10-14: *"the actual skill (re)writes would
   ideally be done by a Fable (sub)agent"*. *Why:* the cost model — a
   context that never saw the history cannot leak it, and a file that
   cannot be rebuilt from its charter proves the charter incomplete; a
   builder that researches the gap hides that proof and pays for it
   (*The derive is bounded*). The lead's law-6 check is the review, so an
   advisor inside the derive only forwards the builder's whole context to
   buy a second one. The range read is because the budget guard refuses a
   whole-file Read past 400 lines, and grepping for symbols — its advice —
   is wrong for the one job whose input is the whole file.
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
   *Why:* a hand patch is the file drifting from its charter on the very
   pass meant to align them.
7. **`mise run rules-hygiene` adds no violation, then one commit holds the
   charter and its derived files.** `docs(skill): <name> — <what moved>`
   (`docs(agent):` for an agent), the README index in the same commit when
   the charter is new. The charter and the file never commit apart. *Why:*
   `folded in <sha>` names one commit, and a history where the charter and
   the file move separately is a history where they can be read as
   disagreeing.
8. **The folded posts are answered after the commit, by one Haiku clerk
   with an inline order.** A `clerk` subagent, `model: "haiku"`, the
   *clerk order* below as its whole prompt. Per post: its comment id and the verdict,
   `folded in <sha>: <law or digest row>` or `rejected: <why>`; the clerk
   runs `feedback -- reply --resolve` and reports one line per post; the
   lead checks every post the pass folded or rejected has a line, and
   lists one that does not under `Not done`. *Why:* unanswered is unprocessed (README):
   a post folded but not replied is folded again next pass.
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
10. **Scope is the charter, its files, and the README index.** A rule, a
    doc, a mise task or a code change the wish implies is named in the
    report, not made here; `.claude/rules/charters.md` is a rule and
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

## Frontmatter

- `name: charter`
- `description`: revise a skill or an agent file through its charter —
  edit the charter (a wish, or fold its feedback board with `mise run
  feedback -- unanswered <charter>`), one advisor pass on the charter, a
  fresh Fable subagent re-derives the instruction file from the charter
  alone, rules-hygiene, one commit, the folded posts answered through a
  Haiku clerk. Use when the user says "revise a skill", "update the
  charter", "fold the feedback board", "re-derive <skill>", "change the
  <agent> agent", "/charter <name>", or when a session is about to patch a
  `SKILL.md` or an agent file directly.

## Briefs and orders, verbatim

The skill file carries these two texts exactly, placeholders in angle
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

Read exactly those two files and nothing else: the charter with
`sed -n 'a,bp'` in ranges of about 250 lines, from your first call (a
whole-file Read of a long file is refused), the README with one Read. Open
no other file — not the current version of the target, not any other
skill or agent file, not the tools the file names. Run no command but
those reads, a `mkdir` and your writes. Do not call advisor. Budget: about
six tool calls.

A string the file must state exactly — a command line, a verb, a path, a
brief, an order or a report shape — that the charter does not give is
never looked up and never invented: write `<gap: law N — what is missing>`
in its place and list it in your handback. The lead closes it in the
charter and sends you the lines to re-read.

The file's frontmatter is `name:` and `description:` as the charter's
*Frontmatter* section states them. [Agent: and `model:` and `tools:` as
the charter states them.] The body is steps only — the pipeline a fresh
session follows, with the exact briefs and orders it uses, taken from the
charter — with one one-line pointer to the charter and nothing the
charter's *What the skill file must not contain* section forbids (no
dates, issue numbers, owner quotes, or reasoning-behind). Every numbered
law in the charter must be recognisable as a step or a line in the file.

When done, report each path and the gap list (or "no gaps") via
SubagentHandback.
```

**Clerk order** (law 8):

```
Reply to and resolve each feedback post below on the `<charter>` board.
For each: write the verdict text to a file, run
`mise run feedback -- reply --resolve <comment-id> <file>`, and report one
line per post (comment id, verdict, done or the error).

- <comment-id>: folded in <sha>: <law N | digest row: <date · kind → what>>
- <comment-id>: rejected: <why>
```

## What the skill file must not contain

The owner's quote, the reasoning behind the fresh-context derivation, the
names of the charterless files beyond the rule that covers them, this
charter's history, the cost figures. It carries the steps, the derive brief
and the clerk order, verbatim.

## Revisit when

- Derivation diffs routinely churn wording in laws that did not move —
  the brief should allow the subagent to read the current file for wording
  only, or the skill should distinguish a one-law patch from a rewrite (a
  single-law change patched and checked against that law, a full rebuild
  only when laws move). Raised again 2026-10-17 as option (d) of the
  derive-cost post; the bounded brief (law 5) cuts the derive's reads but
  still rebuilds the whole file, so it does not deliver this for free.
- **Open fork, needs the owner — the derive's tier.** Owner, 2026-10-14:
  *"the actual skill (re)writes would ideally be done by a Fable
  (sub)agent"*; owner, 2026-10-17: *"charter skill touched ~3 issues last
  time and these spawned eventually 3 fable subagents which then like went
  to town on researching the fuck out of what they were rewriting which is
  uhm.. COSTLY"*. Figures: four 2026-10-15 derives at 1.2–1.7M
  sonnet-units each, 5.8M for two charter commits, against 16M for the
  2026-10-16 train of 21 issues; Fable is about 2× Opus per token.
  Options: (1) keep Fable with the bounded brief (law 5, folded
  2026-10-17) and measure whether the bound alone brings a derive near
  the cost of its reads; (2) derive on Opus — law 5's *why* is freshness,
  not capability, so a fresh Opus context keeps the leak-proof and the
  completeness proof at half the price; cost: reverses the 2026-10-14
  call; (3) Opus by default, Fable for a charter's first derive or a
  rebuild that moves most laws. Not decided; law 5 stays Fable until the
  owner picks.
- The budget guard gains an exemption for `docs/charters/` — the derive
  brief's range-read line becomes optional.
- Derives routinely hand back gaps — the charters are thin on exact
  lines, and a pass that lifts each skill's commands into its charter
  pays off before the next derive.
- The advisor pass routinely returns nothing — drop it to on-request.
- Every charterless file has its charter — law 9 collapses to "a file
  with no charter is a bug".
- A charter is edited by a `/handoff` sweep without this skill — handoff's
  sweep should spawn this skill's steps instead of carrying its own copy.

## Fold digest

| Date | Kind | Became |
|---|---|---|
| 2026-10-17 | law-candidate (derive cost) | law 5 bounded brief — two files in, gaps handed back, no advisor, ~six calls (a); one builder per charter (c); cost-model paragraph; tier fork (b) open under *Revisit when*; one-law patch (d) stays there |
| 2026-10-17 | gotcha (Read guard) | law 5 and the derive brief: the charter read with `sed -n` in ranges from the first call; guard exemption under *Revisit when* |
| 2026-10-17 | gotcha (swarm rebuild lost six lines) | law 12: the current file read against the laws before every derive (the post asked first passes only; widened on the advisor pass), the diff read as a loss list before every commit |

## Incident corpus

| date | source | finding | laws |
|---|---|---|---|
| 2026-10-14 | owner, this charter's birth | the protocol lived in the README and in every session's memory of it; files were patched with lessons and re-derived by the session holding the history they must omit | 1, 5 |
| 2026-10-15 | `mise run agent-cost`, derives a06730d2 / ae1fd716 / a9f29b0e / aa109524 (swarmify, swarm-train, swarm, swarm-lead) | 8–18 tool calls, 72–101k peak, 1.2–1.7M sonnet-units each; builders grepped `mise.toml`, the ledger task, session-report.md, the drone charter, ran `whip --help` for thirteen verbs, each called advisor twice; swarm-train's charter fed two derives | 5 |
| 2026-10-15 | derive ae1fd716 | the budget guard refused the whole-file Read of a 498-line charter; the builder re-read it with `sed -n` in five ranges — one refused turn | 5 |
| 2026-10-17 | owner | *"…went to town on researching the fuck out of what they were rewriting which is uhm.. COSTLY"* | 5, tier fork |
| 2026-10-17 | `/charter swarm`, commits b786bea + f542946 | the first rebuild from the charter alone dropped six instructions the old file had and the charter lacked, invented two shapes it left implicit; found by a reverse check after the first commit; two commits, a three-turn derive (~87k, 97k, 113k) | 12 |
