# The Aspect Matrix — every concept × every attack mode

> Design doc: the living table. Every status/concept must fill every column —
> Ranged (arrow), Addon, Magic (infusion) — each delivered through
> whatever hit kind the concept actually is (Scout is a status whose rows draw vision, not a damage
> status). An empty cell is a deliberate call written into the table, never
> a gap.

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

**The passes run transposed** (owner, 2026-10-02: *"Transpose by
column"*): each column has a different gate — arrows none, addons #1212,
infusion #1250 — and every row appends to the same three registries (ammo
roster, procgen content pools, spell catalog), so one branch per column
beats five per row. #1317 is the arrow pass for every statused concept.
The design passes now run **per cell** (owner, 2026-10-03, #1376: *"1 pass
per cell, sometimes groupable"*): one issue per concept × facet, grouped
under a row hub per concept; #1318's per-concept pass is superseded by them.

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
| Corruption | buildup, %dmg, spread | `corruption_aspect` | #1382 — scaffold (#1349) | #1383 | #1384 | #1250 | row: #1378. Spreads as a sandpile by nature (#1202); health bar shows blips per stack, extra-mean when critical (#1092) |
| Curse | fragility, spill | `curse_aspect` | #1385 — scaffold (#1349) | #1386 | `hex` shipped; no second spell proposed | #1250 | row: #1379. Raises `min_damage_taken`; spills to surviving direct neighbours on death AND dealloc (#1204) |
| Wither | anti-heal *(proposed)* | `wither_aspect` | #1387 — scaffold (#1349) | #1388 | #1389 | #1250 | row: #1380. Drives healing received negative |
| Blindness | vision debuff *(proposed)* | `blindness_aspect` | #1390 — scaffold (#1349) | #1391 | `dazzle` shipped; **Throw Sand** #1392 (candidate, owner 2026-09-30) | #1250 | row: #1253. Count stacks, effect reads as a % via a saturating curve |
| Scout (a status whose rows draw vision, #949) | reveal *(proposed)* | `scout_aspect` | scouting arrow shipped (stacks: #1345, #1346) | watchtower shipped (map face); blade face + look #1393 | #1394 | #1250 | row: #1254. `effects/status/scouted.tres` is live: the arrow lands camp-keyed stacks, VisionSystem draws `radius_for` discs from the rows (#1346); first-class concept (owner, 2026-09-30) |
| Armor break | armor debuff *(proposed)* | `armor_break_aspect` | #1395 — scaffold (#1349) | #1396 | `sunder` shipped; second spell #1397 | #1250 | row: #395 (child 0: penetration stat #1401). Flat −1 armor per stack, uncapped, can go below zero (#1203, owner 2026-09-30) |
| Explosive | AoE | `explosive_aspect` | #1398 | #1399 — detonation kills the blade node, reuses spike-pop plumbing (owner, #1211) | #1400 (or none) | #1250 | row: #1211. Euclidean hitscan radius from `SkillNode.radius`; barrels / friendly fire open (#1399). The concept names the content, never the reverse (owner, 2026-10-05): *"an explosive barrel blast would at best do an *explosive* (as a concept) blast, not an \"explosive arrow blast\" literally cuz it's not like *arrows* determine the concept but the concept determines arrows+addons+spells etc."* — so the addon is an `ExplosiveBarrelAddon` doing the explosive blast. A detonated blade node is *damaged*, and today that means popped: *"so far we put their HP on 1 so they pop after taking 1 dmg"* (owner, 2026-10-05) |

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
| Bleeding | DoT | DEX+STR? | TBD | spikes? (see Spikes) — look: tangential spikes rotating like a sawblade (owner, 2026-10-03) | TBD | Owner, 2026-10-05: *"Bleeding is an excellent game concept maybe too classic to pass up. And it's one that could naturally be a DoT. Would need a different profile, character (damage & mechanics, decay, tick trigger, spread mechanics if any) than poison"*. Earlier: *"what would bleeding mean in a graph-based game? leaking "skill point" essence until deallocated..?"* (2026-10-03) |
| Fatigue / Slow | debuff, movement | TBD | TBD | TBD | TBD | Owner, 2026-10-05: *"fatigue OR slow (or both): slows movement stat, possibly deallocation point stat too"* |
| Paralysis | debuff, AP | TBD | TBD | TBD | TBD | Owner, 2026-10-05: *"lowers action points cap?"* |
| Petrified | debuff, initiative | TBD | TBD | TBD | TBD | Owner, 2026-10-05: *"lowers initiative gain? (Iff we ever want to flesh out initiative some more, this would be one issue part of that"* |
| Thorns | retribution | TBD | TBD | TBD | TBD | Owner, 2026-10-05: *"canonically more for retribution dmg of incoming attacks back to attacker"*. Not built; today *"blade swings don't deal dmg to own nodes, no thorn dmg or anything (yet?)"* (owner, 2026-10-05). OQ32 in combat_system.md asks whether thorns and spikes share a stat |
| Spikes | offense | STR? | — | `spike_ring_addon.tscn`: local `blade_damage` (×1.5, +3), allocation-scaled per #1369 | — | **Not an aspect**: its defensive face (pop a blade vertex) has no ranged or spell meaning. Owner, 2026-10-05: *"spikes addon just adds blade damage. Switch to bleed stacks instead? (Or keep some blade dmg mods why not). Spikes do fit bleeding thematically. Though they also fit poison"*. The pop budget (`spikes`, `node_spikes`, `spike_regen`) is the #1369 fork; the owner leans to moving the anti-blade face to Explosive (2026-10-04: *"I think the explosive one thematically fits best"*), which would delete those stats |
| Blunting | — | — | — | today only a spiked node's +1 | — | Struck candidate: a counter to a counter, meaningless to an arrow or a spell. Dies with the pop budget if #1369 takes the explosive pivot (and #794 with it) |
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

| Attribute(s) | Row(s) today | Source |
|---|---|---|
| DEX | Poison | 2026-09-22 grid (#1249 open) |
| STR | Corruption; armor break / pierce | grid + owner 2026-09-29 |
| INT | Wither (grid) or Curse (2026-09-29) | #1249 open |
| CON | Curse (grid) or Wither (2026-09-29) | #1249 open |
| PER | Blindness, Scout | grid |
| WIS | none | #1252 open |
| PER+DEX | Scout's watchtower addon | owner 2026-10-05 |
| CON+STR | Armor break? | owner example, 2026-10-05 |
| DEX+STR | Bleeding? | owner example, 2026-10-05 |
| PER+WIS | Blindness? | owner example, 2026-10-05 |

Six singles plus fifteen pairs is twenty-one rows; the sparse-row discipline
above (merge, strike) is what keeps that from being a slot-filling exercise.

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
   only.
3. **Tags** — the Tag column as mechanic vocabulary; a combo is content that
   reads two mechanics (DoT × AoE, spread × retribution, reveal × DoT), the
   Hades duo / Astral Ascent shape. Pairs enumerate themselves; a tag that
   never pairs marks a weak concept.
4. **Facet** — concept × {arrow, addon, spell, infusion} is already a combo
   table.
5. **Trigger** — on-hit, on-tick, on-death / dealloc (curse spill),
   on-contact (detonation). Trigger × tag may be the smallest grammar.

## Personas

Each aspect's personified character lives in
[aspect_personas.md](aspect_personas.md), designed separately on top of
this table's rows.

## Open

- Supply model: settled (#1248, closed).
- Attribute archetype per concept: the 2026-09-22 grid in
  [node_subtypes.md](node_subtypes.md) (DEX poison, STR corruption, INT
  wither, CON curse, PER blindness/scout, WIS none) vs. the owner's
  2026-09-29 mapping (INT curse, CON wither, STR also armor break) —
  unresolved (#1249).
- Can one hit carry two aspects (#1251).
- WIS status family (#1252).
- Which row holds the anti-blade face: Explosive (owner lean, 2026-10-04) — barrels / friendly fire on #1399, the pop budget's fate on #1369; ADR 0005 would be superseded, not edited.
- Combos / hybrids and the attribute-pair rows (above): an exploration, no issue yet.

Related: #1199 (the hub), #1317 (arrows), #1318 (addon + spell design), #1255 (status model: decay / spread / timing, #1256), #1211, #1212 (addons become scenes),
#1202, #1204, #1203, #1217, #971–#973, #395, #1200.
