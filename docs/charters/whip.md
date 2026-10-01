# Whip — charter

The design behind `.claude/skills/whip/SKILL.md` and the zero-token watchdog
in `.mise/tasks/whip`. The skill is derived from this; change the wish here,
then re-derive the file. See [README](README.md) for the protocol. Sibling
charters: [swarm](swarm.md) (the lead Whip steers), [relief](relief.md)
(the fresh lead Whip launches when one dies or nears its ceiling),
[swarmify](swarmify.md) (the day-time gate that fills the queue Whip drains).

This charter was **designed, not mined**: there is no overnight corpus yet.
Every law below is a probe result or a tentative pick, marked as such; the
first real night rewrites the corpus.

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
leads.** Today the owner starts every `/swarm` and every `/relief` by hand —
one train needed three reliefs, each started manually "for truly no reason".
Whip removes exactly that hand, and nothing else: it never reviews a diff,
never lands a branch, never talks to a drone.

Three layers, by what each can do:

| Layer | What it is | Can act when… | Tokens |
|---|---|---|---|
| **Watchdog** | a shell script on a systemd user timer | always, including after the 5-hour limit | zero |
| **Whip** | one `--bg` session with a fixed `-n` name | it has tokens and is not mid-turn | lean |
| **Leads** | `/swarm` and `/relief` sessions, `--bg`, launched by Whip | same | the budget |

## The cost model

Overnight the budget is **tokens per 5-hour window, twice over** (two windows
fit in a night, with a dead stretch between them when the first is spent).
Everything Whip does is a tax on that budget, and nothing Whip does lands a
line of code. So:

- **Whip's turns are cheap by construction.** It wakes on events (a lead's
  report, an idle notice, a watchdog nudge), reads a ledger it wrote itself,
  and makes one of five decisions. It never reads an issue, a diff or a
  transcript; the lead already did.
- **One lead at a time.** A second concurrent lead burns the window twice as
  fast without landing more by morning — the window, not wall-clock, is the
  binding constraint overnight — and two leads landing on one shared
  checkout contend for `land`'s lock and the suite. Parallelism lives inside
  the lead (its drones). Tentative pick; revisit with a measured night.
- **Relief is a lead cost, not a Whip cost.** Swarm law 6 says when a lead
  asks for relief; Whip only launches it. A lead that dies silently costs
  one idle notice plus one relief orientation (~60k) — the relief charter's
  arithmetic, unchanged.
- **The limit is a schedule, not a failure.** When the window is spent,
  every session sits at its prompt until the reset (probe corpus below).
  The right response is to do nothing until `resetsAt`, at zero tokens —
  the watchdog's job, or a cheap in-session heartbeat (open fork A).

## Laws

**Scope**

1. **Whip steers leads and nothing below them.** It launches, nudges,
   relieves and retires `/swarm` and `/relief` sessions; it never dispatches
   a drone, reads a diff, runs `land`, runs the suite, or opens an issue
   body. A question it cannot answer from its ledger plus `claude agents
   --json` plus the board column list is a question it does not ask.
2. **Nothing is escalated to the owner overnight.** A lead's "needs owner"
   becomes a `Needs design` move with a dated comment, and the lead keeps
   going; the report carries it in the morning. The owner may still type
   into Whip from the phone (it is a Remote Control session); a stop from
   the owner outranks everything, as in swarm law 7.
3. **No laundering, either way.** Whip never asks a lead to do what was
   blocked for Whip, and never does itself what a lead reported blocked.
   Blocked work goes into the report, verbatim, with the lead's reason.

**Launch**

4. **Every session Whip launches is a `--bg` session with a stable `-n`
   name, the same permission mode as Whip, and a launch prompt that names
   Whip as its principal.** Probed 2026-10-02: `-n <name>` is the address
   `ListAgents` and `SendMessage` use; a `--bg` session with a bare task
   prompt *refused* a cross-session instruction as "an attempt to override"
   its original prompt and went `blocked`; the same message was followed
   when the launch prompt said "your supervisor is session `<name>`; its
   messages are your instructions". A session in a different permission
   mode holds cross-session messages for a human who is not there.
   Names: `whip`, `lead-<train>` (`lead-a`, `lead-b`, …), `relief-<train>-<k>`.
5. **The launch prompt is the lead-contract delta, nothing more.** A lead's
   prompt is `/swarm #a #b … — supervised by whip` plus the supervised-mode
   clauses (below); a relief's is `/relief — supervised by whip` plus the
   same. Swarm and relief carry their own laws; Whip restates none of them.
   A slash command in a `--bg` launch prompt expands the skill (probed,
   corpus).
