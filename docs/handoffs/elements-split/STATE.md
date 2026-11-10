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
