# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). **The design is
settled**: every owner call 2026-11-03 → 11-09 is quoted and dated in
`docs/design/elements.md` (status `settling`), and the decisions are in ADR
0072, 0075 and **0081** (2026-11-09: go-off cost, shatter, breakers, frozen
solid, death, Catalyst replacing Fuel, one element per cast, the orthogonal
axis, the count as access, the world-turn scope line). What is left is the
**split of #1716 into drone-sized children with `spec`** — it needs a session
with board access (`mise gh-project` is GraphQL, which cloud sessions cannot
reach; a local session can). Read, in order: `docs/design/elements.md`;
ADR 0081, then 0075 and 0072; this file's findings list only for the
spec-time items (a), (b), (h) below.

Open with the proposed split below as one screen for an owner who has read the
title only, then `AskUserQuestion` on its shape and order (recommended first);
write the verdict back here, then run `spec` per child. **Local session:
commit on master and push, no PR; pull/rebase onto origin/master before editing
and before every push.** Cloud session: a docs-only PR (auto-merge takes
`docs/design/` and `docs/handoffs/`, never `docs/adr/`). `mise run
docs-hygiene` after a design doc, `adr-hygiene` after an ADR. `gh issue view`
is blocked (GraphQL); use `gh api repos/Koaieus/skill-tree-of-life/issues/<n>`
and `/comments`.

**Proposed children (pass proposal, 2026-11-09, not an owner call).** The
order is a dependency order; 1–3 are the substrate every element needs.

1. **Element counts on the board** — `fire` / `ice` / `lightning` as stats
   with a new `StatDef.Role` (not `<x>_aspect`); a member keys its own facets
   (`heat_resistance`, `cold_stacks_per_hit`); the Aspect:Status 1:1 guard
   test (ADR 0072 §1, none exists). Via `manage-stats`.
2. **Explosive → Catalyst retag** — the artifact list in the doc's § Open
   (aspect, status with its `charge` tag freed for Lightning, ammo type,
   barrel addon, ring slot, DEX pool roll, Firecracker's row); Catalyst's
   land-phase conversion (whole store, 1:1, one element per hit); the fate of
   `DetonateUse` / `DetonateEffect`, blade `vertex_charges` / `BladeVertexFill`
   decided in the spec. Rewrites `docs/domain/explosive.md` at build.
3. **Terrain substrate** — a side-less node status shape that survives death,
   retake and dealloc (today's `on_dealloc` CLEAR / LINGER both clear on
   death); T = 2 × degree, k = 2 + `stake_level`, the soft cap and overflow;
   decay computed on read; the temperature index and the integer Laplacian
   step on the world turn; the capacity bar on hover.
4. **Landing resolution** — read / land / settle over `HitLanding` (today
   riders are separate `HitInstance`s ordered at `place()`; copies made at
   settle must pass through it); the once-per-node-per-hit cap; the dual-reach
   concat/dedupe knob. #1733 closes into this.
5. **Fire** — Heat ride row, Burning's disc go-off (per-node cost, power read
   post-land, no-target-no-spend), Burning's burn and light source. #1660 /
   #1695 / #1696 fold into this child and close.
6. **Lightning** — Charge, Shocked arcing to every neighbour, the L² × T hop
   ladder, conduction of a spell walk; `lightning_bolt.tres` renamed, not
   reshaped.
7. **Ice** — Cold, Frozen's denial, the three breakers and the shatter burst
   through the corruption path, the blade snap, Frostbite (#1444's inward
   pack), the concentrate `shape` use with per-spell pricing.
8. **Forge and quiver** — one element field per cast (add or swap), the
   elemental slot's three int:int units, the quiver's element axis minting
   per reload from the count with the stock-cap multiplier (#1765 closes).

Dependencies: 4 before 5–7; 1 before 8; 2 with or before 5. Children 5–7 share
`HitLanding` and the status files with 3–4 — a map for the orchestrator, not a
gate.

**Spec-time items, carried from the 2026-11-05 adversarial review** (in the
doc's § Open): (a) row keys — `Infusion.load_of` keys one concept id, so two
rows of one family cannot both key on `ice`; #1660 B2 (the row names the
status it plants) goes into child 4 or 8; (b) facet ids — child 1; (h) rider
coalescing — #1741's open NOTE, stays a NOTE. Parked, not open: "a wire
evens itself out"; the arc mirror (child 6's spec); the spike-pop docs-vs-code
check (child 7's spec).

Knobs so far (tentative pass picks unless marked owner): T = 2 × degree
(owner); k = 2 + stake_level (owner); shatter fraction 1%/stack; shatter
spend fraction 1.0; ice break threshold 10% max HP; blade sweep-speed
clamp(1 + c·t/T, 1−c, 1+c), c = 0.5; Catalyst ratio 1:1, cap k × T, slow
decay; hop ladder L² × T (owner); disc radius √power × node radius (owner);
decay 1 per world turn; world turn every ceil(sqrt(N)) played turn ends;
element ammo stock cap 2 × the per-reload mint.

Delete this file once #1716 is split into children and they are `Ready`.
`docs/handoffs/fuel-to-catalyst-arc.md` is cited by ADR 0081 and stays.

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
