# Skill candidates, 2026-10-16 → 2026-10-31

Method: `mise run transcripts -- list --since 2026-10-16` (CLAUDE_TRANSCRIPTS_DIR set to the main-repo slug), 59 top-level sessions
(30 swarmify, 1 swarmify~, 4 swarm-train, 3 swarm, 21 unlaunched). Owner-typed prompts extracted by script, harness messages and
hand-backs dropped (about 70), skill preambles dropped (71). Matches are directional; the assistant side was not read in depth.
Compared against `.claude/skills/*` and `docs/charters/*`. Classes: (a) new skill+charter, (b) missing law in a charter, (c) in charter, file failed to carry.

| # | Pattern | Occ / sessions | Class | Nearest |
|---|---|---|---|---|
| 1 | Design-talk closing ritual: record calls, file issues, ADR check, spec/docs subagent, resume prompt | 8 of ~15 design-talk sessions | (b) swarmify, or (a) | swarmify, handoff, spec |
| 2 | Owner has to ask for the advisor pass | 4 prompts / 4 sessions (+817ca437) | (b) swarmify | swarmify |
| 3 | "ADRs needed? use Archivist" | 3 sessions | (c) adr: description already has the "settled call just made" trigger; unlaunched design sessions do not act on it | adr, archivist |
| 4 | Review-then-fix fan-out | 2 sessions (+78bd4716 related) | (a) weak | swarm, sage |
| 5 | Triage results served as AskUserQuestion | 1 session; lives only in memory | (b) triage | triage |
| 6 | Swarm-train tick additions re-typed (ready-queue diff vs ledger, `train add`; advisor between landings) | 817ca437, same text 3x | (b) swarm-train | swarm-train |
| 7 | Usage-window wake and lead-relief corrections | 4 sessions | CHANGED: wake part resolved, see below | swarm-train, relief |
| 8 | Lane alias "needs a design pass" = Needs Design; Readify skipping Intake | 3 sessions | (b) swarmify (selector/P0 already law 37) | swarmify |
| 9 | "Commits this week? backlog + needs-design queue?" | 2 sessions | (a) weak | none |

Charter workflow driven by hand: all-boards feedback sweep with the owner's own bullets (42d1a8fe; charter skill takes named charters only);
cost limits on charter-pass subagents (42d1a8fe complaint, b705b447 spec: one advisor, Sonnet explorer <=5k, Opus for small skills);
handoff directory/gitignore confusion (57fc7fd0, 89d7138a; handoff charter). Memory-only: "ignore ctx until 200k for design sessions" (4b884bfb) -> swarmify law.

## Verification of the (c) calls
- adr SKILL.md description: triggers on "make an ADR", "record this decision", and "when a settled architectural call has just been made". So #3 stays (c).
- swarm-train law 8b ("the boundary is armed at the real reset") landed 725f493f, 2026-10-17 03:54. 153e4757 (2026-10-16) predates it; 42d1a8fe (2026-10-17) is the report that produced it. The wake-time half of #7 is therefore not a recurring failure; only the relief-threshold complaint (eca76d3a, 2026-10-17, "lead a is at 106k tokens?") is unchecked against a later law.

## Samples
- 886c5d9a 2026-10-19: "Start filing what we settled. And handoff for the remaining discussion, I'm off to bed"
- 0500923b 2026-10-19: "Handoff so i can resume this tomorrow with 1 good prompt. Also the prompt should include instructing to scour open issues and codebase etc"
- 817ca437 2026-10-20: "Owner addition for this run: also re-read the live Ready column ... any issue not there -> `mise run whip -- train add` it"
- 89d7138a 2026-10-17: "serve as askuserquestion, faster instead of letting me write issue numbers"

## Exclusions
Sessions outside the window; about 70 harness messages; 71 skill preambles; about 12 off-topic sessions (KVM, audio, network, pi-agent talk); b705b447 "Try again" x3 not investigated.
