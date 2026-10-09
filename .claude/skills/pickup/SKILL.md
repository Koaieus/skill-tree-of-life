---
name: pickup
description: Continue from another session's closing report without the owner pasting it — a fresh session reads the stale one's session report and addenda from its transcript, then acts on the owner's answers to its `Needs the owner` and `Follow-ups`. Use when the user says "pickup", "pick up where the last session left off", "continue the previous session's follow-ups", or opens with /pickup and their answers; the stale session is past its cache window or too large to answer in.
---

# Pickup — continue a stale session's report here

The report is already on disk: every run ends in the session-report shape
(`docs/domain/session-report.md`) and the transcript keeps it. Nobody pastes.

1. **Read the report.** `mise run transcripts -- final --latest 1 --tail 3`
   — the most recent session other than this one, its last three substantive
   messages: the report and any addenda. `--session <id8>` when the owner
   names one, `--latest 3` when the last session was not the one they mean
   (its `list` line shows the launch prompt). Quote nothing back; the owner
   wrote the answers already.
2. **Map the owner's message onto the report.** Their arguments are answers
   to `Needs the owner` in order, and verbs on `Follow-ups` rows ("do 2",
   "drop the rest"). An unanswered question stays a question; ask it in one
   line, do everything else first.
3. **Verify before acting.** The stale session may have left work unpushed or
   a worktree open: `git -C <repo> log --oneline -5`, `mise run worktree:ls`,
   and the SHAs the report cites must exist. A cited SHA that is missing is
   `Not done` in your own report, not an assumption.
4. **Do the work by its own skill.** A follow-up that is an issue is a
   `warp`; a design question is a `swarmify`; a loose end inside a fence is
   just done. This skill only orients.
5. **End with a session report** of your own, whose `Landed` cites the
   session you picked up from (`id8`) in the headline.

Only sessions on this machine are readable: a cloud or other-machine
session's report is not in `~/.claude/projects/` here. For those, the
owner's paste is still the way; ask for the headline and the two tables, not
the whole message.
