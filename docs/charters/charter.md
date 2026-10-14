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
path starts at ~10–20k (charter + README) and *cannot* leak what it never
saw. That is cheaper than the editing session doing one more turn, and it
is the only way to prove the charter is complete: if the file cannot be
built from the charter alone, the charter is missing something, and the
pipeline finds out now instead of at the next rewrite.

**Fable derives.** The instruction file is read and obeyed on every run of
that skill or agent; a sloppier derivation is paid on every one of those
runs, forever, where a stronger model is paid once per change. The advisor
pass on the charter is one call for the same reason: a law written badly
is derived faithfully into a bad instruction.

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
   anything is derived; that lift, and law 9's first charter, are the
   only times a current file is read into a charter. *Why:* law 5 derives from the charter alone, and the
   frontmatter is what makes a skill fire at all — a derivation that has to
   guess the triggers, or read the old file for them, is not from the
   charter alone.
3. **Two inputs, same pass.** A *wish* — the owner's words, verbatim and
   dated, or a lesson from a session — becomes a law (with its why), a row
   in the incident corpus, an entry under *Revisit when*, or a fork noted
   there as open. The *board* — `mise run feedback -- unanswered <charter>`
   — is folded the same way, every post becoming one of those or a
   rejection, with a row in the charter's *Fold digest* (date · kind → what
   it became). A post that belongs to another charter is moved with
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
5. **Derivation is a fresh Fable subagent briefed with the charter path
   and the target path, nothing else.** No summary of what changed, no
   diff, no paste of the old file; the subagent reads the charter and the
   README's protocol, and writes the whole file from them. It does not
   open the current file. Owner, 2026-10-14: *"the actual skill (re)writes
   would ideally be done by a Fable (sub)agent"*. *Why:* the cost model —
   a context that never saw the history cannot leak it, and a file that
   cannot be rebuilt from its charter proves the charter incomplete.
6. **The lead checks the build law by law, and fixes gaps through the
   builder.** Every numbered law has its line in the file; the file cites
   the charter once; it holds no date, no issue number, no owner quote, no
   "was:" — the mechanical half is a grep for `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]`
   and `#[0-9]{3,}` that finds only template placeholders; a quote or a
   reasoning-behind is caught by the law-by-law read. A gap is sent back to the
   same subagent naming the law, never hand-patched; a law the subagent
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
   with an inline order.** Per post: its comment id and the verdict,
   `folded in <sha>: <law or digest row>` or `rejected: <why>`; the clerk
   runs `feedback -- reply --resolve` and reports one line per post; the
   lead checks every post the pass folded has a line, and lists one that
   does not under `Not done`. *Why:* unanswered is unprocessed (README):
   a post folded but not replied is folded again next pass.
9. **A file with no charter gets its first one in the same pass.**
   `handoff`, `manage-stats` and `pickup` have none today; any file found
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
    not answered and the advisor points declined; `Needs the owner` a fork
    the wish opened and did not close. *Why:* the owner reads it on a
    phone, after the fact.

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

## What the skill file must not contain

The owner's quote, the reasoning behind the fresh-context derivation, the
names of the charterless files beyond the rule that covers them, this
charter's history. It carries the steps, the derivation brief and the
clerk order shape.

## Revisit when

- Derivation diffs routinely churn wording in laws that did not move —
  the brief should allow the subagent to read the current file for wording
  only, or the skill should distinguish a one-law patch from a rewrite.
- The advisor pass routinely returns nothing — drop it to on-request.
- Every charterless file has its charter — law 9 collapses to "a file
  with no charter is a bug".
- A charter is edited by a `/handoff` sweep without this skill — handoff's
  sweep should spawn this skill's steps instead of carrying its own copy.

## Fold digest

| Date | Kind | Became |
|---|---|---|

## Incident corpus

| date | source | finding | laws |
|---|---|---|---|
| 2026-10-14 | owner, this charter's birth | the protocol lived in the README and in every session's memory of it; files were patched with lessons and re-derived by the session holding the history they must omit | 1, 5 |
