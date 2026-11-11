---
name: opencode
description: 'Drive a cheap OpenCode subagent headless from any agent — the run line (`/usr/bin/opencode run`, DeepSeek flash `#max` or `#high`, stdin, timeout, a JSON log), reading its result by digest without flooding your context, continuing its session by ID, listing and picking OpenCode agents. Use when you want an OpenCode drone for mechanical edits, a big sweep, boilerplate or codebase research, when the user says "opencode", "opencode drone", "flash drone", "hand this to opencode", "continue the opencode session", or when a brief tells you to dispatch work to OpenCode.'
---

# OpenCode

The why behind every step: `docs/charters/opencode.md`.

1. **Send only work whose decisions are made** — mechanical edits, big
   sweeps, boilerplate, codebase research answered with `file:line`. Decide
   a clever solution in the brief first, or give the work to a Claude
   subagent.

2. **Write a brief that stands alone** — the run sees nothing of your
   context. It names:
   - the task, the files, and what not to touch;
   - a command that checks it is done;
   - whether it may commit (by default it may not);
   - the closing report it ends with: files changed, commands run and
     their result, anything it was unsure of;
   - that it stops and reports rather than guess at a design choice.

   A long brief goes in a file outside the checkout, passed as
   `"$(cat <file>)"`, or attached with `-f <file>` and the message
   `"Follow the attached brief."`.

3. **Pick the model.** Every new session passes
   `-m "opencode-go/deepseek-v4.1-flash#max"`; use `#high` instead of
   `#max` for plainly mechanical work (a rename, a grep sweep, boilerplate,
   a format fix). Another model only when your brief or the owner names
   one, always with its `opencode-go/` prefix; list them with
   `/usr/bin/opencode models </dev/null | grep opencode-go/`.

4. **Pick an agent, if one fits:** add `--agent <name>`. List them with
   `/usr/bin/opencode debug agents </dev/null | jq -r '.[] | select(.hidden|not) | "\(.id)\t\(.mode)\t\(.model.id // "-")"'`
   (a subagent works with `run --agent` too); the global agent files are
   `~/.config/opencode/agents/<name>.md`, read with
   `grep -H -E '^(description|mode|model):' ~/.config/opencode/agents/*.md`.
   `-m` still goes on the line and overrides the agent's pinned model.

5. **Run it** — always `/usr/bin/opencode` by absolute path, never the bare
   name:
   ```
   cd <dir> && timeout <secs> /usr/bin/opencode run --archived --auto --format json -m "opencode-go/deepseek-v4.1-flash#max" "<brief>" < /dev/null > <log>.jsonl 2> <log>.err; echo "rc=$?"
   ```
   - `cd <dir> &&` — `run` has no `--dir`; it works in the cwd. Runs in
     separate directories do not cross-talk.
   - `run` — the bare `opencode` command starts the interactive TUI.
   - `< /dev/null` on the opencode command itself, every time — an open
     non-TTY stdin hangs it, even with a message argument. Never pipe into
     a zsh function wrapping it.
   - `timeout <secs>` — about 600 for a small task, up to 3600 for an
     implementation unit. `rc=124` is the timeout; `rc=1` is an error event
     (step 7); `rc=0` goes to step 8.
   - `--auto` — auto-approves every permission not explicitly denied.
   - `--archived` — keeps the run out of `session list`; read the session
     ID from the log (step 7).
   - `--format json` — one JSON event per line, each carrying `sessionID`;
     types `step_start`, `tool_use`, `text`, `step_finish`, `error`.
   - `<log>` outside the run's checkout (your scratchpad).

6. **A run longer than a minute goes in the background:** the Bash tool's
   `run_in_background: true`, which re-invokes you when it exits — no
   polling, no sleep. Parallel runs are several background calls in one
   message, each in its own directory. Set the Bash call's `timeout`
   parameter (milliseconds) above the shell `timeout <secs>`: a foreground
   call is cut at 120 s unless raised and tops out at 600 s; a background
   one is cut at 1800 s unless raised, up to 7200 s. A call cut by the tool
   leaves no `rc=` line.

7. **Read the log by digest, never whole:**
   - the reply: `jq -r 'select(.type=="text") | .part.text' <log>.jsonl | tail -n 40`
   - the errors: `jq -r 'select(.type=="error") | .error.message' <log>.jsonl`
   - what it did (also a progress check on a run still going):
     `jq -r 'select(.type=="tool_use") | .part.tool' <log>.jsonl | sort | uniq -c`
   - the session ID: `jq -r '.sessionID' <log>.jsonl | head -1`
   - the window it used: `jq -c 'select(.type=="step_finish") | .part.tokens' <log>.jsonl`
     (tokens are the measure; per-step `cost` reads 0)
   - the full record: `/usr/bin/opencode session export <session-id> </dev/null > <file>.json`,
     read with `jq`, never whole

8. **`rc=0` does not prove the work was done.** Read the reply, then check
   the tree against the brief — `git -C <dir> status --short` and the diff
   of what it touched — before anything built on it lands.

9. **Continue a session by its ID** — a question it stopped on, a fix after
   review, a follow-up: the run line with `-s <session-id>` and without
   `-m` (the session keeps its model and variant), from the same directory,
   logging to a new `<log>`. Add `--fork` to continue a copy and leave the
   original untouched. Copy the ID from step 7's digest: `-s` with an ID
   that does not exist creates a fresh empty session. A session that was
   not archived (one the owner started) is found with
   `/usr/bin/opencode session list </dev/null | head`, run from its
   project — `<id>  <title>  <date>`, newest first.

10. **A run that fails oddly gets the smoke test first:** the run line with
    the brief `"Run pwd, then reply with exactly: ok"` — it shows the shell
    tool, the cwd and the model all work.

11. **Never print, paste or post OpenCode's `service.json`** (in
    `~/.config/opencode/` and `~/.local/state/opencode/`) — it holds the
    local server's password. Debug with `/usr/bin/opencode debug paths` and
    `/usr/bin/opencode debug config` instead.
