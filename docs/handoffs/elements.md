# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). Read, in order:

1. `docs/design/elements.md` — every owner call to date, quoted and dated
   (2026-11-03/04/05); pass proposals are marked as such.
2. `docs/adr/0072-*.md`, `0073-*.md`, `0074-*.md`, then `0070-*.md` (a row's
   use is a swappable `LoadUse` Resource, the open set the owner reached for
   again on 2026-11-05 for the Ice use).
3. The adversarial review findings at the end of this file (most are now
   closed in the doc; the live ones are listed in the doc's § Open).
4. #1733 (payload and reach rules, owner verdicts rounds 2–3), #1444 (Ice),
   #1660 (Fire), #1741 (a hit crits once), #1765 (ranged Fuel access).

Work case by case with `AskUserQuestion`, one or two forks per question, the
recommended option first; after each verdict write it into
`docs/design/elements.md` with the quote and date. **Local session (the
checkout is `/home/bramh/...`): commit on master and push, no PR** (owner,
2026-11-05). Cloud session: a docs-only PR (auto-merge takes `docs/design/`
and `docs/handoffs/`, never `docs/adr/`). `mise run docs-hygiene` after a
design doc, `adr-hygiene` after an ADR. `gh issue view` is blocked
(GraphQL); use `gh api repos/Koaieus/skill-tree-of-life/issues/<n>` and
`/comments`. **Pull before editing**: on 2026-11-05 local master was left
behind origin on purpose (owner WIP in `ui/hud/minimap_panel/` blocks a
fast-forward); the verdicts live on origin/master.

Settled 2026-11-05 (all in the doc): same-element sources are one go-off of
size S + SI, one stack spent per landing; a go-off with no parent hit is a
terrain hit credited to the sided party, synced by determinism; a medium
rides a copy; copies land
raw on the as-cast payload; Ice concentrate onto a keg is a combo; **Burning
ignites** (Heat ≥ T), a Burning tick spends min(heat, fuel); the world clock
is the world turn as built over a temperature index (rate knob
`ceil(sqrt(N))`, tentative); an arc's third key is **fickle** (seeded random
among ties); the Ice price is an authored mass per spell spent by a
swappable use (hops / visits); ranged Fuel access reframed as Clamp parity →
#1765.

Settled later on 2026-11-05 (continuation 2, local): S + SI confirmed by the
owner for Fire and Charge alike; a copy carries **every** rider, the medium
its reach spent included (decay rates are the buildup knob; the pass's
"except the spent medium" proposal is rejected); a hit's copies take the
hit's target mask. **Owner lean, not yet firm**: a chained go-off's copies
carry the root payload flat (*"LET IT RIDE"*), with the owner's own doubt
about whether medium *planting* along a chain should decay per link.

Settled 2026-11-06 (doc § Derived states): the three derived states are the
**travel triad** — Frozen ends a path (0D), Shocked conducts one (1D, a
pass-through spends one Charge, no hop), Burning re-blasts a disc (2D,
backdraft, Heat spent to T − 1); **Shocked = #1733's critical Charge**
(Charge ≥ T), named; Burning is a light source through fog; the Shocked
crackle (`sensor_range`) parked as minor; the medium cap is
**k × T, k = 2 + `stake_level`** (k 3–5 under the default stake ceiling of
3); the cap is **soft** — stacks past it are an **excess band** that
decays fast and does one thing per element. Deep freeze is the owner's
(shatter removes T plus all the excess, which adds to the damage).

Settled 2026-11-08 (doc § The threshold model, which overrides the older
passages it lists): one side-less terrain stack per element (Heat, Cold,
Charge), inert up to **T = 2 × degree**, primed past it (Burning, Frozen,
Shocked); **reach is terrain-only** (a hit is damage + riders; an element
infusion plants Heat or Charge); the trigger is a hit on a primed node;
**a go-off pays one stack per node it reaches** (½T = degree); copies carry
everything (the per-copy spend is the brake, so § Open (d) and #1735 fork 1
close *flat*); Shocked arcs to every neighbour (the arc pick rule is gone);
one size ladder L at count > L² × T; Burning burns its holder; Fuel is an
accelerant spent whole into 2 Heat on its own node; Frozen × blade is a
two-vertex fragile snap; flat decay of 1 per world turn cools the board;
"excess" = above T, "overflow" = above the cap; Blaze/Supercharge dropped.

Still open, in this order:

- **The deletion pass** (first, before any new call): § The threshold model
  ends with the list of superseded passages in elements.md; delete or rewrite
  each against it (the family table, the forge's `reach` use, § The reach
  rule, the pair table, § Derived states, § Temperature, § Three things wear
  "explosive", the Vocabulary guard). The five atomics need re-reading
  under "the node must be primed".
- **Ice concentrate** (doc § Open): a `shape` use that survives, or a Cold
  ride row like the other two.
- **Pass picks to confirm in one line**: Fuel never counts toward T; a
  Burning node holding Fuel goes off on the world tick; the shatter spends
  everything above T as single-target damage; the blade speed curve of `t`;
  a go-off spends down to T at most (a node at excess 1 fires whole); § Open
  (d) / #1735 fork 1 closed *flat* (inferred from "everything rides").
- **Burning's disc geometry** (doc § Open): hop ball or Euclidean under the
  cost law.
- **Explosive artifacts**: every orphan in finding 15 needs a destination or
  a supersession before any element issue goes `Ready` — mostly spec-time
  facts (`explosive` → `fuel` rename, `DetonateUse`/`DetonateEffect` retired
  by Burning-ignites + the `ReachUse` seam, the barrel addon → the Fire::Fuel
  addon cell, `docs/domain/explosive.md` rewritten at build).
- **Element count as a stat**: `fire` / `ice` / `lightning` on the StatBoard
  (manage-stats), a new `StatDef.Role`; a member keys its own facets.
- **ADR 0075** (needs a human merge): supersedes 0073 in part (the use is
  0070's open set, `CleanseUse` beside ride, the Ice use as a resource; the
  reach entry is gone, reach is terrain-only, 2026-11-08) and 0074 in part
  (Cold under T no longer absorbs; the cost law, 2026-11-08), and
  records the eight 2026-11-05 verdicts above; ADR 0074 is merged (#1747),
  so today's landing verdicts go in 0075, not an amendment. 0075 also
  supersedes 0074 §5 in part: the cap's k is `2 + stake_level`, and the cap
  is soft (the excess band) where 0074 wasted the surplus.
- Remaining adversarial items in § Open: (a) row keys (#1660 B2), (b) facet
  ids, (f) the `charge` tag → `fuel` retag in the first Fire issue, (h) rider
  coalescing (#1741's open NOTE).
- Greed (#1659); the arc leap radius per excess Charge (#1733); inner-tree
  shape; #1765. The pair table is rewritten in the deletion pass.
- Housekeeping: a comment on #1694 pointing at ADR 0072; the Aspect:Status
  1:1 guard test (code, first element issue).

Delete this file once #1716 is split into children (below) and the
items above are all settled or filed.

When the list is empty: split #1716 into drone-sized children with `spec`
(first: the element count + `ReachUse` seam; Fire = #1660's children; Ice =
#1444).

---

## Adversarial review findings (2026-11-05)

Hostile read of elements.md + ADR 0072/0073 against the code and the issue
verdicts. C = contradiction, G = gap, N = nit. Items 1, 2, 8, 9, 14 and 18 were
corrected in elements.md the same day; 7a, 7b, 10, 11, 12 and the per-attack
half of 11 were settled 2026-11-05 (see the doc); the rest are in the doc's
§ Open.

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
