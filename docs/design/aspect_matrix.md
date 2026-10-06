---
status: settling
---

# The Aspect Matrix — every concept × every attack mode

> Design doc: the living table. Every status/concept must fill every column —
> Ranged (arrow), Addon, Magic (infusion) — each delivered through
> whatever hit kind the concept actually is (Scout is a status whose rows draw vision, not a damage
> status). An empty cell is a deliberate call written into the table, never
> a gap.

## Glossary — the shared vocabulary (pinned, owner 2026-10-05)

Owner: *"clean language use leads to clean development"* — use these words,
and correct a loose one when you see it (the owner asked to be corrected too).

| Term | Means | Not to be confused with |
|---|---|---|
| **Aspect** | One row: a theme with its content and status (Poison as a whole) | "concept" — the same thing; prefer *aspect* |
| **Aspect stat** | `<aspect>_aspect`, the count an entity holds | the aspect itself |
| **Mechanic** / **keyword** | A reusable rule: DoT, spill, sandpile topple, AoE, reveal. The Tag column is the keyword list | an aspect, which *uses* mechanics |
| **Facet** / **slot** | A delivery channel: arrow, addon, spell, infusion (Hades: boon slots) | "attack mode" (melee / ranged / magic), which facets serve |
| **Face** | One aspect in one facet — a single cell (Poison's arrow) | — |
| **Status** | The runtime effect on a node (poison stacks) | the aspect |
| **Axis** | A classification dimension: the defence an aspect attacks, how it travels, or which tempo lever it hits (tempo is an axis, not a school) | — |
| **School** | The top tier grouping aspects: the six primary attributes (owner, 2026-10-05). An aspect's school is the one whose verb it performs or whose own strength it turns bad | a facet (attack modes are facets) |
| **Variant** | One aspect, a different delivery shape (poison DoT / cloud / projectile) — horizontal, never numbers | a second face in another facet |
| **Duo** / **cross-synergy** | Content reading two aspects or mechanics (Hades Duo boons, Astral Ascent auras) | a pair row |
| **Color pie** | Which aspect owns which mechanic (MTG). "A mechanic lives on the row it expresses" is our pie | — |
| **Pie break** / **bleed** | A mechanic on a row that doesn't express it (Fortress drag) | — |
| **Parasitic** | A mechanic that only works with its own kind (MTG). `spikes` × `blunting` was: each existed only for the other, melee-only | — |
| **Horizontal vs vertical** | Variation by shape vs by numbers. Our variants must be horizontal | — |

Further reading: Mark Rosewater's *Making Magic* columns (color pie,
parasitic, linear vs modular); *Characteristics of Games* (Elias, Garfield,
Gutschera); *Game Mechanics: Advanced Game Design* (Adams, Dormans).

## The rule (owner, 2026-09-30)

Every concept gets a stat, an arrow, an addon, and a magic infusion. Naming:
`<concept>_aspect` (e.g. `poison_aspect`), so it sorts with the concept's
other `poison_*` stats. Every first-class row now has its stat name
pinned (owner, 2026-09-30), and all eight exist as entity stats under the
`aspects` family parent (+1 `aspects` is +1 to each). Supply is settled
(owner, 2026-10-01, #1248): the aspect is a plain stat, sourced mostly from
nodes, and each mode reads it its own way — ranged **mints that many arrows
of the type on every reload** (*"i AM poison"*), melee caps that concept's
temp upgrades per swing, magic's use is #1250. It is a count, not potency:
`<family>_stacks_per_hit` stays separate.

**One stat, every facet (owner, 2026-10-03).** *"one stack supporting
`aspect` gets application source, in many aspects (as in facets) — arrow,
addon (copied onto blade), spell, spell infusion"*. What each facet does by
default:

- **Arrow** — *"an arrow type likely applies 1 or more stacks (pending
  balancing) of the status the type represents"*; a few do a special thing
  *"still in line with its archetype"* (explosive: a euclidean AoE hitscan
  besides the single-target hit). An arrow type is an arrow whose payload is
  a list of on-hit effects (damage, status, other), plus its own look.
- **Addon** — *"should provide something that fits it too, as local
  modifiers or sometimes an entity wide modifier"* (SpikeRing: local
  `blade_damage`, so only that blade node hits harder).
  Local modifiers scale with **allocation level**, never stake. Owner: *"few
  things scale with stake, e.g. node_radius. actual modifiers (from addons
  or rolled) should by default only scale with allocation_level, spike ring
  no exception"* (fix: #1369).
- **Addon on the map** — an aspect-derived addon grants +1
  `<concept>_aspect` to whoever allocates its node. *"this is not counted
  for a temp upgrade (those mods never reach the entity's board!)"*.
- **Addon on a blade** — *"should generally apply a stack of the aspect on
  hit"*: the addon provides the on-hit rider; *"blade node itself doesn't
  need to know, the addon provides"*.
- **Spell** — *"should generally apply stacks of the status that goes with
  the aspect, or do something that thematically matches it"*, with a twist
  of its own.
  **A status's coverage is four shapes (owner, 2026-10-05; merged into the
  rule 2026-10-06):** many small hits (+1 stack each), few big hits (+10
  each), a utility hit (no damage, doubles the stacks on the node it hits),
  and a boon (no damage, cleanses the stacks and leaves a benefit per stack
  cleared — the only buff face there is; buffs are never a row). A status's
  first spell takes one shape; the other three are the gaps a second spell,
  an infusion or an arrow may close, and a shape an infusion fills needs no
  spell. Spells differ from each other by topology (Reverberator on
  self-loops, Trail Blazer on 2-degree strings, Leafblower on leaves) — that
  is the twist — so the eight conceptless damage spells are the spell library,
  not orphans. Today `venom`, `hex`, `dazzle` and `sunder` are one template
  (3-hop single target, 0.4 power, one status, differing in stack count
  only): no first spell has its shape yet, so a second-spell fork (#1381,
  #1397) starts by giving the first one its shape.
  **A second spell is optional, never a default (owner, 2026-10-03):** one
  closes a gap, never fills a slot. Owner: *"extra spell only needed if gaps
  are to be closed or e.g. a spell that does "many hits low poison stacks"
  might be complemented by a spell that does "low / heavy hits, but each hit
  applies a bigger stack count". not all spells need this, sometimes 1 source
  is enough -- given future infusions might fill gaps too, a spell is a lot of
  maintenance and shouldn't be added willy nilly"*. A `Spell 2` cell's first
  fork is therefore whether the gap exists at all.
  **Good splits (owner, 2026-10-03):** *"one that adds stacks or deals
  damage, other that's more utility or spreads stuff or has a different
  characteristic for spreading or targeting. and there could be many splits
  like this, all bound to what would be fun elements without doing more of the
  same"*. A pair of spells differs on an axis (payload vs utility, spread,
  targeting shape, hit count vs stack size), never on numbers alone.
- **Infusion** — spending aspect budget to mutate the next cast; the gist is
  on #1250.

**Defensive faces are rare (owner, 2026-10-03).** *"if every thing has a
defensive option (against just melee) swinging a blade is always just
swinging it across a mine field"*. An addon's default job is offensive or
utility; an anti-blade face (pop, deflect, drag) is a deliberate exception.

**A status should not saturate at 1–2 stacks (owner, 2026-10-06).** *"I
think generally if a status takes full effect at 1 or 2 stacks already it'd
be hard to get right on all facets"* — an infusion adding a stack per spell
hit, or a volley of arrows adding one each, blankets a whole entity. Stacks
should grade the effect.

**Blade-intrusive faces are budgeted, plain defensive stats are not (owner,
2026-10-05).** *"addons should be mindful of adding blade node affecting
defensive mechanics that e.g. require more hit scans or otherwise interact with
blade nodes. Spike nodes currently POP blade nodes, bunkers deflect them and
fortress slows them. Each of these is intrusive and should be balanced and
intuitive and not every aspect should grow one most likely. But other defensive
modifiers on addons like boosting some health or other defensive stat is mostly
fine"*. Pop (Spike Ring), deflect (Bunker) and drag (Fortification) are taken;
a new blade interaction needs a reason none of the three covers.

