# DELTA — what the 2026-11-10 calls change in `docs/handoffs/elements-split/`

Sources: `docs/handoffs/elements.md` § 000 (lines 96-220), ADRs 0083, 0084 and 0085, and `docs/design/elements.md`. Line numbers into `elements.md` here are approximate (scouted at `faf6da79`); find the text by heading.

Rules for the writers:
- Do not touch `elements.md` line ranges or drift stamps in the bodies. A last pass re-places every range by content and restamps.
- Re-cite any call that Part A attributes to 0083, 0084 or 0085 as that ADR (with its § number), not as 0081 or 0082.
- The ADR-corrections sibling (`adr-fixes.md`) now covers only 0081 §5, §6 and §9; 0082's Context; and 0061, 0062 and 0070. A body that sends a correction to it for anything else (0081 §1, §7, §8; 0082 §1) cites the new ADR instead. A body that cites "0081 §5-§7, §9" as the sibling's scope cites "§5, §6, §9".
- The night call (blade vertex weight gate, A34-A37) has no ADR. It lives only in the doc.
- Nothing is re-decided. The "Still open" list stays open: a body names the item as open (a knob with a tentative default, or a NOTES line), it does not settle it.

## Part A — the calls

Format: call | `elements.md` heading (approximate line) | ADR.

**Late afternoon**
- A1. Disc radius r = A × (√power + B) × node radius, A=2, B=1, both knobs, replacing `radius_per_node_radius` 1.0 (probe `tools/disc_reach.py`; tables in `cast-shapes-rates.md`) | The threshold model, "Size" (l.109) | 0084 §2
- A2. One radius has three readers: Burning's go-off disc, Burning's light source, the Fire shape | The threshold model, "Size" (l.109) | 0084 §2
- A3. Go-off zero's Explosive disc keeps ×3 (`reach_per_radius` 3.0) until the Catalyst retag deletes it | The threshold model, "Size" (last sentence) | doc only
- A4. Lightning's shape talks in levels: level N = every node within N hops; the walk's `max_hops` is untouched | Shape and ride, "Lightning's shape talks in levels" (l.~655) | 0084 §1
- A5. Lightning level N costs 1+2+…+N points | Shape and ride (same paragraph) | 0084 §1
- A6. Fire's shape feeds the same radius formula with points × a multiplier knob (tentative 5; ballpark, not a fit) | Shape and ride (same paragraph, l.663-665) | 0084 §2
- A7. Shape and ride are independent and the caster picks each. A shape acts on the walk and plants nothing; a ride plants terrain; a hit still carries no reach | Shape and ride (opening, l.610) | 0084 §1
- A8. A shape and a primed node of the same element add into one go-off. Lightning N on Shocked M gives level N+M; it is one go-off, not two | Shape and ride, "A shape and a primed node of the same element add up" | 0084 §3
- A9. A shape-added landing carries what a go-off copy carries: the go-off's share of damage and riders, the seed's crit, and it is a copy to a Frozen node. The seed itself lands in full | Shape and ride, "A landing a shape adds…" | 0084 §6

