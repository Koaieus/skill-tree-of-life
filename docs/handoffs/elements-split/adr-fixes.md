The element ADRs say several things the design has since moved past, and three older ADRs are superseded by the Catalyst retag without saying so. This issue collects the corrections for the next element ADR (or a superseding one). Sibling of the elements hub #1716, not a child; no code.

Write it through the `adr` skill: each correction needs the owner's dated sentence, all of which are quoted in `docs/design/elements.md` at the sections named below. ADR numbers are immutable — a correction is a new ADR that supersedes in part, never an edit of the old text.

## The corrections

- **ADR 0081 §1** (one spend law): a node's own go-off fires once per hit, not once per landing entry (owner, 2026-11-10; § Temperature). The transfer of a Shocked arc's Charge and the arc that reads its power after the breaking hit are carried by ADR 0084 and ADR 0083, not here.
- **ADR 0081 §3** (the three breakers): a blade vertex's touch breaks the ice only if the vertex is at least as heavy as the node — build-time sim mass `(radius / 32)²`, Bunker counts, a tie breaks; a lighter vertex still snaps and the ice holds; crit and the flat threshold stay ungated (owner, 2026-11-10; § A blade on Frozen). No ADR carries it yet.
- **ADR 0081 §5** (a holder's death changes nothing on terrain): stands for Heat / Cold / Charge, which are node state; it no longer covers Catalyst, which clears with its holder.
- **ADR 0081 §6** ("one side-less terrain status in no family"): Catalyst is an aspect status on allocated nodes only, clearing with its holder like Poison (owner, 2026-11-09, with the hedge *"but we can always make an exception"*; § The threshold model).
- **ADR 0081 §7** (a cast carries one element): add the arrow rule — an arrow is an aspect subtype or an element, never both; element arrows are their own ammo type, one per element (owner, 2026-11-09; § The forge). The forge-field half of §7 is ADR 0085's.
- **ADR 0081 §9** (two clocks): the no-parent go-off it lists under the world turn has no caller and is not built; Charge decays in the world-turn pass with Heat and Cold; the scoping of ADR 0079's "mutated only by `OutcomeApplier`" is restated against the settle as built by #{flow}.
- **ADR 0082's Context** says spell shrapnel's `draws_own_crit()` is false. On the code the ADR was written against it is true (`paired` is null, so shrapnel rolls its own crit); the decision (a copy carries its parent's crit) is unaffected.
- **ADR 0061, 0062, 0070**: the DETONATE / PLANT / FUEL faces, the default face on the status def, the two-sided blade contact and `DetonateUse` / `FuelUse` are superseded once #{catalyst} and #{catalyst-blade} land (Catalyst never goes off; a blade vertex copies only a primed state). `PlantUse`, `CleanseUse` and the swappable `LoadUse` itself stand.

## Notes

- Best written after #{catalyst-blade} has landed, so the supersession of 0061 / 0062 / 0070 describes code that exists.
- `mise run adr-hygiene` after it; the design doc's superseded passages are deleted in the same pass, not annotated.

Intended lane: Backlog.
