# Scan: re-asks and knob-shaped asks in `/swarmify` sessions — 2026-09-26

Source: 59 sessions with a literal `/swarmify` command block; the 32 most
recent by mtime (2026-09-03..26) parsed in depth — 97 `AskUserQuestion`
calls, 251 questions. Plain-text questions outside the tool were not tallied
(undercount). Sonnet-read, directional not exact. Session files are under
`~/.claude/projects/-home-bramh-skill-tree-of-life/`.

## Totals

- Most questions are code-grounded (a `file:line`, a measured cost, a
  contradiction found in the repo) — the re-ask is a **minority** pattern,
  not the norm. What it costs is attention and trust, not volume.
- Re-asks concentrate in three shapes:
  1. **Numeric magnitudes deferred** ("magnitudes yours", "which tier, t1 or
     t2?") instead of defaulted inside the owner's stated range and marked
     tentative → law 32.
  2. **Confirm-everything closers** ("OK?", "does that hold as the rule?",
     "Settle both?") → law 31.
  3. **The milestone question**, in nearly every session — a board rule, not
     a design fork; the live milestone is the default → law 32.
- Cause: nothing in the skill said "an answer the owner already gave is
  settled" or "a value is not a design answer"; "never invent a design
  answer" was read as "confirm everything".

## Re-asks

- `3717298e…` (#848, 09-24) — found marshalling ~1% of a swing; **the issue
  said to drop it if marshalling is not a visible share**; asked "What do we
  do?" instead of applying the owner's stated rule.
- `54ffd67b…` (tooltip v3, ~09-24) — owner: keep-out "like a **capsule
  shape** i guess… pushout force field"; Fork 5 asked the keep-out shape with
  "One rect" as Recommended, overriding the owner's shape without naming why.
- `28484c19…` (#842/#883/#884) — "Default tier (**you said t1 or t2**):
  which one?"; "you picked the T1 ladder but never gave a number" — a knob
  inside a stated range, asked.
- `6f05643b…` (status-fx sandbox tab, #1114 — a `/warp`, not `/swarmify`) —
  asked "How should the always-on tooltips be shown?" and "What does 'single
  node with vision range' mean to you?". Narrower than a pure re-ask (real
  fan vs standalone column is a *how*), but stated intent framed as open.

## Knob-shaped asks

- `d220871a…` — "Live ring count on every core? core_presence.tscn authors 3,
  the bench used 5" — an `@export` defaulted to the bench value.
- `54ffd67b…` — "Fork 6 — trunk length", already framed as "one fan-wide knob
  on the driver" — right shape, still posed as a question.
- `30207f7b…` — "Blindness depth curve for v1?", "Magnitudes yours".

## Good behaviour

- `205513e3…` (#1126) — "You said there were no real forks, so I picked
  those two numbers myself and marked them tentative on the issue. They're
  easy to change." Zero questions.
- `255e9e4f…` (procgen cluster) — "Keystones stay stitch-anything, exactly
  as you said."
- `3bfe77c4…` — owner: "I expect I could leave most of these forks for you
  to settle" → zero questions across four issues.

## Legit asks — the guard against overcorrecting

- `dfab5816…` — owner asked for "a hard zoom onto only the target";
  `_fit_zoom` never zooms past the player's zoom (ADR 0027). A review
  finding, correctly surfaced.
- `26074cf7…` — "~13 lying nodes per 800-node level at 10% blight": the
  arithmetic exposed a hole in the design.
- `8330a637…` (#1102) — "the agreement test is vacuous today": a bug in the
  issue's own proposed fix.
- `d78aefc4…` (StatPool `k`) — the owner's prompt was itself an open
  question.
- `25b40275…` (#949) — the body listed "Open forks (all owner calls)"; the
  questions mapped 1:1 onto them.
