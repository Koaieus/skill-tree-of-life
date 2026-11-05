# Owner review of the 2026-11-05 overnight cleaning pass: continuation

Walking the cleaning crew's morning post section by section with the owner. Verdicts below are owner calls made on 2026-11-05.
Spec digests (Sonnet-read, checked against master that day): `digestA.md`, `digestB.md` (Ready candidates) and `digestC.md` (Needs-design forks and #441).

## Done
- **PRs:** #1748, #1754, #1759, #1760 and #1761 are all merged. #1761 got a six-reviewer meaning pass, and its ~43 garble fixes are in 29fe5453. The suite was green.
- **Closed (7):** confirmed; no action.
- **`stale?` (11):** all closed with dated owner comments. #243's tuning list was folded into #1077, and #280's leftover work was refiled as #1764 (Intake). #433 closed as not planned, to revisit CI at the first official release builds.

## Verdicts made but NOT yet applied (spec comments and board moves still to do)
- **#427 → Ready.** Owner asked how self-loops get authored. Answer: as an Edge with from == to. `SkillNode.self_loops` is only a back-index that rebuilds from Edge registration, so un-exporting it loses no authoring knob or save data.
- **#580 → Ready.**
- **#1216 → Ready** with the spec's UX: push on top of any armed level, including an attack plan; no badge.
- **#1014 → Ready**, report-only. Strike the `--fix` arm.
- **#1415 → close, not planned.** Owner: "momentum isn't a better name. the tempo stat indicates 'limited amount of optional action points to be gained [but only if you kill an entity or whatever other trigger we add later that grants it]'". The name `tempo` stays.
- **#436 → blocked-by #1579, re-scoped.** Once the tag channel is gone, only ModifierGrant remains. Drop the dead kind-switch and build no Grant hierarchy until a second kind exists.
- **Save versions:** owner doesn't care until a real release. Any spec bumping `FORMAT_VERSION` should say "next free version", never a literal.

## Still to walk with the owner, one AskUserQuestion per item (owner's preferred pace)
- **Mechanical candidates** (digest recs): #986, #1214, #442, #1145, #1242 (tweak: stop and report rather than add a Stat signal), #855 (tweak: acceptance = `test/unit/attack/` green instead of the nonexistent goldens file; name `mise run native:build`), #1579 (tweak: next free version).
- **Needs a tweak or a call:** #471 (Opus; accept exact-but-partial), #721 (Opus), #440 (use `graph.get_neighbours`, or close), #1124 (keep or close), #335 (seed by duplicate; Opus; after #1145 and #1579), #347 (split: the tool button goes Ready, the readouts go to Needs design).
- **Needs-design forks:** #428, #435, #1186, #859, #1026, #422 and #441. See digestC.md.
- **"Your calls" section:** #1620's VFX judgments; the ~35 dated owner decisions with no ADR (listed in the #1761 PR description); stale In-progress / In-review claims (#1076, #1107, #1108 and others); hygiene's 16 flags (stale Designing #1429/#1590/#1659/#1708; hub drift #1313/#1397/#1591/#1608/#1646; all-parked hubs #199/#420/#1255/#1380/#1439/#1615/#1711).

Apply the verdicts via a Haiku `clerk` work order (`--body-file`). Board lanes, priority and size are settable from a local session.
