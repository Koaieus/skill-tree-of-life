# Skill candidates, window 2026-09-01 → 2026-10-15

Method: `CLAUDE_TRANSCRIPTS_DIR` set to the main-repo slug (the worktree slug has no sessions); `mise run transcripts -- list`, then a script extracting owner-typed
prompts (harness hand-backs, task notifications, cross-session messages and skill preambles dropped). 72 sessions, 260 owner prompts. Matches are directional; the
assistant side was only sampled (Skill/Agent tool-use counts). Classes: (a) new skill + charter, (b) missing law in an existing charter, (c) in a charter/skill
already, the file or the owner's habit does not use it. Sibling scans: skill-candidates-b (10-16..31), -c (11-01..).

Window caveat: the transcript directory holds nothing dated before 2026-10-10, so 2026-09-01..10-09 contributes 0 sessions; the real span is 10-10 → 10-15.
Skills created inside the span: pickup, archivist (10-09), spec (10-11), swarm-train (10-10), charter, triage (10-14); "not covered" is judged against today's tree.

| # | Pattern | Occ / sessions | Class | Nearest |
|---|---|---|---|---|
| A | Owner pastes a prior agent's closing text into a new prompt instead of `/pickup` | 9 prompts / 8 sessions; `/pickup` launched 0 times in any transcript | (c) pickup (and pickup has no charter) | pickup |
| B | Resume a design thread from a `docs/handoffs/*.md` file plus the last agent's open points | 4 sessions | (b) pickup/swarmify: pickup reads transcripts, not handoff files | pickup, handoff |
| C | Design-talk closing ritual: file what's settled, "ADR needed?", docs sweep, handoff | 6 sessions; `Skill:adr` used in 1 of 4 ADR-asking sessions, ADR files written by Bash in 2 | (b) swarmify closing step / (c) adr | swarmify, adr, handoff |
| D | Charter workflow by hand: feedback -> advisor -> Fable rewrite; relay feedback commands into `/charter`; close boards | 7 sessions (5 before `/charter` existed) | (c) mostly resolved by `/charter`; residue (b) charter | charter |
| E | YAML `description` truncated at ` #` | swarm, warp, relay, swarmify descriptions plain scalars cut at char 262/294/324/613 | (b) charter Frontmatter + lint | charter, rules-hygiene |
| F | Agent worktrees start without native libs / class cache | 1 prompt, 3 grep sessions | (b) warp or mise task, not a skill | warp |
| G | Golden-test churn from agents/editor saves | 2 sessions | rule, not skill | none |
| H | RC `bypassPermissions` refuses trigger delete; auto mode works | 5 sessions | (c) swarm-train law already states it | swarm-train |
| I | "A stat nobody targets must not be a stat" | 2 sessions | (b) manage-stats (no charter) | manage-stats |
| J | Swarmify research load (Explore fan-out, issue reads) | 1 prompt (4df04c01) | (b) swarmify | swarmify |
| K | Model-tier slips ("started as Opus, ended up Fable") | 2 sessions | not a skill | none |
| L | "Send me screenshots" to phone | 2 sessions | (a) weak | artifact-design |
| M | Owner asks for an Archivist scan | 6 prompts / 5 sessions | covered, working: 10 archivist spawns in 9 sessions | archivist |

Charter-less skills (charter law 9): handoff, pickup, manage-stats (no `docs/charters/<name>.md`).

## Samples
- A, 6ce992e6 2026-10-14: "continue with docs/handoffs/explosive-axis-two.md / last agent ended with for part 1 which might not be entirely correct:"
- A, eb269943 2026-10-14: "I'm forced to start a new convo with "agent: ```(paste)``` let's do something about this" or smth. I feel like this happens MOST."
- C, 999a5ca0 2026-10-14: "File this so far to lock it in or instruct a sub to do so, possibly an ADR too (also a sub?)" then "And handoff for part 2 locally i guess"
- D, eb269943 2026-10-14: "after writing out charter, one advisor pass. And the actual skill (re)writes would ideally be done by a Fable (sub)agent. Actually we should have a skill for that maybe?" (-> `/charter`, same day)
- E, cd2568b0 2026-10-14: "The same YAML truncation hits the warp and relay skill descriptions. Each needs its own charter pass." Today swarm is also plain again after the 10-17 rebuilds.

## What recurs
Handing context between sessions by hand (A, B, C) is the dominant theme; every piece (pickup, handoff, adr) exists, none is used at the moment of need.

## Exclusions
0 sessions before 2026-10-10 in the directory; ~255 harness/hand-back prompts dropped; 13 "swarm-train tick/boundary" prompts (4 sessions) treated as trigger-fired, not owner-typed (inferred from identical text); "reply ok" x4 (10-15) are probes.