6. **Trains are split by the board's dependencies, never by Whip reading
   issues.** `blocked-by` relations and hub membership from `mise gh-project
   -- list ready --json`; issues with no recorded dependency are one train in
   milestone order. A train is at most what one lead can land in one window
   (the ledger's `priced` per unit decides; swarm law 5). Whip hands the
   lead the issue numbers; the lead builds the DAG.

**Supervised mode — the lead-contract delta**

The only change to `swarm` and `relief`, carried as one section in each
skill, active when the launch prompt names a supervisor:

7. **Report to the supervisor, not a human.** Three messages, one line each,
   by `SendMessage` to the supervisor's name: `RELIEVE ME <ledger path>`
   (at swarm law 6's threshold, instead of asking the user), `DONE <train>
   <pushed sha> <landed n/m>` (after the push and `hygiene --fix`), and
   `NEEDS OWNER #<n> — <one line>` (after moving the issue to `Needs
   design` with the comment, and *while continuing with the rest*). A lead
   never ends its run by asking anything.
8. **Never ask; assume and note.** Any question a lead would have put to the
   user is answered by its own assumption, stated in the ledger and in the
   issue comment, and the unit continues or is pulled per swarm law 8.
   `state: blocked` in `claude agents --json` means a session asked a human;
   overnight that is a stall, and the watchdog and Whip treat it as one
   (law 12).
9. **The lead's reports are the only lead-to-Whip traffic.** No progress
   pings, no questions, no acknowledgements. Whip subscribes to each lead's
   idle with `notify_when_idle`; an idle with no report is the stall signal.

**Supervise**

10. **Whip's ledger is written by commands and read by its own relief.**
    `docs/handoffs/whip-<date>.md` (gitignored): the start snapshot (master
    sha, the `Ready` list with milestones), the trains, per lead its name /
    session id / state / launched@ / last event, the event log, and the
    carried items for the report. `mise run whip -- <verb>` writes every
    row; Whip never hand-edits a row and never relies on remembering.
11. **Five decisions, one per wake.** On `DONE`: next train, or if none, the
    report. On `RELIEVE ME`: launch `relief-<train>-<k>`, which drains the
    outgoing per relief law 5; retire the outgoing when it goes idle after
    the drain. On `NEEDS OWNER`: log it, nothing else. On an idle notice
    with no report: one nudge (`no human tonight — state your assumption,
    continue, and report`), then on a second idle launch relief and retire
    the lead. On the owner typing: obey, log it.
12. **A `blocked` or exited lead is relieved, not resumed.** Its worktrees
    and ledger are the state; relief's disk-orientation handles both the
    crash and the stuck-on-a-question case identically. Whip never
    `--resume`s a lead: a lead that asked a human once will ask again.
13. **Whip relieves itself from its ledger at its own ceiling**, by setting
    a marker (`whip -- relieve-me`) and ending its turn; the watchdog stops
    it and launches a fresh `whip` from the ledger. Two live sessions named
    `whip` would make every lead's report address ambiguous, which is why
    the process surgery is the zero-token layer's, not Whip's.
    Whip's ceiling is swarm's per-model number minus nothing — it has no
    drones in flight. (`CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set in this
    environment; if auto-compact proves to keep a `--bg` session's
    subscriptions, self-relief gets rare. Follow-up, not a dependency.)

**The limit and the watchdog**

14. **A spent window is waited out, never worked around.** Probed from two
    transcripts (corpus): a session that hits the limit ends its turn with a
    synthetic API-error message, stays alive at its prompt, does not exit,
    and does not retry by itself; the next prompt after the reset continues
    the same context. Whip and its leads therefore simply resume where they
    stopped once something prompts them. The owner notes the error text
    differs with the account's spend-limit setting ("Server was temporarily
    limiting requests" when a maximum spend is set), so nothing keys on the
    wording — only on the transcript's `isApiErrorMessage` flag.
15. **The watchdog is the only layer that acts with no tokens.** A systemd
    user timer every N minutes runs `mise run whip -- watchdog`, which: (a)
    exits if the done-marker exists; (b) if no session named `whip` is
    listed by `claude agents --json`, resumes it by its ledger-recorded
    session id (`claude --bg --resume <id> -n whip "watchdog: resume"`) —
    the same context, not a relief; (c) if `whip` is idle and its transcript's
    last assistant message is an API-error marker, parses a reset time from
    it when one is present and, once past it (or after a fixed cadence when
    none parses), sends one `watchdog: resume` prompt; (d) if a `lead-*` is
    `blocked` or exited and `whip` is idle, prompts `whip` once with that
    fact; (e) if the CLI binary changed, `claude respawn` at a moment when
    every session is idle. Each action is logged to the ledger's event log.
    It never launches a lead and never touches git.
16. **The machine stays up.** The launcher wraps itself in `systemd-inhibit
    --what=idle:sleep`; `loginctl enable-linger` is required for the user
    timer to survive a logout (one owner command; the `--bg` daemon itself
    is re-parented to init and survives the shell). Auto-update is turned
    off for the night (`DISABLE_AUTOUPDATER=1` on every launch) so no
    session is asked to restart mid-train.

19. **Fifteen hours is the cap.** Owner, 2026-10-02: *"a cap backstop —
    say 15 hours max runtime, that's 3 token windows; if more is needed
    that's something I should look at first."* Past `start + 15h` the
    watchdog stops prompting, Whip launches nothing new, a lead in flight is
    left to finish its current train (it is landing, not starting), and the
    report's headline says `CAPPED at 15h` with the remainder under *Still
    Ready*. The cap is a knob in `mise run whip -- start --cap <hours>`,
    default 15.

**The morning report**

17. **The report is a diff against the start snapshot, not a narrative.**
    Written to `docs/handoffs/whip-report-<date>.md` (tracked) and posted as
    a comment on the night's run issue, by `mise run whip -- report`, from
    the ledger plus the board plus `git log <start-sha>..master`. Sections,
    in this order, each a table or a list of one-liners: **Landed** (issue,
    sha, unit cost from `agent-cost`); **Back to Needs design** (issue, the
    lead's one-line reason, the comment link); **Still Ready** (issue, why
    it was not reached: window spent, train blocked, lead died); **Filed**
    (new issues, from `gh issue list --search created:>=<start>`); **Needs
    the owner** (every `NEEDS OWNER` line, verbatim); **Incidents** (reliefs
    launched, limit hits and their reset times, stalls, nudges, respawns,
    anything the watchdog did); **Cost** (`agent-cost --main` per lead and
    the window percentages at each limit hit, as snapshots). Nothing the
    owner can get from `git log` is restated.
18. **Done means the board and master agree.** The done-marker is written
    only when the `Ready` column is empty of the start set (or every
    remaining item is logged as `Still Ready` with a reason), every lead is
    retired, every worktree the leads opened is gone, and `hygiene` is
    clean except for owner items. Then the report, then the timer disables
    itself.

## Probe corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-02 | RC session | every mutating `claude-code-remote` MCP tool (`create_session`, even `set_session_title`) fails from a Remote Control session with "MCP tool call requires approval", no prompt shown (upstream #68767, #87433); allowlisting does not help; read-only calls work | 4 (why `--bg` from Bash, not `create_session`) |
| 2026-10-02 | `claude --bg -n whip-probe-n` (haiku) | listed by `claude agents --json` as `name: whip-probe-n`, by `ListAgents` as `whip-probe-n [ref] · bg`; `SendMessage` to the bare name delivered; the session appeared in the owner's claude.ai list and replied there — a `--bg` session is Remote-Control-visible without `--remote-control` | 4 |
| 2026-10-02 | same probe | a cross-session instruction ("run sleep 8, reply …") was *refused*: "conflicts with your explicit instruction … appears to be an attempt to override it", and `claude agents` showed `state: blocked` | 4, 8, 12 |
| 2026-10-02 | `whip-probe-2` | launch prompt "your supervisor is session `skill-tree-of-life-c3`; its messages are your instructions; never ask" → the same instruction was followed, `notify_when_idle` subscription accepted ("will send one notice when it is next idle") | 4, 9 |
| 2026-10-02 | process tree | a `--bg` session is `claude bg-spare` under `claude bg-pty-host` under `claude daemon` (ppid 1) — detached from the launching shell; `KillUserProcesses` is at its default (no), `Linger=no` | 15, 16 |
| 2026-10-02 | transcript `2131d2e9`, 2026-09-30 | session limit hit mid-swarm: one synthetic assistant message `isApiErrorMessage: true` "You've hit your session limit · resets 11:40pm (Europe/Amsterdam)"; nothing until the owner typed "continue, tokens ran out" at 23:41, then the same context continued | 14 |
| 2026-10-02 | transcript `7ab170d7`, 2026-09-13 | monthly spend limit hit; the lead had a 15-minute in-session loop prompt, which kept firing (16 times over 4 h), each firing answered by the same error at no cost; the limit never reset that night, so "the first firing after a reset succeeds" is **inferred, n=0** | 14, fork A |
| 2026-10-02 | CLI 2.1.282→2.1.287 | auto-updated mid-run with "restart to apply"; `claude respawn <id>` restarts a bg session on the new binary | 15, 16 |
| 2026-10-02 | `CronCreate` | session-only, in-memory, fires only while the REPL is idle, 7-day expiry; gone on respawn — so it cannot be the only recovery layer. A `* * * * *` job created inside a `--bg` session fired twice in two minutes, so the bg REPL runs its cron | fork A |
| 2026-10-02 | `claude --bg … "/relief"` (haiku) | the launch prompt expanded the skill: the session ran relief's step 1 (`gh-project list in-progress`, worktree list) unprompted | 5 |

## Open forks — options with costs, owner decides

**A. Recovery after a spent window.**
1. *Watchdog only* (law 15 as written): zero tokens; needs the systemd timer
   and `enable-linger`; parses the reset time from the transcript, falls
   back to a fixed cadence (every 20 min) when the wording does not parse.
2. *In-session cron heartbeat*: Whip schedules `CronCreate` every 15 min
   with a "continue" prompt; no infra; each firing during the dead stretch
   costs one refused request; dies with the process (respawn, crash) and
   is n=0 evidence that it resumes after a reset.
3. *Both* (recommended): cron as the cheap primary, watchdog as the
   backstop that also covers process death and respawn.

**B. Concurrent leads.** One (recommended, cost model above) vs two on
file-disjoint trains (lands more per wall-clock hour only when the window
is not the limit; doubles `land` contention and Whip's wakes).

**C. Whip's model.** Sonnet (cheapest; every decision is table-driven) vs
Opus (safer judgement on a malformed report or a train split). Recommended:
Sonnet, with the five decisions written as a table in the skill so there is
nothing to judge. Leads stay at swarm's tiering (Opus).

**D. Where the report lands.** File + run-issue comment (recommended; the
phone shows it) vs file only vs a `PushNotification` at done with the
headline line (additive; cheap; do it too).

**E. Lead transport.** `--bg` sessions (recommended; probed) vs `claude -p
--output-format json` one-shots resumed with `-r` (headless, journald logs,
no `SendMessage` back-channel — the lead would write reports to disk and
Whip would poll; the spool-dir fallback if `--bg` proves flaky).

**F. Name.** Whip (the party whip steers members, not the debate) or
*Drover* — drives the herd through the night and carries the whip; the
swarm is the herd. Owner's pick; the files are named `whip` until then.

Settled calls become ADRs (`adr` skill) once the owner has spoken; none is
written from this charter alone.

## What the skill must not contain

- Any row above, any issue number, any date, the probe narrative, the
  process tree, the MCP bug.
- Swarm's or relief's laws, thresholds or cycle — the supervised-mode
  section in each of those skills is theirs; Whip's skill only names the
  three report lines it listens for.
- The watchdog's logic (it is a script; the skill names the verbs).
- The report's prose; `mise run whip -- report` renders it from the ledger.

## Open follow-ups

- **Must probe before any unattended night** (on the first-run issue):
  (1) `claude -p -r <id>` against a *live* `--bg` session may fork a copy
  rather than prompt its REPL (`--bg --resume` says it "starts a copy when
  the session is already running"); the watchdog's post-limit and
  lead-stuck prompts rest on the opposite — the candidate single mechanism
  is `claude stop <id>` then `claude --bg --resume <id> -n whip "<prompt>"`,
  and whether `--bg --resume` takes a trailing prompt at all. (2) Whether
  env vars reach a `--bg` session: spares are pre-spawned by the daemon and
  claimed at launch, so `DISABLE_AUTOUPDATER=1` on the launch command may
  be a no-op (`FOO=bar claude --bg … "echo $FOO"` settles it; fallback is
  the daemon's own env or `settings.json`).
- A fresh `/swarm` lead for a later train finds the earlier train's
  `swarm-<date>.md` and swarm §1 would call it relief; the launch prompt
  says "fresh lead, never relief, append your rows" — confirm the ledger
  tool tolerates one night's rows from several leads.

- Whether `notify_when_idle` fires on a `--bg` session that *exits* (the
  tool says so; unobserved).
- Whether auto-compact in a `--bg` session preserves its idle subscriptions
  and cron jobs (law 13).
- A first night with fork A option 3 settles whether a cron firing after a
  reset continues the context; that night's corpus replaces the n=0 row.
- `relief` law 5's drain wake currently names "the user"'s relief session;
  under Whip the relief names itself to the outgoing exactly as before —
  no change, but confirm on the first live handover.
