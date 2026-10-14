# Scan: research-phase cost of `/swarmify` sessions — 2026-10-14

Rows: `2026-10-14-research-cost-rows.tsv` (133 sessions, one row each).
Script: `2026-10-14-research-cost-scan.py` (stdlib python over the
top-level transcripts in the project's `~/.claude/projects/` directory).
Window: 2026-09-14 → 2026-10-14. A session qualifies if its first prompt
contains `/swarmify` or a Skill tool_use names `swarmify`. The research
phase is every tool result before the first `AskUserQuestion` or the first
`gh issue comment`. Unit is **chars of tool results** (≈4 chars/token);
reasoning and output are not counted.

## Totals

| bucket | total chars | per-session median | max |
|---|---|---|---|
| session's own `cat` / `sed -n` / `head` reads (Bash) | 3,046,916 | 19,149 | 132,280 |
| `gh issue view` + `--comments` | 2,092,584 | 11,759 | 69,805 |
| Read tool (12 sessions only; 9 whole-file, 11 ranged) | 431,601 | 0 | 70,044 |
| Explore agent final returns (120 agents, 114 haiku, 6 sonnet) | 403,952 | 1,056 | 16,593 |
| research phase, all tool results | 9,439,067 | 61,907 | 195,464 |
| research share of the session's tool results | | 72.7% | 100% |

45 of 133 sessions ran no Explore at all. 31 sessions exceed 100k research
chars. Explore returns are the smallest bucket by ~7x; the session's own
file reads are the largest.

**Caveat on the Explore column:** many sessions show exactly one Explore
returning exactly 1,056 chars, the length of a background-launch
acknowledgement rather than a report. Explore returns are therefore
*under*-counted; the conclusion (returns are not the cost) only strengthens.

## By issue count in the prompt

| issues named | sessions | median research chars | median gh chars | median own-read chars |
|---|---|---|---|---|
| 0 (title / free text) | 41 | 65,234 | 9,219 | 24,342 |
| 1 | 58 | 57,505 | 11,376 | 14,868 |
| 2–3 | 20 | 75,532 | 16,099 | 20,785 |
| 4+ | 14 | 93,269 | 21,107 | 17,479 |

Issue reads scale with N; own file reads do not (a coherent cluster shares
a code region). A 4+ pass costs ~1.6x a single-issue pass, not Nx.

## The tail, read

- `0b4bcb87` (2026-09-28, #1132/#1133): 195k research chars, 132k of them
  own reads, no Explore. Cat'ed `docs/reviews/2026-09-27-architecture.md`
  whole (10k) and `loot_round_command_handler.gd` (9k); neither is cited in
  the resulting Ready comments. Long `sed` windows through
  `network/command_link.gd` (1,300+ lines) — that one *is* cited 5x.
- `d3d8642b` (2026-10-06, #1280/#1433/#1435): 193k. `cat -n` of the whole
  `attack/outcome/hit_instance.gd` in one 24.6k call — never cited;
  `crit_roll.gd` and `status_instance.gd` whole — cited.
- `bebb84f4` (2026-10-08, #1381/#1383/#1489): the max issue-read case,
  70k chars over 13 `gh issue` calls. The three named issues were read once
  each; the rest was six *related* issues' comment tails (#1377, #1378,
  #1202, #1271, #1384, #1397) plus a nine-issue status loop that a
  `--json title,state` one-liner or the Explore could have answered.

## What follows

- The knob is the session's own source reads, not explorer count or return
  size. Orientation belongs in the Explore's question list; the session
  reads ranged windows to confirm a contract it has already named, and
  never a source file whole. (law 36)
- Named issues are read in full, once, in-session (law 2 stands — the
  2026-08-02 retraction incident). Related issues are not read in full by
  the session: a status question is a `--json` one-liner, a content
  question goes to the Explore. (law 2, amended)
- No cap on Explore returns; a shape (`file:line` facts, one-line answers,
  no excerpts) is enough at ~3.4k chars/agent.
- No read-clamping hook exists (checked 2026-10-14: context-size, rule-path,
  godot-kill-guard, commit-mention-guard, drone-budget-guard). Bash reads
  bypass the Read tool's 2000-line cap entirely.