**Evening**
- A10. Riders first. Heat, Cold and Charge riders land, then primed-ness and power are both read from the result, so the hit that tips a node over T sets it off. Reverses ADR 0082 §1's pre-hit read | The threshold model (l.93-96); Landing resolution item 1 (l.~828) | 0083 §1
- A11. Stage one at a node is admit / land / read (was read / land / settle) | Landing resolution item 1 | 0083 Consequences
- A12. Frozen admits an arriving copy against the node as it arrives. An absorbed copy lands no riders | Landing resolution item 1; What breaks the ice (l.~239) | 0083 §2
- A13. Frozen's path-end and break check read after the riders land | What breaks the ice (l.~239-245); Landing resolution | 0083 §2
- A14. Crit conditions still read the pre-hit node at the head of the gather | Landing resolution, "Build shape" (l.~884) | 0083 §4
- A15. Per target, aspect riders still land before damage | Landing resolution (l.~852-857) | 0083 §3
- A16. Fire adds the roots: r = A × (√(points × multiplier) + √excess + B) × node radius | Shape and ride, "Fire adds the roots" (l.677) | 0084 §3
- A17. The node pays its solo cost for the combined go-off, what its own go-off would have spent. Pass pick, tentative: at least 1 | Shape and ride, "The node pays its solo cost" (l.684) | 0084 §4
- A18. A shape and another element's go-off are two reaches, concatenated (the dual-reach rule), with one dedupe switch at the gather step. The seed node takes the seed once, in full | Landing resolution, "Dual reach" (l.~949-966); Shape and ride | 0084 §5
- A19. A go-off picks its nodes by shape alone at every level, unallocated nodes included. Allocated-only at level 1 is a parked backup | The reach rule (l.~594-601) | 0084 §7
- A20. An arc transfers its Charge: each stack a Shocked go-off spends lands on the reached node, as a knob that defaults to transfer. Burning and Frozen keep the void | Temperature: Heat and Cold are one flow (l.~1126-1145) | 0084 §7
- A21. Ice shape is a `ConcentrateUse` on the spell's Ice intake row: seed × (1 + bonus × hops removed) | Ice on a cast, "It is a `ConcentrateUse`…" (l.723) | 0084 §8
- A22. The Ice bonus is one number per spell, default 0.5. 1 Ice = 1 hop, and the rate is authorable per spell | Ice on a cast (l.734, l.766) | 0084 §8
- A23. The Ice bonus scales damage and aspect riders, never Heat, Cold or Charge stacks | Ice on a cast (l.757) | 0084 §8
- A24. On a Frozen node, the hops cut add to the shatter's excess (× a knob, unnamed). The Ice seed is no breaker of its own | Ice on a cast (l.750) | 0084 §8
- A25. A node gathered by two reaches takes riders and payload twice. Its own go-off fires once per hit. Already in the bodies; not listed in § 000 | Landing resolution, "Dual reach" (l.~955-960) | doc only
- A26. Forge has three kinds of slot: the old element field becomes the shape field, a second field is the ride, and the aspect slots are untouched | Shape and ride, "Three kinds of slot" (l.638); The forge (l.~427) | 0085 §1
- A27. The ride holds one terrain element at most and may differ from the shape. The same element splits one count between them; the spell's authored baseline is free | Shape and ride (l.638-652) | 0085 §1
- A28. The ride takes no aspect slot, but its points count against `SpellDef.infusion_capacity` together with the aspects' points | Shape and ride (l.~648-655) | 0085 §2
- A29. Overqualified casting: capacity = base 10 + 5 per degree above `min_degree`, one formula; below `min_degree` the node cannot cast | The forge, "Overqualified casting" (l.430) | 0085 §3
- A30. The loadout gates the caster. The target union admits only sources whose capacity carries it, and targets light up for those alone. The pick stays the highest node-local `spell_damage`. A later point re-picks the source or the socket refuses it. The union rebuilds on every loadout change | The forge, "Overqualified casting" (l.430-445) | 0085 §4 and Consequences
- A31. The cap is enforced at socketing and at source gathering, not only at launch. `aspect_overrun()`'s total-points term needs the casting node | The forge (l.~430-448) | 0085 Consequences
- A32. UI asks: a reset-to-base control (0 overqualification) with a "n targets hidden" hint. Once a target is picked, show the real cap, the best capacity among casters that reach it. #744's heatmap is the neighbour | The forge, "Overqualified casting" (l.445-451) | doc only
- A33. Stale fact: `stats_system/defs/infusion_slots.tres`'s description says 100/1000/10000; the board grants at 10/100/1000 | n/a (code fix) | n/a

**Night** (no ADR carries these)
- A34. A blade vertex's touch breaks the ice only if the vertex is at least as heavy as the node. A tie breaks | A blade on Frozen (l.198) | doc only
- A35. Weight is the sim mass `(radius / 32)²`, read at build time (not `1/inv_mass`: pivot and dead vertices are 0). Bunker's `blade_mass` counts. Nothing per-contact (Cold drag) does | A blade on Frozen (l.202-208) | doc only
- A36. A lighter vertex still snaps and the ice holds. Fallback if melee is nerfed too much: it deflects off the ice like a defender plate (deals nothing, nothing breaks) | A blade on Frozen (l.209-211) | doc only
- A37. Only the touch is gated: a light vertex's contact that crits or would deal threshold damage still breaks the ice | A blade on Frozen; What breaks the ice | doc only

**Still open (do not settle; none blocks the split)**
- Whether shape points also count against the capacity (0085 revisit-when).
- The knob name and value for hops cut → shatter.
- The Fire multiplier (5, tentative).
- The pass pick "at least 1" on the solo cost.

**Decided for this pass (owner, 2026-11-10 evening):** `ice-cast.md` is rewritten from the Needs-design menu into a spec for cast shapes; its writer says whether it should split. Overqualified casting gets its own new body, `overqualified-casting.md`.

## Part B — per body

Column 3 gives stale lines as file:line, with the stale phrase abbreviated.

