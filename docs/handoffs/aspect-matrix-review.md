# Handoff — aspect-matrix misplacement review

**State:** written against the commit that adds this file. Authoritative:
`docs/design/aspect_matrix.md` (Glossary, Schools, Addons outside the
Matrix, **Misplacements — the 2026-10-05 sweep**), `skill_node_addons.md`,
`core_classes.md`. This file only orders the open forks.

Speak the pinned Glossary (top of `aspect_matrix.md`); the owner asked to be
corrected on loose terms.

## Open forks, best first

1. **Schools** (`aspect_matrix.md` § Schools) — attributes vs defence-axis vs
   none. Couples to everything below: settling it decides where pie breaks
   get moved *to*. Procgen already treats attributes as de-facto schools.
2. **Tempo row** — Fortress drag lands here (owner); candidates to join:
   Anti-Magic as its spell-terrain face (item 3), the `tempo` stat name
   collision (Twins), Paralysis/Petrified/Fatigue merge, Freeze naming
   (Elemental row). Pacifist is ruled *not* a misplacement.
3. **Misplacements items 3–8** — Anti-Magic, Halo thorns/spikes (couples to
   #1369 / #1399), spells.md pool ideas, Corrupted Node, Bleeding Edge.
   Items 1–2 have owner rulings.
4. **Twins/duplicates** — travel as one axis (Contagion as infusion), the
   four one-template spells (couples to #1381, #1397), Scout vs Blindness,
   Anchor Node, `dealloc_damage`.
5. **Defender map** — whether bulk %HP, vision, tempo stay bare on purpose.
6. **Orphans** — WIS content (couples to #1252, Affliction parent), six
   unsupplied aspect stats (#1248), armor-break stats (#1401), eight
   conceptless damage spells, Relay, Skill Dust, Clamp.
7. **Elemental** — all or nothing; contender row holds the owner's pros.
8. **Production vs firing** — #1413 (design), "needs a big think".

## Ready to dispatch

- #1414 — stale-fact fixes, no call needed.

Delete this file once the Misplacements section is empty (every line ruled
and moved into its row) and #1413 has a spec.
