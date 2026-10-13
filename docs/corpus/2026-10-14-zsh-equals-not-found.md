# zsh "= not found" errors in Bash results

**Method.** Stream every `~/.claude/projects/*/**/*.jsonl` (top-level sessions and subagents), pair each `tool_result` with its `tool_use` command, and keep Bash results with a line-start `(eval):N: <word> not found` whose word begins with `=`. Denominator is every Bash `tool_use` in the same files. Rows: `2026-10-14-zsh-equals-not-found-rows.jsonl`.
**Window.** First Bash call 2026-09-13, last 2026-10-13 (all available transcripts; no earlier Bash call exists in the store). Keyword-level scan: directional, but the anchored pattern is specific.
**Mechanism.** zsh drops the first `=` of an unquoted word before reporting it, so the typed word `====` is reported as `=== not found`. "Run length" below is the reported run; the typed run is one longer.

## Counts

| Measure | Value |
|---|---|
| Bash tool calls in window | 39,529 across 361 sessions |
| Bash results with a `= not found` line | 390 (1.0% of Bash calls) |
| …pure `=` run (`=`, `==`, `===` …) | 274 |
| …word with `=` plus other text (`=SAGE======`, `=954`) | 116 |
| Sessions with ≥1 such result | 144 of 361 (40%); pure-run: 132 |
| Pure-run results from subagents / top-level | 156 / 118 |

**By reported run length** (pure runs; typed = reported + 1):

| reported `=` run | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| results | 8 | 38 | 78 | 54 | 86 | 6 | 1 | 1 | 2 |

Most common: `=== not found` (typed `====`) and `===== not found` (typed `======`).

**Per week** (ISO week from Monday; rate per 1,000 Bash calls):

| week of | Bash calls | pure-run results | per 1k | sessions | mixed-word results |
|---|---|---|---|---|---|
| 2026-09-07 (pre-window, 6 days, zero hits) | 694 | 0 | 0 | 0 | 0 |
| 2026-09-14 | 8,850 | 67 | 7.6 | 27 | 69 |
| 2026-09-21 | 7,404 | 48 | 6.5 | 24 | 21 |
| 2026-09-28 | 11,193 | 61 | 5.4 | 38 | 14 |
| 2026-10-05 | 9,803 | 69 | 7.0 | 29 | 9 |
| 2026-10-12 (partial, to 13 Oct) | 1,585 | 29 | 18.3 | 14 | 3 |

Reading: flat at roughly 5-8 per 1k across four full weeks, with no decline after the `zsh-bash` rule was in place (I did not locate the rule's commit date; not checked). The partial last week spikes; it is two days and driven by a few subagents (`54a278b6` 6 hits, `4a213a0c` 5, both subagents), so treat 18.3 as noise until a full week lands. Mixed-word results fell from 69 to 3 over the same weeks.

## Trigger shape

- **Echo separator: 386 of 390 (99%).** The bad word sits in an `echo` argument: `echo ===` between two commands, `echo ===COMMENTS===` as a label, `echo ==954` before a grep. Example, `06190902` 2026-09-14: `... echo ======SAGE======; cat swarm-sage-handover.md` → `(eval):1: =====SAGE====== not found`.
- **`[ a == b ]` test operands: 0.** No occurrence in the window.
- **Replayed output: 3.** `cat` of a background task's `.output` file re-displays an earlier error, so the same failure is counted once at launch and again at re-read (e.g. `f5c2e432` 2026-09-20 `==UI===`, `ba4c3633` 2026-09-29 `==`, `5d313974` 2026-10-01 `=====`). Kept in the counts; excluding them changes nothing material.
- **Unclassified: 1** (`7d8c486b`, a `python3 << 'EOF'` heredoc command whose body contains `===`; the source of the error is not confirmed).

## Samples

1. `1002ce81` 2026-10-08, subagent, `=====` (13 pure-run hits, the most of any session; `f5c2e432` has 17 hits including mixed words): `cat -n docs/domain/attack-timeline.md | sed -n 640,890p; echo ======; cat d…`
2. `12cef8b4` 2026-09-15, `===`: `grep -n "must move with distance" -B40 test/unit/attack/test_ranged_attack_plan.gd | grep -vE … ta…`
3. `b66dd8fc` 2026-10-01, `==COMMENTS===`: `gh issue view 1274 && echo ===COMMENTS=== && gh issue view 1274 --comments`
4. `8d43d12e` 2026-10-13, `=====`: `gh issue view 1568 --comments; echo ======; gh issue view 1566 --json body,comments …`
5. `08b12d51` 2026-10-03, `=====`: `W=/home/bramh/skill-tree-of-life/.worktrees/wt-defense-axes-docs; cd $W; sed -n 137,206p docs/design/lore.md; …`

## What recurs / what varies

- Recurs: the `echo` separator with an unquoted `=` run, across every week and across subagents and top-level sessions alike (156 vs 118).
- Varies: run length (1 to 9 reported; 3, 4 and 5 dominate), and whether the label is pure `=` (274) or `=` glued to text (116). The glued form is what is disappearing.
- Not checked: whether the agent saw and recovered from each error (the rows hold the error line but not the following turn).

## Exclusions

- `zsh: command not found: <word>` (e.g. `bc`, `tempo`, `git` as the command): different error, not `= not found`; not counted.
- Matches that are not at the start of a result line (text quoting the error, e.g. docs and handoffs that describe it): not counted.
- Sessions with Bash calls but no `= not found`: 217 of 361. JSONL lines that fail to parse were skipped silently; their count was not measured.
