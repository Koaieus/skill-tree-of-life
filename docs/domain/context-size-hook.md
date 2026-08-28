# The context-size-hook (#652)

A `PostToolUse` hook, wired in the checked-in `.claude/settings.json`, that
injects nothing on the overwhelming majority of tool calls and exactly one
informational line the first time a session crosses 150k / 200k / 250k tokens
(then every 50k after that):

```
CONTEXT SIZE SO FAR: ~212k (crossed 19:31, ~38 min into session)
```

The script is `.mise/tasks/context-size-hook`. It exists to make one line of
`drone` guidance ("reconsider past 250k") *actionable* — an agent otherwise has
no reliable way to observe its own context size. See GitHub #652 for the full
research trail (three comments; the last corrects the second on a load-bearing
point — read it if you're touching this).

## Why this needs its own doc, not just comments

The payload this hook receives has one surprising property that is easy to
"fix" back to something more intuitive and wrong. Everything below is verified
empirically (2026-08-28), not inferred from documentation.

## The subagent payload quirk

For a **subagent's** tool call, `PostToolUse`'s JSON payload carries:

```
session_id      = the PARENT session's uuid
transcript_path = .../<project-slug>/<parent-session-uuid>.jsonl   (the PARENT's transcript)
agent_id        = <hex id>
agent_type      = <e.g. "general-purpose">
```

Both `session_id` and `transcript_path` belong to the orchestrator, **not** the
subagent that actually made the call. A main-session call carries neither
`agent_id` nor `agent_type` (it has an `effort` key instead) — so **presence of
`agent_id` is the only reliable discriminator** between "this is a subagent
call" and "this is the main session."

Naively trusting `transcript_path` would measure the orchestrator's context on
every drone's tool call and latch the entire fleet against one shared key —
i.e. it would report the wrong number and fire at most once across every
drone combined. Since the hook's entire offender population (see #652's
evidence table) is drones, that bug would make the hook appear to work while
silently measuring nothing useful.

## Deriving the subagent's own transcript

The subagent's real transcript is not named in the payload directly, but is
derivable from what the payload *does* carry:

```
dirname(transcript_path) + "/" + session_id + "/subagents/agent-" + agent_id + ".jsonl"
```

i.e. `~/.claude/projects/<slug>/<session_id>/subagents/agent-<agent_id>.jsonl`.
This is exactly what `context-size-hook`'s `_run()` builds when `agent_id` is
present. Never hardcode a `~/.claude/projects/...` path elsewhere — always
derive it from the payload the same way.

## Tail-read, never full-parse

This hook runs after **every single tool call**, in every session on the
machine, and transcripts run to hundreds of MB over a long session. Parsing
the whole file every time would make the tax grow with the exact thing the
hook exists to warn about. So `_tail_lines()` seeks to the last 64KB of the
file and scans backward for the most recent `type: "assistant"` record whose
`message.usage` has `input_tokens` / `cache_read_input_tokens` /
`cache_creation_input_tokens` — that sum is the token count (confirmed against
a real harness-reported `subagent_tokens` figure during #652's research, within
rounding).

The one exception is the session-start timestamp, read once (on the first
threshold crossing only) from the head of the file and then cached in the
latch — see below — so the steady-state path never leaves the tail-read.

Measured overhead against the largest real transcript on this machine
(`.mise/tasks/context-size-hook-selftest`, ~11 MB file): well under the 200ms
acceptance bar — see that script's own output for the current number, which
this doc deliberately doesn't hardcode since it'll drift with hardware.

## Latching

A threshold must fire once, not on every subsequent tool call, and a drone's
crossings must never be latched against the orchestrator's key (see above).
The latch is keyed on `session_id` **plus** (`agent_id` or `"main"`), stored as
one JSON file per key under `<dirname(transcript_path)>/ctx-hook-state/` — that
directory sits beside the transcripts Claude Code itself already writes, so it
exists and is writable in the same cases the hook can do anything useful at
all.

Each latch file holds `{"session_start_utc": ..., "highest_fired": <tier>}`.
A new tool call only fires when the newly-computed tier is strictly greater
than `highest_fired` — this also means a large jump in one call (e.g. straight
from 140k to 260k) reports only the highest newly-crossed tier once, not one
line per skipped threshold. That is deliberate: "a handful of lines total, not
thousands" is the acceptance bar, not "every threshold, always."

## Fail-closed is the load-bearing property

This hook is checked into project `.claude/settings.json` specifically because
subagents do **not** inherit `.claude/settings.local.json` — so it runs
unattended, in every session, for every tool call, indefinitely. A hook that
prints a traceback to stdout on a bad day breaks the JSON contract for every
agent on the machine that turn. `context-size-hook`'s `__main__` wraps all real
work in one blanket `try/except Exception: pass` before `sys.exit(0)`, and the
save-before-print ordering in `_run()` means an unwritable latch directory
degrades to *silence*, never to a re-fired line on every call.

## What this hook deliberately does NOT do

The injected line is a number and a wall-clock time — no advice, no "you
should wrap up." Behavior prose (what an agent should *do* with the number)
lives in the `drone` skill (#652's sibling issue), kept decoupled on purpose:
the hook has no opinion to go stale.

## Stats ledger (optional, for #649)

Every fire also best-effort-appends one CSV line
(`session_id,kind,threshold,elapsed_min`) to `~/.claude/ctx-hook-ledger.csv`,
so a future measurement pass over "did warned drones actually see fewer
runaway sessions" is a `sort | uniq -c` rather than transcript archaeology.
This append can never affect the hook's exit code or stdout — see
`_append_ledger`.
