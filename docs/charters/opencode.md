# OpenCode — charter

The design behind `.claude/skills/opencode/SKILL.md`. The file is derived
from this; change the wish here, then re-derive. See [README](README.md) for
the protocol.

## What opencode is for

Any Claude agent — a main session, a lead, a subagent — that wants a cheap
OpenCode subagent loads this skill and gets the mechanics of driving one
headless: the run line, the model and its variant, reading the result back
without flooding its own context, continuing the session by its ID, and
picking an OpenCode agent. It owns the CLI mechanics only. What a drone does
inside a unit is the [drone](drone.md) charter's; how a swarm lead dispatches
and reviews OpenCode drones is the planned `opencode-drone` charter's, which
cites the laws here as foreign rather than restating them.

## The cost model

An OpenCode run on the `opencode-go` subscription costs next to nothing per
call (the stream's per-step `cost` reads 0); the scarce budget is OpenCode's
rolling 5-hour window, and flash drones use it at roughly 5–10 issues per 1%
of it. So the expensive side is the Claude caller: every line of the
OpenCode stream it reads, and this skill file itself, is paid in the
caller's context, whose whole point in delegating was to stay lean. Hence a
short skill file, the stream logged to a file and read by digest, and
judgement spent where it pays — in the brief before the run and in the
check after it, Claude-side.

## Laws

1. **Call OpenCode v2 by its absolute path, `/usr/bin/opencode`.** *Why:*
   inside the repo mise's npm install (1.19.5) comes first on `PATH` and its
   Go key has expired; `opencode --version` in the repo prints `1.19.5`.
2. **Every new session passes `-m "opencode-go/deepseek-v4.1-flash#max"`.**
   `#max` is the default; `#high` for plainly mechanical work (a rename, a
   grep sweep, boilerplate, a format fix), where max reasoning buys only
   wall-clock. Another model only when the caller's own brief or the owner
   names one; `/usr/bin/opencode models </dev/null | grep opencode-go/`
   lists them. *Why:* the owner, on the wish: flash#max *"is the one to
   use"*, *"sometimes #high may be more useful, depends on how dumb the
   work is"*. The owner recalled that the model need not be named; the
   probe says otherwise: with no `-m` a run picks `opencode/gemini-4-carbon`
   and fails `provider.quota` 402 "Insufficient balance". Observed: the 402
   came from the `opencode/` provider, and every `opencode-go/` model tried
   ran; `opencode models` lists both prefixes for the same model names, so
   the prefix is part of what `-m` must say.
3. **The run line, every part of it:**
   ```
   cd <dir> && timeout <secs> /usr/bin/opencode run --archived --auto --format json -m "opencode-go/deepseek-v4.1-flash#max" "<brief>" < /dev/null > <log>.jsonl 2> <log>.err; echo "rc=$?"
   ```
   - `cd <dir> &&` — `run` has no `--dir`; it works in the cwd. Two runs in
     separate directories do not cross-talk.
   - `run` — the bare `opencode` command starts the interactive TUI.
   - `< /dev/null` on the opencode command itself — an inherited open
     non-TTY stdin hangs `opencode run` forever, even with a message
     argument; never pipe into a zsh function wrapping it (multios still
     hangs).
   - `timeout <secs>` — about 600 for a small task, up to 3600 for an
     implementation unit (the lead's pick, not the owner's). `rc=124` is
     the timeout; `rc=1` is an error event (law 6); `rc=0` is law 7.
   - `--auto` — auto-approves every permission not explicitly denied, so a
     headless run is never left waiting on a prompt.
   - `--archived` — keeps scripted runs out of `session list`; the session
     ID is read from the log (law 6).
   - `--format json` — one JSON event per line, each carrying `sessionID`;
     the types are `step_start`, `tool_use`, `text`, `step_finish`, `error`.
   - `<log>` outside the run's checkout (the caller's scratchpad), so the
     log never dirties the tree it is working in.
4. **A long brief goes through a file:** write it to a file outside the
   checkout and pass `"$(cat <file>)"` as the message, or attach it with
   `-f <file>` and the message `"Follow the attached brief."`.
