# Whip — charter

The design behind `.claude/skills/whip/SKILL.md` and the zero-token watchdog
in `.mise/tasks/whip`. The skill is derived from this; change the wish here,
then re-derive the file. See [README](README.md) for the protocol. Sibling
charters: [swarm](swarm.md) (the lead Whip steers), [relief](relief.md)
(the fresh lead Whip launches when one dies or nears its ceiling),
[swarmify](swarmify.md) (the day-time gate that fills the queue Whip drains).
**Feedback board: [#1324](https://github.com/Koaieus/skill-tree-of-life/issues/1324)**
— post there what a run teaches; the fold digest is at the end of this file.

This charter was designed before the first night and **rewritten after it**
(run #1319, 2026-10-02; the autopsy is the board's first post). Laws marked
*mined* come from that night; *designed* ones are still a probe result or a
tentative pick.

## What Whip is for

Whip is the **unattended supervisor above swarm leads**: the owner spends the
day in `/swarmify` passes until ten, twenty, fifty issues are `Ready`, then
hands Whip the queue and goes to bed. By morning the `Ready` column is empty,
master carries the night's commits, and one report says what landed, what
went back to `Needs design` and why, what was filed, and what the owner has
to look at. Owner, 2026-10-02: *"hey Whip, whip up orchestrators and set up
relief agents as needed until the orchestrators' drones have landed all
issues on master … next morning: a clean board with no Ready issues, lots of
new commits on master, and a report."*

The division of labour is one sentence: **leads steer swarms; Whip steers
leads.** Whip removes exactly the hand that starts every `/swarm` and
`/relief`, and nothing else: it never reviews a diff, never lands a branch,
never talks to a drone.

Four layers, by what each can do:

| Layer | What it is | Can act when… | Tokens |
|---|---|---|---|
| **Daemon unit** | `claude daemon run` as its own systemd user unit — the fleet's cgroup | always | zero |
| **Watchdog** | `mise run whip -- watchdog` on a systemd user timer | always, including after the 5-hour limit and after Whip is dead | zero |
| **Whip** | one `--bg` session, identity = the ledger's session id, address = the name `whip` | it has tokens and is not mid-turn | lean |
| **Leads** | `/swarm` and `/relief` sessions, `--bg`, launched by Whip | same | the budget |

## The cost model

Overnight the budget is **tokens per 5-hour window, twice over**, and
**one machine's process budget**. Nothing Whip does lands a line of code. So:

- **Whip's turns are cheap by construction.** It wakes on events (a lead's
  report, a watchdog prompt), reads a ledger it wrote itself, and makes one
  of five decisions. It never reads an issue, a diff or a transcript.
- **One lead at a time, by default, enforced.** A second concurrent lead
  burns the window twice as fast, races `land` on one checkout, and —
  mined — five at once with their drones and sharded suites exhausted the
  pids budget they shared with the owner's terminal. The ceiling is a ledger
  number the owner raises on purpose, never a prose rule Whip may be talked
  out of.
- **Relief is a lead cost, not a Whip cost.** Swarm law 6 says when a lead
  asks for relief; Whip only launches it.
- **The limit is a schedule, not a failure.** A spent window leaves every
  session at its prompt until the reset; the watchdog prompts after it.
- **Polling is a tax.** Whip never loops on `claude agents --json`; liveness
  is the watchdog's, and the watchdog has no tokens to spend.

## Laws

**Scope**

1. **Whip steers leads and nothing below them.** It launches, nudges,
   relieves and retires `/swarm` and `/relief` sessions; it never dispatches
   a drone, reads a diff, runs `land`, runs the suite, or opens an issue
   body. A question it cannot answer from its ledger plus the board column
   list is a question it does not ask.
2. **Nothing is escalated to the owner overnight.** A lead's "needs owner"
   becomes a `Needs design` move with a dated comment, and the lead keeps
   going; the report carries it in the morning. The owner may still type
   into Whip (it is a Remote Control session); a stop from the owner
   outranks everything, as in swarm law 7.
3. **No laundering, either way.** Whip never asks a lead to do what was
   blocked for Whip, and never does itself what a lead reported blocked.

**Process model** (*mined*)

4. **The fleet lives in its own cgroup, never the caller's.** A `--bg`
   session lives under whatever `claude daemon` is running; with none
   running, `claude --bg` spawns a *transient* daemon in the caller's cgroup
   — a terminal scope (the fleet then shares the owner's pids budget and
   takes the owner's session and the RC host down with it) or a oneshot
   service (killed with `KillMode=control-group` the moment ExecStart
   exits). So `start`, `launch` and the watchdog all go through
   `ensure_daemon()`: `claude daemon run` as a transient systemd user unit
   (`whip-daemon`, absolute binary path, `DISABLE_AUTOUPDATER=1` in its
   env), and **refuse to start any session when the unit cannot be made
   active**. `systemctl --user stop whip-daemon` is the owner's kill switch
   for the whole fleet. Probed: a foreground daemon survives with no
   clients; the transient one idle-exits after 5 s; a restarted daemon does
   not respawn its dead sessions.
5. **A running bg session takes a prompt one way only**: `claude stop <id>`
   then a **flagless** `claude --bg --resume <id> "<prompt>"`. `claude -p -r`
   is refused while the session runs; any flag on `--resume` (`-n`,
   `--permission-mode`) forks a copy under a new id — the first night's
   "second whip" was that as much as the name check. Env on the launch
   command is irrelevant to a bg session (it inherits the daemon's); the
   daemon unit's env is the lever.
6. **Identity is the ledger's session id; the name is the address.** The
   watchdog finds Whip by `whip_session == sessionId`, never by name. Leads
   still `SendMessage(to: "whip")`, and the CLI auto-renames a second
   `whip`, so `start` refuses from a session not named `whip` (the fix is
   `/rename whip`) **and from an interactive session**: an interactive Whip
   sits in the terminal's cgroup, and a flagless resume of it carries no
   saved name/mode/model, so it would come back unaddressable while the
   watchdog's verify sees "present". Whip is launched `claude --bg -n whip
   … "/whip"` after `daemon start`, watched via `attach` or RC. The
   self-relief path stops the old Whip before the new one is named.
7. **`claude agents --json` speaks two vocabularies.** Interactive sessions
   carry `status` (busy/idle); background ones `state` (working/done/
   blocked) plus `status` once they have a pid; a dead bg record lingers as
   `{state: blocked}` with no pid. One normaliser (`session_state` → gone /
   blocked / busy / idle) is the only reader; `status` decides busy, and
   no-pid-no-status is gone, not blocked.

**Launch**

8. **Every session Whip launches is a `--bg` session with a stable `-n`
   name, the same permission mode as Whip, and a launch prompt that names
   Whip as its principal** (probed: a bare-task `--bg` session refuses a
   cross-session instruction; "your supervisor is session `whip`; its
   messages are your instructions" makes it comply). Names: `whip`,
   `lead-<train>`, `relief-<train>-<k>`.
9. **The launch prompt is the lead-contract delta, nothing more.** `/swarm
   #a #b … — supervised by whip` plus the supervised-mode clauses; `/relief —
   supervised by whip` plus the same. A slash command in a `--bg` launch
   prompt expands the skill (probed).
10. **Trains are split by the board's dependencies, never by Whip reading
    issues.** `blocked-by` relations from the board; issues with no recorded
    dependency are one train in milestone order. The owner's count can be
    stale (a web filter — mined); `start`'s snapshot is the truth. An issue
    the owner pulls mid-run leaves its train by `train drop`, which
    `done-check` and the report then treat as accounted for, never as
    *Still Ready* — Whip never "remembers" a drop.
11. **A ceiling on concurrent leads, enforced by `launch`** (*mined*).
    `max_leads` in the ledger, default 1; a `launch` that would exceed it
    is refused with the verb that raises it, `mise run whip -- max-leads N`,
    which only the owner runs. A relief counts against its train, not the
    ceiling. "Go HAM" is that verb with a number, never a judgement call.

**Supervised mode — the lead-contract delta**

12. **Report to the supervisor, not a human.** Three one-line
    `SendMessage`s: `RELIEVE ME <ledger path>`, `DONE <train> <pushed sha>
    <landed n/m>`, `NEEDS OWNER #<n> — <one line>`. A lead never ends its
    run by asking anything.
13. **Never ask; assume and note.** `state: blocked` means a session asked
    a human; overnight that is a stall, and the watchdog treats it as one.
14. **The lead's reports are the only lead-to-Whip traffic, and Whip never
    subscribes to a lead's idle** (*mined*). Idle is not stalled: a lead
    idles for long stretches legitimately (waiting on drones, `mp:e2e`,
    `refresh`); subscribing to an already-idle lead fires at once (a loop);
    the first nudge *causes* a turn, so a "second idle" is the lead's own
    reply. Reports arrive as messages regardless of subscription. Stall is
    the watchdog's call (law 17), from `blocked` or gone — never from idle.
    A message to a lead is one line; `SendMessage` with an empty `message`
    does not parse.

**Supervise**

15. **Whip's ledger is written by commands and read by its own relief.**
    `docs/handoffs/whip-<date>.md` (gitignored): the start snapshot, the
    trains, per lead its name / session id / state, the event log, the
    watchdog's pending action and failure count, the carried items. Two
    writers exist — Whip's verbs and the watchdog timer — so every verb
    holds one `flock` for its lifetime (released around the self-relief
    re-exec); last-writer-wins on `pending`/`failures`/`done` is the
    alternative (*designed*, no incident yet).
16. **Five decisions, one per wake.** On `DONE`: next train, or the report.
    On `RELIEVE ME`: launch `relief-<train>-<k>`; retire the outgoing when
    it goes idle after the drain. On `NEEDS OWNER`: log it. On a watchdog
    prompt naming a stalled lead: relieve it and retire it. On the owner
    typing: obey, log it. Nothing else is a wake.
17. **A `blocked` or gone lead is relieved, not resumed.** Its worktrees and
    ledger are the state; relief's disk-orientation handles crash and
    stuck-on-a-question identically. Whip never `--resume`s a lead.
18. **Whip relieves itself from its ledger at its own ceiling**, by setting
    a marker (`relieve-me`) and ending its turn; the watchdog stops it and
    launches a fresh `whip` from the ledger, recording the new id.

**The watchdog** (*mined*)

19. **The watchdog is the only layer that acts with no tokens, and it
    watches the leads whether or not Whip is alive.** Every tick, from the
    ledger's session ids: a running lead that is gone or `blocked` is
    marked `stalled` in the ledger; then Whip: gone → stop+resume it with a
    prompt that names the stalled leads; at its prompt with a limit marker
    past its reset time → the same prompt; at its prompt with a stalled
    lead → the same; `blocked` → "no human is awake — answer your own
    question from the ledger"; busy → nothing. Each prompt is rate-limited
    by one nudge gap. It never launches a lead and never touches git.
20. **Every action is verified on the next tick, and three misses are a
    give-up.** An action records `pending`; the next tick checks the target
    session is present, else `failures += 1`. At three, the watchdog writes
    the `.gave-up` marker, stops its own timer, comments the run issue, and
    `show` says `GAVE UP` in its header. No action is ever logged as
    success on its own say-so. (Mined from 44 silent forks over eight hours.)
21. **`start` is the owner's last act awake.** It **verifies** `Linger=yes`
    (refuses otherwise; `--linger-unchecked` overrides), prints the sleep
    inhibit it cannot verify (`systemd-inhibit --what=idle:sleep`) and the
    kill switch, brings the daemon unit up, installs the timer, and only
    then snapshots. A lead never runs without the backstop; the owner never
    learns of linger at 09:00.
22. **A spent window is waited out, never worked around.** The session ends
    its turn with a synthetic `isApiErrorMessage` message, stays at its
    prompt, and the next prompt after the reset continues the same context.
    Nothing keys on the error wording (it differs with the spend-limit
    setting), only on the flag. **A limited lead is idle, not stalled**, so
    nobody but the watchdog would ever prompt it: a running lead that is
    idle with the marker and past its reset gets the same stop + flagless
    prompt Whip gets ("continue from your ledger; re-dispatch what died"),
    rate-limited per lead (*designed*, 2026-10-02 evening; the first
    reset-in-anger is tonight's experiment).
23. **Fifteen hours is the cap.** Owner, 2026-10-02: *"a cap backstop — say
    15 hours max runtime, that's 3 token windows; if more is needed that's
    something I should look at first."* Past `start + 15h` the watchdog
    prompts nothing, `launch` refuses, a lead in flight finishes its train,
    the report's headline says `CAPPED`. `start --cap <hours>`.

26. **A ledger that outlives its night never hijacks the next start**
    (*mined*, 2026-10-02 evening: the unreported #1319 ledger would have been
    tonight's). The ledger lookup returns today's file whether done or not,
    and an unreported one for 36 h; so `start` refuses a live ledger by name
    (`retire --force` is the owner's verb, never Whip's) and auto-retires a
    done one. `retire` moves json/md/markers into `docs/handoffs/archive/`
    suffixed with the start time, the tracked `whip-report-*` stays, and
    `report` never overwrites a report it did not write (same-date runs get a
    start-time suffix). Every artifact is date-keyed; two runs on one date
    are the normal case after a bad night.
27. **The fleet's task count is measured, not guessed** (*designed*; fork D
    waits on it). Each watchdog tick records the daemon unit's
    `TasksCurrent` as `tasks_last`/`tasks_peak` in the ledger — a field,
    never an event — and the report headline carries the peak. Until a
    night's peak is on file, `TasksMax` stays at the user manager's default
    and the lead ceiling stays 1.

**The morning report**

24. **The report is a diff against the start snapshot, not a narrative.**
    `whip-report-<date>.md` (tracked) and a comment on the run issue, from
    the ledger plus the board plus `git log <start-sha>..master`: Landed,
    Back to Needs design, Still Ready (with the noted why), Dropped by the
    owner, Filed, Needs the owner, Incidents (every watchdog event, stall,
    refusal, give-up), Cost. Nothing the owner can get from `git log`.
25. **Done means the board and master agree.** The done-marker is written
    only when `Ready` is empty of the start set minus drops (or every
    remainder is noted), every lead is retired, every worktree is gone, and
    `hygiene` is clean bar owner items. Then the report, then the timer
    uninstalls itself.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-02 | run #1319, 01:46 | five concurrent leads (owner: "go HAM") × drones × sharded suites in the owner's kitty scope: `cgroup: fork rejected by pids controller`; 17 coredumps at 01:49 — owner's session, RC host, bg daemon, whip, lead-a, lead-c. Which family ate ~76k tasks is unverified; a GUT shard peaks at ~20 threads, so not the shards | 4, 11 |
| 2026-10-02 | watchdog, 01:49→09:42 | 44 `--bg --resume` forks, each a fresh transient daemon in the oneshot's cgroup, dead in 0.5 s, each logged as success | 4, 5, 20 |
| 2026-10-02 | watchdog, 01:28 | first tick finds no session *named* `whip` (owner's was titled otherwise) → forks a second whip with the same context; the owner talks to the copy | 6 |
| 2026-10-02 | `cmd_watchdog` | `whip.get("status") == "idle"` never true for a `--bg` whip: the limit-resume and stuck-lead branches were dead code | 7 |
| 2026-10-02 | probes, CLI 2.1.287 | `-p -r` on a running bg session refused; flagged `--bg --resume` forks a copy; flagless after `stop` continues the id with its saved name/mode/model and takes the prompt; `claude daemon run` under `systemd-run --user` persists with no clients and hosts every later `--bg`; a restarted unit respawns nothing | 4, 5 |
| 2026-10-02 | lead-a, 01:28 | idle "waiting on two drones" — healthy; the table's "second idle = relieve" would have killed it; subscribing to the idle lead looped; `message: ""` failed 4× | 14 |
| 2026-10-02 | owner, 01:25 | #1317 pulled from queued train e by hand; the drop lived in a `note` | 10 |
| 2026-10-02 | RC session | mutating `claude-code-remote` MCP tools fail from a Remote Control session with "requires approval" and no prompt; read-only calls work | 8 (why `--bg` from Bash) |
| 2026-10-02 | `whip-probe-*` | `-n <name>` is the `SendMessage` address; a bare-task bg session refused a cross-session instruction and went `blocked`; naming the supervisor as principal fixed it; `/relief` in a launch prompt expanded the skill | 8, 9 |
| 2026-09-30 | transcript `2131d2e9` | session limit mid-swarm: one `isApiErrorMessage: true` message, nothing until the owner typed "continue" after the reset, same context continued | 22 |
| 2026-10-02 | `CronCreate` | session-only, in-memory, gone on respawn — cannot be the recovery layer | 19 |

## Open forks — options with costs, owner decides

**A. Concurrent leads.** The ceiling is 1 and the verb exists; whether 2 on
file-disjoint trains lands more per night when the window is not the limit
is unmeasured. Cost: two `land`s racing master, two windows burning.
Owner, 2026-10-02 (a lean, not a decision): "2 trains at once is an increased
risk in both crashing as token limit is reached. Though if 1 would do only
lots of tiny mechanical issues (or a mass rewrite or clenaup or idk) then it
would consume little tokens (cheap agents, few turns) and could run alongside
i guess?" — i.e. a second lead only for a cheap train, never two heavy ones.
**B. Whip's model — settled: Opus.** Owner, 2026-10-02: "I ran this whip as
Opus, my reasoning: they barely read, they barely output, but if things go
wrong they have the thinking capacity. They have more responsibility than a
swarm agent, who is doing more serious coordination work". `WHIP_MODEL`
overrides.
**C. Name — settled: Whip.** Owner, 2026-10-02: "I indeed named it whip after a
parliamentary whip, not a slave driver, though in some sense both meanings can
go up. Drones are also called drones despite often being full fledged Opus
agents. It's just which hat they're wearing. And the whip has the
responsibility to nuke sessions if things go really wrong and that's not a
friendly move".
**D. `TasksMax` on the daemon unit.** Unset = the user manager's per-unit
default (76146 here), a separate pool from the terminal's. A lower knob
(`WHIP_TASKS_MAX`) would make the fleet fail earlier and cleaner; the right
number needs the culprit family measured first.

## What the skill must not contain

- Any corpus row, issue number, date, probe narrative, the process tree, the
  cgroup story, the MCP bug — the skill names the verbs; the tool holds the
  mechanism.
- Swarm's or relief's laws, thresholds or cycle.
- The watchdog's logic beyond "it exists and prompts you".
- The report's prose.

## Open follow-ups

- Whether env vars set on `claude --bg` reach the session at all (spares are
  pre-spawned by the daemon); the daemon unit's env carries
  `DISABLE_AUTOUPDATER=1` on that assumption.
- A fresh `/swarm` lead for a later train finds the earlier train's
  `swarm-<date>.md`; the launch prompt says "fresh lead, never relief,
  append your rows" — confirm the ledger tool tolerates several leads' rows.
- Whether auto-compact in a `--bg` session keeps enough context that
  self-relief (law 18) gets rare.
- The first night with the new watchdog settles whether a flagless resume
  after a window reset continues the context (n=0 for the reset case; the
  mechanism itself is probed).
- Which process family exhausts pids under a multi-lead fleet; until
  measured, fork D stays open and the ceiling stays 1. Law 27 puts the
  per-tick count on file; the family split (claude / godot / git) is still
  a `ps -eLo comm=` the morning after a high peak.
- **Black swans seen in the code, not yet in the field** (2026-10-02 evening
  pass; the board holds the long form): the flagless resume after a spent
  window is n=0 in anger; a CLI update mid-night changes the two parsed
  shapes (`claude agents --json`, the `backgrounded · <id>` line) — the
  version probe and the adopt-on-launch path degrade it, the daemon unit's
  `DISABLE_AUTOUPDATER` is an assumption; a second train's `/swarm` lead
  finds the first train's `swarm-<date>.md` and may orient as relief of a
  done run (the same date-keyed shape law 26 fixed one layer up); a dirty
  main checkout (owner WIP, untracked files) makes a lead's `land` refuse
  and the lead "assume and note" around it; the sleep inhibit is printed
  not verified; what `done`/`report` do when a `gh` call fails mid-night is
  untraced; Whip's own self-relief has never fired.

## Fold digest — board [#1324](https://github.com/Koaieus/skill-tree-of-life/issues/1324)

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
