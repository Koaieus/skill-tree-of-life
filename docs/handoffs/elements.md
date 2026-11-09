# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). **Read nothing in full.**
`docs/design/elements.md` is ~950 dense lines and the handoffs are long; a
session that reads them whole spends a third of its context before the first
fork (2026-11-09 pass: ~150k at minute two). Instead, open with **one
`Explore(model: haiku)`** carrying two lists and read only the ranges it
returns:

- **Doc ranges**: for each fork below, the section and line range of
  `docs/design/elements.md` that carries it, plus the owner quote verbatim
  with its date; the same for ADR 0081 and 0082 (`docs/adr/`), one line each.
- **Seam grep** (code, against master): `on_dealloc` and its CLEAR / LINGER
  handling on death; `NodeStatus` and `StatusHost` (is a node's status row
  sided, where does `applier_id` live); `Infusion.load_of` / `use_of` /
  `StatusRoster.by_concept` keying; `StatDef.Role` and `EntityStatBoard`'s
  minting; `HitLanding.place` / `detonated`; `PairedDamageInstance.draws_own_crit`;
  `AmmoType.per_reload_stat_id`; `procgen/pools/*.tres` aspect rolls; the
  world-turn hook (`_end_world_turn`, ADR 0055). One `file:line` fact each.

The design is **settled**: owner calls 2026-11-03 → 11-09 are in the doc,
and the decisions in ADR 0072, 0075, **0081** (go-off cost, shatter,
breakers, frozen solid, death, Catalyst, one element per cast, the count as
access, the world-turn scope line) and **0082** (two-stage hit resolution,
Frozen absorbs under-threshold copies, a copy carries its parent's crit,
Catalyst colours on hit or prime). Work `AskUserQuestion` case by case,
recommended first; write each verdict into the doc with quote and date;
commit, push. **Local session: commit on master, no PR; pull/rebase onto
origin/master before editing and before every push.** Cloud session: a
docs-only PR (auto-merge takes `docs/design/` and `docs/handoffs/`, never
`docs/adr/`); **the board (`mise gh-project`) is GraphQL and unreachable from
a cloud session**, so the split (step 3) needs a local one. `mise run
docs-hygiene` after a design doc, `adr-hygiene` after an ADR. `gh issue view`
is blocked; use `gh api repos/Koaieus/skill-tree-of-life/issues/<n>` and
`/comments`.

## 1. Forks still open — content and acquisition (owner, design hat)

Nothing is playable until a count exists and something carries an element.
§ Acquisition says *"nothing picked"*; § The forge leaves the arrow tag and
the blade's element unstated.

- **How a player gains `fire` / `ice` / `lightning`.** Procgen pool rolls
  like today's `explosive_aspect` in `dexterity.tres` (an element roll in
  the STR / DEX / INT pools, so Fire sits in STR's pool with melee); the
  inner-tree third ring or three-spoke tree; a periodic card offer; a
  keystone (the Hearth). Which ship in v1, and is there a starter count of 1
  (the access shape of ADR 0081 §7 assumes one)?
- **Which content carries an element in v1.** Spells: `lightning_bolt.tres`
  renamed not reshaped (#1716 r1); Firecracker's row (Heat ride? Catalyst?);
  a Frost Nova (Cold ride) vs a Pestilence concentrate — which shipped spells
  get an Ice row at all. Ammo: the element-tagged arrows per reload. Addons:
  the Catalyst barrel; is there a Heat or Cold addon for blades?
- **How a blade gets its element** (§ The forge: *"a blade has its addons
  and an element"*): an addon, the count directly, or none in v1.
- **Which arrows of a reload take the element tag** (count mints N): the
  first N fired, N of the player's choosing, or every arrow while N > 0 and
  a tagged arrow spends one.

## 2. Architectural seams to settle in the pass (swarmify step 9, after the Explore)

- **A terrain row that survives death.** `on_dealloc` CLEAR and LINGER both
  clear on death; options: a third mode (PERSIST), a side-less row kind the
  host never clears, or terrain held off the StatusHost on the node. Cost
  and smell per option; the applier_id of the latest Heat still wanted.
- **Row keys.** `Infusion.load_of` keys one concept id; one element per
  spell makes the collision moot on casts, live for arrows, addons and a
  spell wanting two rows of one family. #1660 B2 (the row names the status it
  plants) — rekey by planted status id, or by row.
- **The element count's `StatDef.Role`** (a new ELEMENT role vs ASPECT with
  a tag), and members keying their own facets (`heat_resistance`).
- **Rider coalescing** (#1741's NOTE): an id-keyed map merges a BEFORE rider
  with an AFTER copy of the same id — now the stage-two landing list of ADR
  0082; coalesce per entry or never.
- **The two-stage resolver's home**: a gather step producing the record's
  blast table (`attack/`), with `HitLanding.place` applying stage two.

## 3. Then the split of #1716 (needs board access)

Proposed children (pass proposal, 2026-11-09), dependency-ordered; 1–3 are
the substrate: **1** element counts on the board + member facets + the
Aspect:Status 1:1 guard test (`manage-stats`); **2** Explosive → Catalyst
retag (artifact list in the doc's § Open; `charge` tag freed; land-phase
conversion; fate of `DetonateUse` / `DetonateEffect`, blade `vertex_charges`
/ `BladeVertexFill`; `docs/domain/explosive.md` rewritten); **3** terrain
substrate (the surviving row, T / k / cap / overflow, decay on read, the
temperature index + integer Laplacian on the world turn, the capacity bar);
**4** the two-stage landing resolver (ADR 0082; #1733 closes into it);
**5** Fire (Heat ride row, Burning's disc go-off, burn, light source; #1660 /
#1695 / #1696 fold in); **6** Lightning (Charge, Shocked arcs to every
neighbour, L² × T ladder, conduction; `lightning_bolt` renamed); **7** Ice
(Cold, absorption, breakers + corruption-path burst, blade snap, Frostbite
#1444, concentrate `shape` use); **8** forge and quiver (one element field
per cast, 3 int:int units, per-reload mint + stock cap; #1765 closes).
4 before 5–7; 1 before 8; 2 with or before 5.

Spec-time, not forks: adversarial (a) → child 4 or 8, (b) → child 1, (h) →
child 4. Parked: "a wire evens itself out"; the arc mirror (child 6); the
spike-pop docs-vs-code check (child 7).

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
