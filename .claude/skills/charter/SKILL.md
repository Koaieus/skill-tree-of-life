---
name: charter
description: >-
  revise a skill or an agent file through its charter — edit the charter (a
  wish, or fold its feedback board with `mise run feedback -- unanswered
  <charter>`), one advisor pass on the charter, a fresh Fable subagent
  re-derives the instruction file from the charter alone, rules-hygiene, one
  commit, the folded posts answered through a Haiku clerk. Use when the user
  says "revise a skill", "update the charter", "fold the feedback board",
  "re-derive <skill>", "change the <agent> agent", "/charter <name>", or when
  a session is about to patch a `SKILL.md` or an agent file directly.
---

# charter

Design: `docs/charters/charter.md`.

Input: a wish (the owner's words, or a lesson from a session) and/or the
charter's feedback board. Output: one commit holding the charter and its
derived file(s), plus every folded post answered.

## 1. Gate and scope

- Every change to a `.claude/skills/<name>/SKILL.md` or a
  `.claude/agents/<name>.md` goes through these steps: the charter changes
  first, the file is derived from it. If you are patching an instruction file
  directly, stop and run this skill instead. A diff that touches a file and
  not its charter is the bug.
- Scope is the charter, its derived files, and the README index
  (`docs/charters/README.md`). A rule, a doc, a mise task or a code change
  the wish implies is named in the report, not made here.
  `.claude/rules/charters.md` is a rule and follows `writing-rules.md`.
- This skill's own charter is changed the same way: through these steps.

## 2. Find or create the charter

- The charter is the one whose first paragraph names the file — usually
  `docs/charters/<name>.md`, but an agent may be built by a skill's charter;
  check the README index before concluding there is none.
- Only if no charter names the file, write its first one in this pass, from the
  file's own imperatives: each must/never becomes a numbered law with the why
  the file or the rule it points at gives; add *What it is for*, a cost
  model, *Frontmatter*, *Revisit when*, and an empty incident corpus. Add it
  to the README index. Then continue with the wish and the derivation below.
  Never patch a charterless file.

## 3. Check the charter carries the build

- Its first paragraph names every file it builds (a charter may build more
  than one — a skill and an agent).
- It has a *Frontmatter* section — the `description` with its trigger
  phrases, and for an agent the `model` and `tools` — or states them in its
  laws.
- Anything missing is lifted from the current file into the charter now,
  before anything is derived. This lift, and the first charter of step 2,
  are the only times the current file is read into a charter.

## 4. Read the board, every pass

- `mise run feedback -- unanswered <charter>`. Read it whether or not the
  pass carries a wish, so a wish never lands on top of an unfolded post.
- If `unanswered` fails (Discussions not set up, GraphQL budget spent), the
  pass continues on the wish and the failure is listed under `Not done`.

## 5. Fold the wish and the board into the charter

- A wish — the owner's words, verbatim and dated, or a session's lesson —
  becomes one of: a law (with its why), a row in the incident corpus, an
  entry under *Revisit when*, or a fork noted there as open.
- Each board post becomes one of those or a rejection, and gets a row in
  the charter's *Fold digest* (date · kind → what it became).
- A post that belongs to another charter is moved, not folded here:
  `mise run feedback -- post --verbatim <other-charter> <file>`.
- Keep the comment id of every post folded or rejected, with its verdict
  text, for step 10.

## 6. One advisor pass on the charter

- After editing, before deriving: call the advisor once on the charter.
- Apply each point to the charter or decline it; the declined points are
  named in the commit body (step 9) and under `Not done` (step 11).
- One pass, not a loop.

## 7. Derive the file through a fresh Fable subagent

Spawn one `general-purpose` subagent with `model: "fable"`, a `name` (you
send gaps back to it in step 8), `run_in_background: false`. The brief holds
the charter path, the README path and the target path — no summary of what
changed, no diff, no paste of the old file. The subagent does not open the
current file.

```
Repo: <absolute repo path> (a shared checkout; do not commit, do not run
git write commands).

Write the file `<absolute target path>` (create the directory if it does
not exist) from the charter at `<absolute charter path>`, following the
protocol in `<absolute README path>`. Read those two files, then write the
whole file. Do not open any other skill or agent file.

The file's frontmatter is `name:` and `description:` as the charter's
*Frontmatter* section states them. [Agent: and `model:` and `tools:` as the
charter states them.] The body is steps only — the pipeline a fresh session
follows, with the exact briefs and orders it uses — with one one-line
pointer to the charter and nothing the charter's *What the skill file must
not contain* section forbids (no dates, issue numbers, owner quotes, or
reasoning-behind). Every numbered law in the charter must be recognisable
as a step or a line in the file.

When done, report the path and the file's line count via SubagentHandback.
```

A charter that builds more than one file gets one brief per file.

## 8. Check the build law by law

- Mechanical half: grep the derived file for `20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]`
  and `#[0-9]{3,}`; only template placeholders may match.
- Read half: every numbered law in the charter has its step or line in the
  file; the file cites the charter exactly once; it holds no owner quote, no
  "was:", no reasoning-behind.
- A gap goes back to the same subagent by `SendMessage`, naming the law.
  Never hand-patch the derived file.
- A law the subagent cannot place is a law written unclearly: fix the
  charter and re-derive (step 7).

## 9. Hygiene, then one commit

- `mise run rules-hygiene` adds no violation.
- One commit holds the charter and its derived file(s), and the README
  index when the charter is new. Message: `docs(skill): <name> — <what
  moved>` (`docs(agent): <name> — <what moved>` for an agent); the body
  names the advisor points declined.
- The charter and the file never commit apart.

## 10. Answer the folded posts through one Haiku clerk

After the commit, spawn one `clerk` subagent with `model: "haiku"`, the
order inline as its whole prompt:

```
Reply to and resolve each feedback post below on the `<charter>` board.
For each: write the verdict text to a file, run
`mise run feedback -- reply --resolve <comment-id> <file>`, and report one
line per post (comment id, verdict, done or the error).

- <comment-id>: folded in <sha>: <law N | digest row: <date · kind → what>>
- <comment-id>: rejected: <why>
```

Check that every post the pass folded or rejected has a line in the clerk's
report; one that does not is listed under `Not done`.

## 11. Report

Session-report shape (`docs/domain/session-report.md`):

- `Landed` — the commit sha and the laws that moved.
- `Not done` — posts not answered, advisor points declined, a failed
  `unanswered`, and any rule/doc/mise/code change the wish implies.
- `Needs the owner` — a fork the wish opened and did not close.
