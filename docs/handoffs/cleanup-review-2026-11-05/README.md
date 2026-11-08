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

## Third pass (2026-11-05, late evening): the four filings
- **#1186 → Ready as one unit.** Ten `mp:e2e` runs at b6d215aa: 10/10 pass, 13–17 s wall, 17–30 entity-turns. The owner's condition held, so F1 = A (`--timeout` 600 as a knob); the turn-bounded-pass child is dissolved. #1770 did not reproduce.
- **#435 → 4 children filed Ready** (uniforms; non-tinted sweep; tinted sweep blocked by 1; delete blocked by 2+3). Tentative pass pick: the minimap takes the shared translucent fill, allow-list stays empty; owner eyeball pass is acceptance 5 of child 3.
- **#422 → 7 children filed Ready**, strictly serial, golden-hash test first (integration tier). Labelled `needs Opus` + "Fable drone (owner call)" in the body, the #471 convention.
- **#441 → Ready** with the re-scope spec: `FoldReducer` abstract base with a virtual `_fold_damage`; CancelIfMulti extends FirstReducer with the guard (the Retract-over-Max shape). No `.tres` changes.
- Milestones: `Cross-cutting / infra` for #1186, #422 and its children, #435's children; #441 keeps `Status effects & spell automata`.

## Fourth pass (2026-11-05/06, night): "your calls", served one by one
- **Stale Designing:** #1429, #1590, #1708 released to Needs design. #1659 closed, not planned (owner: Greed stacks are exploit-sensitive; they are consumed by the kill's XP payout and vanish with the node).
- **Parked hubs:** #347, #199, #1380 closed; their lone children #1768, #1653, #1658 detached as standalone issues. #1711 and #1615 moved to Needs design. #1619's premise shifts: barrels produce the goo / "volatile fuel", check the Element Matrix (owner, verbatim on the issue).
- **#1255 children after an Explore staleness scan** (posted on each): #967 closed (per-status decay mode, not a rule); #968 stays Backlog as two addon cells awaiting an aspect/element home; #969 → Needs design on one fork only, "which Aspect Matrix cell takes a rare costly cure-all"; #1203 closed, superseded by the per-def decay slot. Hub → Needs design.
- **Mark row:** #1439, #1442, #1443 bodies rewritten to the shipped row (DEX, `mark_aspect`, status `mark`, flat +5%/stack, −1 decay; rename premise dropped, rider restated as `+1 mark_stacks_per_hit`); children → Needs design. Old bodies in the edit history.
- **Gimbal:** #1076 closed, done. #1107/#1108: an Opus state check (posted on both) found every build item landed on 2026-09-24; only the #804 `perf:idle` post and the sandbox eyeball pass are open, and the drift stamps cite an unknown sha. **Left In progress for the owner's call**, since the owner's premise ("deletion still needs to be done") turned out false — recommended: close both as landed, file one small perf+eyeball issue, and a one-line ADR/doc note sanctioning the per-viewport group lookup in `GimbalWorld.acquire`.
- Hygiene after this pass: only #422/#435 derived "In progress" (children Ready — correct).

## Fifth pass (2026-11-08): the owner answered; everything applied
- **#1659 (Greed) correction:** the fourth pass's closure never actually landed — the issue was OPEN and still claimed in `Designing`, and the newer elements handoff carried it as a stale open entry. No elements session ever revisited it (git -L on the line), so the recorded verdict stood: closed not planned with the dated owner rationale posted; the `Greed (#1659)` line struck from `docs/handoffs/elements.md`.
- **#1620 → kept open, body rewritten to the eyeball checklist.** Owner asked whether a playground exists; it does, fully (blast tab `71_blast_tab.tscn` with the three-zoom slider and rider picker; melee sandbox with beads/flare forcing, shrug slider, piece-blast-ring toggle), so nothing was built. The four judgments are now checkboxes naming the tabs.
- **ADRs: the architectural ones, walked one by one with the owner.** Sync model and ContestantRule were already ADR 0002/0010; the blocker-latch line was dropped as a code idiom (lives in the pitfalls rule). Filed as dated backfills: 0076 VisionCircles/OverlayFieldTileIndex don't-merge, 0077 AttackRecord post-apply, 0078 SpellDef.id, 0079 shadow-always + required world, 0080 MenuGraph. Owner chose two separate records for the attack pair (0077/0079), and asked whether post-apply delays multiplayer — it does not: resolve+apply run synchronously inside command validation, the record ships with the command, presentation plays out locally on each machine. Tuning calls stay domain-doc prose.
- **#1107/#1108 → closed as landed** (recommended option). The two open checks (perf:idle deltas on #804, first_level_sandbox eyeball) are #1782 — Ready, child of hub #804, milestone Cross-cutting / infra. The per-viewport group-lookup sanction landed in `docs/domain/gimbal-3d.md`.
- **#1442/#1443 stay in Needs design** for their own pass — `docs/handoffs/elements.md` has zero mark content, so "the week's aspect/Elements rework" was never their vehicle.

Nothing remains from this review; this handoff folder can be deleted.
