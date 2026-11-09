# Elements design — continuation prompt

Paste the block below as the first message of the next session. Everything it
names is on master; nothing lives only in a transcript.

---

Continue the elements design pass (#1716 is the hub). **Read nothing in
full** — `docs/design/elements.md` is ~950 dense lines; a session that reads
it whole is at 150k before the first fork (it happened twice, 2026-11-09).
Open with one `Explore(model: haiku)` that returns, per item below, the doc
section + line range and the owner quote verbatim with its date, and read
only those ranges. The seam facts are already in § 2 here: do not re-grep.

The design is **settled** (ADR 0072, 0075, 0081, 0082 — 0082 reached master
2026-11-09 evening, 895e9c06). Work `AskUserQuestion` case by case,
recommended first; write each verdict into the doc with quote and date;
commit, push. **Local session: commit on master, no PR; pull/rebase onto
origin/master before editing and before every push.** Cloud session: a
docs-only PR (auto-merge takes `docs/design/` and `docs/handoffs/`, never
`docs/adr/`); the board (`mise gh-project`) is GraphQL, so the split needs a
local session. `mise run docs-hygiene` after a design doc, `adr-hygiene`
after an ADR. `gh issue view` is blocked; use `gh api
repos/Koaieus/skill-tree-of-life/issues/<n>` and `/comments`.

**Settled 2026-11-09, evening pass (owner quotes in the doc):** acquisition
— v1 sources are the aspect sources (school pool roll, inner tree, found and
stolen mods); starter count **1 in every element for now, 3 each for the dev
sandbox Player**; later 0 with gains from the inner tree / core class /
metagame / board keystones. **Generator keystones** filed as #1787 (Needs
design; +2 stacks per world tick, not a hit so no go-off, Charge piles to
~4T). **Catalyst is an aspect status on allocated nodes only**, clearing with
its holder like Poison — not terrain (owner lean taken as settled, hedge
*"but we can always make an exception"* noted: `explosive.tres` leaves
`on_dealloc` at its default CLEAR, so the retag changes no lifecycle). **ADR
0081 §6's "one side-less terrain status" wording is stale** — carry the
correction into the next element ADR. **A blade's element is an addon
per element**, rider only, no stat. **A blade vertex copies its source
node's primed state** (Burning vertex booms, Shocked vertex arcs, Frozen
vertex is brittle). **v1 spells:**
`lightning_bolt` carries Charge; a **new single-target Cold spell** whose
innate Ice row concentrates it to 0 hops, swap the element at the forge and
hops return. **Melee crit condition** filed as #1786 (Needs design, P0; crits
shatter Frozen). Doc fact fixed: spell shrapnel rolls its *own* crit today
(`paired` null → `draws_own_crit()` true), it does not draw none.

