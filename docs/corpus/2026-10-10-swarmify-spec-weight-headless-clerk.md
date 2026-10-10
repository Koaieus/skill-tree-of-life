# Swarmify: spec-format weight, headless uses, clerk friction (2026-10-10)

Window 2026-08-01 -> 2026-10-10. Method: `mise run transcripts list --json --subagents` (1387 transcripts), then
stdlib scans of tool_use records. "Turn" = distinct assistant API call (requestId); "owner turn" = non-tool-result user
prompt. Spec start = first Bash heredoc/Write whose text has a line `## Acceptance spec`. Context = input + cache read +
cache creation of the call. All counts are directional (regex markers). Rows: `...-rows.jsonl` (part a / b / c).

## (a) When spec-writing starts (101 owner-led /swarmify sessions, 87 reached a spec)

| metric | median (p25-p75) |
|---|---|
| assistant calls before first spec text | 24 of 38 total (0.64 of the session; 0.52-0.72) |
| owner turn at spec start | 3 of 5 |
| ctx at spec start | 132k (110k-152k) vs session peak 270k (spec starts at ~46% of peak) |
| manifest written (50 sessions) | call 25.5, 0.71 of session, ~152k ctx |
| clerk spawn (54 sessions, none before 2026-09-27) | 0.77 of session |

Whole SKILL.md = 21.5 KB (~5.4k tokens), steps 8-10 + tail = 9.1 KB (42%, ~2.3k tokens). The file arrives in the
launch prompt, so 100% of calls carry it; the spec/manifest half is unused for the first ~64% of calls (67 of 87 sessions
> 50%, 16 > 75%, 0 < 25%). 14 of 101 sessions never wrote a spec (design-only or short): carried it 100% unused.
Pooled: 59% of all assistant calls (sum) precede the first spec text.

## (b) Headless uses

- No subagent, swarm lead, whip or warp session invoked /swarmify (Skill tool: 12 invocations, all in owner-led top-level
  sessions with no launch verb, e.g. c73aa385 2026-09-14, b9d181b3 2026-09-28; plus 101 launched ones).
- Subagents that read swarmify SKILL.md (11 transcripts) were rewriting/auditing it (drone a6eb8eb1 #905 2026-09-15,
  Explore verifiers, general-purpose audits), not authoring a spec.
- Headless issue filers: 25 swarm, 11 relief, 5 warp tops + ~11 subagents (drone 4, general-purpose 4, swarm-lead 1, named
  drones 2). Almost all file a plain body (`gh issue create --body-file` + `gh-project add`), no Acceptance spec, no
  drift stamp; none opened clerk.md; none used AskUserQuestion inside a subagent (AskUserQuestion: 15 swarm/relief/warp
  tops, about landing/spec defects, not about swarmify).
- Coping patterns: (1) park for an owner session: drone afb0fab3 2026-10-07 "Every decision below is the owner's, for a
  `/swarmify` session; each fork carries scored options and a recommendation, nothing is settled here." (2) lead triages
  itself: 0ad13edc 2026-09-23 "#1096 (the 2D/3D question) -> Needs design. It's an open question for a `/swarmify` pass with
  you". 1c2af8a0 2026-09-24 "I filed it as #1111 in Needs design". (3) hand-rolled "acceptance section", self-corrected:
  warp 6f05643b 2026-09-24 "I filed #1114 and moved it straight to In progress, skipping swarmify and the Ready gate. It has
  a plan and an acceptance section, but that isn't a real acceptance spec."
- Misapplied owner-present rule is the reverse case: owner-led fd15143e 2026-10-10 (#1524) treated the owner as absent from a
  harness autonomy note, posted options and ended the turn; owner: "swarmify is a speccing slash design session WITH the
  user. I AM THE OWNER." (already law 1, charter incident 2026-10-10).
- Read/consume side is wide: drones read `## Acceptance spec` comments cold (a8d33e9f, ade50acc); not authoring.

## (c) Clerk friction (54 clerk-using sessions, 81 clerk transcripts, 2026-09-27 -> 2026-10-10)

- Orchestrator opened `.claude/agents/clerk.md` in 25 of 54 sessions (47 calls); 22 of 25 on or before 2026-10-03, i.e. before
  the full grammar sat in SKILL.md (charter law 33). After: 98e81a03 2026-10-07 ("grep -n -i -E 'needs[ -]design|backlog|in
  progress' .claude/agents/clerk.md"), eb7e09db 2026-10-10 ("clerk status grammar"), 52c1b4ef 2026-10-10. Remaining lookups
  are status-value vocabulary and `gh` flag spelling, not the key list.
- Multi-clerk sessions (4cccc792 x3, aaed944f x4, f7a8e5ed x4, f83b1341 x4, d359f7ce x3) are mostly owner-reply amendments
  (manifest2/3), not retries.
- Final reports with SKIPPED/FAILED: 4 of 81 (5%). 2 GitHub (rate limit: dcfc7028 2026-10-01, 36fafe16 2026-09-30), 2
  manifest/grammar-shaped: 1e8b49ba 2026-10-07 ("comment skipped (file 1448-spec.md missing)", orchestrator then posted by
  hand) and 27fdc865 2026-10-09 ("SKIPPED: blocked-by - no documented command to remove blockers"; orchestrator ran
  `gh-project blocked-by 1519 clear`).
- In-run self-recovered errors (clerk transcripts, runs affected): status string wrong case/space (`Ready`, `needs design`
  vs `ready`/`needs-design`) 22; hygiene's `git` outside a repo 26 (noise); milestone passed by number to `gh issue edit` 5;
  `ready` label 4; wrong gh/flag 5; GraphQL rate limit 4; shim REFUSED unresolved `#{name}` 2 (eb7e09db, 27fdc865). Roughly
  API 4-5 runs vs clerk/grammar-vocabulary ~35 runs (not additive, regexes overlap): GitHub errors are the minority.
- Handle substitution defects (old `#@slug` sigil, since replaced by `#{slug}`): 59cf3f36 2026-10-03 (comments on existing
  issues not substituted, patched by hand, feedback posted), b27f3a88 2026-10-06 (eleven bodies #1419-#1429 shipped with raw
  `#@`), 3eef2c77 2026-10-03 (orchestrator grep-counts `#@` after clerk).
- Orchestrator by-hand `gh` after clerk: 47 of 65 clerk sessions run some gh write after the clerk, but most are owner-driven
  amendments; clear grammar-gap cases: 9c263e8d 2026-10-02 (no re-parent of existing issue; feedback posted), 27fdc865,
  1e8b49ba, 59cf3f36, b27f3a88.
- Clerks seldom improvise visibly: one hit for "no documented command"; a5010cab (27fdc865) bypassed `gh-project` for raw
  `gh issue create`, as did bebb84f4/37ff0b0d (milestone number, `ready` label errors) -- all recovered.

## Exclusions
14 owner-led sessions without a spec (kept in rows, excluded from (a) medians); 36fafe16 and 8 other sessions used clerk but
carry no launch verb (counted in (c) only); 5 `swarm~/swarmify~`-style free-text launches included. Subagent Explore (363) and
drone (358) transcripts not mined beyond issue-create/skill-read markers.
