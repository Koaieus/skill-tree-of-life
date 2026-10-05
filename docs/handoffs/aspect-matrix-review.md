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

## 2026-10-05 pass 2 — explorers done, don't re-sweep

Findings, so the next session starts from them:
- Schools: owner's "1" read as *attributes are schools* — confirm in one
  line. No free scaling is owner-settled (2026-09-28); written into
  § Schools. Corruption → WIS is an owner lean. WIS three-way (patience /
  mind / status quo) is the live sub-fork; tempo row may be WIS or INT.
- Tempo-row cost: no sum-over-nodes aggregation, no dealloc lock, no per-node
  spell hop cost exists today (nothing blocks them; `skill_node_
  specializations.md` "Crystallized Node" already proposes the lock). Three
  new mechanics — a build, not a move. Levers are real: `initiative_speed`
  (TurnManager replenish), `movement_points`, `deallocation_points`,
  `action_points`; `swing_drag` is read in `attack/melee/sim/blade_defender_zones.gd`.
- `tempo` stat (kill-AP refund) is a self-speed buff; the slow row attacks
  tempo without being named it — rename is a knob.
- ADR contradictions (librarian) → route to #1414: 0023's per-type
  `<id>_arrows_per_reload` vs 0044/0041's `<concept>_aspect` minting; 0022's
  potency clause overturned by 0029; R/G/B as live colours vs legacy D-5's
  deferred damage-type triangle.
- Issue-trail sweep was Haiku: #1358 persona quotes ("Tithe", corruption
  raising `min_damage_taken`) look misattributed — read #1358 yourself
  before citing. Reference-game research ran from recall, no web.
- Milestone 23: Schools adds a school to the eight row hubs, answers #1249
  and redirects #1252; the tempo row is a new hub; the anti-blade ruling
  gates #1369/#1399; ~30 per-face cells untouched.

## Round 3–4 state (2026-10-05) — open with this

Schools settled, placement rule accepted (see § Schools and the round 3/4
blocks in `aspect_matrix.md`). The twelve as they stand:

| School | Row 1 | Row 2 |
|---|---|---|
| STR | Bleeding | Armor break |
| DEX | Poison | Explosive |
| INT | Curse | Silence/Paralysis? (needs faces: "node can't originate any attack") |
| CON | Wither | Fatigue (movement + dealloc; inherits Fortress drag) — or INT |
| PER | Scout | Blindness |
| WIS | Corruption | Greed? (negative resistance to every status) |

Struck: Thorns, Debt, Petrified, Frailty. Open: Fatigue's school, Greed's
name/shape, movement+dealloc together vs separate, Silence's faces, buffs
only as faces inside rows (pass proposal). Then: write the school onto each
row hub, file the Bleeding/Fatigue/Greed contender rows, procgen content
fix (corruption → WIS pool), and only then the per-face cells.

## Ready to dispatch

- #1414 — stale-fact fixes, no call needed.

Delete this file once the Misplacements section is empty (every line ruled
and moved into its row) and #1413 has a spec.
