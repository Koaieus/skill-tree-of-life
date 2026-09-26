# Clerk-tail and throughput measurement — read-only, 2026-09-26

Method note: everything below comes from two scripts
(`measure2.py`, `measure3.py` in this scratchpad) run once over every
transcript that matched, plus two direct `git log` / `gh issue list` /
subagent-transcript scans for Part B. Per-session numbers were spot-checked
by eye on two tails (`08190876…` pre-fix, `255e9e4f…` post-fix) rather than
hand-read one by one — that is the scale trade-off the advisor flagged and I
followed.

## Selection

A "swarmify session" = any main-session transcript under
`~/.claude/projects/-home-bramh-skill-tree-of-life/*.jsonl` containing the
literal invocation marker `<command-message>swarmify</command-message>\n<command-name>/swarmify</command-name>` in a `user`-type record (this is stricter than
grepping for the word "swarmify", which also matches the skill-listing
system-reminder text present in nearly every transcript). This found **59
sessions**, 2026-08-27 through 2026-09-26: 21 before 2026-09-15, 38 on/after.
`isSidechain` records (embedded subagent turns inlined in the parent log)
were excluded from all main-session accounting.

**Tail-start heuristic**: the first tool_use (Bash / Write / AskUserQuestion
input) whose *full* JSON-encoded input matches `acceptance spec`
case-insensitively. Classifying on the truncated 2000-char snippet (my first
pass) undercounted badly — the repo's actual pattern is one Bash call doing
`cat > /tmp/foo.md <<'EOF' … long spec body … EOF` followed by
`gh issue create --body-file /tmp/foo.md` in the *same* call, so truncation
cut the `gh` invocation before it could be classified. Fixed by classifying
on the untruncated string. 56/59 sessions produced a tail; 3 had no
"acceptance spec" tool input at all (design-only sessions that didn't reach
a spec, or the phrase used different wording — not separately verified per
the effort budget).

**Clerk-shaped turn** = a tail turn (by requestId) whose tool_use inputs
match any of: `gh issue create|edit|comment|view|close|reopen`, `gh api`,
`mise (run )?gh-project`, `mise run issue-drift|refresh`, `--parent`,
`--blocked-by`, `--body-file`, or a heredoc/`cat > /tmp/*.md` body-file
write. Two counts are reported because the boundary is genuinely fuzzy:

- **loose** (all of the above, matches the task's literal list, *excluding*
  the tail-start turn itself — that one turn is Opus drafting the spec, not
  clerking it)
- **relay-only / strict** (drops the heredoc/body-file *writes*, which are
  drafting labor even though mechanical, and keeps only `gh issue
  edit/comment/view/close`, `gh api`, and the `mise gh-project` /
  `issue-drift` / `refresh` calls — i.e. things a clerk could do from a
  finished brief with no judgment)

## Part A — totals

| | pre 09-15 (21 sessions, 08-27→09-14) | post 09-15 (38 sessions, 09-15→09-26) | all 56 (tail found) |
|---|---|---|---|
| Σctx whole sessions | 146.7M | 205.7M | 352.4M |
| Σctx tail | 116.2M (79% of session) | 119.9M (58%) | 236.1M (67%) |
| tail turns | 793 | 805 | 1598 |
| clerk turns, loose | 313 | 333 | 646 |
| clerk turns, strict (relay-only) | 188 | 209 | 397 |
| Σctx clerk, loose | 45.5M | 49.2M | 94.7M |
| Σctx clerk, strict | 27.6M | 30.3M | 57.9M |
| failure-flag entries | 69 | 33 | 102 |

