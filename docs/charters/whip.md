# Whip — charter

The design behind `.claude/skills/whip/SKILL.md`, the relay contract that
`swarm`'s *whip relay* section carries for every lead, and the zero-token
watchdog in `.mise/tasks/whip`. The skill is derived from this; change the
wish here, then re-derive the file. See [README](README.md) for the
protocol. Sibling charters: [swarm](swarm.md) (the lead that runs each
train), [relief](relief.md) (the fresh lead that takes a train over),
[swarmify](swarmify.md) (the day-time gate that fills the queue Whip drains).
**Feedback board: `whip — skill feedback board`** (Discussions, `Skill feedback`)
— post there what a run teaches (`mise run feedback -- post whip <kind> <file>`);
the fold digest is at the end of this file.

This charter was designed before the first night, **rewritten after it**
(run #1319, 2026-10-02) and **rewritten again after the second** (run #1363,
2026-10-03): v1 had a central `whip` session above the leads; **v2 has
none** — Whip is a relay protocol, a ledger, a set of verbs and a watchdog,
and `/whip` from any session is how a run starts. Laws marked *mined* come
from a night; *designed* ones are still a probe result or a tentative pick;
*retired* ones are kept under their number so the contract still diffs.

## What Whip is for

Whip is the **unattended relay of swarms**: the owner spends the day in
`/swarmify` passes until ten, twenty, fifty issues are `Ready`, then types
`/whip` — from a terminal, from a Remote Control session on a phone, from
anywhere — and goes to bed. By morning the `Ready` column is empty, master
carries the night's commits, and one report says what landed, what went
back to `Needs design` and why, what was filed, and what the owner has to
look at. Owner, 2026-10-02: *"hey Whip, whip up orchestrators and set up
relief agents as needed until the orchestrators' drones have landed all
issues on master … next morning: a clean board with no Ready issues, lots
of new commits on master, and a report."* Owner, 2026-10-03: *"I mean i
could run swarm from anywhere. And whip is just 1 step up, a chain of
swarms. Estafette swarm."*

The division of labour is one sentence: **leads steer swarms; the relay
hands the baton from lead to lead.** Whip removes exactly the hand that
starts every `/swarm` and `/relief`, and nothing else: nothing in Whip
reviews a diff, lands a branch, or talks to a drone. There is no session
above the leads; the baton is the ledger on disk, and the lead that
finishes a train, or runs out of context, passes it by running a verb that
launches the next runner itself.

Four layers, by what each can do:

| Layer | What it is | Can act when… | Tokens |
|---|---|---|---|
| **Daemon unit** | `claude daemon run` as its own systemd user unit — the fleet's cgroup | always | zero |
| **Watchdog** | `mise run whip -- watchdog` on a systemd user timer | always, including after the 5-hour limit and when every lead is dead | zero |
| **Leads** | `/swarm` and `/relief` sessions, `--bg` under the daemon unit, launched by the verbs | they have tokens and are not mid-turn | the budget |
| **Console** | whichever session ran `/whip` — the owner's window onto the run; optional after `start` | the owner is typing | one `show` per question |

## The cost model

Overnight the budget is **tokens per 5-hour window, twice over**, and
**one machine's process budget**. Nothing Whip does lands a line of code. So:

- **Whip has no turns of its own.** A baton pass is one Bash verb run by
  the lead that is finishing anyway; a watchdog tick is a Python process;
  the console costs one `show` per owner question. v1's lean central
  session was still a context that had to be kept alive, resumed after
  every window, relieved from its own ledger and found by id — the
  corpus's most-failed paths were all that session's (44 forks in one
  night, dead branches, a self-relief that never fired); v2 deletes the
  role rather than hardening it.
- **One lead at a time, by default, enforced.** A second concurrent lead
  burns the window twice as fast, races `land` on one checkout, and —
  mined — five at once with their drones and sharded suites exhausted the
  pids budget they shared with the owner's terminal. The ceiling is a
  ledger number the owner raises on purpose, never a prose rule a session
  may be talked out of.
- **Relief is a lead cost.** Swarm law 6 says when a lead asks for relief;
  the verb only launches it.
- **The limit is a schedule, not a failure.** A spent window leaves every
  session at its prompt until the reset; the watchdog prompts after it.
- **Polling is a tax.** No session loops on `claude agents --json`;
  liveness is the watchdog's, and the watchdog has no tokens to spend.

## Laws

