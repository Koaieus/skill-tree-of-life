# Long-running commands: launch once, then go quiet

The full GUT suite is ~215s. `mise run refresh` and the perf benches are the
other repeat offenders. All three have the same correct shape and the same
expensive wrong one.

## The rule

**Launch it once with `run_in_background: true`. Then do nothing about it — no
`sleep`, no `tail`, no `ls`, no re-reading the log or the task output file — and
end your turn. The harness resumes you when the command exits.**

That is not a style preference. It is the only shape that costs one tool call
instead of N.

## Why polling is not free

A backgrounded `sleep 300; cat <output>` *looks* like a legitimate wait. It is
not: the backgrounded sleep returns to the model almost immediately in
conversation terms — measured wall clock between two such "waits" was ~25s
despite `sleep 300`. So each one is a full tool round-trip carrying the whole
context, against a result that was going to arrive as a notification regardless.
A dozen of them against one 210s suite is a dozen round-trips bought for nothing,
and context budget is the scarcest resource in a long session.

Foreground-with-a-big-timeout is the other wrong shape: it buys nothing the
notification doesn't, and it holds the turn open so the user cannot interject for
minutes at a time.

## The forbidden forms, concretely

| Form | Why it's wrong |
|---|---|
| `sleep N; cat <output>` backgrounded | a poll wearing a wait's clothes — see above |
| `tail -f` / repeated `tail` on the output file | same round-trip cost, and the log is already streamed |
| `mise run test 2>&1 \| tail -30` backgrounded | `tail` buffers until EOF, so the output file stays 0 bytes for the whole run — a mid-run peek is then indistinguishable from a crash |
| `ls -la <output>` to "check progress" | a poll |
| foreground with `timeout: 600000` | blocks the user out of their own session |
| ending the turn with `"idle"` / `"waiting"` / `"still going"` | a full model turn on a full context, N times over |

**A backgrounded command's cwd:** it does inherit the Bash tool's persisted
working directory, but never assume it — make `pwd` the first thing the command
prints, as its receipt.

## Waiting on a *condition* rather than a task exit

Sometimes there is no task to be notified about — you need external state to
change (a CI run, a peer's branch appearing). The one sanctioned form is a
single backgrounded loop that exits on the condition:

```
until <check>; do sleep 5; done
```

One launch, one notification, not N. Pick the interval from how fast the state
actually changes.

## Every dispatch brief needs all three clauses

A brief that says "background it" and "end your turn" but omits "never poll"
**still produces a poller** — verified twice. The clauses are independent; paste
all three, verbatim:

> Launch the suite once with `run_in_background: true`; then do nothing — no
> sleep, no tail, no ls, no re-reading the log; then END YOUR TURN with no
> further output. The harness resumes you when it exits.

The third clause is the one most often dropped, and the second is what stops an
obedient worker from replacing polling with a string of one-word idle turns.

## Incident record

- **#710 warp drone, 2026-09-03** — backgrounded the suite, then polled it
  "madly" (`tail` / `ls` / `sleep`) until the owner intervened.
- **#756 fix agent, 2026-09-04** — obeyed a mid-run "stop polling" order, then
  emitted a string of one-word `idle` / `waiting` turns instead of stopping. The
  owner had to intervene a second time. This is why "end your turn" is its own
  clause.
- **The `tail`-buffering blindness, 2026-09-04** — found on the very run that
  fixed it in `.mise/tasks/test`.
- **Lead session, 2026-09-08 (#779)** — ~12 backgrounded `sleep; cat` polls
  against one suite run. The orchestrator, not a drone.
- **BRIEF 1 / edges-structural, 2026-09-08** — brief carried the
  `run_in_background` clause *and* the end-your-turn clause but not the
  no-polling clause; the worker polled ~a dozen times and the owner killed it
  mid-run. Its work was already committed, so only the drone's remaining context
  was lost — but the merge gate had to be re-run by the lead.

Correcting a worker mid-run is itself expensive (it re-derives its whole
context), so the clause belongs in the brief at dispatch, not in a follow-up.

## Related

- `.claude/rules/testing.md` — what to actually read out of a finished run, and
  the log-grep gotcha.
- `CLAUDE.md` — the suite is a **gate, not a feedback loop**: earn it at most
  once per unit of work. Iterate on `check` → `test:one` → `test:dir` instead.
  Not polling is the second half of that discipline; not *re-running* is the
  first.