Medians (post window, 35 sessions with a tail): tail_turns 19, clerk_turns
(loose) 9, context-at-tail-start ≈116k tokens (already well past the "finish
cleanly" line for a fresh session).

Session-level detail (post window; pre window numbers are in
`pre0915.json`/`post0915.json` in this scratchpad, one row per session,
`model`s were uniformly `claude-opus-5` — no session mixed models):

```
session file                          tail? clerk relay tail_turns
08190876-...441896   09-15  True   4   3   14   (incomplete — cut off mid-tail,
                                                  continued same day in e0bafa9e)
e0bafa9e-...e232     09-15  True   9   6   25
e9c0d4ce-...0ea1a5   09-16  False  -   -   -   (no acceptance-spec tool input found)
84b0b6f1-...9df168   09-16  True  14  13   30
794d07e4-...c95b     09-16  True  17  12   45
243c15c4-...64d0e32  09-16  True   5   3    7
7d8c486b-...09811b   (n/a)  True  13   3   39
63c9f0ed-...9df393   09-17  True  20  12   51
ec5e3da0-...66d0a5   09-17  False  -   -   -
747ff9a6-...33da94   09-18  True  15   8   30
9ad49ead-...12ce     09-20  True  12   9   16
180528f3-...28ad     09-20  True   9   7   19
766f3427-...74b3     09-20  True   7   4   22
a78bc86a-...94b      09-21  True   5   5   13
42b82a91-...dbe53    09-21  True   5   3    8
ba9198f6-...850f     09-21  True  12   5   28
25b40275-...98e9     09-21  True  17  11   47
d8162dbc-...df90a5   09-21  True   2   1    7
e1a3021e-...717f     09-21  True  20  10   32
2e04ee79-...517      09-22  True   5   4   12
dfab5816-...81f      09-22  True   9   6   19
255e9e4f-...9e7f     09-22  True  24  10   54
65f779bf-...783055   09-22  True   8   4   19
26074cf7-...780f     09-22  True  10   6   29
d78aefc4-...466      09-22  False  -   -   -
789037f0-...d595     09-23  True  17  12   40
d64f73d1-...530      09-23  True   5   4   13
24f3c91a-...9c9      09-23  True   6   3    9
3717298e-...9cf9     09-23  True   9   7   25
28484c19-...b127     09-23  True  11   5   19
292c24f8-...918496   09-23  True   5   3    9
3bfe77c4-...af34     09-23  True   8   6   14
dfecd75b-...cbf2f    09-23  True   4   3    8
30207f7b-...12b5f    09-23  True   3   2    5
8330a637-...f393     09-24  True   4   4    7
d220871a-...dd5     09-24  True   5   5   16
54ffd67b-...c35f     09-24  True   9   6   45
205513e3-...ab9      09-26  True   5   4   29
```

**Issues touched in tail** (created via `issues/(\d+)` URLs in `gh issue
create` results, promoted via `gh-project -- status <n> Ready`): every
session that reached the mechanical end touched 1–7 issues; the modal shape
is a hub (`#N`) plus 2–5 children. Exact per-session lists are in
`priced.json`/`post0915.json`; aggregating across all 56: dozens of distinct
issue numbers, no session touched zero.

**Failures/retries inside the tail** (102 flagged entries total; kinds, by
frequency):
- **`gh` field-schema drift** — `Unknown JSON field: "blockedByIssues"` /
  similar, i.e. the CLI's queryable field names moved under the session
  (recurs across 3+ sessions pre-09-15; not seen post-09-15, suggesting the
  swarmify rewrite already absorbed this).
- **Exit code 1 from `gh issue edit --add-blocked-by` / `gh-project`
  commands** hitting a not-yet-existing issue or a milestone name typo —
  the classic "created child before parent settled" ordering bug.
- **`mise gh-project -- hygiene` catching something the session then fixed
  by hand** (grep-filtered for `WARN` in-line, so a genuine violation was
  visible in ~6 sessions).
- **Repeated identical commands** (`repeated_command` in the raw data) — a
  retry after a failure, or a defensive re-check; ~15 instances.
- **One `command timed out after 2m` on an unrelated `magick` icon-cache
  build**, not a clerk-shaped failure but sitting inside the tail window.
- **No backtick-mangled `--body` seen** in the sample — every session that
  posts a multi-line body already goes through `--body-file` + heredoc, so
  the CLAUDE.md rule against inline backticks appears to already be
  followed consistently in this corpus. Worth carrying forward as "keep
  doing this," not a caveat to add.

These are exactly the caveats a clerk's instructions need to carry:
sequence issues before setting relations on them, expect `gh` JSON field
names to occasionally drift and re-check with `gh issue view --json` rather
than trusting a remembered field list, run `hygiene` and actually read its
output rather than assuming clean, and don't retry blind — the repeated-command
pattern suggests some retries happened without diagnosing the first failure.

## Part A — cost estimate

Raw Σctx tells a misleading story: it says the loose-clerk turns are ~40% of
the tail's Σctx, i.e. "moving 40% of the tokens to Haiku saves ~40% of the
cost." That's wrong because ~90%+ of an Opus turn's context in this corpus
is `cache_read` (billed at 0.10 of a raw input token in the agent-cost
weighting), and a fresh Haiku clerk turn starts with none of that cache —
it pays full-price input for its ~5k-token brief instead. Repricing turn by
turn with the same weights `agent-cost` uses (input 1.0, cache_creation
1.25, cache_read 0.10, output 5.0; model tiers opus 2.5, sonnet 1.0, haiku
0.5, in "sonnet-token" units) over the 646 loose-clerk turns across the 56
sessions with a tail:

- Opus-priced, as currently spent: **35.73M** sonnet-token-units
- Same turns re-priced as a Haiku clerk (5k-token fresh context per turn,
  same observed output token counts, output re-priced at Haiku's rate):
  **4.04M** sonnet-token-units
- **Estimated saving: ~31.7M sonnet-token-units, ≈89%** of what those turns
  currently cost.

Caveats on this number, stated rather than hidden: (1) it assumes the
Haiku clerk's output token count per turn matches what Opus currently
emits — plausible for `gh`/`mise` command turns, since the command text
itself dominates output, but the clerk's briefs would likely be shorter
than an Opus turn's surrounding prose, which would improve the estimate
further; (2) it does **not** discount the drafting turns (the spec body
heredocs) that stay with Opus — those keep their current cost, so total
session cost drops by less than 89% of the tail, only by 89% of the
**loose-clerk share** of the tail (loose-clerk is ~41% of tail Σctx, ~27%
of whole-session Σctx pre-09-15 and ~24% post); (3) cross-agent chatter
(Opus handing a brief to Haiku) isn't itself free — I added one Opus
brief-authoring turn is *not* separately subtracted here since the
"loose" clerk set already excludes the tail-start turn, but a second
brief-per-child-issue overhead is plausible and not modeled.

## Part B — throughput

Windows: pre = 2026-08-15→09-14 (31 days), post = 2026-09-15→09-26 (12
days), post-law = 2026-09-22→09-26 (5 days, subset of post).

**Commits on master, non-merge:**

| | pre (31d) | post (12d) | post-law (5d) |
|---|---|---|---|
| total | 1224 (39.5/day) | 810 (67.5/day) | 288 (57.6/day) |
| feat+fix | 571 (46.6%) | 317 (39.1%) | 106 (36.8%) |
| docs+test | 432 (35.3%) | 397 (49.0%) | 141 (49.0%) |

**Issues (gh issue list --state all, 1000 fetched, covers back to
2026-07-06 so no truncation in-window):**

| | pre (31d) | post (12d) | post-law (5d) |
|---|---|---|---|
| created/day | 14.26 | 19.33 | 16.0 |
| closed/day | 12.06 | 18.75 | 16.6 |

**Drone-tagged subagent transcripts/day** (grepped `drone` in first 3KB of
each `agent-*.jsonl`, bucketed by the transcript's own first timestamp —
a rough proxy, not a strict `subagent_type: "drone"` field match):

| | pre (31d) | post (12d) | post-law (5d) |
|---|---|---|---|
| drone transcripts/day | 4.42 | 11.42 | 10.8 |

**Directional reading**: commits/day rose ~70%, issue creation and closure
both rose ~35–60%, drone throughput roughly **2.5×**. But the docs/test
share of commits also rose (35%→49%), and feat/fix share fell — consistent
with the swarmify/charter rewrite itself generating a wave of docs and test
commits in the same window it's supposed to be measured against. **This is
not causal evidence the rewrite increased net feature throughput** — it may
equally reflect: (a) the rewrite's own documentation and test churn
inflating the post window's commit count without inflating shipped
gameplay work; (b) the swarm/relay/warp tooling itself maturing over the
same 12 days (visible in the post-window commit prefixes: `swarm`, `stub`,
`drone`, `sage`, `land` appear only post-09-15); (c) unmeasured owner hours
— a 12-day window this active could simply reflect more calendar time spent
driving the repo, independent of the swarmify rewrite; (d) the post-law
5-day subset (09-22→09-26) shows *lower* commits/day and issue-created/day
than the full post window, which cuts against "laws 29–30 accelerated
things further" — if anything the last 5 days look like a plateau or a
partial regression toward pre-window issue-creation rates, though 5 days is
too short to trust as a trend.

## Caveats on method, honestly

- The invocation-marker grep found 59 `/swarmify` sessions; "as many earlier
  as cheap" was interpreted as "run the same script over every match" since
  the script's marginal cost per session is a few seconds, not as manually
  reading each — per the advisor's steer, no session was hand-inspected
  beyond the two spot-checks.
- Same-minute session clusters (e.g. 09-23 11:46–11:49, three sessions
  seconds apart) are parallel swarmify tabs on different issues, not one
  session continuing into another — treated as independent rows, which is
  correct for Σctx accounting but means "sessions/day" is not the same as
  "swarmify invocations/day" if a person runs several tabs at once.
- The tail-start heuristic can fire mid-way through a session that then
  continues into a *second*, unrelated design thread (verified in
  `255e9e4f…`: after issue #975's spec is drafted and its children filed,
  the same session pivots into a fresh "node subtypes" design pass with its
  own `AskUserQuestion`s and a new design doc) — my clerk/non-clerk split
  correctly marks that stretch non-clerk, but it does inflate "tail_turns"
  as a raw count beyond what a real mechanical tail would be. Σctx and
  clerk/non-clerk splits are the more trustworthy numbers than tail_turns
  alone for this reason.
- `gh --json` field names drifted under the corpus (`blockedByIssues` vs
  `blockedBy`) — pre-09-15 sessions hit this; the classifier's `gh api` /
  `mise gh-project` patterns may under-match older sessions if the CLI
  surface used different subcommand spellings before the swarmify rewrite,
  which is a plausible source of the pre/post clerk-turn-share difference
  being smaller than expected (41% loose both windows) — i.e. the
  measurement may be *understating* how much more mechanical post-09-15
  tails are, not overstating it.
- Drone/day is a crude proxy (keyword grep on the first 3KB of a subagent
  transcript, not the actual `subagent_type` field in the spawning parent's
  Agent tool_use) — directional only.

## Scripts

`/tmp/claude-1000/-home-bramh-skill-tree-of-life/cdee5006-dd80-52bc-8cf7-d2339ad46740/scratchpad/measure2.py` — per-session tail/clerk/failure extraction (used for `pre0915.json`, `post0915.json`).
`/tmp/claude-1000/-home-bramh-skill-tree-of-life/cdee5006-dd80-52bc-8cf7-d2339ad46740/scratchpad/measure3.py` — Opus-vs-Haiku repricing of loose-clerk turns (`priced.json`).
Raw per-session JSON: `pre0915.json`, `post0915.json`, `priced.json`, `issues.json` in the same directory.