**Scope**

1. **Whip steers leads and nothing below them.** Its verbs launch, prompt,
   relieve and retire `/swarm` and `/relief` sessions; nothing in Whip
   dispatches a drone, reads a diff, runs `land`, runs the suite, or opens
   an issue body. A question the ledger plus the board column list cannot
   answer is a question Whip does not ask.
2. **Nothing is escalated to the owner overnight.** A lead's "needs owner"
   becomes a `Needs design` move with a dated comment, and the lead keeps
   going; the report carries it in the morning. The owner may still type
   into the console; a stop from the owner outranks everything, as in
   swarm law 7 (law 32 is the verb).
3. **No laundering, either way.** The console never asks a lead to do what
   was blocked for it, and never does itself what a lead reported blocked.

**Process model** (*mined*)

4. **The fleet lives in its own cgroup, never the caller's.** A `--bg`
   session lives under whatever `claude daemon` is running; with none
   running, `claude --bg` spawns a *transient* daemon in the caller's cgroup
   — a terminal scope (the fleet then shares the owner's pids budget and
   takes the owner's session and the RC host down with it) or a oneshot
   service (killed with `KillMode=control-group` the moment ExecStart
   exits). So every verb that starts a session, and the watchdog, go
   through `ensure_daemon()`: `claude daemon run` as a transient systemd
   user unit (`whip-daemon`, absolute binary path, `DISABLE_AUTOUPDATER=1`
   in its env), and **refuse to start any session when the unit cannot be
   made active**. `systemctl --user stop whip-daemon` is the owner's kill
   switch for the whole fleet. Probed: a foreground daemon survives with no
   clients; the transient one idle-exits after 5 s; a restarted daemon does
   not respawn its dead sessions. The caller of `/whip` — a kitty scope, an
   RC host, anything — is never where a lead lives.
5. **A running bg session takes a prompt one way only**: `claude stop <id>`
   then a **flagless** `claude --bg --resume <id> "<prompt>"`. `claude -p -r`
   is refused while the session runs; any flag on `--resume` (`-n`,
   `--permission-mode`) forks a copy under a new id. Env on the launch
   command is irrelevant to a bg session (it inherits the daemon's); the
   daemon unit's env is the lever. This is how the watchdog and the
   console's `stop` speak to a lead: a prompt, never a `SendMessage`.
   **The stop must be verified before the resume** (*mined 2026-10-03
   11:36*, corpus row 15): a `stop` that does not take — the session was
   `waiting` on a held cross-session message — leaves it running, and the
   flagless resume then forks a copy under a new id exactly as a flagged
   one does. `prompt_session` waits for the pid to go, and skips the
   resume (one `failures` strike) if it does not.
6. ***Retired 2026-10-03 (fork E).*** v1: *identity is the ledger's
   session id; the name `whip` is the address; `start` refuses from an
   interactive session or one not named `whip`.* There is no whip session
   to identify, name, claim or resume; law 28 replaces it.
7. **`claude agents --json` speaks two vocabularies.** Interactive sessions
   carry `status` (busy/idle); background ones `state` (working/done/
   blocked) plus `status` once they have a pid; a dead bg record lingers as
   `{state: blocked}` with no pid. One normaliser (`session_state` → gone /
   blocked / busy / idle / **waiting**) is the only reader; `status`
   decides busy, and no-pid-no-status is gone, not blocked. `status:
   waiting` (*mined 2026-10-03*) is a session holding a cross-session
   message for its user's approval: `state` reads `blocked` at the same
   time, but it is not a question to a human and not a stall — the
   watchdog leaves it alone, and a cross-session message to a fleet
   session is therefore something nobody sends (law 5 is the channel).

**Launch**

8. **Every lead is a `--bg` session with a stable `-n` name, the
   permission mode and model the ledger records, and a launch prompt that
   names the whip relay as its principal** (probed: a bare-task `--bg`
   session refuses a cross-session instruction; naming the principal makes
   it comply — in v2 the only instructions a lead receives are the
   watchdog's and the console's prompts, and the clause says so). Names:
   `lead-<train>`, `relief-<train>-<k>`.
9. **The launch prompt is the lead-contract delta, nothing more.** `/swarm
   #a #b … — whip relay, train <t>` plus the relay clauses (law 12); `/relief
   — whip relay, train <t>, relieving <name>` plus the same. A slash command
   in a `--bg` launch prompt expands the skill (probed). A `/swarm` launch
   also says *fresh lead for train `<t>`, never relief, append your rows*:
   a later train on the same date finds the earlier train's `swarm-<date>.md`,
   and without that clause the swarm skill's "ledger on disk = you are
   relief" rule would orient it as relief of a done run — the date-keyed
   hijack of law 26, one layer down. The swarm skill's ledger rule carries
   the same exception. **The relay clauses and swarm's *whip relay* section
   are one contract, two readers** — a difference between them is a bug.
10. **Trains are split by the board's dependencies, never by reading
    issues.** `blocked-by` relations from the board; issues with no recorded
    dependency are one train in milestone order. The owner's count can be
    stale (a web filter — mined); `start`'s snapshot is the truth. An issue
    the owner pulls mid-run leaves its train by `train drop`, which the
    done-check and the report then treat as accounted for, never as
    *Still Ready* — nobody "remembers" a drop.
11. **A ceiling on concurrent leads, enforced by every launching verb**
    (*mined*). `max_leads` in the ledger, default 1; `start` launches up to
    that many first trains, `done` launches the next only while under it,
    and a `launch` that would exceed it is refused with the verb that
    raises it, `mise run whip -- max-leads N`, which only the owner runs. A
    relief counts against its train, not the ceiling. "Go HAM" is that verb
    with a number, never a judgement call.

**The relay — the lead-contract delta**

12. **A lead reports by verb, not to a human and not to a session** (v2;
    v1's three `SendMessage` lines to `whip` are retired). Where swarm says
    "request relief": `mise run whip -- relieve-me` — it launches
    `relief-<train>-<k>` and the outgoing drains per `relief`. After the
    push and `hygiene --fix`: `mise run whip -- done <sha> <landed n/m>` —
    it records the train, launches the next train's lead under the ceiling,
    or, with no train left, runs the done-check and renders the report
    (law 29). After moving an issue to `Needs design` with a dated comment:
    `mise run whip -- needs-owner <n> "<one line>"`, then keep going. The
    verbs read the caller's session id from the environment to find its
    train; a lead never names itself. A lead never ends its run by asking
    anything.
13. **Never ask; assume and note.** `state: blocked` means a session asked
    a human; overnight that is a stall, and the watchdog treats it as one.
14. **Nothing subscribes to a lead's idle, and idle alone is never a
    stall** (*mined*). A lead idles for long stretches legitimately (waiting
    on drones, `mp:e2e`, `refresh`); subscribing to an already-idle lead
    fires at once (a loop); a nudge *causes* a turn, so a "second idle" is
    the nudged session's own reply. Stall is the watchdog's call, from
    `blocked`, gone, or **disk silence** (law 30, *mined 2026-10-03*: a lead
    idle five hours "waiting on" drones that had died, every tick passing).
    The test keys on disk, never on the idle summary's prose — the
    prose-keyed strike rule stays rejected.

**Supervise**

15. **The ledger is written by verbs and read by relief, the watchdog and
    the console.** `docs/handoffs/whip-<date>.md` (gitignored): the start
    snapshot, the trains, per lead its name / session id / state, the
    event log, the watchdog's pending action and failure count, the
    carried items. Three writers exist — the leads' verbs, the watchdog
    timer, the console — so every verb holds one `flock` for its lifetime
    (released around a child launch); last-writer-wins on `pending` /
    `failures` / `done` is the alternative (*designed*, no incident yet).
16. ***Retired 2026-10-03 (fork E).*** v1: *five decisions, one per wake,
    in the whip session.* The five became verbs: `DONE` → `done` (law 29),
    `RELIEVE ME` → `relieve-me`, `NEEDS OWNER` → `needs-owner`, a stalled
    lead → the watchdog's own relief launch (law 19), the owner typing →
    the console's `stop` / `note` (law 32).
17. **A `blocked`, gone or disk-silent lead is relieved, not resumed.** Its
    worktrees and ledger are the state; relief's disk-orientation handles
    crash, stuck-on-a-question and dead-drones identically. Nothing ever
    `--resume`s a lead with a new task — the only resume is the watchdog's
    flagless window-reset prompt (law 22).
18. ***Retired 2026-10-03 (fork E).*** v1: *Whip relieves itself from its
    ledger at its own ceiling.* No session, no ceiling, no self-relief.

**The watchdog** (*mined*)

19. **The watchdog is the only layer that acts with no tokens, and it is
    the relay's backstop for every lead.** Every tick, from the ledger's
    session ids: a running lead that is gone, `blocked`, or disk-silent
    past `stall_minutes` (law 30) is marked `stalled` in the ledger and
    **the watchdog launches its relief itself** — `relief-<train>-<k>`,
    through the same verb a lead's `relieve-me` uses, after `claude stop`
    on the stalled session — bounded by the per-train relief cap (law 31).
    A lead at its prompt with a limit marker past its reset time gets the
    window-reset prompt (law 22). Busy → nothing. It never touches git, and
    it launches nothing while `stopped` (law 32) or past the cap (law 23).
    (v1's "never launches a lead" was a *designed* restriction that only
    made sense with a session to hand the decision to.)
20. **Every action is verified on the next tick, and three misses are a
    give-up.** An action records `pending`; the next tick checks the target
    session is present, else `failures += 1`. At three, the watchdog writes
    the `.gave-up` marker, renders the report with `GAVE UP` in the
    headline, stops its own timer, and comments the run issue. No action is
    ever logged as success on its own say-so. (Mined from 44 silent forks
    over eight hours.)
21. **`start` is one verb from any session, and it sets up everything it
    needs** (*mined 2026-10-03*; v1's "the owner's last act awake", with a
    `--bg`-only, `-n whip`-only, `Linger=yes`-or-refuse start and a
    two-command launch line, is the DX the owner called terrible). From a
    terminal, an RC session on a phone, a `--bg` session — `/whip` is the
    whole incantation. `start` brings the daemon unit up (law 4), installs
    the timer, **tries `loginctl enable-linger` itself** and records the
    result; a `Linger!=yes` it could not fix is a **warning in the ledger
    header and the report**, never a refusal (the machine is a desktop that
    stays logged in; linger matters only at logout). The sleep inhibit it
    cannot verify and the kill switch are printed for the console to relay
    once, as information, not as prerequisites. Then it snapshots `Ready`
    and master, writes the trains, and launches the first lead(s) under the
    ceiling. The caller is now the console (law 28) and may close. What is
    still unprobed: `claude --bg` and `systemd-run --user` *from an RC
    session* landing under the daemon unit (corpus: `--bg` from Bash worked
    from RC on 2026-10-02; the unit was not yet involved) — the first thing
    the tool unit verifies. **A session started from claude.ai (phone or browser, host = this
    machine; its transcript says `entrypoint: sdk-cli`) gets its permission
    mode from the app/server side per session, not from the user's
    `defaultMode: bypassPermissions`** (*mined 2026-10-03*, from the
    transcripts of the last three days: 57 such sessions came up bypass,
    18 auto, in clusters — four of seven at one minute on 10-01 differed —
    and every one from 04:37 on 10-03 was auto; every `entrypoint: cli`
    session, terminal or `--bg`, was bypass. The owner never changes the
    setting; the trigger is unknown — the app's per-session mode picker is
    the suspect). So the phone console *may* be an auto-mode session: a
    cross-session message between it and a bypass-mode lead is held for
    approval and expires — one more reason v2 sends none — and auto mode's
    classifier can deny a Bash call that stops or launches sessions (it
    denied `claude stop` to the rewriting session). The verbs a console
    runs (`start`, `stop`) must therefore be probed from an auto-mode
    session too; the watchdog, under systemd, has no classifier.
22. **A spent window is waited out, never worked around.** The session ends
    its turn with a synthetic `isApiErrorMessage` message, stays at its
    prompt, and the next prompt after the reset continues the same context.
    Nothing keys on the error wording (it differs with the spend-limit
    setting), only on the flag. **A limited lead is idle, not stalled**, and
    not disk-silent in law 30's sense either (the marker exempts it): the
    watchdog gives it the stop + flagless prompt ("continue from your
    ledger; re-dispatch what died"), rate-limited per lead (*designed*; the
    reset-in-anger case is still n=0 — night two stopped before one).
23. **Fifteen hours is the cap.** Owner, 2026-10-02: *"a cap backstop — say
    15 hours max runtime, that's 3 token windows; if more is needed that's
    something I should look at first."* Past `start + 15h` the watchdog
    prompts nothing, every launching verb refuses, a lead in flight
    finishes its train, and the report's headline says `CAPPED`.
    `start --cap <hours>`.

**The morning report**

24. **The report is a diff against the start snapshot, not a narrative**
    (*mined*: the first morning's report, corpus row 12).
    `whip-report-<date>.md` (tracked) and a comment on the run issue, from
    the ledger plus the board plus `git log <start-sha>..master`: Landed,
    Back to Needs design, Still Ready (with the noted why), **Orphaned In
    progress** (start-set issues a dead lead left `In progress` with an
    unmerged worktree — every start-set issue lands in exactly one bucket),
    Dropped by the owner, Filed (keyed on the start *timestamp in UTC*),
    Needs the owner, Incidents (every watchdog event, stall, relief,
    refusal, give-up — one line each, ANSI stripped at `event()`, identical
    repeats collapsed to `×N, HH:MM–HH:MM`), Cost, and the linger / cap /
    give-up / stop warnings in the headline. The verb says what it tore
    down (the timer unit files). Nothing the owner can get from `git log`.
25. **Done means the board and master agree.** The done-marker is written
    only when `Ready` is empty of the start set minus drops (or every
    remainder is noted), every lead is retired, every worktree is gone, and
    `hygiene` is clean bar owner items. Then the report, then the timer
    uninstalls itself. The done-check runs inside the verb that ends the
    run (law 29); what it finds untrue and cannot fix itself (a stale
    worktree of a retired lead it removes; a `Still Ready` it notes) goes
    into the report, never to a human at 03:00.

26. **A ledger that outlives its night never hijacks the next start**
    (*mined*, 2026-10-02 evening: the unreported #1319 ledger would have been
    tonight's). `start` refuses a live ledger by name (`retire --force` is
    the owner's verb, run from the console) and auto-retires a done one.
    `retire` moves json/md/markers into `docs/handoffs/archive/` suffixed
    with the start time, the tracked `whip-report-*` stays, and `report`
    never overwrites a report it did not write (same-date runs get a
    start-time suffix). "From anywhere" never means a phone `/whip` silently
    hijacks a live run: on a live ledger the skill is the console, not a
    start.
27. **The fleet's task count is measured, not guessed** (*designed*; fork D
    waits on it). Each watchdog tick records the daemon unit's
    `TasksCurrent` as `tasks_last`/`tasks_peak` in the ledger — a field,
    never an event — and the report headline carries the peak. Night two's
    peak with one lead: 141 (the 54k of the gh-shim bomb was before the
    fix). Until a multi-lead night's peak is on file, `TasksMax` stays at
    the user manager's default and the lead ceiling stays 1.

**v2 — the relay** (*designed 2026-10-03*, fork E)

28. **There is no whip session; whichever session ran `/whip` is the
    console, and the run does not need it.** The console relays `start`'s
    information lines once, answers the owner's status questions with
    `show`, forwards a stop with `stop`, records the owner's words with
    `note`, and decides nothing — every decision is a verb's. It may be an
    RC session that goes offline at once. A later `/whip` on a live ledger,
    from any session, is a console too, never a second start and never a
    "relief of Whip". Identity is the ledger file; there is nothing else to
    claim.
29. **The baton passes inside `done`.** The verb records the train's sha
    and count, retires the calling lead's row, and then: another queued
    train and headroom under the ceiling → launches `lead-<next>`; no train
    left and no lead running → done-check (law 25), report (law 24),
    done-marker, timer uninstall. A lead that runs `done` is still alive
    while the next lead starts — the verb launches before it returns, and
    the caller ends its turn afterwards; the watchdog `claude stop`s a
    `done` lead that is still present a tick later. The run ends in exactly
    one of: the last `done`, the watchdog's give-up or cap, the console's
    `stop --now`.
30. **Disk silence is a stall** (*mined 2026-10-03*: lead-a idle from 06:06
    to 11:13 waiting on drones whose worktrees had not changed since 06:02;
    the owner found it). A running lead that is `idle`, has no limit marker,
    and shows **no activity for `stall_minutes`** (ledger knob, default 45)
    — no event of its own in the whip ledger, no write to the swarm ledger,
    no commit and no mtime change under any `.worktrees/*` — is `stalled
    (silent)` and relieved like a gone one. The threshold is a ledger
    number: a healthy lead's longest silent idle is bounded by the suite
    and `refresh` (minutes), and a drone that is alive writes files; the
    false-positive cost is one relief that orients from disk and finds live
    work (relief classifies it, the stopped lead's drones are the loss).
    *Why the drones died is swarm's question, posted on swarm's board.*
31. **Two reliefs per train, then the train is failed, not relieved again.**
    A relief that dies is relieved once more; a third launch for the same
    train is refused, the train's row says `failed`, its issues fall into
    *Orphaned In progress* in the report, and `done`'s baton moves to the
    next train. Without this the watchdog's own relief launch loops under
    the give-up counter's nose (each launch verifies, so `failures` never
    reaches three).
32. **`stop` is the owner's verb, and it drains.** From the console:
    `mise run whip -- stop` sets `stopped` (no verb launches anything, the
    watchdog relieves nothing), and gives every running lead the stop +
    flagless prompt *"owner stop: go quiet, let in-flight drones report,
    land what is reported, then `whip -- done`"* — swarm law 7's shape; the
    last `done` then renders the report as usual. `stop --now` additionally
    `claude stop`s every lead and renders the report at once (unmerged
    worktrees become *Orphaned In progress*). Night two's owner stop at
    11:26 ("no further trains; let relief-a-1 land train a, then wrap up")
    was this verb done by hand with `train drop` × 16.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-02 | run #1319, 01:46 | five concurrent leads (owner: "go HAM") × drones × sharded suites in the owner's kitty scope: `cgroup: fork rejected by pids controller`; 17 coredumps at 01:49 — owner's session, RC host, bg daemon, whip, lead-a, lead-c. Which family ate ~76k tasks: **verified 2026-10-02 19:38, second night** — the `.mise/bin/gh` shim; a worktree carries its own copy and mise puts both `.mise/bin` dirs on PATH, each copy skipped only itself, so they called each other until the budget was gone (54k tasks, 30 GB, caught by law 27's counter inside the daemon unit, the terminal untouched). Fixed in the shim (marker scan + depth guard, `gh-shim-selftest` cages the regression in a TasksMax scope). Killing one by hand: `pkill` loses to a chain that forks faster than it dies — `chmod -x` the worktree's shim, then kill, then restore the mode | 4, 11, 27 |
| 2026-10-02 | watchdog, 01:49→09:42 | 44 `--bg --resume` forks of the whip session, each a fresh transient daemon in the oneshot's cgroup, dead in 0.5 s, each logged as success | 4, 5, 20, E |
| 2026-10-02 | watchdog, 01:28 | first tick finds no session *named* `whip` (owner's was titled otherwise) → forks a second whip with the same context; the owner talks to the copy | 6 (retired), E |
| 2026-10-02 | `cmd_watchdog` | `whip.get("status") == "idle"` never true for a `--bg` whip: the limit-resume and stuck-lead branches were dead code | 7 |
| 2026-10-02 | probes, CLI 2.1.287 | `-p -r` on a running bg session refused; flagged `--bg --resume` forks a copy; flagless after `stop` continues the id with its saved name/mode/model and takes the prompt; `claude daemon run` under `systemd-run --user` persists with no clients and hosts every later `--bg`; a restarted unit respawns nothing | 4, 5 |
| 2026-10-02 | lead-a, 01:28 | idle "waiting on two drones" — healthy; the table's "second idle = relieve" would have killed it; subscribing to the idle lead looped; `message: ""` failed 4× | 14 |
| 2026-10-02 | owner, 01:25 | #1317 pulled from queued train e by hand; the drop lived in a `note` | 10 |
| 2026-10-02 | RC session | mutating `claude-code-remote` MCP tools fail from a Remote Control session with "requires approval" and no prompt; read-only calls work; `claude --bg` from Bash works | 8, 21 |
| 2026-10-02 | `whip-probe-*` | `-n <name>` is the `SendMessage` address; a bare-task bg session refused a cross-session instruction and went `blocked`; naming the principal fixed it; `/relief` in a launch prompt expanded the skill | 8, 9 |
| 2026-09-30 | transcript `2131d2e9` | session limit mid-swarm: one `isApiErrorMessage: true` message, nothing until the owner typed "continue" after the reset, same context continued | 22 |
| 2026-10-02 | `CronCreate` | session-only, in-memory, gone on respawn — cannot be the recovery layer | 19 |
| 2026-10-02 | `report`, 09:42 | the first morning's report, rendered by hand: three start-set issues left `In progress` by the dead lead (unmerged worktrees) fell in no bucket, so the headline under-counted; `Filed` missed #1323 (01:47 local = the previous UTC date, and the filter was a local date); Incidents ran 136 lines — 44 identical "whip missing" events with multi-line coloured `claude --bg` output pasted into each | 24 |
| 2026-10-03 | run #1363, 06:06→11:13 | lead-a's two drones died silently (worktrees untouched from 06:02); the lead sat `idle` "waiting on d1355a and d1362" for five hours; its state never went `blocked`, so every 10-minute tick passed, the whip session was never woken, and the owner found it. 20 Ready, one train of four started, half of it landed by the relief the owner then launched by hand | 14, 19, 30 |
| 2026-10-03 | run #1363, 11:36 | the rewriting session `SendMessage`d the v1 whip two questions; whip went `{state: blocked, status: waiting}` (holding the message for approval — a different permission mode); the watchdog read it as blocked, `claude stop`ped it (it did not stop: pid still alive, status `waiting`) and flagless-resumed it — which forked a copy (`0f6835c4`, auto-titled "watchdog ledger initialization") that then wrote a note into the ledger as whip. Corpus row 3 again, by a different door; the stop of the copy was denied to the rewriting session and left to the owner | 5, 7 |
| 2026-10-03 | run #1363, 11:19 | owner: *"this skill is terrible DX … It should be a skill i can use from anywhere, no extra stuff needed"* — `start` refused unless `--bg`, named `whip`, `Linger=yes`, after a two-command shell launch line; impossible from a phone. Then: *"whip is just 1 step up, a chain of swarms. Estafette swarm."* | 21, 28, E |

## Open forks — options with costs, owner decides

**A. Concurrent leads.** The ceiling is 1 and the verb exists; whether 2 on
file-disjoint trains lands more per night when the window is not the limit
is unmeasured. Cost: two `land`s racing master, two windows burning.
Owner, 2026-10-02 (a lean, not a decision): "2 trains at once is an increased
risk in both crashing as token limit is reached. Though if 1 would do only
lots of tiny mechanical issues (or a mass rewrite or clenaup or idk) then it
would consume little tokens (cheap agents, few turns) and could run alongside
i guess?" — i.e. a second lead only for a cheap train, never two heavy ones.
**B. Whip's model — settled for v1: Opus; moot in v2.** Owner, 2026-10-02:
"I ran this whip as Opus, my reasoning: they barely read, they barely
output, but if things go wrong they have the thinking capacity. They have
more responsibility than a swarm agent, who is doing more serious
coordination work". v2 has no whip session; the reasoning now argues for
the *lead's* model (`WHIP_LEAD_MODEL`, default opus — swarm's own default),
since the lead is the thinking entity when a night goes wrong.
**C. Name — settled: Whip.** Owner, 2026-10-02: "I indeed named it whip after a
parliamentary whip, not a slave driver, though in some sense both meanings can
go up. Drones are also called drones despite often being full fledged Opus
agents. It's just which hat they're wearing. And the whip has the
responsibility to nuke sessions if things go really wrong and that's not a
friendly move".
**D. `TasksMax` on the daemon unit — culprit found, knob still open.** The
culprit was the gh shim's mutual recursion through worktrees (corpus row 1),
now fixed at the source; night two's one-lead peak was 141; a multi-lead
night's is unmeasured, so the knob waits. Parked with it: a watchdog alarm
on a sudden spike in `tasks_last` — once a multi-lead peak is on file, the
knob and the alarm are one decision.
**E. No central session — the v2 shape (tentative pick, 2026-10-03, made
by the rewriting session from the owner's words, not an owner decision).**
*Chosen:* the relay — leads pass the baton by verb, the watchdog relieves
stalls itself, `/whip` is a starter + console. Cost: the "thinking
supervisor" is gone; when a night goes wrong the thinking happens in the
relief lead, oriented from disk; the stall decision is a disk heuristic
(law 30) rather than a judgement. *Rejected for now:* the self-bootstrapping
central whip — `/whip` from anywhere launches a `--bg` `whip` under the
daemon unit and the caller becomes its console; everything else as v1.
It meets the DX bar with less change, but keeps every path the corpus
shows failing (resume-whip, identity, self-relief, the five watchdog
branches) and a second session kind to keep alive across windows. Revisit
if the relay's first night shows a decision a verb could not make.

## What the skill must not contain

- Any corpus row, issue number, date, probe narrative, the process tree, the
  cgroup story, the MCP bug — the skill names the verbs; the tool holds the
  mechanism.
- Swarm's or relief's laws, thresholds or cycle; the lead-side relay
  contract (that is swarm's *whip relay* section, derived from law 12).
- The watchdog's logic beyond "it exists and relieves stalls".
- The report's prose.

## Open follow-ups

- **The tool is v1 until its unit lands** — tracked as the issue the v2
  rewrite filed: `start` from any session (no `--bg`/name/linger refusals,
  linger try-enable, first-lead launch); `done` / `relieve-me` /
  `needs-owner` keyed on the caller's session id, `done` passing the baton
  and ending the run; `stop [--now]`; the watchdog's disk-silence test,
  its own relief launch, the per-train relief cap; `CLAUSES` rewritten to
  the relay; `report`'s buckets per law 24 (still the first morning's
  shape); the `whip`/`claim`/`relieve-me`-for-whip paths removed; and an
  **RC-session launch probe** before anything else (law 21). Until then
  the v2 skill cannot run a night.
- Whether env vars set on `claude --bg` reach the session at all; the
  daemon unit's env carries `DISABLE_AUTOUPDATER=1` on that assumption.
- The first window reset in anger (law 22): whether a flagless resume after
  a reset continues the lead's context (the mechanism is probed, n=0).
- A healthy multi-lead fleet's task peak (fork D).
- Why a lead's drones die silently with no wake to the lead (night two,
  06:02) — swarm/drone territory, posted on swarm's board; whip only
  detects it (law 30).
- **Black swans seen in the code, not yet in the field**: a CLI update
  mid-night changes the two parsed shapes (`claude agents --json`, the
  `backgrounded · <id>` line) — the version probe and the adopt-on-launch
  path degrade it, the daemon unit's `DISABLE_AUTOUPDATER` is an
  assumption; a dirty main checkout (owner WIP, untracked files) makes a
  lead's `land` refuse and the lead "assume and note" around it; the sleep
  inhibit is printed not verified; what `done`/`report` do when a `gh` call
  fails mid-night is untraced; `stall_minutes` has no false-positive data.

## Fold digest — board `whip — skill feedback board` (Discussions, `Skill feedback`)

What the board's processed posts became, so `grep` on the repo still finds
the substance. One line per fold; the post holds the detail.

- 2026-10-02 · autopsy (run #1319) → laws 4–7, 19–21; corpus rows 1–5.
- 2026-10-02 · friction (tool, ledger: count mismatch, `train drop`, `start`
  installs the timer, fork by name) → laws 6, 10, 21.
- 2026-10-02 · gotcha (lead signalling: empty `message`, subscribe loop,
  second-idle, idle is the wrong stall signal) → law 14, corpus row 6.
- 2026-10-02 · law-candidate (concurrency; "Whip wants a board") → law 11,
  fork A, and this board.
- 2026-10-02 · law-candidate (evening pre-flight: stale-ledger hijack, linger
  unverified, two ledger writers, pids culprit unmeasured, black swans) →
  laws 15, 21, 26, 27; open follow-ups.
- 2026-10-02 · tool bug (`report`: orphaned In-progress bucket missing,
  `Filed` on a local date, 136-line Incidents, silent timer teardown) → law
  24's bucket list, corpus row 12; the tool fix is an open follow-up.
- 2026-10-02 · black swan (19:32 gh-shim fork bomb under a lead; `pkill`
  loses to the chain; spike alarm proposed) → corpus row 1's kill recipe;
  the alarm parked under fork D with the `TasksMax` knob.
- 2026-10-02 · autopsy (second night, 19:38: the pids culprit is the gh
  shim; fixed at the source, `gh-shim-selftest`) → corpus row 1, fork D.
- 2026-10-03 · autopsy (watchdog missed a five-hour stall: idle lead,
  dead drones, never `blocked`) → law 30 (disk silence), laws 14/17/19
  amended, corpus row 13.
- 2026-10-03 · friction ("terrible DX": `--bg`/name/linger prerequisites,
  the two-command launch line, impossible from a phone) → law 21 rewritten,
  law 28, corpus row 14.
- 2026-10-03 · friction ("whip is just 1 step up, a chain of swarms.
  Estafette swarm") → the v2 shape: fork E, laws 12, 16, 18, 19, 28–32;
  laws 6, 16, 18 retired.
- 2026-10-03 · autopsy (11:36, posted by the forked copy itself: a held
  cross-session message read as `blocked`, the stop did not take, the
  flagless resume forked) → laws 5 and 7 amended, corpus row 15.