**Addon column note:** "addon" and "temp addon" are one thing — a
`SkillNodeAddon` scene (entity + node-local modifier lists, plus the
overridable `apply_to_blade` hook). A map addon is placed by procgen and
stays; a temp addon is added to a blade before a swing, costs aspect
charges + blade size budget, and is removed after. Addons are copied onto
melee blade nodes and take effect there — hence one column, not two.

**The addon recipe (owner, 2026-10-01).** It's just "addon", never "melee
addon". Designing a concept's addon cell means filling in these parts:

1. **Modifier list** — the entity + node-local modifiers the scene carries.
2. **Blade-node behaviour** — what it does when copied onto a blade
   (`apply_to_blade`), or "none".
3. **Looks** — how it reads on the board: a visual child of the addon scene
   (#1212's shape) and/or a central emblem (`get_emblem`). An addon with no
   look is invisible outside its tooltip.
4. **Customization needed?** — be on the lookout for anything the addon
   contract doesn't already cover: a new hook, extra hitscans, perf work,
   worst case C++ marshalling (e.g. explosive's AoE, #1211). Name it in the
   cell, so it becomes its own unit instead of a surprise mid-build.
5. **Procgen weight** (optional, lower priority) — whether procgen places it
   as a map addon, and at what rate.
6. **Temp price** — whether a player may place it on a blade for one swing
   (`temp_placeable`), its `blade_size` cost (≥ 1), and any aspect costs
   (`temp_cost_aspects`, each > 0). Authored on the scene; every currency is
   a pooled per-swing budget capped by the attacker's live stat.

**These recipes grow (owner, 2026-10-03).** The facet rules above and the
addon recipe are a target to iterate on, not a finished checklist. When a
cell's design pass learns something the next cell should know (a new rule,
an extra spec part, a thing to take into account), it adds it here, dated
and attributed, so the next session starts from it. A cell issue points at
these sections and never copies them, so an addition reaches every open
cell at once.

**Magic infusion** is a fifth spell component (an `Infusion` resource adding
an on-hit effect plus optional drawback on another component), not a patch
onto the existing four — keeps #1200 (composable spells) open. Mechanics
TBD on #1250.

## Authoring a row, and why the passes run by column

What each cell touches — files, fields, registry, guarding test — is
`docs/domain/aspect-cell-authoring.md`. A full row is every cell for one
concept; a column pass is one cell for every concept.

The row's data twin is `aspects/defs/<concept>.tres` — one `Aspect`
(identity, `<concept>_aspect` stat, status, arrow, addon scene, spells) on
`aspects/aspect_roster.tres`. A landed cell sets its facet there; an empty
facet is a cell not yet landed. `test_aspect_roster.gd` pins that every
facet carries the row's `Identity` and that the `aspects` stat family and
the roster list the same concepts.

**The passes run transposed** (owner, 2026-10-02: *"Transpose by
column"*): each column has a different gate — arrows none, addons #1212,
infusion #1250 — and every row appends to the same three registries (ammo
roster, procgen content pools, spell catalog), so one branch per column
beats five per row. #1317 is the arrow pass for every statused concept.
The design passes now run **per cell** (owner, 2026-10-03, #1376: *"1 pass
per cell, sometimes groupable"*): one issue per concept × facet, grouped
under a row hub per concept; #1318's per-concept pass is superseded by them.

**A mechanic lives on the row whose concept it expresses (owner,
2026-10-05).** Reading the tables, a mechanic sitting on a row that does not
name it must stick out — *"should be the first thing that comes to mind,
and should stick out, be jarring, be thorn in the eye"*. The worked case:
Fortress (node health) carries swing drag, which is a *slow*, while the slow
concept has no row to hold it. Moving drag over fixes both rows at once:
*"moving drag slow out of a "node hp buffing" addon and onto a slow-related
row ... is what takes 2 rows that both have 1 thematic or gameplay-wise
faults or misplacements and solves both by moving one mechanic over from 1
row to the other"*. The owner wants this sharp look taken at every aspect,
stat and addon, shipped or planned.

**The Tag column (owner, 2026-10-05).** *"a 1-3 word sharp summary of
what it is or what kind of jargon could capture it perfectly"*. The owner's
examples: poison → DoT; explosive → AoE; corruption → buildup, %dmg, spread;
curse → fragility *("cuz raises damage floor?")*, spill. The four tags the pass proposed (anti-heal, vision debuff, reveal, armor debuff)
were closed as written by the owner, 2026-10-06 (round 9); every Tag is now the owner's.

## The Matrix

Each cell links its cell issue (`<Concept> × <Facet>`, a child of the row hub in Notes), or says shipped. Infusion is one issue for the whole column, #1250.

| Concept | Tag | Stat | Ranged (arrow) | Addon (map / temp) | Spell | Magic (infusion) | Notes |
|---|---|---|---|---|---|---|---|
| Poison | DoT | `poison_aspect` | shipped; look designed (see "Rows designed in #1318"), building in #1352 | #1271 — designed (see "Rows designed in #1318"), needs an acceptance spec | `venom` shipped; second spell #1381 | #1250 | row: #1377. Spread signature deferred to an authoring pass (owner, #1204) |
| Corruption | buildup, %dmg, spread | `corruption_aspect` | #1382 — scaffold (#1349) | #1383 | #1384 | #1250 | row: #1378. Spreads as a sandpile by nature (#1202) — no `spread` authored yet, the diffusion classes are test-only; health bar shows blips per stack, extra-mean when critical (#1092). `skill_node_specializations.md`'s Corrupted Node is this row's content under another name; its penalties (double damage, floor −1) are Curse's and the floor axis's |
| Curse | fragility, spill | `curse_aspect` | #1385 — scaffold (#1349) | #1386 | `hex` shipped; no second spell proposed | #1250 | row: #1379. Raises `min_damage_taken`; spills to surviving direct neighbours on death AND dealloc (#1204) — the only authored spread today (`spill_spread.gd`). `spells.md`'s Aftershock restates this spill |
| Wither | anti-heal | `wither_aspect` | #1387 — scaffold (#1349) | #1388 | #1389 | #1250 | row: #1380. Drives healing received negative. `spells.md`'s Flood wants this anti-heal (#1389) |
| Blindness | vision debuff | `blindness_aspect` | #1390 — scaffold (#1349) | #1391 | `dazzle` shipped; **Throw Sand** #1392 (candidate, owner 2026-09-30) | #1250 | row: #1253. Count stacks, effect reads as a % via a saturating curve |
| Scout (a status whose rows draw vision, #949) | reveal | `scout_aspect` | scouting arrow shipped (stacks: #1345, #1346) | watchtower shipped (map face); blade face + look #1393 | #1394 | #1250 | row: #1254. `effects/status/scouted.tres` is live: the arrow lands camp-keyed stacks, VisionSystem draws `radius_for` discs from the rows (#1346); first-class concept (owner, 2026-09-30). Scout and Blindness are two PER rows by the owner's table, not one vision axis. Watchtower's offence stats and production-vs-firing: #1413 |
| Armor break | armor debuff | `armor_break_aspect` | #1395 — scaffold (#1349) | #1396 | `sunder` shipped; second spell #1397 | #1250 | row: #395 (child 0: penetration stat #1401). Flat −1 armor per stack, uncapped, can go below zero (#1203, owner 2026-09-30). School CON (round 7). Has no `_stacks_per_hit` / `_resistance` while the DEX pool rolls a raw `armor` −% bane that bypasses the aspect. `spells.md`'s Heavy / Piercing Bolt (seek max / min armor) are its second spell (#1397) |
| Weakness | damage debuff | `weakness_aspect` | #1427 (Sap?) | #1428 | #1429 (Enfeeble?) | #1250 | row: #1425 (child 0: the status, #1426, Ready). Stacks cut damage dealt by attacks originating from the node, % on a saturating curve (round 7) |
| Greed | status magnet | `greed_aspect` | #1422 | #1423 | #1424 | #1250 | row: #1419 (child 0: the landing term, #1420, Ready; Hoard #1421, Ready). One Greed stack on the node doubles every negative status the next hit lands, Greed included, then one stack is spent; Hoard pays bonus XP per stack left when an attack removes the node (rounds 5–6) |
| Explosive | AoE | `explosive_aspect` | #1398 | #1399 — detonation kills the blade node, reuses spike-pop plumbing (owner, #1211) | #1400 (or none) | #1250 | row: #1211. Euclidean hitscan radius from `SkillNode.radius`; barrels / friendly fire open (#1399). The concept names the content, never the reverse (owner, 2026-10-05): *"an explosive barrel blast would at best do an *explosive* (as a concept) blast, not an "explosive arrow blast" literally cuz it's not like *arrows* determine the concept but the concept determines arrows+addons+spells etc."* — so the addon is an `ExplosiveBarrelAddon` doing the explosive blast. A detonated blade node is *damaged*, and today that means popped: *"so far we put their HP on 1 so they pop after taking 1 dmg"* (owner, 2026-10-05). `spells.md`'s Detonate / Supernova are its spell (#1400) |
| Bleeding | wound, exertion | `bleeding_aspect` | #1436 | #1437 — Spike Ring refit, with #1369 | #1438 | #1250 | row: #1434 (child 0: the status + origin set, #1435). Promoted 2026-10-06. **Round 10 (owner, 2026-10-06) replaces round 9's conditional tick:** a node in an attack's origin set has its stacks ×`exert_growth` (2) **at launch**; every turn end the row pays ⌈stacks × `bleed_rate` (½)⌉ flat HP, then decays on a ramp (−1, −2, −3 … while not exerting; exertion resets it). A core exerts by *moving*, once per turn, never by attacking. Dealloc or death spills ⌊S/(N+M)⌋ to each owned neighbour, the unallocated shares soak away. STR: the price of exertion. Edgelord's **Bleeding Edge** jab takes a new name (#1449) |
| Hex | jinx, crit taken | `hex_aspect` | #1441 | #1442 | #1443 — the shipped spell `hex` (Curse payload) is renamed or repointed | #1250 | row: #1439 (child 0: the status, #1440). INT's slot (owner, 2026-10-06, round 9). The defender side of crit: per stack, hits *against* the node crit more often, a % on the saturating curve (Blindness / Weakness shape); attacker-side `crit_chance` / `crit_multiplier` stay DEX's native stats, never an aspect. The crit roll must open for a hexed target even when the attacker's board holds no crit investment (#1280's stream note) |

## Rows designed in #1318

### Poison (owner, 2026-10-03)

- **Twist:** *"it remains the classic slow poison, the special twist is that
  it's so consistent in dealing damage, and building up. so far most other
  status effects don't deal damage each turn in most cases."* Decay is
  linear, −1 stack per turn.
- **Addon on the map:** +1 `poison_aspect` to whoever allocates the node.
- **Addon on a blade:** a poison on-hit rider; its stacks multiply with the
  node's **allocation level**, not its stake. Owner: *"most if not all local
  modifiers by an addon multiply with allocation level (not stake level,
  stake raises the max, allocation is the actual)"*. So 1/X → 1 stack,
  2/X → 2, 3/X → 3.
- **3/3 unlock (owner's PoC pitch, "possibly this is too strong"):** at full
  allocation, a bonus to the node's poison landings. The owner wants *"~6
  stacks per hit"*. A flat +1 `poison_stacks_per_hit` gives only 4, because
  landing folds `stacks_per_hit` as `base_add` (`docs/domain/effect-system.md`
  § Landing); ~6 needs the stat's INCREASE row (+100%) — open, for the addon
  unit's spec. Where it reads, owner: *"landing reads attackers stats yes,
  of the blade node carrying the addon, and that blade node (== the
  attacker's) therefore the stats, no readout on defensive nodes needed"*.
- **No defensive face** (see "Defensive faces are rare").
- **Addon look (owner, 2026-10-03):** *"froth popping into green gas, along
  the rim or maybe innerdisk too idk, implementer's + advisor's design call --
  can always tune or refine later"*. Neon green and noxious, with any glow on
  a named emissive tier (`docs/domain/hdr-color.md`). Tipped needles stay the
  owner's favourite in reserve. Combining with other addons' looks on one
  node: #1368.
- **Arrow look (owner, 2026-10-03):** *"neon green poison looking emissive
  tip (fading to "regular"), leaving the occasional bubbly froth along
  travel path (occasional as in, if i'd be shooting 20 of these arrows that
  the game doesn't become all green bubbles and froth and gas"*. The froth
  density is a knob, and it must stay sparse when a whole volley flies (the
  owner's 20-arrow case). Lands with #1352.
- **Spells:** `venom`; room for a second.

## Contenders — sparse rows

Pure design, no concrete thing going for it yet, and struck freely. Owner,
2026-10-05: *"adding sparse rows in the "to be considered" rows of the
Matrix, as in pure design that has no concrete things going for it and might
be struck later. Or later we find (as we keep plopping ideas down) that 2
sparse rows could complement one another and best be merged into 1 complete
row, reducing rows that way to consolidated fleshed out rows. Just to throw
many things at a wall so we have an exhaustive list of things we do or don't
want to include in the game"*. A row is promoted when every facet has an
honest face (the rule above); a row with a face in one mode only stays here
or is struck (the ADR 0045 "dead for two of three attack modes" test).

| Concept | Tag | Attributes (vibe) | Ranged (arrow) | Addon | Spell | Notes |
|---|---|---|---|---|---|---|
| Silence | mute | INT | stacks of the status | stacks of the status | stacks of the status | **Back to contender (owner, 2026-10-06, round 7).** A node that can't originate an attack is a boolean at 1 stack; a flat −1 per stack on shots / pivot blade size / spell hops dies on `blade_size`'s 2-to-100+ range and on spells with under 5 hops (round 7). Returns when a graded mute shape turns up; the `min_degree` gate variant is parked with a smell note |
| Creep (working name) | inward trail | INT or DEX (open) | stacks of the status | stacks of the status | stacks of the status | **Round 9 (owner, 2026-10-06), the Hemorrhage candidate re-read as its own aspect.** Stacks never tick in place: each turn end one stack hops one node along the shortest owned path toward the core, damaging the node it leaves, and damages the core directly on arrival. Owner: *"genuinely fun idea that could close a gap: cowardly entities that have their core far away from the front. this would be a direct threat to them if we allow direct core damage on arrival there"*; *"it doesn't feel as much like a hemorrhage though more like a black venom trail travelling along the veins to the heart. or maybe the real hemorrhage was the damage dealt along the way"*; *"would need extensive design for travel and reaction to core movement, perf, damage rates (travel, and arrival)"*; *"there needs to be *some* level of counterplay though, given dealloc_damage is direct (and mostly permanent) core damage"*. Counterplay on the table: the trail needs an owned path, so deallocating a node on it strands it and a stranded trail dies; a cleanse. Deallocating the bleeding node voids the stacks but fires `dealloc_damage` — the orphan stat's candidate home. Design issue #1444 |
| Exposed | surface DoT | STR × INT (pair) | stacks of the status | stacks of the status | stacks of the status | **Round 9 (owner, 2026-10-06): the third-row candidate.** Tick = stacks × the node's edges to *non-owned* neighbours; decay counts the same edges, so consolidating territory is the cure. Owner: *"excellent topological twist of counting *non owned edges* only. it eats away leaf nodes that arent true dead ends. the ratio of connected vs not connected could also be mapped out. and could also be made to decay using edge-counting logic that would fit its scaling mechanic, would also determine counterplay to some extend. a strong contender. if we would add a 3rd row to each, this would 100% be in it"*; *"STR themed feel with an INT themed (edge counting) touch"*. Design issue #1445 |
| Fatigue / Slow | — | — | — | — | — | **Struck (owner, 2026-10-06)** with Paralysis, *"the whole tardy bunch"*: movement and dealloc are entity pools with no node-local meaning, and a per-node cost deadlocks chokepoints while the nodes worth slowing sit out of reach (round 5) |
| Paralysis | — | — | — | — | — | **Struck (owner, 2026-10-06)** with Fatigue / Slow. An AP-cap cut also sits on core-class territory (the Pacifist ruling) |
| Spikes | offense | STR? | — | `spike_ring_addon.tscn`: local `blade_damage` (×1.5, +3), allocation-scaled per #1369 | — | **Not an aspect**: its defensive face (pop a blade vertex) has no ranged or spell meaning. Owner, 2026-10-05: *"spikes addon just adds blade damage. Switch to bleed stacks instead? (Or keep some blade dmg mods why not). Spikes do fit bleeding thematically. Though they also fit poison"*. **Round 9 lean (pass, 2026-10-06): Spike Ring is Bleeding × Addon** — a sawblade that opens wounds: keeps its local `blade_damage`, gains the bleed rider, and Blunting dies with the pop budget; settled on #1369 and the Bleeding addon cell. The pop budget (`spikes`, `node_spikes`, `spike_regen`) is the #1369 fork; the owner leans to moving the anti-blade face to Explosive (2026-10-04: *"I think the explosive one thematically fits best"*), which would delete those stats |
| Blunting | — | — | — | today only a spiked node's +1 | — | Struck candidate: a counter to a counter, meaningless to an arrow or a spell. Dies with the pop budget if #1369 takes the explosive pivot (and #794 with it) |
| Elemental (family) | — | — | — | — | — | **Keep away (settled with Schools, 2026-10-05):** each pro is harvested as a mechanic for existing rows. Owner, 2026-10-05: *"Chill or burn sound like pure elemental, which is also a real mechanic family we haven't touched on yet. And if we start adding it, shouldn't half-ass it"*. A family, not a row: which elements, what each does on a graph, and whether elements share a resistance layer are one design pass. Chill would absorb the tempo debuffs above (Fatigue/Slow, Paralysis, Petrified). All or nothing (owner, 2026-10-05): *"either fully flesh it out or keep it away"*. Owner's pros: burning is a canonical DoT; burning could spread to neighbours; freeze may lock a node (can't act, can't be deallocated), chill a lesser or building version (*"enough chill turns into freeze idk"*); lightning *"might do hops based shenanigans"*. Against: the settled aspects (Corruption, Curse, Wither, Poison, Armor break) fit none of fire/cold/lightning, nor a fourth element. Advisor read: burn collides with Poison's axis unless edge-spread sets it apart, freeze is the tempo row's name, lightning is a targeting shape — so elements may be flavour, not a school |
| Frailty / Fragile | fragility | — | — | — | — | Struck: owner, 2026-10-05, *"likely what curse does so no"* |

## Attributes and pairs

Owner, 2026-10-05: *"Maybe we stick to 6 primary attrs, each with matching
aspect/concept, and then for each pair of those attrs we also have a matching
concept/aspect row, like "CON+STR = armor (breaking) aspect" or "DEX+STR =
bleed aspect" or "WIS+INT=..." or "PER+WIS = blindness aspect" (just examples,
to show the idea, and by "=" i mean "has a row concerning")"*.

The attributes join the table *"to also track what's already designed for
them, just by association or vibe most likely i guess given addons dont give
primary attrs"*. Watchtower is PER+DEX *"no doubt about that"*; *"A pure DEX
addon we don't have yet. Not saying we need one"*.

| School | Aspects | State |
|---|---|---|
| STR | Bleeding, Weakness | Bleeding: owner 2026-10-05, promoted 2026-10-06 (round 9). Weakness: owner 2026-10-06 (round 7) |
| DEX | Poison, Explosive | owner 2026-10-05 |
| INT | Curse, Hex | Curse: owner 2026-09-29. Hex: owner 2026-10-06 (round 9) — the defender side of crit, in the school whose verb (jinx) it performs. Silence stays in Contenders |
| CON | Wither, Armor break | Wither: owner 2026-10-05. Armor break: owner 2026-10-06 (round 7), *"it straddled STR+CON thematically anyway"* |
| PER | Scout, Blindness | owner |
| WIS | Corruption, Greed | Corruption: owner 2026-10-05. Greed: closed round 6 (owner); row #1419 |

Procgen still ships the 2026-09-22 grid (curse → CON, wither → INT,
corruption → STR); it moves to this table as a content fix (#1249). Pairs
are a content layer (duo content reading two aspects), not rows: pass
proposal, 2026-10-05.

## Schools

**Settled: a school never scales its aspects (owner, 2026-09-28, #1199).**
*"aspects seem coupled to (archetypes of) primary stats! Yet we surely don't
want to scale these effects innately with those stats for free"*. A school
couples by geography (procgen places an aspect's nodes in its attribute's
territory) and by vibe (colour, persona), never by a fold.

**Settled: an aspect's hue is its own, not its school's family (owner,
2026-10-06, #1410/#1411 review).** Asked whether aspects should take their
attribute's colour family or stay separate *"(and ignore most collisions like
purple-purple)"*, the owner picked separate: *"option 1 sounds good"*. Each
identity keeps a semantic tint (poison green, explosive orange); a school match
like Poison under DEX green is incidental, and cross-kind collisions
(Corruption and Perception both purple) are accepted. "Vibe (colour)" above
therefore means an occasional coincidence, not a rule. If school recognition
proves to matter in play, the reserve option is a second channel (a ring or
backplate in the school's colour) behind the glyph — never a retint of the
aspect.

**Settled: the six primary attributes are the schools (owner, 2026-10-05).**
*"i think the 6 primary attributes serving as schools is the way to go about
this"*. The rules for the primaries:
- *"generally never scale via other primaries (unless a real customization
  via a coreclass or keystone is done along the lines of "STR now counts for
  INT" ... which we have no plans for yet)"*.
- They *"may be used as scaling base for other stats, not the other way
  around (e.g. blade_size gets a STR-dependent addition but blade_size value
  won't affect how much STR you have"*. Read together with the 2026-09-28
  sentence above: a primary scales its own native stats (`blade_size`,
  `xp_per_turn`), never an aspect's.
Elemental is therefore "keep away": freeze's lock, burn's edge spread and
lightning's hops become mechanics that existing rows can use.

- **WIS is the skill-point economy; Corruption → WIS (owner, 2026-10-05).**
  *"WIS deals with "skillpoint economic" gains (XP gain) first and foremost.
  wisdom -> reads as experience -> manages XP/turn. corruption fits here due
  to the slow buildup, economic/political corruption but then for
  skillnodes"*. Procgen still rolls corruption on STR (a content fix).
- **WIS has three claimants.** The first is patience: growth plus time, i.e.
  Corruption and a tempo row (working name *Stasis*: stacks summed over the
  afflicted nodes slow the entity, and a threshold locks a node). The second
  is mind: the owner's 2026-09-29 *"the silence/confusion isn't that bad of
  an idea tbh"* and *"enlightenment"* (#1199). The third is the procgen
  status quo: generic DoT plus growth. The tempo row could equally sit on
  INT's *bind* verb (MTG puts tempo in blue; tempo and ramp meet only in
  Simic).
- **Coolness / swagger is not a school (owner, 2026-10-05: *"2cool4skool
  does fit"*).** *"it just sits on a generic procgen pool and could roll onto
  any archetype, not sure if they also get one of their own ("pure
  coolness") or it's just a side roll of other nodes"* — the pure-coolness
  node is open.
- **Tempo is broad, not one school (owner, 2026-10-05):** the owner lists
  the kill-AP refund (`tempo`), `sp_per_levelup`, `xp_per_turn` (turns per
  level-up), `movement_points`, `deallocation_points` and `action_points` as
  all being tempo. *"so "tempo" to me sounds like a very broad concept that
  doesn't apply to a single school"*. The `tempo` stat (the kill-AP refund)
  is renamed `momentum` so the name stops colliding with the axis (#1415).
  Pacifist's no-move-unless-you-save-AP is class identity, not a status (owner,
  2026-10-05): a core class tunes the hard-to-balance stats procgen rarely
  touches (AP, XP gain, tempo, `SET`); per-class tempo notes in
  `core_classes.md`.

**Owner calls, 2026-10-05 (round 3).**
- **Bleeding → STR:** *"STR -> bleeding sounds better in my head. more
  "physical", whereas DEX -> assassins -> poisons"*.
- **`tempo` → `momentum`** (the kill-AP refund): *"might be a good call"*.
- **Spells keep status payloads alongside infusions.** *"spells do provide
  something that pure infusion couldn't, and or something that even without
  fusion does interesting stuff"*. The coverage the owner wants per status
  is: many small hits (+1 stack each); few big hits (+10 each); a utility
  hit (no damage, doubles the stacks on the node it hits); a boon (no
  damage, cleanses the stacks and leaves something beneficial per stack
  cleared). An infusion extends a spell; it never replaces it.
  Spells otherwise diverge by topological targeting (owner, 2026-10-05:
  Reverberator on self-loops, Trail Blazer on 2-degree strings, Leafblower
  on leaves), so the eight conceptless damage spells are the spell library,
  not orphans.
- **Halo is not a design basis:** *"its design is not what we base our
  designs on, rather we will reskin or redesign that class"*.
- **Thorns fails the facet rule (owner, 2026-10-05).** Retribution has no
  sensible target against a blade (the pivot? the blade node?), a forking
  spell or an arrow volley — *"shooting 100 arrows into someone won't make an
  archer die that's just not sensible"*.
- **Ideas, unplaced:** a spell that trades 1 AP for single-turn movement or
  dealloc surplus (a mid-turn `ap_transfer_rate`); buffs as statuses, with
  the owner wary of a flurry: *"settling into something we don't want to be at
  is worse than taking some more time and settling into somewhere likeable"*.

**Owner calls, 2026-10-05 (round 4).**
- **The placement rule is accepted.** An aspect sits in the school whose verb
  it performs (Poison: the assassin's DEX; Bleeding: STR's force) or whose
  own strength it turns bad (Corruption: WIS's growth gone malignant;
  Wither: CON's health). By that rule Armor break first read as STR; the owner
  moved it to CON in round 7 (below).
- **Explosive → DEX** (the saboteur beside the poisoner).
- **Petrified is struck** until the initiative system is expanded. Owner:
  more initiative means more turns, and so more XP, more level-ups and more
  ticks suffered, which may make it *"one of the most influential tempo stats
  in the game"*. Every entity holds the same value today, and node-local
  initiative changes are illegal.
- **Debt is struck.** Losing even one skill point *"would be insanely
  overpowered"*. In code, skill points are minted at each level-up from
  the live `sp_gain_on_levelup` (`Entity.sp_minted_for_level`).
- **WIS's second row candidate is Greed** (owner idea): *"a status attracting
  status — increases stacks gained of negative statuses"*. This is **not**
  negative `dot_resistance`. Owner, 2026-10-05: resistance *"works for poison
  at the tick moment (reduces that damage); other statuses idk yet how it
  works"* (ADR 0031 filters at effect time, not at landing), and
  `<family>_stacks_per_hit` is the attacker's. Greed needs a new
  defender-side landing term (e.g. a susceptibility on the host) that landing
  folds with the attacker's stacks per hit, and a readout that overlays the
  two. The term is round 6's "does the node hold a Greed stack"; open: how
  resistance behaves for non-damage statuses.

**Owner calls, 2026-10-05 (round 5).**
- **Silence: unsettled, the owner is sleeping on it (2026-10-06).** The
  shape on the table: a node can't originate an attack (fire, pivot a blade,
  source a spell) while it holds ≥ 1 stack, −1 per turn (*"stacks is
  duration" sounds already better yet not enough"*); a node-local threshold
  instead is degenerate on allocation level (below). The worry is the boolean:
  *"when e.g. spells infusions were to add "+1 silence for each spell hit" and
  an entire entity gets blanketed; or silence arrows were to add +1 silence
  per hit ... I think generally if a status takes full effect at 1 or 2 stacks
  already it'd be hard to get right on all facets"*. No origin gate exists in
  code today: arrows fire from the leaf list, a blade's pivot is validated on
  pick, a spell's source is auto-picked.
- **Fatigue as a per-node pass-through cost is rejected.** Movement (1 per
  hop) and dealloc (1 per node) are entity pools with no node-local meaning,
  the Petrified problem. The pass proposed a per-node cost raised by stacks;
  owner: *"3+ stacks on a chokepoint would deadlock most players. and also:
  applying it to frontline nodes which an enemy doesn't think about
  deallocating anytime soon will do absolutely nothing. the nodes you'd want
  to apply it to are wayyy back, hence impossible to reliably target"*. A
  spell-hop cost *"might be worth something, but thematically doesn't feel
  like "fatigue" and could be put elsewhere maybe"*.
- **Greed doubles the final landed count** of every negative status, spending
  one Greed stack. Owner: *"all negative statuses should count"*; *"final
  landed count doubling sounds good. then the only defender stat we need to
  finalize the computation of "how many stacks are added" is whether there is
  a greed stack"*. The owner's worked example: 3 Greed stacks, four 1-stack
  poison landings → +2 +2 +2 +1. Doubling the final count makes the
  attacker's `stacks_per_hit` BASE/BONUS split irrelevant to Greed. Greed
  favours big hits: a +10 landing gains 10 for one Greed stack.
- **Hoard rides Greed** (owner: *"could also be added in here as extra
  bonus, sounds excellent"*): bonus XP per Greed stack still on a node when an
  attack removes it, on top of the per-node kill XP the loot system already
  pays.
- **Spell affinity** (owner idea): a spell carries innate aspect budget,
  landed by the infusion plumbing, with a per-spell rate as the balancing
  knob. Posted to #1250.

**Owner calls, 2026-10-06 (round 6).**
- **Greed, closed.** One Greed stack per hit: if the node holds one when a
  hit lands, every negative status that hit lands is doubled, Greed itself
  included, and one Greed stack is spent directly after the hit. Owner:
  *"exactly that yes! And post hit directly a stack is consumed"*. Greed is
  read before the hit lands, so a hit carrying Greed onto a clean node doesn't
  double its own riders. Self-compounding equals no compounding for a 1-stack
  landing (1→2→3); an *n*-stack Greed landing gains 2n−1 (1→4→7).
- **Struck: Fatigue / Slow and Paralysis**, *"the whole tardy bunch"*. No
  status attacks the tempo axis; tempo stays core-class and addon territory.
- **Fortress may be struck** *"until we can give it a better meaning or
  modifier content"*, and swing drag may leave it for no home at all: *"Possibly
  none, or something if we find it. I need to see it in action first"*.
  The pie-break reading above (drag as Fortress's misplaced slow) has no slow
  row to move to now.
- **School balance: 1 row per school is fine, 2 is ideal**, and the spread
  stays within one. Owner: *"ideally min and max differ by at most 1, keeping
  them in lockstep. If each school got N rows, then N±1 would still be
  acceptable"*. CON holding only Wither is fine: *"we won't force something
  that doesn't fit, and its one open spot now that at some point will get
  filled with an idea that's just too perfect"*.
- **Silence's threshold B on allocation level is degenerate today.** Owner:
  at most ~1% of nodes have stake > 1, so 1 stack would silence a node 99% of
  the time. Staking costs 1 AP + 1 SP (N/M → N/(M+1)), then 1 SP to allocate
  into it; the AP is there so a player can't stake 1/1 → 3/3 right before an
  attack and undo it next turn — staking is a long-term investment. Revisit B
  if staking gets cheaper.
- **Statuses can land on a core** (owner, 2026-10-06): *"status effects can
  also land on a core if the applying hit hits the core sitting on a depleted
  node (the node it sits on takes the brunt of damage and statuses, but when
  depleted it will prevent nor damage nor status from landing on the core
  itself"*. As a general rule a status on a core reads entity-wide (owner,
  2026-10-06: *"Generally reading C should hold as general rule"*, C being
  "the whole entity"). Greed and Hoard read the same on a core, with Hoard
  paying on the kill. For Silence that reading is the AP-neuter the tardy rows
  were struck for, which is part of why Silence is unsettled.

**Owner calls, 2026-10-06 (round 7).**
- **Weakness is the new row; Silence goes back to Contenders.** Owner on the
  graded mute (−1 per stack on a node's shots / pivot blade size / spell
  hops): *"A sounds promising but also hard to really balance. and i'm not
  married to the name `silence` yet, we could maybe pick a mechanic first and
  then name it"*. The objections, each fatal to a flat −1: `blade_size` *"is
  anywhere between 2 (for level 1 low STR entity) and 100+ ... would we need
  100+ stacks to prevent a high STR entity from using a node as pivot?"*;
  spells: *"most spells have less than 5 hops in total -> would that mean the
  spells would drop dead after initial hit? also: aren't we confusing attacker
  and defender here?"*; and the house problem *"of things costing 1 and then
  adding +1 on there doubles it; skill points, movement, deallocation, there's
  a LONG list"*. The owner's own candidate: *"a simple damage nerf, a
  weakening hex that nerfs local damage dealt, is also something we haven't
  got yet"*.
- **Weakness, the mechanic.** Stacks cut the damage of every attack that
  *originates from* the afflicted node — the leaf that fires, the blade node
  that sweeps, the source that casts — as a percentage on a saturating curve
  (Blindness's shape: one `MULTIPLY` on the node-local `ranged_damage`,
  `blade_damage` and `spell_damage`, all three already read from the origin
  node). Percent, so it grades at level 1 and level 100 alike; shot counts,
  blade size and hops are untouched, so a few-hops spell and a many-hops spell
  suffer the same cut. Full mute is a knob (the curve's floor), never a
  threshold. Core reading, per the general rule: the entity's damage, never
  its AP. Name: **Weakness** is the pass's tentative pick from the owner's list
  (*"weakness, or weakening? enfeeble also sounds good. `sap` also comes to
  mind as snappy"*); Sap and Enfeeble are face names waiting for a spell or
  arrow cell. Stat `weakness_aspect`, status *weakened*. Row #1425.
- **Armor break → CON, Weakness → STR.** Owner: *"how about this: armor break
  -> CON (it straddled STR+CON thematically anyway?); weakness -> STR"*. Spread
  2/2/1/2/2/2, INT now holding the open slot.
- **Silence, the contender it is now:** a mute wants a graded shape and has
  none yet. Parked variants: the owner's `min_degree` gate (*"we take the
  max(min_degree, silence stacks)"*) — the pass's smell: a status that lies
  about degree fights `docs/domain/degree.md` and every degree-reading spell.
- **Buffs are never a row (owner, 2026-10-06).** The boon shape (no damage,
  cleanse, a benefit per stack cleared) is the one buff face, and it lives on
  the status it cleanses.
- **Coolness gets its own archetype (owner, 2026-10-06):** *"a new archetype
  (low weight, few per 100 nodes) that rolls just coolness and draws itself
  with the fanciest morphing rainbow shaders on the rim does sound cool"*.
  Not a school: it still has no verb and no row. Filed as #1430.
- **Hex may become a concept later** (owner: *"which does sound enticing"*);
  the shipped spell `hex` keeps its name until then. The pass's association,
  for the Contenders table: a hex is a *jinx*, the misfortune lever — chance
  per stack that a hit from the node misfires or that crits roll against the
  holder — the one debuff family nobody holds, and a partner for the Crits
  milestone.
- **Single-node spell-terrain stays addon territory**, not a status. The
  owner's shapes: *"some anti-magic design, that consumes more hops, or one
  that mangles the node local `degree` ... like a black hole (but less intense
  than that, a BH is a bit extreme) that nabs hops when spells pass through it
  (or lets them consume +1 extra hop on landing or smth) or eat (a limited
  amount of?) projectiles outright (potentially very unbalanced so i struck
  that in my mind too)"*. Recorded on the Spell routing family below.
- **Fortress / drag stays on notice** until seen in action (round 6); nothing
  new to rule.

**Owner calls, 2026-10-06 (round 8 — details of settled rows).**
- **Weakness half-depth is 5** (`cut = n / (n + 5)`: 1 stack 17%, 5 stacks
  50%, 10 stacks 67%). Owner: *"k = 5 table looks best for now. a -5% per
  stack also sounds intuitive, but would mean a cap of 20 stacks"*.
- **Weakness decays by a fraction**, not −1. Owner: *"fractional sounds best
  here, some more sensible recovery, and keeping someone at near-0 power
  requires consistent application of these stacks"*. The fraction is open.
- **Weakness on a core: yes**, the entity-wide reading. Owner: *"core statuses
  are always very strong"*. Open: how a node's N stacks and its owner's M
  stacks compose on one attack.
- **Weakness cuts raw damage only.** Owner: *"allows counterplay in the shape
  of poisons etc"*. A status build is Weakness's counter.
- **Greed on a core stays dormant unless the core itself takes a status.**
  Owner: *"greed stacks on the entity core only trigger if the core itself
  takes >0 status effects from a hit, otherwise dormant"*. Hits that land
  only on nodes never spend the entity host's Greed.
- **Weakness knobs closed (owner picks from the pass's options):** floor
  10% per host (reached at 45 stacks), fractional decay 0.25 (10 → 7 → 5 →
  3 → 2 → 1 → 0), and a node's N stacks and its owner's M **multiply** —
  cut(N) × cut(M), worst case 1% — which is how two `MULTIPLY` modifiers fold
  anyway. Spec: #1426.
- **Greed never decays, for now.** Owner: *"Greed no decay for now; while we
  keeping door open to let greed start decaying out of combat just like nodes
  start healing after being out of combat for a few turns"*.
- **Hoard pays a percent: +10% per Greed stack** of what the removed node
  pays. Owner: *"option 1 @ +10% per stack. possibly doable via an `overlay`
  readout?"* It is: a victim-side `bounty` stat (tentative name) read with the
  loot rate as an overlay `base_add`, Greed planting `INCREASE` on it. Core
  Greed then scales the whole kill payout, every removed node plus the core
  bonus. Spec: #1421.
- **Poison's 3/3 unlock leans `MULTIPLY` ×2, never +100% INCREASE.** Owner:
  *"never 100% increase, IFF we want to achieve that it's a `2.0` multiplier
  instead. because INCREASE can also be scaled separately. and i think we might
  go for the option 2 here but with a MULTIPLY (PoE "More") modifier"*. That
  lands `(3 + N) × 2`, doubling the attacker's rolled stacks too. A lean, not
  final: #1271.
- **The ×2 is local only.** Owner: *"the poison ×2 should be local only -- so
  if *that* node is the attacking node ... holding e.g. 3 of these 3/3 nodes
  shouldn't make it ×8 altogether"*. So it sits in the addon's local
  modifiers, and landing must fold `stacks_per_hit` from the origin node; today
  it folds the attacker's entity board only, so this is a prerequisite unit
  (#1433, blocking #1271).

**Owner calls, 2026-10-06 (round 9 — the final design round).**
- **Bleeding is promoted; the mechanic is Open wound.** Stacks sit idle on a
  node. A node that *exerted* itself this turn — it sat in the origin set of an
  attack the owner launched — pays `stacks` flat HP at turn end (ADR 0040's
  tick) and its stacks ×2; every bleeding node then decays −1, used or not.
  Owner: *"bleeding could also like *double* the stacks when it triggers, and
  decay with -1 regardless"*; on the growth factor: *"i'd call it ×2 until it
  turns out to be OP"* (a knob; ×1.5 *"might be largely invisible"* on integer
  stacks). Arithmetic the owner saw: 5 stacks used five turns straight pay
  5, 9, 17, 33, 65 (Poison's 5 pay 15) — a two-or-three-turns-then-rest status,
  and a big wound is permanent until cleansed. Why not a per-turn flat DoT: a
  second flat-HP DoT beside Poison was ADR 0022's smell; Bleeding's character
  is the conditional tick. Core reading: an entity whose core bleeds pays at
  turn end on any turn it attacked at all.
- **The origin set is one fact per attack mode**, read by Bleeding, Weakness,
  crit (#1280's open "which node is a hit's origin") and #1433 alike: ranged —
  every leaf that fired this turn; melee — the pivot plus every node copied
  onto the blade; magic — the source plus the neighbours that supplied its
  `min_degree`. A node exerts at most once per turn however many volleys it
  fired. Owner on the ranged side: *"ranged volley may be put to fire exactly
  1 arrow. and that 5 times. i guess that's all the more reason to launch 5 at
  once"*. Magic's set is small — *"even a 6-hub would affect at most 7 nodes
  … while a blade can get dozens of nodes in the blade"* — and the asymmetry
  is accepted for now: the pass's "draw" (owned nodes within `max_hops`)
  *"feels a bit off"*, a per-mode damage weight is three cases that are one.
  Parked by the owner, not for now: *"magic fires from all eligible owned
  nodes in range of target … a rabbit hole we're not ready for yet"*; and the
  Tesla-relay boost (twist library below).
- **Hex fills INT's slot; no reshuffle.** Crit has two sides: the attacker's
  `crit_chance` / `crit_multiplier` are DEX's native stats (the DEX pool rolls
  them; a primary scales its own native stats), never an aspect — as `armor`
  is CON's stat and Armor break the row attacking it. The row is the defender
  side: a node holding Hex takes crits more often, a per-stack % on the
  saturating curve. Owner floated *"armor break -> INT. explosive -> STR. crit
  -> DEX"* and chose *"Hex into INT, no moves"*. Spread 2/2/2/2/2/2.
- **ADR 0022 is superseded hard** (owner: *"ADR 22 must be superseded hard,
  these design sessions since it have brought a lot of good designs we are
  now working out"*). Survives: uncapped stacks; no per-tick clamp. Replaced:
  "stacks halve" → decay is authored per status on its def (Poison −1 flat,
  Weakness ×0.75, Greed none, Bleeding ×2-on-use then −1); "one DoT per
  defensive axis" → the placement rule plus *rows differ in character
  (trigger, decay, spread), never in numbers* — two flat-HP DoTs may coexist
  when their character differs (Exposed beside Poison). The ADR is written by
  the `adr` skill from these sentences (#1448).
- **Tags closed**, all four as proposed.
- **Pairs: a school's third row is its pair row** (pass lens, owner took it):
  two pure rows per school, a third that leans on a neighbour (Exposed =
  STR × INT), capping the table at 18 rows; duo content (a spell reading two
  statuses) stays the separate layer. Exploration: #1446.
- **Travel is an axis** any row picks from (in place, sandpile, spill, edge
  spread, hop, inward trail); Contagion is an infusion on it, never a row.
  **Bare axes stay bare by rule** ("defensive faces are rare"); Bunker and
  Fortress are the exceptions. **Addons outside the Matrix keep the de facto
  split**: afflictions here, structures in `skill_node_addons.md`, no parent
  categories. **No new `_resistance` stats**; where one exists or a blessed
  roll adds one, it scales the read effect by (1 − res) at effect time (ADR
  0031's shape). **Fortress / drag** stays on notice.
- **Codex** (owner): a uniform status tooltip, and *"a second page for effects
  in the spell catalog UI (making it about more than just spells, could be the
  main help with a page per game concept (`Manage` actions, each attack type,
  spells, statuses, addons, arrow types, the whole shebang)"* — a UI unit,
  #1447, not a Matrix decision.

**Owner calls, 2026-10-06 (round 10 — Bleeding reshaped in its `/swarmify` pass).**
Round 9's "pay `stacks` at turn end only if the node exerted" needed a per-node
flag carried to turn end; the owner moved the exertion effect to launch and the
damage to every turn, and the flag died.
- **Exertion doubles at launch, damage lands every turn end at a rate.** A node
  in an attack's origin set has its bleeding ×`exert_growth` (2) the moment the
  attack lands its first beat (the node is still alive then — owner: *"might be
  tricky with the attacking node possibly dying right as it fires"*); at turn end
  every bleeding row pays ⌈stacks × `bleed_rate`⌉ flat HP (½), then decays. The
  pass's table (5 stacks: launch 10, pay 5, →9; 18, pay 9, →17; 34, pay 17, →33)
  reproduces round 9's 5, 9, 17, 33, 65 exactly; resting pays 3, 2, 2, 1, 1 (≈
  half a Poison); a 1-stack scratch exerted every turn stays at 1 forever, a
  2-stack wound compounds. Owner: *"option 1. is good"*; the ⅓×allocation-level
  rate *"mechanics are.. for another status, not this one"*.
- **Ranged exerts by firing, never by reloading.** Owner: *"leaning just firing,
  leaving reloading alone (which is done by leaf nodes so far but possibly other
  nodes could later start producing arrows as well which might be problematic
  like "all your nodes" shouldn't trigger bleeding at once)"*. The origin set per
  mode stands as round 9 wrote it; the per-hit read node is the same attribution
  — owner: *"a magic cast has 1 source node doing the attack … easily
  attributable to that source node. a ranged volley has N leaf nodes partaking …
  each arrow fired has a clear source leaf node it got launched from. a melee
  attack is a pivot + a bunch of copied nodes. a copied node could hold a
  reference to the original for attribution."*
- **A core exerts by moving, once per turn, never by attacking.** Round 9's
  "pays on any turn it attacked" is withdrawn — owner: *"a stack of N means you
  gotta wait N turns before it's gone and you can start attacking again. that's
  crazy talk."* Movement: *"moving sounds good, once per turn could be
  manageable, more than that could get out of hand quickly."* A still core
  trickles at the rate; a fleeing core compounds — Bleeding is the anti-kite row.
  Per-hop ticking along the path was floated and set aside (*"maybe too
  convoluted"*).
- **Decay ramps while resting: −1, −2, −3 …, reset by exertion.** Owner chose
  the ramp over flat −1 and fractional; the row stores its *current decay step*,
  not turns rested — *"we track the current decay value and calculate the next
  from it, easy peasy"*. Reset (pass's call, owner asked *"reset to -1 on exert,
  or to 0?"*): exertion zeroes the step, so the exerting turn's own end tick
  decays −1 again. 33 stacks clear in 8 still turns for ≈90 HP.
- **Cauterizing spills with dissipation.** Owner's twist: *"spill everywhere,
  include unowned neighbors, but dissipate on arrival there … L and K are
  ignored, each of N gets floor(S/(N+M)) stacks"* — N owned, M unallocated,
  L enemy, K friendly-camp neighbours; the M shares soak into the ground, and
  a wound smaller than N+M vanishes (*"maybe we should allow vanishing;
  cauterizing hard to clear i guess"*). Including K was rejected as *"more a
  consideration for a viral or plague spreading type of status"*. **On a kill
  too, at half the share** (pass's call on the owner's *"different spill rates
  for graceful vs forced deallocation?"*, an exported fraction) — 1000 stacks on
  one node is a crisis to offload, not a guaranteed kill.
- **Open, parked:** Poison's own dealloc question (owner: *"whether we should let
  it stick on deallocation or clear it, and if not clearing, then the default
  unowned node ticking"*) — Poison row, not here.

## Twist library

Reusable knobs a cell shops from — each should land as an *"oh of course it
does that"* (owner, 2026-10-06: *"we should keep such knobs in mind, there's
more like it, where it could give special twists to spells to boost their
power in certain areas, especially areas that are under-boosted so far"*).

| Twist | What it does | Fits |
|---|---|---|
| Allocation-level scaling | effect × the node's allocation level (Rupture's idea); degenerate as a *status* today (~1% of nodes stake > 1) but a fine spell or addon twist | a spell boosting under-boosted areas; addon local modifiers (the house rule) |
| Non-owned-edge counting | effect or decay × edges to non-owned neighbours | Exposed; a decay cure |
| Origin-set reading | the attack's exerting nodes as the fact a status reads | Bleeding, Weakness, crit |
| Inward trail | a stack hops toward the core along the shortest owned path | Creep |
| Stacks as duration | −1 per turn, effect while > 0 | Silence's parked shape |
| Tesla relay (owner, round 9) | *"if you e.g. fire a 4-degree spell from a node, and your core is in range you get a boost, and if not directly in range but another equally cast-eligible (4-degree or more; same predicate as spell being cast) node of yours is, then you count the boost (or even more, or less, or depends entirely on spelldef knob for it including "off" entirely)"* — and bleed stacks halfway down the relay become a real threat if you keep casting from it; counterplay is repositioning the core or reshaping hubs by de/reallocation | a `SpellDef` knob; Bleeding's magic side |

## Combos and hybrids

Owner, 2026-10-05: *"for each concrete aspect we put out, we'd have content
for that aspect (content = arrow, addon, spell, spell infusion), and sometimes
more than 1 (maybe 2 spells or addons). Then it hit me: combos, or hybrid
mechanics. Think of: Hades' Duo boons: Each god has a few mechanics and Duo's
combine mechanics of 2 gods. Or Astral Ascent also clearly has a few
mechanics for each element, then layered with modifiers that target 2 of
these mechanics to gain interesting coverage and variety/content. Like i want
to explore these things."*

Round 9 lens (owner took it, 2026-10-06): a school's **third row is its pair
row** — see § Owner calls, round 9. Still open: whether a pair row (above) *is* the combo, or a combo is a separate
layer of content that reads two existing rows (a duo spell, an addon whose
rider needs two aspects on the board). #1251 (one hit, two aspects) is the
nearest existing fork.

**Candidate combo grammars (owner + advisor, 2026-10-05).** Owner: *"Primary
attrs as combo elements could be 1 option, other could be to declare e.g.
4-5 aspects as parent aspects to which any other aspects are childed. Sounds
less intuitive tho unless we find that perfect split. Or maybe theres other
layers i haven't considered yet"*. Layers on the table, none exclusive:

1. **Attributes** — the pair table above; vibe-only since addons grant no
   attributes.
2. **Parent aspects** — ADR 0022's "one DoT per defensive axis" (HP flat,
   bulk, floor, healing) is an existing non-arbitrary split for the DoTs; a
   new DoT childs under the axis it attacks or justifies a fifth. Covers DoTs
   only. Advisor proposal, 2026-10-05: **Affliction** as that parent (a
   `affliction_aspect` composing into the four DoT aspects, ADR 0029) — an
   umbrella in genre vocabulary, too generic to be its own row.
3. **Tags** — the Tag column as mechanic vocabulary; a combo is content that
   reads two mechanics (DoT × AoE, spread × retribution, reveal × DoT), the
   Hades duo / Astral Ascent shape. Pairs enumerate themselves; a tag that
   never pairs marks a weak concept.
4. **Facet** — concept × {arrow, addon, spell, infusion} is already a combo
   table.
5. **Trigger** — on-hit, on-tick, on-death / dealloc (curse spill),
   on-contact (detonation). Trigger × tag may be the smallest grammar.

## Addons outside the Matrix

The Matrix runs concept → facet; these addons run the other way — board
structure first, no status — so they have no row. Whether the Matrix splits
(afflictions vs. structures), keeps one table with per-kind facet rules, or
grows parent categories over both is **open** (owner, 2026-10-05: *"may need
a split. But I'm not sure which"*). Family grouping below is an advisor
proposal, 2026-10-05; the per-addon calls live in
[skill_node_addons.md](skill_node_addons.md).

| Family (proposed) | Addons | State |
|---|---|---|
| Fortify | Bunker (armor, floor, deflect), Fortress (`fortification_addon`: node health + swing drag; may be struck, see round 6) | both shipped; Reinforcement folded into Fortress |
| Survival | Lifeline, Lifelink, Fountain (heal / cleanse) | Lifeline may merge into Fountain; Lifelink keystone / core-class only. Anchor Node (`skill_node_specializations.md`, "a built-in Lifeline") is Lifeline's intrinsic variant or struck — unruled |
| Topology | Gate, Winch, Clamp | Clamp shipped; Gate landing; Winch has a determinism fork. Clamp is blade-build crafting more than board topology; Winch's Serpent relief is a class concern |
| Spell routing | Anti-Magic, Conduit, Relay, Void? | needs design. Anti-Magic (+1 hop cost through the node) is an addon, not a status, and never Silence's twin (owner, round 7). Owner shapes, 2026-10-06: a hop-nabbing "black hole, but less intense", a node that mangles its local `degree` to confuse degree-targeting spells, a projectile-eater (struck by the owner as unbalanced). Relay's damage bonus is spell power riding a routing addon |
| Growth | Skill Dust | shipped; technical — consumed on allocation, never persistent; a loot window (`begin_claim` / `offers_for`), not a placed addon. Owner: WIS-related (*"permanent growth"*) |
| — | Buffer | discontinued indefinitely (owner, 2026-10-05) |
| Coolness | the pure-coolness archetype | owner, 2026-10-06: its own low-weight procgen archetype rolling only coolness, rainbow-rim look; #1430. Not a school |

## Axes: attacked and defended

The 2026-10-05 misplacement sweep (four read-only agent passes reading every
mechanic against the rule) is folded in: each ruled line sits in its row's
Notes, the unruled ones in § Open, the stale facts on #1414. What remains is
its one table — Bunker and Fortress are the defender side of the status axes,
not a family of their own:

| Axis | Attacked by | Defended by |
|---|---|---|
| flat HP | Poison | Fortress (`node_health`) |
| bulk %HP | Corruption | nothing |
| damage floor | Curse | Bunker (`min_damage_taken` −5), Bulwark class |
| armor | Armor break | Bunker (`armor` +5) |
| healing | Wither | Lifeline / Fountain, `healing_beam` (enemy-targetable — its twist) |
| vision | Blindness | nothing |
| damage dealt | Weakness | nothing |
| exertion (HP on use) | Bleeding | nothing — rest is the cure |
| crit taken | Hex | nothing; attacker-side crit stats are DEX's own |
| status landing | Greed (more land) | `<family>_resistance` filters at effect time, not landing (ADR 0031) |
| tempo | nothing — no status attacks tempo (round 6) | nothing |

Whether bare axes stay bare on purpose is a call ("defensive faces are
rare"). Resistances exist only as blessed rolls; Scout, Explosive and Armor
break have none.

## Personas

Each aspect's personified character lives in
[aspect_personas.md](aspect_personas.md), designed separately on top of
this table's rows.

## Open

- Supply model: settled (#1248, closed).
- Attribute per concept: settled in § Attributes and pairs; #1249 keeps the
  content work (write it into [node_subtypes.md](node_subtypes.md), swap the
  procgen pools, and supply the six aspect stats that have no node source yet
  — `corruption`, `curse`, `wither`, `blindness`, `armor_break`, `explosive`).
- Can one hit carry two aspects (#1251).
- WIS status family: answered — Corruption and Greed (#1252 closes).
- Travel is an axis (Glossary) any row picks from — in place, sandpile, spill,
  edge spread, hop; Contagion would be an infusion on it, never a row. Pass
  proposal, unruled.
- `dealloc_damage` has no row; Creep (Contenders) is its candidate home; stale facts: #1414 (incl. `damage_over_time.md` still tabulating halving decay).
- Which row holds the anti-blade face: Explosive (owner lean, 2026-10-04) — barrels / friendly fire on #1399, the pop budget's fate on #1369; ADR 0005 would be superseded, not edited.
- Combos / hybrids: #1446; third row = pair row is the lens.
- The shipped spell `hex` applies Curse; it is renamed or repointed now that Hex is a row (Hex × Spell, #1443).
- The Edgelord jab "Bleeding Edge" is renamed now that Bleeding is a row (#1449).

Round 9 (2026-10-06) was the final design round; the table is now the cell swarm's basis.

Related: #1199 (the hub), #1317 (arrows), #1318 (addon + spell design), #1255 (status model: decay / spread / timing, #1256), #1211, #1212 (addons become scenes),
#1202, #1204, #1203, #1217, #971–#973, #395, #1200.
