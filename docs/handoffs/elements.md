# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). Read, in order:

1. `docs/design/elements.md` — every owner call to date, quoted and dated
   (2026-11-03/04/05); pass proposals are marked as such.
2. `docs/adr/0072-*.md` (an aspect is one status, an element is a family) and
   `docs/adr/0073-*.md` (a hit is damage + rider map + reach entry; an intake
   row has a use) — then `docs/adr/0070-*.md`, which 0073 should have cited:
   a row's use is a swappable `LoadUse` Resource (`attack/spell/load_use/`),
   not an enum. "ride" = `PlantUse`, "reach" = a `ReachUse` replacing
   `DetonateUse` + `FuelUse`, "shape" = whatever spell-only shaping remains;
   `CleanseUse` is a payload modifier beside ride.
3. The adversarial review findings recorded at the end of this file.
4. #1733 (payload and reach rules R1–R5, owner verdicts in round 2), #1444
   (Ice: Frost / Frostbite / Frozen, the toll, shatter), #1660 (Fire: Fuel +
   Heat, Metropolis diffusion), #1741 (landed: a hit crits once, its payload
   copies it).

Work case by case with `AskUserQuestion`, one or two forks per question, the
recommended option first; after each verdict, write it into
`docs/design/elements.md` with the quote and date, then a docs-only PR (the
cloud auto-merge takes `docs/design/` and `docs/handoffs/`, NOT `docs/adr/`
— an ADR needs a human merge, so batch ADRs separately). Run
`mise run docs-hygiene` after touching a design doc and `mise run
adr-hygiene` after an ADR. `gh issue view` is blocked (GraphQL); use
`gh api repos/Koaieus/skill-tree-of-life/issues/<n>` and `/comments`.

Still open, in this order:

- **"member"** as the term for a status of an element (Fuel is a member of
  Fire; an Element Matrix row is a member row). Owner asked for a word; not
  yet accepted.
- **read / land / settle** as the landing resolution (pass proposal in the
  doc). If held → ADR 0074 and the pair table's cells are final. Check it
  against #1741's sequencing first (riders land before their hit, ADR 0067;
  `CritRoll.decide` memoised by `crit_decided`).
- **Ice pricing knob**: per-spell int:int affinity converting count to hops
  plus a per-hop payload multiplier near the measured ratio; whether the
  multiplier is one number per spell or the measured ladder. Reads both
  `max_hops` and `max_visits`. Numbers are in the doc (two tables).
- **Fuel access for ranged**: Element Matrix chosen; availability (a reload
  grant from the `fire` count?) and the per-element ammo stock cap
  (`AmmoType.max_stock`, knob or stat?) undecided.
- **Explosive artifacts**: the design says no Explosive aspect survives; each
  of `aspects/defs/explosive.tres`, `identity/defs/explosive.tres`,
  `effects/status/explosive.tres` (tag `charge` → must become `fuel`),
  `attack/ammo/types/explosive.tres`, the Explosive addon,
  `docs/domain/explosive.md`, ADR 0061/0062 needs a named destination or a
  supersession before any element issue goes `Ready`.
- **Element count as a stat**: `fire` / `ice` / `lightning` on the StatBoard
  (manage-stats skill), what `_facet_id` keys a member's
  `<x>_stacks_per_hit` / `<x>_resistance` on (the element or the member).