| file | A items | stale lines | § 000 owed |
|---|---|---|---|
| burning.md | A1 A2 A3 A10 A17 A18 A19 | :12 "primed-ness reads pre-hit"; :13 "radius ≈ √power × node radius" (cites 2026-11-08 only); :21 `radius_per_node_radius` = 1.0; :40 "reach grows with √excess (ratio test across two powers)"; :42 "Heat ≤ T lands plainly" (the tipping hit now sets off); :43 "power read after the Heat rider" (add: primed-ness too); :52 "forge element field"; :63 cites the old dedupe lines | Rewrite the size Decision to cite A1 with 0084 §2. Replace `radius_per_node_radius` with two knobs, A=2 and B=1. One radius function that fire.md's light and the Fire shape also read (A2). Go-off zero keeps ×3 (A3). Cite A19 as 0084 §7 |
| fire.md | A1 A2 A10 | :40 acceptance 3 "radius of √power × node radius" (the quote "light radius same formula as explosion size would" is right, the formula is stale); :49 "forge element field" | Light-radius line: same formula A(√p+B) × node radius, read from the same function as Burning's disc |
| go-off-zero.md | A3 A10 A19 | none stale in formula: :19 `reach_per_radius` unchanged is right. :1 "Closes #1733 and #1735" and :55 "#1733 closes when this unit lands" conflict with the pass pick; :56 sends the ADR-0082 Context correction to "the next element ADR" (stays in adr-fixes) | Keeps ×3: add one explicit line (disc stays 3 × √power × node radius, retired with the Explosive retag, A3). Pass pick: #1733 and #1735 close now as completed with a pointing comment, so drop the "Closes" at :1 and reword :14/:55. Check for "pre-hit" wording |
| lightning.md | A4 A5 A8 A10 A19 A20 | :19 and :60 cite ADR 0081 §1 and a "sibling issue for ADR corrections. Write no ADR here" (0084 §7 now carries the transfer); :20 shape-blind cites `:532-542` (0084 §7); :49 acceptance 1 "Charge ≤ T lands plainly" (a tipping Charge rider now sets off) | Re-cite 0084 §7 at :19 and :20. Check "pre-hit" wording. Add a note that the arc go-off must accept a combined level, shape N + node M (A8), built by the cast-shapes unit |
| ice.md | A10 A12 A13 A24 A34-A37 | :12 "every check reads pre-hit state"; :18 path-end "read pre-hit"; :30 "against the pre-hit band" (admit-on-arrival stays; break check reads after the riders); :32 "pre-hit band is Frozen is terminal"; :54 acceptance 6 "breakers read pre-hit"; :80 "pre-hit reads"; :9 and :74 cite 0082 §3 and 0081 | Night call already carried, verified by grep: :10 and :12 (Decisions), :33 (Composition), :56 acceptance 8, :57 acceptance 8b; check it against A34-A37 only. Fix the pre-hit wording per 0083 §2. One NOTES pointer: the shatter's excess later adds hops cut (A24), built by the cast-shapes unit |
| pairs.md | A10 A12 A13 A18 A25 | :9 "Primed-ness and the Frozen check read pre-hit" (admit on arrival, then riders, then read); :56 "every check reads pre-hit"; :11/:16/:22/:37/:60 dedupe switch (add: it also covers a cast's shape against another element's go-off); :49 "0081 §5-§7, §9" | Check "pre-hit" wording. Re-cite the dedupe switch as 0084 §5 |
| resolver.md | A10-A15 A17 A18 A19 | :9 "ADR 0082 §1-2" (§1 is now 0083 in part); :19 dedupe and shape-blind cite no ADR (0084 §5/§7); :28 crit "against the pre-hit node" (right, A14; add 0083 §4); :29 `GoOff` given "the pre-beat read" (also riders-first order and admit/land/read, A11); :47 acceptance 6 "pre-hit" (right for crit); :57 | :28 and :47 are crit-only and correct; the stage-one text needs the riders-first rewrite. The dedupe bool is also the shape-vs-go-off switch (A18). The gather must leave room for a reach added by a shape (A8, A9, A18) without building it. Check `GoOff` spend against the solo cost (A17) |
| catalyst.md | A10 | :55 acceptance "The hit reads primed-ness pre-hit"; :84 "0081 §5-§7 and §9" | Check "pre-hit" wording |
| forge.md | A26-A28 (A29-A31 by pointer) | :1 "at most one element… adds or replaces it, three int:int units"; :9 quote and :16 "stays outside `infusion_capacity`" (now counts against it, A28); :11 "3 units of int:int" quote (doc no longer holds it) and :73 "the '3 units' quote"; :17 "three units"; :26-:28 `Infusion` owns one element field (now shape + ride fields); :29 `aspect_overrun` element points above COUNT; :35, :47 acceptance 3, :48 acceptance 4; :61 "0081 §7 'orthogonal to its subtype'… next element ADR" (0085 carries §7 now); :76 cites 0081 §7/§8 only | Rewrite around A26-A28 and cite 0085 §1-§2. Drop the "3 units of int:int" quote at :11 and :73. The capacity formula, the caster gate and the socket-time cap (A29-A31) belong to `overqualified-casting.md`: point, do not own. What the shape field *does* on a cast belongs to `ice-cast.md` (cast shapes): point, do not own |
| forge-ui.md | A26-A28 A32 | :1 and :9 "forge's element field… add or replace"; :19 "one element socket… is not one of `infusion_slots`"; :33-35 acceptances 1-3 (adds/replaces, one element line) | Rework to shape socket + ride socket; show the ride's points under the cap (A28). The A32 UI asks (reset-to-base, "n targets hidden", real cap) are owned by `overqualified-casting.md` unless its writer and this one report otherwise: point, do not own |
| ice-cast.md | A4-A9 A16-A18 A21-A24 | The whole file: :1 shape table "Lightning lengthens the walk by whole hops" (now levels, A4); :~13 "price is a lean, not settled" (A22 settles it); Forks 1-3 answered | Rewrite wholesale from the doc (§ Shape and ride, § Ice on a cast, § The threshold model "Size", § Landing resolution "Dual reach") and ADR 0084 as a spec for cast shapes: what each element's shape does on a cast. Strip the title line and the lane line from the body. The writer reports whether it should split (e.g. per element) and what it is blocked by. `cast-shapes-rates.md` will not survive the folder: inline the numbers the spec needs |
| adr-fixes.md | – (the ADR record) | :8 §3, :12 §8 ("flat price… seed × (1 + 0.5 × hops removed)" stated as settled), :11 §7 (carried by 0085/0084), :7 §1 transfer (0084 §7) | Rewrite wholesale from § 000's "ADRs filed" paragraph: what is left is 0081 §5, §6 (Catalyst is an aspect status, not terrain), §9; 0082's Context; 0061, 0062 and 0070. Drop what 0083-0085 carry. The night call (A34-A37) has no ADR: if the current §3 line is that correction, keep it and report it as a gap |
| refresh.md | – | :1 and :10 "eight late issues"; :16 "drift-stamp bd800181" in prose; :47 ice-cast comment (check against the rewrite); :48 "0081 §5-§7 and §9" | Fix "eight" (count the late units after this pass, including cast shapes and overqualified casting if they are late); remove the stamp sha from prose (keep the fence at :53) |
| defs.md | – | :94 "0081 §5-§7 and §9" | `defs.md:64` asks for two doc fixes that are already done: remove them |
| flow.md | – | :83 "0081 §5-§7, §9" | – |
| catalyst-blade.md | – | :43 "0081 §5-§7 and §9" | – |
| quiver.md | A26 | :1 "`forge`… owns the element field, the units" | Light touch only: an arrow has no shape/ride split unless the doc says so; check § The forge and say |
| overqualified-casting.md (NEW) | A29-A33 (A28 by pointer) | – | New body from § The forge "Overqualified casting" and ADR 0085 §3-§4. Code anchors: `attack/targeting/spell_target_union.gd:125-224` (sources, pick), `attack/plan/magic_attack_plan.gd:759-770` (overrun check, launch only), `attack/spell/spell_def.gd:79,135` (`min_degree`, `infusion_capacity`), `systems/armed/armed_stack.gd:137` (clamp). #744 is the neighbour. The `infusion_slots.tres` description fix (A33) rides here |
| applier.md, blade-elements.md, terrain.md, terrain-ui.md, inner-tree.md | – | untouched | untouched |
| ORDER.md | – | `{ice-cast}` line (title "Ice on a cast — the concentrate", lane, blockers); `{forge}` title "the forge's element field"; `{adr-fixes}` title "0081 §1 and §5-§9"; "twenty children" count | After the writers report: `{ice-cast}` becomes the cast-shapes spec with the lane, parent and blockers its writer reports; add `{overqualified-casting}`; fix the forge and adr-fixes titles; fix the children count. Keep: the six closes as completed with a pointing comment, adr-fixes in `Backlog`, labels `ui` on the two display units and `tech-debt` on `applier` |
| split-comment.md | – | :25 lists `#{ice-cast}` under the late units | Place cast shapes and overqualified casting where ORDER.md files them; update "ADR 0072, 0075, 0081, 0082" to add 0083-0085 |
