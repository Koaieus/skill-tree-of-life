# Drift stamp — cost vs value

Sonnet archivist scan, 2026-10-11. Window 2026-09-15 (stamp shipped, c6fac17)
→ 2026-10-10. Counts directional (regex over transcripts); "a drone read a
stamp path" is inferred from path strings in its Bash commands. No row file:
the agent returned findings inline; this page is its report, condensed.

**Verdict: slim** — keep the sha check and the reading list; seam map as a
hint, not a fence; cut write-time verification effort; quiet the check's noise.

## Cost (78 `/swarmify` sessions that wrote a stamp)

- Median session 38 assistant calls; `sed -n N,Mp` range checks median 11
  (934 total — an upper bound, the same seds serve spec research).
- Explore dispatches asked for ranges / a reading list: 67 across 52
  sessions, median 20 calls each.
- Re-stamp / "fix the stamp" in 10 of 78; no stamp that failed to parse.
- Clerk `no stamp`: mostly noise on `Needs design` children (afff5b02
  09-30, eb7e09db 10-10). One real failure (1e8b49ba 10-07) was a missing
  spec file, not the stamp.
- Tool defects: 1c2af8a0 09-24 "errored on all three issues, calling the
  stamp sha 'unknown' even though it's current HEAD"; `missing-at-stamp` for
  a path a sibling creates (bc56e8dd 10-04, agent-a457d593 10-07).
- Roughly ~10 seds + one ~20-call Explore per spec, about a third of the
  authoring session's calls.

## Value — sha check (203 runs in swarm / relief leads)

- 118 reported drift (58%), 85 clean or `no stamp`.
- After drift: 7 spawned an Explore, 10 read the diff themselves, 101
  dispatched straight on; ~23 called it expected. Mostly the run's own
  landings — ba254ba8 09-17 "exactly #944's landing — the intended
  predecessor, not a stale spec".
- Changed behaviour: 4e263e0c 09-18 (`NOT_GRANTED` may already be on
  master → verified), 568fb55a 09-22 (two Explores, briefs "carry the
  post-drift seams"), 6a136d14 09-30 (shifted ranges into the briefs),
  021d8dc3 10-06 (re-stamped).
- Drones ran `issue-drift` themselves in 3 of 358.

## Value — reading list (358 drones)

- 313 viewed a stamped issue, typically at tool call 2.
- 69% of stamp paths (1,978 / 2,872) appear in their commands within 15
  calls of the view; 2 drones touched none. Median 15 non-stamp paths too.

## Value — seam map

- Edits to existing non-test source: 69 of 97 (71%) in the stamp; 16 of 34
  drones edited outside it — agent-a5874938 #1179 ("wasn't on the issue's
  file list"), agent-ab13e817 ("a one-line repoint … the spec missed"),
  agent-a79ceec3 ("an eighth copy the spec missed"). A start, not a fence.

## Misleading stamps

- 65f779bf 09-22: "Six entries across #1050 and #1053 pointed at the wrong
  functions" — a stub commit shifted lines after the ranges were read; Sage
  caught it pre-dispatch.

## Stamped vs unstamped

Median 34 calls stamped vs 29 unstamped — confounded, shows nothing.
