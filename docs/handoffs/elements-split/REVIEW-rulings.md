# Review round — lead's ownership rulings (structure only, no design)

Findings are in `docs/handoffs/elements-split/REVIEW.md`, grouped by file, numbered. Fix every finding under YOUR file, plus what the rulings below assign to you. Edit only your file. Same rules as your first brief (no line ranges, no stamps, verbatim quotes only). Where a ruling says "point", name the owning unit and drop your own claim. Report in under 100 words: finding numbers fixed, any you could not fix and why.

- F1: `{resolver}` owns BOTH seams: the admit step (before the generation's riders) and a second, post-rider read where the path-end and the break check are asked; it also owns where a walk ends on that answer. `{ice}` implements the answers (land / absorb / land + break) and owns no gather code. ice.md points at those two named seams.
- F2: `GoOff` returns four things: spend, nodes reached, share, own damage. resolver.md states the contract; burning.md already answers four.
- F3: `GoOff` is handed the terrain read AND the hit's load (go-off zero needs the load); resolver.md states it.
- F4: the dedupe switch is owned by `{resolver}` (the bool and its test at both settings). pairs.md points at it and keeps only the pair-rule tests that read it. Its surface (`@export` on the gather's tunables resource vs. code switch): resolver decides from elements.md § Landing resolution "Dual reach" / ADR 0084 §5; pairs.md follows resolver.md's wording — pairs says `dedupe_dual_reach`, keep that name.
- F6: the "shape and a go-off" half of pairs acceptance 9 moves to `{cast-shapes}` (cast-shapes.md adds it; pairs.md drops it).
- F7: pairs acceptance 5 must not need an arrow: use a seam pairs is behind (a spell's Cold ride row / a direct terrain write).
- F8: ORDER.md will put `{pairs}` and `{lightning}` behind `{terrain-ui}`; their bodies add it to their blocker line.
- F9: no concrete `GoOff` subclass ships in `{resolver}`; `{go-off-zero}` adds the disc; `{lightning}` builds the edge (arc) subclass and lists the file (F14). defs.md fixes its pointer.
- F10: starter count belongs to `{forge}`; defs.md fixes line 87.
- F11: rekeying `Infusion.load_of` / `use_of` (a row named by element resolves its status) is owned by `{burning}`, the first unit that needs it; defs.md points at `{burning}`; catalyst.md relies on it.
- F12: `{defs}` creates the elements domain doc and lists it under Files touched; every other body says "appends to the doc `{defs}` opens".
- F13: `{resolver}` owns the blast mark's seat for naming its `GoOff`; go-off-zero's generation index stays. lightning.md / burning.md already point at resolver.
- F15: the addon knob is `ApplyStatusEffect.power` on the rider (blade-elements.md); fire.md and lightning.md follow.
- F16: lightning.md points the disc look at `{burning}`.
- F17: `{ice}` sets the one-shot flag; `{blade-elements}` ships only the seat. ice.md fixes its line 34.
- F19/F5/F30: "Blocks" lines follow ORDER.md: pairs blocks `{cast-shapes}`; ice blocks `{pairs}`, `{forge}`, `{quiver}`, `{ice-cast}`; forge-ui blocks `{cast-shapes}`, `{ice-cast}`, `{overqualified-casting}`.
- F21: `{terrain}` owns the band function; blade-elements.md fixes its pointer.
- F23: catalyst.md must say what happens to the blade's board blast and `test_blade_explosive.gd` between `{catalyst}` and `{catalyst-blade}` (read both bodies and go-off-zero.md; keep the suite green without re-deciding who deletes what).
- F25: fire.md's burn step must not make `{flow}`'s pure settle routine impure: read flow.md and place the mint at the seam flow names for world-turn effects.
- F27/F28: #1660, #1695, #1696, #1765 are closed at filing with a pointing comment; no body says "Closes" for them.
- F29: forge.md's `set_ride` / `set_shape` are ungated here; `{overqualified-casting}` adds the gate. Say so in one line.
- F32: forge-ui.md shows the tally; the refusal at the cap is `{overqualified-casting}`'s. Point.
- F34: applier.md: `{go-off-zero}` dissolves `detonate_effect.gd`.
- F20, F24, F33, F35 and anything not ruled: fix from the doc; if the doc does not say, carry a tentative reading marked as such and report it as a gap.