5. **A run longer than a minute goes in the background:** the Bash tool's
   `run_in_background: true`, which re-invokes the caller when it exits —
   no polling, no sleep. Parallel runs are several background calls in one
   message, each in its own directory. The Bash call's own `timeout`
   parameter (milliseconds) is set above the shell `timeout <secs>`: a
   foreground call is cut at 120 s unless raised and tops out at 600 s, a
   background one is cut at 1800 s unless raised (up to 7200 s), and a
   call cut by the tool leaves no `rc=` line. *Why:* the caller's turn is
   not blocked and its context is not spent watching; without the raised
   parameter law 3's 3600 s unit dies at 1800 s.
6. **Read the log by digest, never whole.**
   - the reply: `jq -r 'select(.type=="text") | .part.text' <log>.jsonl | tail -n 40`
   - the errors: `jq -r 'select(.type=="error") | .error.message' <log>.jsonl`
   - what it did: `jq -r 'select(.type=="tool_use") | .part.tool' <log>.jsonl | sort | uniq -c`
     (also a progress check on a run still going)
   - the session ID: `jq -r '.sessionID' <log>.jsonl | head -1`
   - the window it used: `jq -c 'select(.type=="step_finish") | .part.tokens' <log>.jsonl`
     (per-step `cost` reads 0 on the subscription; tokens are the measure)
   - the full record: `/usr/bin/opencode session export <session-id> </dev/null > <file>.json`,
     read with `jq`, never whole
   *Why:* the stream is the bulk of a run; law 5's whole point is lost if
   the caller reads it.
7. **`rc=0` does not prove the work was done.** Read the reply, then check
   the tree against the brief — `git -C <dir> status --short` and the diff
   of what it touched — before anything built on it lands. *Why:* flash
   *"has lapses in judgment at times, or gets loopy"*; review stays
   Claude-side.
8. **Continue a session by its ID:** the run line with
   `-s <session-id>` and without `-m` — the session keeps its model and
   variant — from the same directory, logging to a new `<log>`. Add
   `--fork` to continue a copy and leave the original untouched. Copy the
   ID from law 6's digest: `-s` creates a fresh empty session when the ID
   does not exist. A session that was not archived (one the owner started)
   is found with `/usr/bin/opencode session list </dev/null | head`, run
   from its project — `<id>  <title>  <date>`, newest first. *Why:* a
   question the drone stopped on, a fix after review and a follow-up all
   go back into the session that holds the context; an OpenCode run has no
   `SendMessage`.
9. **Agents:** `--agent <name>` runs under that agent's prompt. List them
   with
   `/usr/bin/opencode debug agents </dev/null | jq -r '.[] | select(.hidden|not) | "\(.id)\t\(.mode)\t\(.model.id // "-")"'`
   (every source merged; a subagent works with `run --agent` too); the
   global agent files are `~/.config/opencode/agents/<name>.md`, read
   with `grep -H -E '^(description|mode|model):' ~/.config/opencode/agents/*.md`.
   `-m` still goes on the line (law 2) and overrides the agent's pinned
   model. *Why:* the global `drone` agent pins a model OpenCode v2 does not
   list; `-m` makes the pin irrelevant.
10. **The brief stands alone.** The OpenCode run sees nothing of the
    caller's context. The brief names the task, the files, what not to
    touch, a command that checks it is done, whether it may commit (by
    default it may not), and the closing report it ends with — files
    changed, commands run and their result, anything it was unsure of. It
    tells the run to stop and report rather than guess at a design choice.
    *Why:* a headless run cannot be asked mid-way; a short report is what
    law 6 reads back.
11. **Send OpenCode work whose decisions are made:** mechanical edits, big
    sweeps, boilerplate, codebase research answered with `file:line`. A
    clever solution is decided in the brief first, or the work goes to a
    Claude subagent. *Why:* the owner, ADR 0071: *"BIG mechanical stuff
    they can do, their ctx is basically free. just really clever solutions
    are best specced up front"*.
