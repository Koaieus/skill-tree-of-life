# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). **Open the session
with a quick rundown and game analysis, then re-propose** (owner, 2026-11-09,
EOD: *"next sesh should repropose these, starting with a quick rundown and
game analysis like this"*): the rundown is § Open's "Fuel's place on the
element axis" item in `docs/design/elements.md` — the orthogonal element
axis, the three Fuel shapes, the generic-catalyst analysis (power vs shape,
the three faces, the cap arithmetic, the Frozen 60 % number, the
amplifier-alone note) — restated in a screen for an owner who has read the
title only; then the four drafted forks (supply, fuse, residual, name and
kind) as one `AskUserQuestion`, recommended first. Read, in order:

1. `docs/design/elements.md` — every owner call to date, quoted and dated
   (2026-11-03 to 11-08); pass proposals are marked as such. The doc reads as
   one design under the threshold model and is close to settled.
2. `docs/adr/0075-*.md` (the threshold model and terrain-only reach; its
   "not decided here" list is now almost all decided — see below), then
   `0070-*.md` (a row's use is a swappable `LoadUse`, an open set).
3. The adversarial review findings at the end of this file (most are closed;
   the live ones are in the doc's § Open).
4. Only as needed per § Open item: #1733 (payload and reach), #1444 (Ice),
   #1660 (Fire), #1741 (a hit crits once), #1765 (ranged Fuel access).

Work case by case with `AskUserQuestion`, one or two forks per question, the
recommended option first; after each verdict write it into
`docs/design/elements.md` with the quote and date, commit, push. **Local
session (the checkout is `/home/bramh/...`): commit on master and push, no
PR** (owner, 2026-11-05); from a worktree, push `HEAD:master` (the main
checkout holds owner WIP in `ui/hud/minimap_panel/` and stays behind origin
on purpose — **pull/rebase onto origin/master before editing and before every
push**; other sessions land commits mid-pass). Cloud session: a docs-only PR
(auto-merge takes `docs/design/` and `docs/handoffs/`, never `docs/adr/`).
`mise run docs-hygiene` after a design doc, `adr-hygiene` after an ADR.
`gh issue view` is blocked (GraphQL); use
`gh api repos/Koaieus/skill-tree-of-life/issues/<n>` and `/comments`.

Settled 2026-11-09, late pass (in the doc with quotes): **the element is an
axis orthogonal to the subtype** on arrows (owner, *"explore this concept"*),
generalised by the pass to casts and blades — it dissolves #1765's "one
budget vs each type minting" and reads the Element Matrix columns as the
three places the axis is set; **a spell carries at most one element, the
forge adds to it (same element, synergy) or replaces it for the cast**
(owner, verbatim in § The forge) — the elemental slot is one element field,
not a slot count; **the ADR 0077/0079 terrain-path tension is closed by a
scope line** (§ Landing resolution: the record carries what a command did,
go-offs included; the world turn carries what time did, reproduced from the
end-turn command as DoT ticks are today; the settle is roll-free) — stated
to the owner, not objected to, awaiting the follow-up ADR. Rejected: Fuel as
the keg subtype parallel to Frostbite (owner: a keg is AoE-linked, hence
fiery); per-element Fuel counterparts (pass + advisor: grid-filling, three
rules and supplies, anchored to nothing). #1765's access shape was asked and
redirected into the axis idea — unanswered, the pass's pick is in the doc.

Settled 2026-11-08, evening pass (all in the doc with quotes; commits
0769a0f1..e0b838af): **a go-off pays 1 per node it reaches** (one law:
Shocked 1 per neighbour, Burning 1 per disc node, Frozen the 0D case turned
inward — one target, the whole store); a blast reaching no *other* node does
not go off (no spend); a spend digs below T (full cost); power = excess read
after the triggering hit's riders land (primed-ness reads pre-hit, disc size
post-land); the radiating-blast shape was rejected (mirrors diffusion). **The
shatter burst is corruption-shaped**: excess × knob fraction (default 1%/
stack) × max HP as TRUE damage through the shared `DotTick.mint` path,
nothing if unallocated; spend fraction knob default 1.0. **Ice breakers**:
a blade vertex's touch, any crit hit, and any damage ≥ a flat threshold
(knob, default 10% max HP, deliberately not excess-scaled); the threshold
covers direct hits and arriving copies (a copy that breaks through also
lands). **Frozen + Shocked**: frozen solid — the ice mutes the node's own
go-offs; trapped Charge releases when the ice breaks, same settle, one
compound read ("Frozen mutes Shocked unless this hit shatters"), never a
re-evaluation. **A holder's death changes nothing** to terrain ("death blasts
first" is pre-threshold history). **Fuel takes its own cap of the same
k × T.** **Ice concentrate pricing**: authored per-hop multiplier, confirmed
as a lean; "alters the cast" vs "plants Cold" are two uses of the one row
mechanism, authored per spell. **Forge lean**: a dedicated elemental slot —
3 units of int:int, one per element, spent from elemental attunement
(`fire_element`). Blade speed curve knob written (clamped linear in t/T).
Greed/#1659 was closed not planned by a parallel session and is off the list.

**Settled 2026-11-09, afternoon pass (in the doc with quotes; arc in
`docs/handoffs/fuel-to-catalyst-arc.md`):** Fuel left Fire and is
**Catalyst** — one element-generic converter in no family, an aspect (the
Explosive aspect retagged, DEX; owner: *"yeahhh exactly option 1. w/visually
like purple crystals or smth instead of black goo"*), inert until a hit
carrying one element lands on its node or the node primes by any route, then
its whole store converts 1:1 into that element (no slice; a hit carries 0 or
1 element). The world-tick fuse and the 2-Heat residual went with Fuel; the
per-element buildup alternative was rejected in the owner's words. Greed must
not multiply element stacks (owner's lean, for Greed's spec). **#1765's
access shape is an owner call: the count is the access** (fire ≥ 1 mints
element-tagged arrows per reload; stock cap a knob, 2× the mint). The aspect
matrix's Explosive row, section, arrow-look and DEX lists were retagged to
Catalyst and its Glossary aligned with the doc's Vocabulary guard.

Still open, in this order:

- **Follow-up ADR**: ADR 0075's "not decided here" is now almost all decided
  (go-off cost, shatter shape, ice breakers, trapped charge, death, Fuel's
  cap, the Ice pricing lean), plus tonight's axis, one-element-per-spell and
  the 0077/0079 scope line (§ Landing resolution). Write it with `/adr`
  after the catalyst settles so its supply (the 0072 partial reversal) goes
  in the same ADR; fix the sync model's "exactly one subsystem" sentence in
  the same pass.
- **Explosive artifacts**: finding 15's orphans are now RETAGS (`explosive`
  → `catalyst`) listed in the doc's § Open; `DetonateUse`/`DetonateEffect`,
  blade `vertex_charges`/`BladeVertexFill` and Firecracker's `FuelUse` row
  are spec-time calls (`docs/domain/explosive.md` rewritten at build).
- **Element count as a stat**: `fire` / `ice` / `lightning` (and the
  catalyst's count, if own) on the StatBoard (manage-stats), a new
  `StatDef.Role`; a member keys its own facets.
- Remaining adversarial items in § Open: (a) row keys (#1660 B2), (b) facet
  ids, (f) the `charge` tag → `fuel` retag in the first Fire issue, (h) rider
  coalescing (#1741's open NOTE).
- Parked, not open: "a wire evens itself out"; the arc mirror (Lightning's
  spec); spike-pop docs-vs-code check (Ice spec). The size-ladder and disc
  knobs tune with #1733; inner-tree shape and the card offer's cadence are
  filed against the hub.
- Housekeeping: a comment on #1694 pointing at ADR 0072; the Aspect:Status
  1:1 guard test (code, first element issue).

Knobs so far (tentative pass picks unless marked owner): T = 2 × degree
(owner); k = 2 + stake_level (owner); shatter fraction 1%/stack; shatter
spend fraction 1.0; ice break threshold 10% max HP; blade sweep-speed
clamp(1 + c·t/T, 1−c, 1+c), c = 0.5; Fuel → 2 Heat per Fuel (owner); hop
ladder L² × T (owner); disc radius √power × node radius (owner); decay 1 per
world turn, Fuel slower; world turn every ceil(sqrt(N)) played turn ends.

Delete this file once #1716 is split into children (below) and the items
above are all settled or filed.

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
