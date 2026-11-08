# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). Read, in order:

1. `docs/design/elements.md` — every owner call to date, quoted and dated
   (2026-11-03 to 11-08); pass proposals are marked as such.
2. `docs/adr/0075-*.md`, then `0072-*.md`, `0073-*.md`, `0074-*.md` and
   `0070-*.md` (a row's use is a swappable `LoadUse` Resource, the open set
   the owner reached for again on 2026-11-05 for the Ice use).
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

Earlier verdicts (2026-11-03 to 11-06) live in the doc where they still hold;
ADRs 0073/0074 predate the threshold model and are read as history, superseded
in part by ADR 0075.

Settled 2026-11-08 (doc § The threshold model; the doc now reads as one
design under it, and it overrides the 2026-11-05/06 lines above where they
disagree): one side-less terrain stack per element (Heat, Cold,
Charge), inert up to **T = 2 × degree**, primed past it (Burning, Frozen,
Shocked); **reach is terrain-only** (a hit is damage + riders; an element
infusion's use is an open set, a Heat or Charge ride row or something
bespoke); the trigger is a hit on a primed node; what a go-off pays is open
per element (below); copies carry everything (*"LET IT RIDE!"*, so #1735
fork 1 closes *flat*); Shocked arcs to every neighbour; Charge stays put;
one size ladder L at count > L² × T; Burning burns its holder; Fuel is an
accelerant spent whole into 2 Heat on its own node; Frozen × blade is a
two-vertex fragile snap; flat decay of 1 per world turn cools the board;
"excess" = above T, "overflow" = above the cap; Blaze/Supercharge dropped.

Still open, in this order:

- **What a go-off pays, per element**: 1 per trigger, or ½T = degree. Lean:
  Shocked pays per neighbour, Burning pays 1. This also decides whether a
  spend may take a node below T.
- **How a shatter turns excess into damage**: flat, a percentage, a
  multiplier, or per hit.
- **Ice concentrate**: kept, shape open. The owner's 2026-11-08 line:
  infusions may be bespoke (*"spell infusions may also do bespoke stuff
  instead of simply adding riders"*).
- **Pass picks to confirm in one line**: the shatter spends everything above
  T as single-target damage; the blade speed curve of `t`.
- The rest of the doc's § Open (element rows in the forge, a death blast,
  Fuel's cap, breaking Frozen by reach, Frozen + Shocked on one node, the
  parked "a wire evens itself out").
- **Explosive artifacts**: every orphan in finding 15 needs a destination or
  a supersession before any element issue goes `Ready` — mostly spec-time
  facts (`explosive` → `fuel` rename, `DetonateUse`/`DetonateEffect` retired
  by Burning-ignites + the `ReachUse` seam, the barrel addon → the Fire::Fuel
  addon cell, `docs/domain/explosive.md` rewritten at build).
- **Element count as a stat**: `fire` / `ice` / `lightning` on the StatBoard
  (manage-stats), a new `StatDef.Role`; a member keys its own facets.
- **ADR 0075** is written:
  `docs/adr/0075-reach-is-terrain-only-a-terrain-stack-is-inert-to-t-and-primed-past-it.md`.
  It supersedes 0073 in part (the use is 0070's open set; the reach entry is
  gone, reach is terrain-only) and 0074 in part (Cold under T no longer
  absorbs; the cap's k is `2 + stake_level` and the cap is soft), and records
  the 2026-11-05 verdicts that still hold (terrain hit, determinism, the world
  clock, copies carry everything). It leaves the go-off cost, the shatter
  and Ice concentrate's shape open; a later ADR records them once settled.
- Remaining adversarial items in § Open: (a) row keys (#1660 B2), (b) facet
  ids, (f) the `charge` tag → `fuel` retag in the first Fire issue, (h) rider
  coalescing (#1741's open NOTE).
- The size-ladder and disc knobs (#1733); inner-tree shape; #1765.
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