12. **Never print, paste or post OpenCode's `service.json`** (in
    `~/.config/opencode/` and `~/.local/state/opencode/`): it holds the
    local server's password. Debug with `/usr/bin/opencode debug paths` and
    `/usr/bin/opencode debug config` instead. *Why:* this charter's first
  pass `cat`ed the config directory's files while orienting and put the
  password into a session transcript.
13. **A run that fails oddly gets the smoke test first:** the run line with
    the brief `"Run pwd, then reply with exactly: ok"` — it shows the
    shell tool, the cwd and the model all work.

## Foreign laws

- [charter](charter.md) law 17 — the *Frontmatter* description is stated
  plain; the builder writes it single-quoted.

## Frontmatter

`name: opencode`. `description:`, verbatim (the builder quotes it, [charter](charter.md) law 17):

> Drive a cheap OpenCode subagent headless from any agent — the run line (`/usr/bin/opencode run`, DeepSeek flash `#max` or `#high`, stdin, timeout, a JSON log), reading its result by digest without flooding your context, continuing its session by ID, listing and picking OpenCode agents. Use when you want an OpenCode drone for mechanical edits, a big sweep, boilerplate or codebase research, when the user says "opencode", "opencode drone", "flash drone", "hand this to opencode", "continue the opencode session", or when a brief tells you to dispatch work to OpenCode.

## What the skill file must not contain

Dates, issue or ADR numbers, owner quotes, the probe stories behind laws 1,
2, 3 and 8, the cost figures, the contents of any `service.json`, and the
reasoning behind each law. It carries the steps, the run line and the
digest commands, verbatim, and stays short: it is loaded into the caller's
context, which it exists to keep lean.

## Revisit when

- OpenCode is upgraded past v2.2.6 — re-run the probes in the corpus
  (`run --help`, a run with no `-m`, a `-s` continuation's model,
  `--agent` honoured, `-m` over an agent's pin).
- mise's npm `opencode` is removed or upgraded to v2 — law 1 can use the
  bare name.
- A default model is set in `~/.config/opencode/opencode.jsonc` — law 2
  still passes `-m`, since an explicit model is robust to config drift.
- The global `drone` agent's model pin is fixed — law 9's *Why* goes.
- The `opencode-drone` charter (the swarm lead's side) lands — it lists the
  laws here it uses as foreign; any law here that turns out to be a
  dispatch law moves there.
- `-s` with a mistyped ID: law 8's "creates a fresh empty session" rests on
  the `--help` text alone; the first time it bites, it goes in the corpus.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-11-08 | swarm-train blind-review experiment | an inherited open non-TTY stdin hung `opencode run` with no output, exit 124 under `timeout`; `< /dev/null` fixed it; a pipe into a zsh function still hung; two concurrent runs in separate dirs did not cross-talk; `-f <file>` and a quoted `"$BRIEF"` both carried a long brief | 3, 4 |
| 2026-11-11 | probe, this charter's first pass | `which -a opencode` in the repo lists mise's npm 1.19.5 before `/usr/bin/opencode` (v2.2.6) | 1 |
| 2026-11-11 | probe | `run` with no `-m` picked `opencode/gemini-4-carbon` and failed `provider.quota` 402 "Insufficient balance"; with `-m "opencode-go/deepseek-v4.1-flash#max"` the smoke test replied `ok` | 2, 13 |
| 2026-11-11 | probe | `-s <id>` with no `-m` continued the session on `deepseek-v4.1-flash` variant `max` and answered from its earlier turn | 8 |
| 2026-11-11 | this charter's first pass, orienting | `cat ~/.config/opencode/*.json` printed `service.json`, the local server's password, into the transcript (local 127.0.0.1 server; the owner decides on rotating it) | 12 |
| 2026-11-11 | probe | `--agent flash` (a subagent) ran as agent `flash` on its pinned `glm-5.3-flash`; `--agent drone -m "opencode-go/deepseek-v4.1-flash#high"` ran as agent `drone` on `deepseek-v4.1-flash#high` — `-m` overrides the pin | 9 |

## Fold digest

None yet.
