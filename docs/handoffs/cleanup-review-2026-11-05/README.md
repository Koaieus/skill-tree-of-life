# Owner review of the 2026-11-05 overnight cleaning pass: continuation

Walking the cleaning crew's morning post section by section with the owner. Verdicts below are owner calls made on 2026-11-05.
Spec digests (Sonnet-read, checked against master that day): `digestA.md`, `digestB.md` (Ready candidates) and `digestC.md` (Needs-design forks and #441).

## Done
- **PRs:** #1748, #1754, #1759, #1760 and #1761 are all merged. #1761 got a six-reviewer meaning pass, and its ~43 garble fixes are in 29fe5453. The suite was green.
- **Closed (7):** confirmed; no action.
- **`stale?` (11):** all closed with dated owner comments. #243's tuning list was folded into #1077, and #280's leftover work was refiled as #1764 (Intake). #433 closed as not planned, to revisit CI at the first official release builds.

## Verdicts applied on 2026-11-05 (comments posted, board moved)
Ready items got milestone `Cross-cutting / infra`; Ready requires a milestone, so name one in any clerk order. #427 is a parked child of hub #420, which hygiene flags.
- **#427 → Ready.** Owner asked how self-loops get authored. Answer: as an Edge with from == to. `SkillNode.self_loops` is only a back-index that rebuilds from Edge registration, so un-exporting it loses no authoring knob or save data.
- **#580 → Ready.**
- **#1216 → Ready** with the spec's UX: push on top of any armed level, including an attack plan; no badge.
- **#1014 → Ready**, report-only. Strike the `--fix` arm.
- **#1415 → close, not planned.** Owner: "momentum isn't a better name. the tempo stat indicates 'limited amount of optional action points to be gained [but only if you kill an entity or whatever other trigger we add later that grants it]'". The name `tempo` stays.
- **#436 → blocked-by #1579, re-scoped.** Once the tag channel is gone, only ModifierGrant remains. Drop the dead kind-switch and build no Grant hierarchy until a second kind exists.
- **Save versions:** owner doesn't care until a real release. Any spec bumping `FORMAT_VERSION` should say "next free version", never a literal.

## Second pass (2026-11-05 evening): all Ready candidates and forks decided and applied
- **To Ready:** #986, #1214, #442, #1145, #1242, #855, #1579 (owner: "don't care about save version", so no compat shims), #471 (Fable; exact-but-partial is OK), #721 (Opus), #440 (`graph.get_neighbours`), #1124 (filler), #335 (Fable; blocked-by #1145 and #1579; seed by duplicate), #428 (A: statics), #859 (option 3 guard), #1026 (C: ctx + arg; add MagicAttackPlan).
- **#347** is a hub: #1767 (tool button, Ready, drift-stamped) and #1768 (readouts, Needs design).
- **The `blocked` label means an open upstream design FORK**, not ordering. Ordering goes in the blocked-by relation. Removed the label from #335 and #436.
- **Gates aren't in the first-level sandbox** because procgen places none. That's #1208 (Needs design, no priority). Owner noticed; bump it if wanted.
- **New VFX idea:** panels lens the space beneath them (owner, P1, Needs design, VFX & juice). The feasibility notes are in its body.

## Still to do
- **File children (spec skill, drift stamps, Ready):**
  - **#1186's `--seed` child.** Then time about 10 mp:e2e runs. If runs end around 15 turns, F1 is A (`--timeout` 600).
  - **#435's 4 children.** F1 is B: 3 instance uniforms; GlassPanel deleted at the end.
  - **#422's 7 children,** strictly serial, Fable. The golden-hash test child goes first.
  - **#441:** a fresh spec for the re-scope (FoldReducer base, the 4 folds become thin subclasses, no `.tres` churn).
- **"Your calls" section (not started):**
  - #1620's VFX judgments.
  - About 35 dated owner decisions with no ADR (in the #1761 PR description).
  - Stale In-progress and In-review claims (#1076, #1107, #1108 and others).
  - Hygiene's 16 flags: stale Designing (#1429, #1590, #1659, #1708); hub drift (#1313, #1397, #1591, #1608, #1646); all-parked hubs (#199, #420, #1255, #1380, #1439, #1615, #1711).

Apply verdicts through a Haiku `clerk` work order that names a milestone for every Ready move. A Ready move needs a drift stamp on the issue.
