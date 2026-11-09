---
name: handoff
description: 'Close out a session durably — sweep every decision made in conversation into its permanent home (issue, design doc, rule file, code), commit, and only then decide whether a continuation file is warranted; a continued session gets a one-line `/pickup <file>` resume prompt. Use when the user says "handoff", "wrap this up", "EOD", "persist this", "so i can resume this tomorrow", "this session is getting heavy", or when a long session is about to be continued in a fresh context.'
---

# Handoff

Charter (the why behind each step): `docs/charters/handoff.md`.

The sweep is the work; the continuation file is a maybe. Concluded work gets
the sweep and no file.

## 0. Retiring mid-flight? Three turns, then stop

If you were told to stop, or a context, turn or time budget is blown, skip
everything below. Do exactly this:

1. Commit what exists — explicit paths only, a `wip(...)` commit whose
   message states what is missing.
2. Write the terse report:
   ```
   BRANCH: <branch>
   FILES: <paths touched>
   TESTS: <what ran, or not run>
   DID: <what was done>
   NOTES: <what is unfinished>
   ```
   Post at most one load-bearing line on the issue.
3. Send the report to whoever is waiting, and stop.

No sweep, no routing, no file, no test run, no re-read. A stop outranks the
plan: report the half-finished thing as unfinished.

## 1. Sweep what exists only in the transcript

Hunt the conversation for:

- forks the owner settled — the most valuable, the most often lost;
- claims that turned out false — corrections are as durable-worthy as
  decisions;
- rejected branches, each with its reason;
- gotchas that cost a debugging loop;
- numbers derived mid-session.

Skip anything a commit, issue, design doc or rule already holds. Record
outcomes, not the path that led to them. A sweep that finds nothing says so
and stops — that is a good result.

## 2. Route each item to its home

| Item | Home |
|---|---|
| Settled game-design fork | `docs/design/` or the owning issue |
| Open fork | the issue, written as a fork |
| Engineering gotcha under ~200 tokens | inline in `.claude/rules/<module>.md` |
| Larger engineering context | `docs/domain/<topic>.md` (+ a breadcrule if always-on) |
| Work state and next steps | the issue |
| Code | a commit — do not skip it |
| Un-actioned discovery with no owner | fix it, yourself or via one subagent briefed from the hot context; file to `Intake` only a real fork or a multi-unit job (`docs/domain/session-report.md` → *The follow-up rule*) |
| Change to a skill or agent file | `/charter`, never a direct edit |

- A rule the sweep invalidates is updated in this same pass.
- A decision never lives only in a handoff file: if deleting the file would
  lose information, the sweep is not finished.
- A spent file found in `docs/handoffs/` (its delete condition met) is
  deleted with `git rm` in the sweep's commit.

## 3. Commit the sweep — before anything else

Commit by the repo's conventions, explicit paths, `Closes #<n>` where an
issue is resolved. Never commit scratch — scripts, work directories,
non-`.md` work files go to the session's scratchpad.

## 4. Ask whether a file is warranted

Ask explicitly: *"Is there unfinished work whose context a fresh session
would need and cannot reconstruct from the issues alone?"*

- **No** → stop and report what was swept where.
- **Single-issue continuation** → it goes on the issue, not in a file.
- **Yes** (the work spans several issues and their relationship — a dispatch
  order, a coupling between forks, live numbers — would be lost) → exactly
  one file, `docs/handoffs/<topic>.md`. One file per topic; never at the
  repo root; never a directory of work files.

Handoff is not a substitute for issue hygiene, not a transcript summary, and
not automatic. A swarm still running is not handed off here: it is
`relief`'s, read from the live `docs/handoffs/swarm-<date>-<HHMM>.md` ledger
(`mise run ledger -- show`), which is gitignored and has its own lifecycle.

## 5. Write the file

The file points; it does not hold. Sections, in order:

- **State** — the commit it is written against, and what is authoritative
  (usually a design doc and the issues).
- **Open forks** — ordered by what to take first, each with its issue
  number; name couplings ("settling A forces reversing B").
- **Ready to dispatch** — issues ready to run.
- **Live numbers** — numbers the next session needs.
- **Resume** — when the work continues in a fresh session: the skill the
  work runs under (a `swarmify` design talk, a `warp`), and an instruction
  to scour the open issues the file names and the codebase before acting,
  since the file may be stale or wrong.
- **Delete condition** — the last line: when the file is spent. Whichever
  session meets it deletes the file (`git rm`, in its commit).

`docs/handoffs/` tracks only `<topic>.md` continuation files and the
swarm-train `whip-report-<date>.md` morning reports; `swarm-*.md`,
`swarm-*.inbox/`, `whip-2*`, `archive/` and `.whip.lock` are gitignored.

Commit the file.

## 6. Report

Say what was swept where, and the file if one was written. When the work
continues in a fresh session, the report's last line is the resume prompt,
exactly:

```
/pickup docs/handoffs/<topic>.md
```
