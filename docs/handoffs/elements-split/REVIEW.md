All paths are under `/home/bramh/skill-tree-of-life/.claude/worktrees/bridge-cse_01JiczcwzkyQEDmTg6iM2PQ5/docs/handoffs/elements-split/`. I found no body-vs-ADR contradiction (category 2); the bodies agree with 0083, 0084 and 0085 where they cite them.

## resolver.md
1. **`Admits` has one read, Ice needs two (3).** `resolver.md:30`: "`Admits` gets one method, asked at the admit step … before that generation's riders land". `ice.md:30`: "asks it in two reads per arriving hit … then, after the hit's element riders have landed, the path-end and break check", returning "land, absorb, land + break". No unit owns the post-rider seam or the walk-end seam: `resolver.md:10` says they "are #{ice}'s", `ice.md:30` says "Ice owns no gather code", and `ice.md:32` says "the seam is wherever #{resolver} left departure".
2. **`GoOff` returns three things, Burning answers four (1, 4).** `resolver.md:30`: "return the spend, the nodes reached and the share". `burning.md:31`: "The disc answers four things: … and the own damage". `burning.md:46` (acceptance 3) tests "plus `damage_per_power × power`", which has no seat.
3. **`GoOff` input is the terrain read only (3).** `resolver.md:30`: "given the gather's read of a node (its terrain …)". `go-off-zero.md:25` needs "the stored Explosive status row plus the hit's load: a spell's `DetonateUse` load … a blade piece's charges".

## pairs.md
4. **The dedupe switch is owned twice and shaped two ways (1, 3).** `resolver.md:24`: "one bool in the gather … a code switch with no editor surface", tested in its acceptance 7. `pairs.md:16`: "`dedupe_dual_reach: bool = false` — `@export` on the resource #{resolver} hosts the gather's tunables on"; `pairs.md:26` lists "the mute branch and the dedupe switch" as touched.
5. **Blocks line disagrees with ORDER (5).** `pairs.md:3` "Blocks: none"; `ORDER.md:22` puts `{cast-shapes}` behind `{pairs}`.
6. **Acceptance 9 needs a later unit (4, 5).** `pairs.md:41`: "a dual reach (a shape and a go-off included)"; the shape is `{cast-shapes}`, which is blocked by pairs.
7. **Acceptance 5 needs a sibling (5).** `pairs.md:37` "A Cold arrow onto a Shocked node"; arrows are `{quiver}`, not a blocker.
8. **Edits terrain-ui without being behind it (5).** `pairs.md:28` touches "#{terrain-ui}'s terrain bar and tooltip"; `ORDER.md:18` does not put pairs behind `{terrain-ui}`. `lightning.md:60` ("the node's bar drops") has the same gap.

## defs.md
9. **Disc subclass owner (1).** `defs.md:45`: "#{resolver} owns the contract (methods and the disc subclass)". `resolver.md:30`: "No concrete subclass ships here. #{go-off-zero} adds the disc".
10. **Starter count owner, inside one body (1).** `defs.md:87`: "#{quiver} raises it to 1". `defs.md:92`: "belongs to #{forge}, which sets `StatDef.default_value` = 1"; `quiver.md:21` agrees with forge.
11. **Rekeying is owned by none and needed early (3, 5).** `defs.md:15`: "Rekeying … `Infusion.load_of` / `use_of` belongs to #{forge}"; forge.md never claims it. `burning.md:50` ("a spell with a Heat ride row writes Heat") and `catalyst.md:36` ("intake row names Fire … a landing plants Heat") need it long before forge. I checked the code: `attack/spell/infusion.gd:119,141` call `by_concept(id)` directly, so a row named Fire resolves no status.

## owner (no body claims it)
12. **The elements domain doc has no creator (3).** Five bodies each name a different creator: `flow.md:52` "#{terrain} wrote", `burning.md:41` and `lightning.md:48` "#{defs} opens", `ice.md:45` "#{resolver} created", `pairs.md:29` "#{defs}…#{ice} created". None of those units lists it under Files touched.
13. **The blast mark naming its go-off (3).** `lightning.md:41`: "#{resolver}'s mark, which names its `GoOff`". `go-off-zero.md:27` adds only "a generation index". `burning.md:33` needs the same for Fire's colour.

