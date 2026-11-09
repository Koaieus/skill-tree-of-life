---
name: pickup
description: 'Continue from another session''s closing report without the owner pasting it — from a handoff file (`docs/handoffs/<topic>.md`), a pasted report, or the stale session''s transcript: check it against the code and the open issues, then act on the owner''s answers to its `Needs the owner` and `Follow-ups` under the skill the work runs under. Use when the user says "pickup", "pick up where the last session left off", "continue the previous session''s follow-ups", "continue with docs/handoffs/<x>.md", "continuation <n>: <file>", "(cont from handoff)", pastes a previous agent''s closing text, or opens with /pickup and their answers; the stale session is past its cache window or too large to answer in.'
---

# Pickup

Charter (the why behind each step): `docs/charters/pickup.md`.

Pickup only orients: it reads the prior session's report (shape:
`docs/domain/session-report.md`), checks it, maps the owner's answers onto
it, and hands the work to the skill it belongs to.

## 1. Get the input

The input is one of:

- **A handoff file** — a `docs/handoffs/*.md` path in the prompt. Read it in
  full. It names the skill the work runs under and its open items.
- **A pasted report** — a prior agent's closing text in the prompt. Read it
  in full.
- **Nothing** — read the report from the transcript:

  ```
  mise run transcripts -- final --latest 1 --tail 3
  ```

  This is the most recent session other than this one, its last three
  substantive messages (the report and any addenda). Use
  `--session <id8>` when the owner names a session; use `--latest 3` when
  the last session was not the one they mean (each session's `list` line
  shows its launch prompt).

Only this machine's transcripts are readable. A cloud or other-machine
session's report is not in `~/.claude/projects/` here: ask the owner for
the headline and the two tables, not the whole message. A failed
transcript read is never taken to mean the session ended empty.

Quote nothing of the report back to the owner.

## 2. Check it before trusting it

Treat the file, paste or report as possibly wrong.

- Run `git -C <repo> log --oneline -5` and `mise run worktree:ls`.
- Check that every SHA the input cites exists. A missing one is `Not done`
  in this session's report — never an assumption.
- Check each claim the input makes about the code against the code.
- Check each issue it names against the board: whether it is open, its
  current lane, its comments.

Say any correction in your first message, before acting on any of it.

## 3. Map the owner's message onto the report

- The owner's arguments answer the report's `Needs the owner` items, in
  order.
- They are also verbs on its `Follow-ups` rows — "do 2", "drop the rest".
- A question the owner did not answer stays a question: ask it in one line,
  after everything else is done.

## 4. Run the work under its own skill

- An issue follow-up runs as a `warp`.
- A design question runs as a `swarmify`.
- A loose end inside a fence is just done.
- When the input names the skill the work runs under (a `swarmify` design
  talk, a `warp`), continue under that skill from the input's open items.

That skill's own steps govern the work from here.

## 5. Settle a consumed handoff file

At the end of the work, if the input was a handoff file:

- its stated delete condition is met → `git rm` it in this session's
  commit;
- otherwise → update its State and open items in place, or leave it, and
  name it in the report.

## 6. End with a session report

Close in the `docs/domain/session-report.md` shape. The `Landed` headline
cites the session picked up from — its `id8`, or the handoff path.
