# Skill candidates, window 2026-11-01 -> 2026-11-09 (scan c)

Method: `transcripts list --since 2026-11-01` (CLAUDE_TRANSCRIPTS_DIR pointed at the main-checkout slug; the worktree slug is empty), then `show --role user` on all 10 sessions; owner-typed lines separated from skill bodies and task notifications. Existing skills/charters read from `.claude/skills`, `docs/charters`.

Window is thin: 10 sessions, all 2026-11-04/05, 4 skill launches (3 swarmify, 1 swarm-train), ~14 owner-typed prompts. No `/charter` run and no feedback-folding in the window. Counts are directional.

| candidate | n (sessions) | class | nearest |
|---|---|---|---|
| Git hygiene: pull, resolve conflict, triage dirty files | 3 (2ef23c76, 2c31bb1a, 08faeccf) | (a) small new skill, or (b) rule; no charter has the procedure | `.claude/rules/git-gotchas.md`, warp land |
| Merge a PR (check gate, conflicts, ADR-number collision, squash, local checkout stale) | 1 (08faeccf) | (a) or fold into the above | warp / swarm land |
| Board table on request (lane, prio, title) | 1 (42646ddd) | (a) trivial; maybe a `mise run` task not a skill | triage |
| Review a big agent-produced diff by fan-out Sonnet reviewers ("too much for me to inspect") | 1 (f9337f70) | (a) | none (relay is for building) |
| Serve questions one at a time via AskUserQuestion | 3 (f9337f70, a8c00e38, cd9b5b2a-ish) | (c) already in swarmify/triage | triage, swarmify |
| Continue a design session from a handoff file | 2 (db0490a0, cd9b5b2a) | (c) pickup/handoff exist; owner uses `/swarmify <handoff>` instead | pickup, handoff |
| Ask advisor too | 1 | (c) already default | - |
| RC hub = one stable environment per dir | 1 (de99422a) | not a skill; tooling wish | none |

## Samples
- 2ef23c76 2026-11-04: "pull git, resolve conflicc" -> conflict was the regenerated `tools/balance/snapshot.md`, identical to upstream; discarded local copy, fast-forwarded.
- 2c31bb1a 2026-11-05: "Let's go over dirty git files and see what we do with each" then "Fix that stuff then add 1 line". Steps: diff each dirty file, classify (editor churn / real change / other agent's work), verify, commit in groups, no push.
- 08faeccf 2026-11-04: "make !1744 merge". Steps: gate green, no conflicts, ADR numbers free on master, squash-merge like earlier PRs, delete branch, do not pull into a dirty shared checkout.
- f9337f70 2026-11-05: "i sort of trust the content but it's tbh too much for me to inspect. so maybe option 2? spend any number of Sonnet subagents you need" -> 5+ Sonnet reviewers per diff group, findings files, BLOCKER/FIX/MINOR tally.
- a8c00e38: "Serve one by one via AskUserQuestion"; f9337f70: "maybe rapid fire Askuserquestion speeds things up".

## Recurs
Terse git-chore imperatives, each a different chore (pull, dirty-triage, merge); the agent reconstructs the procedure each time and the same hazards appear (shared checkout with others' uncommitted changes; regenerated snapshot files). "Ask one at a time" is said although swarmify/triage text already offers AskUserQuestion: the instruction is present but weakly worded ("when they are clean choices"), so type (c).

## Charter-workflow driving
None observable in window (0 `/charter` launches, 0 feedback folds; one `swarm-train` run posted a lesson to board #1366 on its own). Cannot assess; widen the window to judge.

## Exclusions
Sessions before 2026-11-01 (not counted; wider greps of "AskUserQuestion", "continuation" are dominated by skill-body text, not owner prompts, and were not used). Task-notification and skill-body "user" records excluded. Owner prompts in swarm-train 2f6a4092 other than the launch: none typed.
