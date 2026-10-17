---
name: charter
description: revise a skill or an agent file through its charter — edit the charter (a wish, or fold its feedback board with `mise run feedback -- unanswered <charter>`), one advisor pass on the charter, a fresh Fable subagent re-derives the instruction file from the charter alone, rules-hygiene, one commit, the folded posts answered through a Haiku clerk. Use when the user says "revise a skill", "update the charter", "fold the feedback board", "re-derive <skill>", "change the <agent> agent", "/charter <name>", or when a session is about to patch a `SKILL.md` or an agent file directly.
---

# charter

The one door for changing a `.claude/skills/<name>/SKILL.md` or a
`.claude/agents/<name>.md`: the charter changes first, the file is derived
from it. Why each step is here: `docs/charters/charter.md`.

Scope is the charter, its derived files, and the `docs/charters/README.md`
index. A rule, a doc, a mise task or a code change the wish implies is
named in the report, never made in this pass — `.claude/rules/charters.md`
is such a rule and follows `writing-rules.md`. This skill's own charter is
changed the same way — through this skill.

## 1. Gate

- A session that finds itself patching an instruction file directly stops
  and runs this skill instead. A diff that touches a `SKILL.md` or an agent
  file and not its charter is the bug.
- A pass writes no design: it moves a wish into laws and laws into
  instructions.

## 2. Find the charter

- The charter is the one whose first paragraph names the file — usually
  `docs/charters/<name>.md`. An agent may be built by a skill's charter
  (one charter may build several files), so check the README index before
  concluding there is none.
- **No charter yet** → write `docs/charters/<name>.md` in this pass, from
  the file's own imperatives: each must/never becomes a numbered law with
  the why the file or the rule it points at gives, plus *What it is for*,
  a cost model, *Frontmatter*, *Revisit when*, and an empty incident
  corpus. Add it to the README index. Never patch a charterless file.
- **Charter incomplete** → before anything is derived, make sure its first
  paragraph lists every file it builds and that it carries a *Frontmatter*
  section (the `description` with its trigger phrases; for an agent also
  `model` and `tools`) or states them in its laws. Lift what is missing
  from the current file. This lift, step 5's lift, and a first charter are
  the only times a current file is read into a charter.

## 3. Read the board

- Every pass, before applying a wish: `mise run feedback -- unanswered <charter>`.
- Fold each post into the charter — a law (with its why), a row in the
  incident corpus, an entry under *Revisit when*, a fork noted there as
  open, or a rejection — and add a row to the charter's *Fold digest*
  (date · kind → what it became).
- Keep each post's comment id and its verdict text for step 11.
- A post that belongs to another charter is moved, not folded here:
  `mise run feedback -- post --verbatim <other> <file>`.
- If `unanswered` fails, continue on the wish and record the failure under
  `Not done`.

## 4. Apply the wish

- The wish — the owner's words, verbatim and dated, or a session's lesson
  — becomes a law (with its why), a corpus row, a *Revisit when* entry, or
  an open fork noted there. A pass may carry both the wish and the board;
  a wish never lands on top of an unfolded post.

## 5. Loss list, first read: the current file against the laws

- Read the current derived file. Every imperative line — each must and
  never, each command, brief and order — has its law in the charter. One
  that has none is lifted into the charter at the law it belongs to.

## 6. One advisor pass on the charter

- After editing, before deriving: one advisor pass on the charter. Apply
  each point to the charter or decline it; name the declined ones in the
  commit body. One pass, not a loop.

## 7. Derive

- One `general-purpose` subagent per charter with `model: "fable"`, a
  `name` (step 8 sends gaps back to it) and `run_in_background: false`. It
  writes every file the charter builds in one context.
- Its prompt is the derive brief below, verbatim, with only the paths
  filled: no summary of what changed, no diff, no paste of the old file.
- The builder reads the charter (with `sed -n` in ranges of about 250
  lines from its first call) and the README, opens no other file, runs no
  command beyond those reads, a `mkdir` and its writes, calls no advisor,
  and spends about six tool calls. Anything exact the charter does not give
  comes back as `<gap: law N — what is missing>`, never looked up, never
  invented.

**Derive brief** — the bracketed alternative for a charter that builds more
than one file, the agent clause when one target is an agent:

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

## 8. Check the build law by law

- Every numbered law has its line in the file; the file cites the charter
  once; it holds no date, no issue number, no owner quote, no "was:".
- Mechanical half: grep each derived file for
  `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]` and `#[0-9]{3,}` — only template
  placeholders may match; grep for `<gap: law` — every match is a gap the
  builder marked (a template placeholder aside). A quote or a
  reasoning-behind is caught by the law-by-law read.
- A gap is closed in the charter at its law, then sent back to the same
  subagent by `SendMessage`, naming the law and the charter lines to
  re-read. Never hand-patch the derived file.
- A law the subagent could not place is a law written unclearly: fix the
  charter and re-derive.

## 9. Loss list, second read: the diff

- Before the commit, every pass, read `git diff` of each derived file as a
  loss list. Each removed instruction is either a law that moved on
  purpose or a gap: lifted into the charter, the builder sent the lines to
  re-read (step 8). Never re-added by hand.

## 10. Hygiene and one commit

- `mise run rules-hygiene` adds no violation.
- One commit holds the charter and every derived file — and the README
  index when the charter is new. The charter and the file never commit
  apart.
- Message: `docs(skill): <name> — <what moved>` (`docs(agent):` for an
  agent); the declined advisor points in the body.

## 11. Answer the folded posts

- After the commit: one `clerk` subagent, `model: "haiku"`, the clerk
  order below as its whole prompt, one bullet per post with its comment id
  and verdict — `folded in <sha>: <law or digest row>` or
  `rejected: <why>`.
- Check that every post the pass folded or rejected has a line in the
  clerk's report; one that does not goes under `Not done`.

**Clerk order:**

```
Reply to and resolve each feedback post below on the `<charter>` board.
For each: write the verdict text to a file, run
`mise run feedback -- reply --resolve <comment-id> <file>`, and report one
line per post (comment id, verdict, done or the error).

- <comment-id>: folded in <sha>: <law N | digest row: <date · kind → what>>
- <comment-id>: rejected: <why>
```

## 12. Report

The session-report shape (`docs/domain/session-report.md`):

- `Landed` — the sha and the laws that moved.
- `Not done` — posts not answered, advisor points declined, a failed
  `unanswered`, and each rule, doc, mise task or code change the wish
  implies but this pass did not make.
- `Needs the owner` — a fork the wish opened and did not close.
