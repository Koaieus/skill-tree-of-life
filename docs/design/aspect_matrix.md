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
curse → fragility *("cuz raises damage floor?")*, spill. Tags marked
*(proposed)* were filled in by the same pass and await the owner's word.

## The Matrix

Each cell links its cell issue (`<Concept> × <Facet>`, a child of the row hub in Notes), or says shipped. Infusion is one issue for the whole column, #1250.

| Concept | Tag | Stat | Ranged (arrow) | Addon (map / temp) | Spell | Magic (infusion) | Notes |
|---|---|---|---|---|---|---|---|
| Poison | DoT | `poison_aspect` | shipped; look designed (see "Rows designed in #1318"), building in #1352 | #1271 — designed (see "Rows designed in #1318"), needs an acceptance spec | `venom` shipped; second spell #1381 | #1250 | row: #1377. Spread signature deferred to an authoring pass (owner, #1204) |
| Corruption | buildup, %dmg, spread | `corruption_aspect` | #1382 — scaffold (#1349) | #1383 | #1384 | #1250 | row: #1378. Spreads as a sandpile by nature (#1202) — no `spread` authored yet, the diffusion classes are test-only; health bar shows blips per stack, extra-mean when critical (#1092). `skill_node_specializations.md`'s Corrupted Node is this row's content under another name; its penalties (double damage, floor −1) are Curse's and the floor axis's |
| Curse | fragility, spill | `curse_aspect` | #1385 — scaffold (#1349) | #1386 | `hex` shipped; no second spell proposed | #1250 | row: #1379. Raises `min_damage_taken`; spills to surviving direct neighbours on death AND dealloc (#1204) — the only authored spread today (`spill_spread.gd`). `spells.md`'s Aftershock restates this spill |
| Wither | anti-heal *(proposed)* | `wither_aspect` | #1387 — scaffold (#1349) | #1388 | #1389 | #1250 | row: #1380. Drives healing received negative. `spells.md`'s Flood wants this anti-heal (#1389) |
| Blindness | vision debuff *(proposed)* | `blindness_aspect` | #1390 — scaffold (#1349) | #1391 | `dazzle` shipped; **Throw Sand** #1392 (candidate, owner 2026-09-30) | #1250 | row: #1253. Count stacks, effect reads as a % via a saturating curve |
| Scout (a status whose rows draw vision, #949) | reveal *(proposed)* | `scout_aspect` | scouting arrow shipped (stacks: #1345, #1346) | watchtower shipped (map face); blade face + look #1393 | #1394 | #1250 | row: #1254. `effects/status/scouted.tres` is live: the arrow lands camp-keyed stacks, VisionSystem draws `radius_for` discs from the rows (#1346); first-class concept (owner, 2026-09-30). Scout and Blindness are two PER rows by the owner's table, not one vision axis. Watchtower's offence stats and production-vs-firing: #1413 |
| Armor break | armor debuff *(proposed)* | `armor_break_aspect` | #1395 — scaffold (#1349) | #1396 | `sunder` shipped; second spell #1397 | #1250 | row: #395 (child 0: penetration stat #1401). Flat −1 armor per stack, uncapped, can go below zero (#1203, owner 2026-09-30). School CON (round 7). Has no `_stacks_per_hit` / `_resistance` while the DEX pool rolls a raw `armor` −% bane that bypasses the aspect. `spells.md`'s Heavy / Piercing Bolt (seek max / min armor) are its second spell (#1397) |
| Weakness | damage debuff | `weakness_aspect` | cell unfiled | cell unfiled | cell unfiled | #1250 | row: #@weak. Stacks cut damage dealt by attacks originating from the node, % on a saturating curve (round 7) |
| Greed | status magnet | `greed_aspect` | cell unfiled | cell unfiled | cell unfiled | #1250 | row: #@greed (child 0: the landing term, #@greed-land). One Greed stack on the node doubles every negative status the next hit lands, Greed included, then one stack is spent; Hoard pays bonus XP per stack left when an attack removes the node (rounds 5–6) |
| Explosive | AoE | `explosive_aspect` | #1398 | #1399 — detonation kills the blade node, reuses spike-pop plumbing (owner, #1211) | #1400 (or none) | #1250 | row: #1211. Euclidean hitscan radius from `SkillNode.radius`; barrels / friendly fire open (#1399). The concept names the content, never the reverse (owner, 2026-10-05): *"an explosive barrel blast would at best do an *explosive* (as a concept) blast, not an \"explosive arrow blast\" literally cuz it's not like *arrows* determine the concept but the concept determines arrows+addons+spells etc."* — so the addon is an `ExplosiveBarrelAddon` doing the explosive blast. A detonated blade node is *damaged*, and today that means popped: *"so far we put their HP on 1 so they pop after taking 1 dmg"* (owner, 2026-10-05). `spells.md`'s Detonate / Supernova are its spell (#1400) |

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
2026-10-05: *"adding sparse rows in the \"to be considered\" rows of the
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
| Bleeding | DoT | STR (owner, 2026-10-05) | TBD | spikes? (see Spikes) — look: tangential spikes rotating like a sawblade (owner, 2026-10-03) | TBD | Owner, 2026-10-05: *"Bleeding is an excellent game concept maybe too classic to pass up. And it's one that could naturally be a DoT. Would need a different profile, character (damage & mechanics, decay, tick trigger, spread mechanics if any) than poison"*. Earlier: *"what would bleeding mean in a graph-based game? leaking "skill point" essence until deallocated..?"* (2026-10-03). Edgelord's **Bleeding Edge** (combat_system.md) is a topology weapon sharing the name — one of the two renames when this row is filed. `dealloc_damage` (flat HP per force-deallocated node) sits on the dealloc trigger this row's "leak on dealloc" would use, owned by nobody yet |
| Silence | mute | INT | stacks of the status | stacks of the status | stacks of the status | **Back to contender (owner, 2026-10-06, round 7).** A node that can't originate an attack is a boolean at 1 stack; a flat −1 per stack on shots / pivot blade size / spell hops dies on `blade_size`'s 2-to-100+ range and on spells with under 5 hops (round 7). Returns when a graded mute shape turns up; the `min_degree` gate variant is parked with a smell note |
| Hex (jinx) | misfortune | — | — | — | — | Pass association, 2026-10-06, after the owner floated `hex` as a future concept: a chance per stack that a hit from the node misfires, or that crits roll against the holder — the variance debuff nobody holds; partner for the Crits milestone. The shipped spell `hex` keeps its name until this is a row |
| Fatigue / Slow | — | — | — | — | — | **Struck (owner, 2026-10-06)** with Paralysis, *"the whole tardy bunch"*: movement and dealloc are entity pools with no node-local meaning, and a per-node cost deadlocks chokepoints while the nodes worth slowing sit out of reach (round 5) |
| Paralysis | — | — | — | — | — | **Struck (owner, 2026-10-06)** with Fatigue / Slow. An AP-cap cut also sits on core-class territory (the Pacifist ruling) |
| Spikes | offense | STR? | — | `spike_ring_addon.tscn`: local `blade_damage` (×1.5, +3), allocation-scaled per #1369 | — | **Not an aspect**: its defensive face (pop a blade vertex) has no ranged or spell meaning. Owner, 2026-10-05: *"spikes addon just adds blade damage. Switch to bleed stacks instead? (Or keep some blade dmg mods why not). Spikes do fit bleeding thematically. Though they also fit poison"*. The pop budget (`spikes`, `node_spikes`, `spike_regen`) is the #1369 fork; the owner leans to moving the anti-blade face to Explosive (2026-10-04: *"I think the explosive one thematically fits best"*), which would delete those stats |
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
| STR | Bleeding, Weakness | Bleeding: owner 2026-10-05. Weakness: owner 2026-10-06 (round 7) |
| DEX | Poison, Explosive | owner 2026-10-05 |
| INT | Curse; one open slot | Curse: owner 2026-09-29. Silence went back to Contenders (owner, 2026-10-06, round 7); the slot waits, like CON's did, for an idea that fits |
| CON | Wither, Armor break | Wither: owner 2026-10-05. Armor break: owner 2026-10-06 (round 7), *"it straddled STR+CON thematically anyway"* |
| PER | Scout, Blindness | owner |
| WIS | Corruption, Greed | Corruption: owner 2026-10-05. Greed: closed round 6 (owner); row #@greed |

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
  arrow cell. Stat `weakness_aspect`, status *weakened*. Row #@weak.
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
  Not a school: it still has no verb and no row. Filed as #@cool.
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

## Combos and hybrids

Owner, 2026-10-05: *"for each concrete aspect we put out, we'd have content
for that aspect (content = arrow, addon, spell, spell infusion), and sometimes
more than 1 (maybe 2 spells or addons). Then it hit me: combos, or hybrid
mechanics. Think of: Hades' Duo boons: Each god has a few mechanics and Duo's
combine mechanics of 2 gods. Or Astral Ascent also clearly has a few
mechanics for each element, then layered with modifiers that target 2 of
these mechanics to gain interesting coverage and variety/content. Like i want
to explore these things."*

Open: whether a pair row (above) *is* the combo, or a combo is a separate
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
| Coolness | the pure-coolness archetype | owner, 2026-10-06: its own low-weight procgen archetype rolling only coolness, rainbow-rim look; #@cool. Not a school |

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
- `dealloc_damage` has no row (see Bleeding's note); stale facts: #1414.
- Which row holds the anti-blade face: Explosive (owner lean, 2026-10-04) — barrels / friendly fire on #1399, the pop budget's fate on #1369; ADR 0005 would be superseded, not edited.
- Combos / hybrids and the attribute-pair rows (above): an exploration, no issue yet.

Related: #1199 (the hub), #1317 (arrows), #1318 (addon + spell design), #1255 (status model: decay / spread / timing, #1256), #1211, #1212 (addons become scenes),
#1202, #1204, #1203, #1217, #971–#973, #395, #1200.
