# Pickup — charter

The design behind `.claude/skills/pickup/SKILL.md`. The file is derived from
this; change the wish here, then re-derive. See [README](README.md) for the
protocol.

## What pickup is for

Starting a fresh session where a stale one stopped, without the owner
pasting anything. Every run ends in the session-report shape
(`docs/domain/session-report.md`), and that report is already on disk — in
the transcript, or in the continuation file [handoff](handoff.md) wrote.
Pickup reads it, checks it, maps the owner's answers onto it, and hands the
work to the skill it belongs to. It only orients; it is the entry half to
handoff's exit half (`relief` is the entry half for a swarm still running).

## The cost model

The expensive thing is the owner's hands: copying a closing report into a
new prompt, re-typing the context a file already holds. A stale session past
its cache window costs a full re-read to answer in; pickup reads three
messages, or one file. The danger is trust — a report or handoff is a prior
agent's claim, and acting on a wrong one specs or builds against a world
that moved — so the read is cheap and the verify is not skipped.

## Laws

1. **Read the report from the transcript when no file is given.**
   `mise run transcripts -- final --latest 1 --tail 3` — the most recent
   session other than this one, its last three substantive messages (the
   report and any addenda); `--session <id8>` when the owner names one,
   `--latest 3` when the last session was not the one they mean (its
   `list` line shows the launch prompt). Quote nothing back. *Why:* the
   owner wrote the answers already; echoing the report costs them a read.
2. **The owner's message maps onto the report.** Its arguments answer
   `Needs the owner` in order and are verbs on `Follow-ups` rows ("do 2",
   "drop the rest"). An unanswered question stays a question, asked in one
   line after everything else is done. *Why:* the owner answers on the
   report's own structure, not in free prose.
3. **Verify before acting.** `git -C <repo> log --oneline -5`,
   `mise run worktree:ls`, and every SHA the report cites must exist; a
   missing one is `Not done` in this session's report, never an
   assumption. *Why:* the stale session may have left work unpushed or a
   worktree open.
4. **The work runs under its own skill.** An issue follow-up is a `warp`, a
   design question a `swarmify`, a loose end inside a fence is just done.
   *Why:* pickup only orients; the skill that owns the work owns its laws.
5. **End with a session report** whose `Landed` headline cites the session
   picked up from (`id8`, or the handoff path). *Why:* the chain of
   sessions stays traceable from the reports alone.
6. **Only this machine's transcripts are readable.** A cloud or
   other-machine session's report is not in `~/.claude/projects/` here; ask
   for the headline and the two tables, not the whole message. *Why:* a
   failed transcript read is not evidence the session ended empty.
7. **A handoff file or a pasted report is input too, and it is checked
   before it is trusted.** The input is any of: a `docs/handoffs/*.md`
   path, a prior agent's closing text pasted into the prompt, or nothing
   (law 1). A file or paste is read in full, then treated as possibly
   wrong: each claim it makes about the code and each issue it names is
   checked against the code and the board (open issues it names, their
   current lane and comments) before any of it is acted on, and a
   correction is said in the first message. When the input names the skill
   the work runs under — a `swarmify` design talk, a `warp` — the session
   continues under that skill (law 4) from the input's open items.
   *Why:* the owner continues sessions this way and never through
   `/pickup`: *"continuation 2: docs/handoffs/elements.md"*, *"#1551, (cont
   from handoff)"*, and pasted closing text 9 times in 8 sessions — *"I'm
   forced to start a new convo with "agent: ```(paste)```" … I feel like
   this happens MOST"* (2026-10-14); `/pickup` was launched in no
   transcript. One sample's own preamble: *"last agent ended with … which
   might not be entirely correct"*. Reads what [handoff](handoff.md) law
   11 writes.
8. **A consumed handoff file is deleted when its condition holds.** At the
   end of the work, if the file's stated delete condition is met, the
   session `git rm`s it in its commit; otherwise it updates the file's
   State and open items in place, or leaves it, and names it in the
   report. *Why:* the session that consumed the file is the one that knows
   it is spent; spent files left in the tree misled later agents
   ([handoff](handoff.md) law 12).

## Foreign laws

- [handoff](handoff.md) law 11 — law 7 reads the resume instruction and
  skill name the file carries.
- [handoff](handoff.md) law 12 — law 8 deletes the file under its
  lifecycle.
- [charter](charter.md) law 17 — the *Frontmatter* description is stated
  plain; the builder writes it single-quoted.

## Frontmatter

`name: pickup`. `description:`, verbatim (the builder quotes it, [charter](charter.md) law 17):

> Continue from another session's closing report without the owner pasting it — from a handoff file (`docs/handoffs/<topic>.md`), a pasted report, or the stale session's transcript: check it against the code and the open issues, then act on the owner's answers to its `Needs the owner` and `Follow-ups` under the skill the work runs under. Use when the user says "pickup", "pick up where the last session left off", "continue the previous session's follow-ups", "continue with docs/handoffs/<x>.md", "continuation <n>: <file>", "(cont from handoff)", pastes a previous agent's closing text, or opens with /pickup and their answers; the stale session is past its cache window or too large to answer in.

## What the skill file must not contain

Owner quotes, dates, session ids, the paste counts, the reasoning behind
each law. It carries the steps and the commands.

## Revisit when

- The owner still pastes closing text after the description names the
  paste and handoff shapes — the trigger is not the problem; a
  `UserPromptSubmit` hook that spots `docs/handoffs/*.md` or a pasted
  report shape and suggests `/pickup` would be the next step.
- Pickup from a handoff file routinely finds the file wrong in the same
  way — that is a handoff law (its State line, its delete condition), not
  a pickup one.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-10 → 10-15 | scan `docs/corpus/2026-11-09-skill-candidates-a.md` rows A, B | 9 pasted closing reports in 8 sessions, 4 resumes from a handoff file; `/pickup` launched 0 times | 7 |
| 2026-11-04 → 11-05 | scan `docs/corpus/2026-11-09-skill-candidates-c.md` | 2 design sessions continued from a handoff file via `/swarmify <handoff>` instead of `/pickup` | 7 |
