# Follow-up issues filed or proposed at session end (2026-09-16 -> 2026-10-14)

Method: python scan of all 356 top-level sessions in the window for `gh issue create` tool calls (clerk/spec-skill filings are not traceable per session and are not counted); labels are hand-assigned from each session's closing report, so counts are directional. Rows: `2026-10-14-followup-issues-at-session-end-rows.jsonl`. Issue states from `gh issue view` on the 112 issue numbers parsed from create results.

## Denominators
- 150 sessions touched `gh issue create` or the spec skill; 79 non-swarmify, 30 swarmify (filing is their product), ~41 spec-skill sessions (Oct 11-13, filing via clerk, not counted).
- 79 non-swarmify -> 5 excluded (command text only, no follow-up: 4aceb89b cdee5006 755e7ff5 5fc0a765 ba743a68) -> **74 analysed**.
- 31 of the 74 are design/planning sessions where filing the issue was the intended product (owner live) -> 43 are *real follow-ups* from implementation/swarm/relief/warp sessions.

## Tally (74 sessions)
| axis | count |
|---|---|
| presented: filed AND named in the closing report | 68 |
| listed only, nothing filed ("Needs you", visual checks) | 5 |
| offered only ("say which") | 1 |
| ended with context >= 150k (last API call) | 53 of 73 known (67 >= 100k) |
| closing report mentions budget/"fresh session"/"past target" | 25 |
| owner replied after the report | 66 (8 ended on the report) |

Judgement over the 43 real follow-ups: SMALL-FIXABLE 37, NEEDS-OWNER 6, BIG 0. Of the 31 design-product sessions: NEEDS-OWNER 25, BIG 6.
Triggers of the 43: advisor/review finding or scope fence 23, flake/bug seen at the suite gate 10, context-budget excuse leaving a ready unit for a fresh session 4, owner-only item (visual check, permission, charter yes) 5, other 1. 15 of the 37 SMALL-FIXABLE closing reports also say "past target / fresh session".

## Issue state (112 issues filed by those 74 sessions, 2026-10-14)
CLOSED completed 66, CLOSED not_planned 6, OPEN Backlog 29, OPEN Needs design 9, In progress 1, In review 1. For the 45 issues from SMALL-FIXABLE sessions: 22 closed done, 6 closed not-planned, 14 open in Backlog, 3 Needs design (so 17 of 45 = 38% still waiting; 6 = 13% judged not needed). 23 of the 112 were later named in a swarmify/warp/swarm launch by number.

## Owner pasting a report into a new session
Only one verbatim case in the window (free-text scan of first prompts, directional): cb550074 (2026-09-20) opens `Agent: ```Not done, worth a follow-up: TEMP_UPGRADE_KEYCAPS = ["Z","X"] ...``` ` pasted from 894c1f35's closing report; the follow-up was a listed-only, 2-commit fix done at once. Also 5222722e (2026-10-01) opens `/relief` with a pasted "Known failure: test_armed_mode_tint..." line. The owner's own statement (eb269943, 2026-10-14) is that this happens MOST; transcripts show it only when the report was *not* filed, so filed issues are picked up by number instead and are invisible to a paste scan.

## Samples
- 8f99e6dc relief 2026-10-07 (155k): "Small leftovers are filed as #1460: stat docs and tunables missing the new stats, Hex's own glyph, a status readout that under-reports node-local bonuses, Greed's per-hit record that never gets pruned, and one possibly flaky test. I finished at about 150k context" -- six known small fixes in one issue.
- 6f05643b warp 2026-09-24 (162k): "To build it, run `/warp 1114` in a fresh session. The worktree and commit `88d4ffc` are still there." Remaining work: one test.
- 5ca8e1f0 warp 2026-10-01 (181k): "Context is high, so ranged is best done in a fresh session." (lead put on the issue instead of fixed).
- 576eba66 relief 2026-09-24 (159k): "I filed it as #1105 ... goes to Backlog by default, so it needs triage before a drone can take it. I'm past my ~150k context target."
- 243c15c4 warp 2026-09-16 (180k): "This session is well past its context budget -- these two are best warped from a fresh session".
- 9437dc2e swarm 2026-09-23 (145k): "A flaky test: whether to file an issue for test_poison_arrow" (the flake was filed three further times: #1105, #1198, #1483).
- ac0125c9 swarmify 2026-10-12: "I'm at about 151k context, past my target, so I'd rather not design the new spell properly in this session. I'll file it now as a design issue".
- 3dea07a1 swarmify 2026-10-12: "I can file ... as a design issue if you want. Context is past target, so I'm leaving it as an offer rather than filing."

## What recurs
- A ctx-excuse closing line ("past ~150k", "fresh session") is attached to ~60% of the 43 real follow-ups.
- The same test, `test_poison_arrow` shadow replay, was filed as a flaky issue at least 4 times (#1105, #1198, #1483, 2c05054b/337de897) by separate sessions.
- Leftovers batched into a catch-all issue (#1460, #1509) with no lane decision beyond Backlog.
- Offers ("want me to file it?") convert the owner into the dispatcher for a known fix.

## Exclusions / caveats
Clerk-filed and spec-skill sessions (about 41) untraced; sessions without a final long text; SMALL-FIXABLE is my judgement from the closing text, not from the issue bodies; ctx = last API usage, includes cache reads.
