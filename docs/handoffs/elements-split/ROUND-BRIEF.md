# Review-round brief — elements split (#1716)

You are one writer in the review round over the elements-split spec bodies. All 24 are already filed as GitHub issues; do NOT touch GitHub — every body is re-posted from its file later. Your prompt names your file, its unit `{name}` and issue number, your findings and the rulings that assign you work.

1. Read `docs/handoffs/elements-split/WRITER-BRIEF.md` and follow it, except its last paragraph: your final message is specified at the end of this file.
2. Read `docs/handoffs/elements-split/REVIEW.md` (a fresh reviewer's findings, grouped by file, numbered) and `docs/handoffs/elements-split/REVIEW-rulings.md` (the lead's ownership rulings; they override REVIEW.md where they differ). Fix every finding and ruling your prompt names. Where a ruling says "point", name the owning unit as `{name}` and drop your own claim.
3. Edit only your file. Other writers are editing sibling files in this checkout at the same time: run no git command that changes state. When you need a sibling body, read the committed copy, not the working file: `git show 27a0c270:docs/handoffs/elements-split/<file>`.

Three rulings apply to every body:
- F12: the elements domain doc is created by `{defs}`. Any other body that names who creates it says "appends to the doc `{defs}` opens".
- F27 / F28: #1660, #1695, #1696 and #1765 are closed at filing with a pointing comment. No body says "Closes" (or "closes into this issue") for them.
- F5 / F19 / F30: every "Blocked by" / "Blocks" line follows `docs/handoffs/elements-split/ORDER.md` (read the lines that name your unit; `{pairs}` and `{lightning}` are now also behind `{terrain-ui}`).

Where a finding or ruling needs a call the doc does not make, carry a tentative reading marked "(tentative, not the owner's)" in the body and report it as a gap.

## The whole-hit call (only if your prompt says "whole-hit")

A new owner call (2026-11-10, night), in `DELTA.md` Part A as A38 and A39, with a per-body row in DELTA's last section ("Part B addendum"). Read A38, A39 and your addendum row, then in `docs/design/elements.md` § Landing resolution the paragraph "Every landing is a whole hit, and a go-off lands on its own node too" (grep for it) and the "Dual reach" paragraph just above it. No ADR carries it yet: cite the doc paragraph. It changes ADR 0082's share default (now 1) and ADR 0084 §5's "the seed node takes the seed once".

Apply it to your body in the same visit: Decisions, Composition, knobs (the share's default is 1), acceptance items. The hit-node arithmetic is one rule shared by resolver, burning, lightning, pairs and cast-shapes; state it in one acceptance item in exactly these terms, with numbers your unit can test: the hit node takes 1 + 1 per channel that goes off from it; a node one channel reaches takes 1, a node both reach takes 2; terrain riders (Heat / Cold / Charge) land once per node per hit, so the extra landings carry damage and aspect riders only. Do not decide what the doc leaves open: Frozen's shatter tuned to match the doubling stays open (a knob with its tentative default, or a NOTES line).

## Final message

Under 200 words: finding numbers fixed; any you could not fix and why; any contradiction with another unit; gaps for the owner (each tentative reading you carried, one line each). If your prompt says "whole-hit", add: acceptance items added, moved or whose numbers changed, and anything the call breaks in this unit. Nothing else.