**Settled 2026-11-09, night pass (owner quotes in the doc: § The forge,
§ Acquisition, § Open's v1 spell content):** the Cold spell's signature is
the crit condition **Thermal shock** (crits when the target's terrain holds
a different element than the cast carries; with Fire swapped in, the
restored chain shatters every Frozen node it walks). **Whip-crack** (crits
where the walk ends) is parked for a Fire spell, not v1. **Element arrows
are their own ammo type, one per element**, minted 1:1 from the count into
their own bin, a card in the volley order; an arrow is an aspect subtype or
an element, never both; no cap on elements per volley — the "element
orthogonal to subtype" passage is deleted, and "which arrows take the tag"
is dissolved. **Catalyst starts at 1** (dev sandbox Player 3), same interim
rule as the elements. **A vertex go-off spends the copy, never the source
node.** **The Frozen vertex's snap is a concentrate**: one contact hit, then
the vertex pops; the bonus is an overlay on that vertex's `blade_damage`
read at fill, scaled by Cold excess at fill.

## 1. Design beats still open

None blocking the split. One pass reading the owner has not confirmed, for
the Ice child's spec: Thermal shock's "holds a different element" reads the
*primed* state (Burning, Shocked, Frozen), not stray stacks under T.

Seam facts for the picks above (2026-11-09 Explore): a contact hit is
`vertex_damage[i]` × the speed curve (`attack/melee/sim/blade_damage_instance.gd`
`land_on`); `vertex_damage` is `blade_damage` read off the source node at
fill with the swing's overlays (`attack/melee/blade_vertex_fill.gd:30-40,
64-66`, `attack/plan/melee_attack_plan.gd:596` `overlays_for`); no overlay
can attach to a single `HitInstance`; a vertex dies through
`BladePopResolver.LiveGate._kill` (`blade_pop_resolver.gd:603`), and nothing
pops on first contact today, so "brittle" is a new per-vertex flag on
`BladeState` beside `vertex_charges` (`blade_state.gd:91`). Spell crit
conditions are `SpellDef.crit_conditions` (`spell_def.gd:141`), stamped in
`spell_resolver.gd:551-560`; ranged and melee have no condition path. An
element ammo type is the existing shape: `per_reload_stat_id`,
`on_hit_effects` with one `ApplyStatusEffect`, `order`, `max_stock`
(`attack/ammo/ammo_type.gd:38-59`); `explosive_aspect` defaults to 0.0
(`stats_system/defs/explosive_aspect.tres:15`), so the Catalyst starter is a
board value to add.

## 2. Architectural seams — facts in hand (2026-11-09 Explore), to settle with scorecards

- **A terrain row that survives death.** `on_dealloc` is exactly CLEAR |
  LINGER (`effects/status/status_def.gd:31-45`). Voluntary dealloc keeps
  LINGER (`systems/allocation_system.gd:310` → `combat/status_host.gd:277-286`
  with `keep_lingering=true`); node death (`combat/entity_combat.gd:727,
  970-975`), force-deallocate (`allocation_system.gd:337-338`, CAUSE_DEATH)
  and entity death (`entity/entity.gd:1050`, `entity_combat.gd:773`) clear
  both. Core crack moves every row to the entity (`node_combat.gd:430`,
  `status_host.gd:260-268`). There is no retake strip: `force_allocate`
  (`allocation_system.gd:223-250`) keeps the previous rows. Stale comment:
  `status_def.gd:16-19` says a bare force_deallocate keeps LINGER — false.
  Options: a third mode (PERSIST), a side-less row kind the host never
  clears, or terrain held off the `StatusHost` on the node. Catalyst is
  *not* in this seam any more (aspect status, CLEAR like Poison).
  `NodeStatus` records `camp_id` + `applier_id` of the latest applier
  (`effects/status/node_status.gd:18-19`, written `status_host.gd:153-155`).
- **Row keys.** `Infusion.load_of` / `use_of` key on the concept id
  (`attack/spell/infusion.gd:90,115`; `intake_of` `:50` takes the first row);
  `StatusRoster.by_concept` is a first-match scan on `identity.id`
  (`effects/status_roster.gd:26-34`); `StatusDef._facet_id` =
  `StatRegistry.facet_def(concept, role)` (`status_def.gd:91-94`). Callers of
  `by_concept`: `aspect_intake.gd:57`, `infusion.gd:119`,
  `ai_infusion_picker.gd:28`, `readout_lines.gd:113`. #1660 B2 (the row names
  the status it plants) — rekey by planted status id, or by row.
- **The count's `StatDef.Role`.** Role = {NONE, ASPECT, STACKS_PER_HIT,
  RESISTANCE} (`stats_system/stat_def.gd:14`); the mint loop is
  `EntityStatBoard.mint_facets` (`entity_stat_board.gd:233-238`, sparse
  boards skip); `AmmoType.per_reload_stat_id` falls back to the ASPECT facet
  (`attack/ammo/ammo_type.gd:46-52`). New ELEMENT role vs ASPECT + tag; a
  member keys its own facets (`heat_resistance`).
- **Rider coalescing** (#1741's NOTE): `HitLanding.place` orders BEFORE
  riders, the landing's own block, PRIMARY, rest (`attack/outcome/
  hit_landing.gd:137-156`); `detonated` is a per-node dedupe scope, fresh per
  spell wave (`spell_resolver.gd:297`) and per riding landing
  (`hit_landing.gd:98`), chained blasts share the parent's (`detonate_effect.gd:94`).
- **The two-stage resolver's home.** The blast table is `AttackRecord`
  (`attack/outcome/attack_record.gd:211-217`, rows are `BlastMark`s deduped
  `:700-713`); `CritRoll.decide` (`attack/outcome/crit_roll.gd:53-59`) is the
  one reader of `draws_own_crit`; copies also come from `status_instance.gd:84`,
  `splash_effect.gd:139`, `detonate_effect.gd:175`. `world_turn_ended`
  (`systems/turn_manager.gd:30`, emitted `:408` inside `end_turn`) has **no
  production subscriber**; `_lingering` (`combat/combat_world.gd:187-217`)
  ticks from `turn_manager.gd:406`. `DotTick.mint` (`effects/status/
  dot_tick.gd:24-48`) lands TRUE damage with no record; `CorruptionStatus`
  bursts through it (`effects/status/corruption.gd:27-28`).
- **Explosive artifacts** (retag targets, all verified on master):
  `LoadUse` set = `PlantUse`, `DetonateUse`, `CleanseUse`, `FuelUse`
  (`attack/spell/load_use/`); `DetonateEffect.arm` skips when an effect
  already lands explosive (`detonate_effect.gd:47-58, 69`), blasts via
  `ExplosiveSpread.blast_for` (`:98`; also `blade_pop_resolver.gd:421-423`);
  `BladeVertexFill.fill` copies node charges into `state.vertex_charges`
  (`attack/melee/blade_vertex_fill.gd:42-49`), the barrel adds a stack
  (`explosive_barrel_addon.gd:59-61`); `firecracker.tres:20-27` carries the
  `FuelUse`; `explosive.tres:20` carries tag `charge`; `dexterity.tres:239-271`
  rolls `explosive_aspect`; barrels placed by `first_level/content.tres:17`
  and `coop_versus/content.tres:16`; `explosive_face.tres` preloaded at
  `procgen/modules/blockers.gd:152`. No test guards Aspect:Status 1:1
  (`test/unit/aspects/test_aspect_roster.gd:32` counts 13 only).

## 3. Then the split of #1716 (needs board access)

Proposed children (pass proposal, 2026-11-09), dependency-ordered; 1–3 are
the substrate: **1** element counts on the board + member facets + the
Aspect:Status 1:1 guard test (`manage-stats`); **2** Explosive → Catalyst
retag (list above; `charge` tag freed; land-phase conversion and the prime
trigger; fate of `DetonateUse` / `DetonateEffect`, `vertex_charges` /
`BladeVertexFill`, Firecracker's `FuelUse`; `docs/domain/explosive.md`
rewritten) — Catalyst keeps CLEAR; **3** terrain substrate (the surviving
row, T / k / cap / overflow, decay on read, the temperature index + integer
Laplacian on the world turn, the capacity bar); **4** the two-stage landing
resolver (ADR 0082; #1733 closes into it; shrapnel copies the hit's crit);
**5** Fire (Heat ride row, Burning's disc go-off, burn, light source, the
Heat blade addon, a Burning vertex; #1660 / #1695 / #1696 fold in); **6**
Lightning (Charge, Shocked arcs to every neighbour, L² × T ladder,
conduction, the Charge addon, a Shocked vertex; `lightning_bolt` renamed);
**7** Ice (Cold, absorption, breakers + corruption-path burst, blade snap and
the Frozen vertex's concentrate snap, Frostbite #1444, concentrate `shape`
use, the Cold addon, the new Cold spell with Thermal shock); **8** forge and
quiver (one element field per cast, 3 int:int units, the three element ammo
types with their 1:1 mint + stock cap, starter counts incl. Catalyst 1;
#1765 closes).
4 before 5–7; 1 before 8; 2 with or before 5. Later, blocked on these:
#1787 generator keystones; #1786 melee crit condition (P0, independent).

Spec-time, not forks: adversarial (a) → child 4 or 8, (b) → child 1, (h) →
child 4. Parked: "a wire evens itself out"; the arc mirror (child 6); the
spike-pop docs-vs-code check (child 7).

Knobs so far (tentative pass picks unless marked owner): T = 2 × degree
(owner); k = 2 + stake_level (owner); shatter fraction 1%/stack; shatter
spend fraction 1.0; ice break threshold 10% max HP; blade sweep-speed
clamp(1 + c·t/T, 1−c, 1+c), c = 0.5; Catalyst ratio 1:1, cap k × T, slow
decay; hop ladder L² × T (owner); disc radius √power × node radius (owner);
decay 1 per world turn; world turn every ceil(sqrt(N)) played turn ends;
element ammo stock cap 2 × the per-reload mint; starter count 1 each, dev
sandbox Player 3 each, Catalyst the same (owner); Frozen vertex snap +10%
per excess stack as its own multiplier, no base term; generator +2 per world tick, Charge ceiling
~4T (owner, tentative).

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