- Greed under the new vocabulary (#1659); arc pick rule and radius per load
  (#1733); inner-tree shape for elements; Shocked / Burning parked.
- Housekeeping: a comment on #1694 pointing at ADR 0072; the Aspect:Status
  1:1 guard test (code — belongs to the first element issue, not a docs PR).

When the open list above is empty, the doc goes `settling` → spec: split
#1716 into drone-sized children with the `spec` skill (the first is the
element count + `ReachUse` seam; Fire's family is #1660's children; Ice is
#1444).

---

## Adversarial review findings (2026-11-05)

Hostile read of elements.md + ADR 0072/0073 against the code and the issue
verdicts. C = contradiction, G = gap, N = nit. Items 1, 2, 8, 9, 14 and 18 were
corrected in elements.md the same day; the rest are in the doc's § Open and
need an owner call.

1. C: "a blast copy crits iff its parent did" — false today: `PairedDamageEffect` shrapnel has no paired lead, `draws_own_crit()` is `paired == null`, only `BlastToken` (melee) and riding landings copy. *(doc fixed: open)*
2. C: "land: no rider order matters" vs ADR 0067 (riders before their hit) and owner #1741 (*"elemental riders first … then other status(es), then damage(s)"*). *(doc fixed: order kept, reactions forbidden)*
3. C/G: no "landing unit" exists for read/land/settle: riders are separate `HitInstance`s linked by `paired`/`hit_key`, ordered at `HitLanding.place()`; "a planting hit does not trip its medium" is today only `DetonateEffect.arm`'s PlantUse skip. Copies made at settle bypass `place()` and the `land_mask`/`blast_mark` stamping.
4. C: `Infusion.load_of` keys `{concept id: load}`, `use_of` takes a concept's first row, `by_concept` has no single status for a family — Fuel ride + Heat ride + Fire reach rows cannot all key on `fire`. #1660 B2 is the fix; neither ADR carries it.
5. C: `StatusDef._facet_id` keys on identity; `StatDef.Role` is {NONE, ASPECT, STACKS_PER_HIT, RESISTANCE}, naming rule `<concept>_aspect`, `EntityStatBoard` mints nothing else, `AmmoType.per_reload_stat_id` falls back to the ASPECT facet. A `fire` count needs a new role; members key their own facets (#1660 A1 half must survive).
6. C: ADR 0073 never supersedes 0070 (open set of `LoadUse`), 0061 or 0062; `CleanseUse` fits none of ride/reach/shape; Firecracker is both the "shape" example and "becomes a reach row"; `use_for_status` / `default_face=Detonate` sit on a status that no longer exists; 0062's two-reservoir blade formula spends the hit's load.
7. C: pair table vs owner verdicts — (a) blast power *"is the node's fuel"* (#1660 r2), not Fuel plus load; (b) Charge *"consuming 1 at a time"* (#1733 r3), not absorbed; (c) chain-copy share is #1735 fork 1, open; (d) #1660 r1 B *"the hit never needs to know"* is reversed by the reach entry without a later quote; (e) #1444 called the traveller an aspect status, the 11-04 table makes Frostbite an element mover.
8. C: "a medium leaves only by being spent or cleansed" vs decay (ADR 0048, `explosive.tres` FlatDecay), `ExplosiveSpread.on_removed`, owner "death blasts first". *(doc fixed)*
9. C: "element arrow carries innate + floor(count × affinity)" is the per-hit load the doc rejects. *(doc fixed: count mints arrows, load is authored)*
10. C: Ice raising seed payload breaks "the slot buys reach only"; "at cast time" vs "resolve first on landing"; an Ice reach row on an arrow is dead.
11. G: chain cap is per wave in code (`HitLanding.detonated`) and R3, the doc says per attack; dual reach "one copy per reach" is the double count of #1733 r3 Q3 (that pass proposed a union).
12. G: settle after a world-turn tick has no parent hit — copies' payload, crit (no `resolve_seed` stream), receive vs reproduce (ADR 0002); ceil(r·s)·c ≠ ceil(r·s·c).
13. G: "one rider map keyed by status id" is the round-2 agent restatement, not an owner call; #1741 NOTES still list coalescing as open; an id-keyed map merges a BEFORE rider with an AFTER copy.
14. G: "a test guards the 1:1" — none exists. *(doc fixed)*
15. G: orphans of "no Explosive aspect survives", each needing a destination: `effects/status/explosive.tres` (+ `ExplosiveSpread`), `identity/defs/explosive.tres`, `aspects/defs/explosive.tres` + roster entry, `stats_system/defs/explosive_aspect.tres` + `explosive_stacks_per_hit.tres`, the `explosive_aspect` roll in `procgen/pools/dexterity.tres`, `attack/ammo/types/explosive.tres`, `entity/blocker/faces/explosive_face.tres`, `aspect_ring.tscn`, the barrel addon + `first_level/content.tres`, `DetonateUse`/`DetonateEffect`, blade `vertex_charges`/`BladeVertexFill`, `docs/domain/explosive.md`, the matrix's Explosive row / § Explosive / arrow-look row (superseded passages in a settling doc are deleted).
16. C: "Charge" taken twice (Lightning medium vs explosive `charge` tag, `piece_charges`, `vertex_charges`); matrix Glossary :35 still says Payload = damage + *aspect* riders; "Face" means a matrix cell in docs and DETONATE/PLANT in code.
17. N: stock cap is a stat iff something targets it (stat-knobs-and-bins §1); no int:int seam on `AmmoType`/addons.
18. N: Frost is side-less, so it blocks the freezer's own reach too; matrix :553 still said "fire thaws Frozen". *(both fixed)*

Issue bodies the review used are not in the repo; re-fetch over REST.
