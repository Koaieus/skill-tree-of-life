# Elements split — body pass state (2026-11-10, 21:07)

Pick up here. The lead of this pass ran out of context budget after the review came back. Read this file, `ORDER.md` and `REVIEW-rulings.md`; delegate every other read. At most 5 subagents at a time (owner).

## Done, on master
- `DELTA.md`: the 2026-11-10 calls (A1-A37) and what touches each body.
- Body pass: every touched body rewritten for ADRs 0083-0085. New bodies: `cast-shapes.md` (Fire's disc and Lightning levels on a cast), `overqualified-casting.md`. `ice-cast.md` is the Ice concentrate only. `adr-fixes.md` rewritten.
- `ORDER.md` and `split-comment.md` updated: 22 children under #1716, two siblings.
- `REVIEW.md`: 35 findings from a fresh reviewer (none against an ADR). `REVIEW-rulings.md`: the lead's ownership ruling per cross-file finding. `WRITER-BRIEF.md`: the brief every writer got.

## In flight when this was written
- A clerk ran `ORDER.md` as PHASE 1 (owner: "can also just have them file real gh issues, can always update the bodies"): issues created with bodies, parents, blockers, labels, milestone; NO status set, hub comment not posted, #1444 untouched, the six closes not done, no stamp check. Its placeholder → number map is `NUMBERS.md`. If `NUMBERS.md` is missing or short, audit the board (`gh issue list --search "Elements: in:title" --state open`) before creating anything — never re-run phase 1 blind.

## Left, in order
1. Review round: one writer per file with findings in `REVIEW.md` (resolver, pairs, defs, lightning, ice, blade-elements, catalyst, fire, quiver, forge, forge-ui, flow, applier, cast-shapes, burning for F11), each given `WRITER-BRIEF.md`, `REVIEW.md` and `REVIEW-rulings.md`, editing only its file. Then `ORDER.md`: `{pairs}` and `{lightning}` also blocked by `{terrain-ui}` (F8). Re-review only the changed files.
2. Ask the owner the gaps below in ONE AskUserQuestion batch; apply.
3. LAST: one Sonnet pass re-places every `elements.md` line range in every body by content and restamps at the then-current master sha. Run docs-hygiene. Commit, push.
4. Clerk PHASE 2: re-post every body from its file onto its issue (numbers in `NUMBERS.md`), add the F8 blockers, set the statuses `ORDER.md` names, post `split-comment.md` on #1716 and drop its design label, the #1444 line, the six closes with their comments, the stamp check, hygiene. Show the owner `ORDER.md`'s summary first (units, lanes, blockers, the closes).
5. After the owner says go: delete this folder and `docs/handoffs/elements.md`. `cast-shapes-rates.md`: the numbers the specs need are inlined in `cast-shapes.md` / `ice-cast.md`; move the file if anything else still cites it (grep first).

## Gaps for the owner (each is carried in its body as a tentative reading)
- adr-fixes scope: the body keeps three corrections § 000's list does not name, because 0083-0085 do not carry them — 0081 §3 (the blade weight gate has no ADR), 0081 §7 (an arrow is an aspect subtype or an element, never both), 0081 §1 (own go-off fires once per hit). Keep them there, or a new ADR for the weight gate?
- go-off-zero: a mask-excluded charged node inside the disc does not chain, as today (0084 §7 is silent).
- ice: an arrival that shatters the ice still ends its walk (0083 is silent).
- forge: the order `clamp_infusion` trims in; two owner quotes the doc no longer holds were dropped ("×1 stub", "every entity"), rules kept unquoted.
- cast-shapes: a multi-seed cast shapes every seed; the Fire shape reads the seed node's radius; the disc's own damage reads excess only (not shape points); the Frozen mute does not drop a cast's shape.
- ice-cast: the multiplier rides the whole shortened walk (not the seed landing only); a spell with no authored row concentrates at the default.
- overqualified-casting: with no target picked, sockets fill to the best capacity among eligible casters; reset-to-base is a one-shot trim, not sticky; an aimed spell refuses the extra point rather than re-pick its source; the AI fills to its own source's cap. It is filed as one unit behind forge-ui; the non-UI part depends on no element unit and could be split off (seam in its NOTES).
- defs: `aspect_matrix.md:34` still says "side-less terrain, gives reach" and has no `## Element Matrix` heading; those doc asks stay in the body.
- Review findings with no ruling (F20 break threshold on an unowned Frozen node; F24 the Catalyst "one round" invariant and the save-version test; F33 decay below the first band; F35 the shaped range preview) may surface as gaps from the writers.
- Still open by design, untouched: shape points against the capacity; the hops-cut → shatter knob; the Fire multiplier (5); the "at least 1" solo cost.

## New owner call, arrived after the review (relayed 21:07; on master at `7b5c93e4`) — NOT yet in DELTA or any body
**Every landing is a whole hit.** The go-off share defaults to 1 (not 0.5) and each channel that goes off also lands on its own node: the hit node takes 1 payload + 1 per channel that goes off from it (Burning's blast, Shocked's arc); a node one channel reaches takes 1; a node both reach takes 2. Terrain riders (Heat / Cold / Charge) still land once per node per hit, so the extra landings carry damage and aspect riders only. "No other node reached, no go-off" stands as worded. The share stays a knob per go-off and the dedupe a switch; at share 1 the round-up per rider is idle. Written in `docs/design/elements.md` § Landing resolution, paragraph "Every landing is a whole hit" (owner quotes there), and `docs/handoffs/elements.md` § 000 "Settled 2026-11-10, night, after the ADRs".

Do, as step 0 of "Left" (before the review round, so each writer does both in one visit):
- Add it to `DELTA.md` Part A as "doc only"; note it changes ADR 0082's share default and ADR 0084 §5 ("the seed node takes the seed once"). No new ADR yet: bodies cite the doc.
- Bodies it touches: `resolver.md`, `go-off-zero.md`, `burning.md`, `lightning.md`, `pairs.md`, `cast-shapes.md`, and any Ice combo arithmetic in `ice.md` / `ice-cast.md` (a ×4 concentrated seed now copies at ×4, twice on the seed node). Give these writers the call together with their `REVIEW.md` findings. It also bears on rulings F2 (GoOff's four returns) and F4 / F6 (dedupe, dual reach).
- OPEN, do not decide in a body, add to the owner batch: (1) whether a cast's shape alone, on an unprimed node, counts as a channel for the seed (every shaped cast would then land twice on it); (2) Frozen's shatter tuned to match the doubling.
- The owner wants to hear what this does to the units: which acceptance items move, anything it breaks. Have each of those writers report exactly that, and put it in the report to the owner.

### Follow-up to the whole-hit call (relayed 21:08)
Open item (1) is ANSWERED by the owner: **a cast's shape alone is not a channel for the seed.** A Fire- or Lightning-shaped cast on an unprimed node lands once on its seed; the extra landing on the hit node comes only from a primed node going off. Written at the end of "Every landing is a whole hit" in `docs/design/elements.md` § Landing resolution (master commit "a cast's shape alone is not a channel for the seed"). Drop (1) from the owner batch.
Tentative, the fork session's reading and not the owner's: a shape added into a primed node's go-off of the same element counts as that node's one channel, so the seed takes 2. Carry it as tentative in `cast-shapes.md`.
Still open for the owner: Frozen's shatter tuned to match the doubling.

### Clerk phase 1 — done (21:08)
All 24 issues exist: #1793–#1814 are the 22 children of #1716 (order of `ORDER.md`), #1815 inner-tree, #1816 adr-fixes; map in `NUMBERS.md`. Bodies are the pre-review, pre-whole-hit files with placeholders resolved. Parents, 37 blocked-by relations, labels and milestone set; every issue sits in Intake. Not done: statuses, the #1716 comment and label, #1444 blocked by ice, the six closes, stamp checks, hygiene — all phase 2. Never create these again; phase 2 edits bodies in place.

### Next lead, 21:15
Step 0 done: A38 / A39 in `DELTA.md` Part A, the per-body addendum at its end, Frozen's shatter under "Still open". F8 is in `ORDER.md` (`{pairs}` and `{lightning}` also behind `{terrain-ui}`). Review round running: 17 writers (STATE's 15 plus go-off-zero and ice-cast for the whole-hit call), pool of 5. Re-review list after the round: `git diff --name-only` against the commit that added this paragraph.

### Review round — done (21:36); handoff to the next lead
All 17 writers reported; bodies committed in the commit after `041ea86a`. Every report, condensed, is in `ROUND-REPORTS.md` — read that instead of the bodies. Baseline for the re-review: `git diff --name-only 041ea86a HEAD -- docs/handoffs/elements-split/` (17 bodies).
Owner, 21:34-21:36: "AskUserQuestion when the time comes" (ask, don't proceed on "unless you say otherwise") and "put them Designing in the meantime". #1793-#1814 are in Designing (clerk, read back 21:37); #1815, #1816 stay in Intake (ORDER sends them to Needs design / Backlog). Nothing else on GitHub changed this round.

Next, in order:
1. Re-review: ONE fresh reviewer over the 17 changed bodies only, findings to `REVIEW-2.md`, a short summary back. Named task: the whole-hit arithmetic must agree across resolver, burning, lightning, pairs, cast-shapes, ice-cast (hit node 1 + 1 per channel going off from it; bystander 1 / 2; terrain riders once per node per hit), and the contradictions the writers flagged (ROUND-REPORTS: burning, go-off-zero, lightning, pairs, resolver, catalyst, ice-cast, ice) — most were against pre-round committed copies and may already be gone. Then one writer per file with findings.
2. The owner batch, as AskUserQuestion (owner asked for it), at most 4 questions. Put the whole-hit impact summary in the question text (owner asked to hear what it does to the units: per ROUND-REPORTS, numbers moved in resolver, burning, lightning, pairs, cast-shapes, ice-cast; nothing broke beyond the items below). Candidate questions:
   - Go-off zero under whole-hit: exempt until the Catalyst retag (share 0.5, no centre copy, `GoOff.lands_on_own_node` = false; shipped tests green) — recommended, carried — vs. follow it now (re-points `test_explosive_charges` "never the centre", `test_blast_mark`, `test_heal_spell_blast`'s `[n[2]]`; bystander damage doubles).
   - Frozen's shatter tuned to match the doubling: a knob tuned at playtest (carried) vs. something structural.
   - Re-post the reviewed bodies onto #1793-#1816 now (bodies only) vs. all at once in phase 2.
   - The adr-fixes scope (keep 0081 §1 / §3 / §7 in adr-fixes vs. a new ADR for the weight gate), or "accept every remaining tentative reading as written" with a file listing them (write `GAPS.md` from the STATE gap list plus ROUND-REPORTS' gaps, and name it in the question).
3. Then STATE's original steps 3-5 (restamp pass, clerk phase 2, delete the folder after the owner's go). Phase 2 now also moves the 22 children from Designing to the statuses ORDER names.