## lightning.md
14. **Edge `GoOff` subclass is built by nobody (3).** `lightning.md:28`: "(#{resolver}'s edge subclass)", against `resolver.md:30`; lightning's Files touched has no new class.
15. **Addon knob name (1).** `lightning.md:33` and `fire.md:20` say "addon `.stacks` = 1"; `blade-elements.md:18` says "`ApplyStatusEffect.power` on its rider".
16. **Shared seam points at the wrong unit (3).** `lightning.md:47` "shared seam with #{fire}"; the disc look is `burning.md:39`.

## ice.md
17. **Who sets the one-shot flag (1).** `ice.md:34`: "#{blade-elements}'s copy-on-fill sets the … one-shot flag". `blade-elements.md:13`: "This unit ships only the seat; #{ice} sets it".
18. **Cold arrow pointer (3).** `ice.md:72` "The cold arrow — #{forge}"; it is `{quiver}`.
19. **Blocks line (5).** `ice.md:4` omits `{ice-cast}`; `ORDER.md:23` has it.
20. **Break threshold on an unowned node (4).** `ice.md:51` reads "`break_fraction_max_hp` of the holder's max HP"; an unallocated Frozen node has no holder, yet `ice.md:52` has it break.

## blade-elements.md
21. **Band function owner (1).** `blade-elements.md:23`: "the same pure band function #{defs} owns". `defs.md:47`: "#{terrain} owns the band function".
22. **Two stale references (1).** `blade-elements.md:52` "#{catalyst} rewrites that rule", but `catalyst-blade.md:37` deletes it first. `blade-elements.md:13` "beside `vertex_charges`", against its own `:23` "gone by now".

## catalyst.md
23. **Blade suite in the interval (1, 4).** `catalyst.md:35,41` delete the disc and "any `DetonateEffect` / `ExplosiveSpread` remnant", while `:47` says "That keeps the blade suite green". `go-off-zero.md:28` moved the blade's board blast onto that disc; `test_blade_explosive.gd` is in neither acceptance 8 nor 9, and is deleted only at `catalyst-blade.md:33`.
24. **Two things with no acceptance (4).** `catalyst.md:27` "the invariant to pin: Catalyst outlasts the same number of terrain stacks over one round" (round undefined, two clocks). `catalyst.md:48` "Bump the save version" (no test for loading an old `explosive` id).

## fire.md
25. **Burn step in a pure routine (1).** `fire.md:24`: "#{flow}'s settle routine gains one world-turn step … mint". `flow.md:32,40`: `TerrainSettle` is "pure, static" and also called per beat.
26. **Pointer to nothing (3).** `fire.md:34` "the addon pool/roster wiring #{blade-elements} names"; `blade-elements.md:54` names none.
27. **Closing wording (1).** `fire.md:1` "#1660, #1695 and #1696 close into this issue"; `ORDER.md:30-32` closes them at filing.

## quiver.md, forge.md
28. **Who closes #1765 (1).** `quiver.md:1` "Closes #1765" and `forge.md:1` "which `quiver` closes"; `ORDER.md:35` closes it at filing.
29. **Ride setter gated or not (1).** `forge.md:36`: "`set_ride` … mirroring `set_infusion`", which `overqualified-casting.md:29` calls "the ungated `set_infusion`" while listing "the ride setter" as a gated write.

## forge-ui.md
30. **Blocks line (5).** `forge-ui.md:4` "Blocks: none"; `ORDER.md:22-24` puts three units behind it.
31. **Blocker rationale (3).** `forge-ui.md:3` "for one shared element icon and colour"; `terrain-ui.md:26` takes both from `{defs}`.
32. **Socket-time cap refusal overlaps (3).** `forge-ui.md:44` "a further ride point is greyed … picking it changes nothing"; `forge.md:17` gives socket-time enforcement to `{overqualified-casting}`.

## flow.md
33. **Decay below the first band (4).** `flow.md:22,66`: "each band's rate". A count ≤ T has a null band (`terrain.md:37`); the rate there is `defs.md:32` `Element.decay_per_world_turn`, which flow never names.

## applier.md, cast-shapes.md
34. `applier.md:29` "#{resolver} later dissolves `detonate_effect.gd`"; `resolver.md:34` leaves it for `{go-off-zero}` (1).
35. `cast-shapes.md:35` "the range preview draws the shaped seed" has no acceptance item and no named file (4).

No findings: terrain.md, go-off-zero.md, burning.md, catalyst-blade.md, refresh.md, ice-cast.md, overqualified-casting.md, terrain-ui.md, inner-tree.md, adr-fixes.md.
