# The Aspect Matrix — every concept × every attack mode

> Design doc: the living table. Every status/concept must fill every column —
> Ranged (arrow), Addon, Magic (infusion) — each delivered through
> whatever hit kind the concept actually is (Scout is a reveal, not a damage
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

## The Matrix

Each cell links its cell issue (`<Concept> × <Facet>`, a child of the row hub in Notes), or says shipped. Infusion is one issue for the whole column, #1250.

| Concept | Stat | Ranged (arrow) | Addon (map / temp) | Spell | Magic (infusion) | Notes |
|---|---|---|---|---|---|---|
| Poison | `poison_aspect` | shipped; look designed (see "Rows designed in #1318"), building in #1352 | #1271 — designed (see "Rows designed in #1318"), needs an acceptance spec | `venom` shipped; second spell #1381 | #1250 | row: #1377. Spread signature deferred to an authoring pass (owner, #1204) |
| Corruption | `corruption_aspect` | #1382 — scaffold (#1349) | #1383 | #1384 | #1250 | row: #1378. Spreads as a sandpile by nature (#1202); health bar shows blips per stack, extra-mean when critical (#1092) |
| Curse | `curse_aspect` | #1385 — scaffold (#1349) | #1386 | `hex` shipped; no second spell proposed | #1250 | row: #1379. Raises `min_damage_taken`; spills to surviving direct neighbours on death AND dealloc (#1204) |
| Wither | `wither_aspect` | #1387 — scaffold (#1349) | #1388 | #1389 | #1250 | row: #1380. Drives healing received negative |
| Blindness | `blindness_aspect` | #1390 — scaffold (#1349) | #1391 | `dazzle` shipped; **Throw Sand** #1392 (candidate, owner 2026-09-30) | #1250 | row: #1253. Count stacks, effect reads as a % via a saturating curve |
| Scout (a reveal, #949) | `scout_aspect` | scouting arrow shipped (stacks: #1345, #1346) | watchtower shipped (map face); blade face + look #1393 | #1394 | #1250 | row: #1254. `effects/status/scouted.tres` is live (VisionSystem's decay rule); first-class concept (owner, 2026-09-30) |
| Armor break | `armor_break_aspect` | #1395 — scaffold (#1349) | #1396 | `sunder` shipped; second spell #1397 | #1250 | row: #395 (child 0: penetration stat #1401). Flat −1 armor per stack, uncapped, can go below zero (#1203, owner 2026-09-30) |
| Explosive | `explosive_aspect` | #1398 | #1399 — detonation kills the blade node, reuses spike-pop plumbing (owner, #1211) | #1400 (or none) | #1250 | row: #1211. Euclidean hitscan radius from `SkillNode.radius`; barrels / friendly fire open (#1399) |

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

## Contenders

Not yet promoted into the Matrix proper — fill cells when a good idea shows up.

| Concept | Stat | Ranged (arrow) | Addon | Magic (infusion) | Notes |
|---|---|---|---|---|---|
| Spikes | `spike_aspect` (if promoted) | TBD | `spike_ring_addon.tscn` (×1.5 local `blade_damage` + stake-scaled `spikes`) | TBD | owner estimate ~×4.5 damage at 3/3 allocation, unmeasured |
| Blunting | `blunting_aspect` (if promoted) | TBD | today only a spiked node's +1 | TBD | — |
| Bleeding | `bleed_aspect` (if promoted) | TBD | look: tangential spikes rotating like a sawblade (owner, 2026-10-03) | TBD | owner: *"what would bleeding mean in a graph-based game? leaking "skill point" essence until deallocated..?"* |

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

Related: #1199 (the hub), #1317 (arrows), #1318 (addon + spell design), #1255 (status model: decay / spread / timing, #1256), #1211, #1212 (addons become scenes),
#1202, #1204, #1203, #1217, #971–#973, #395, #1200.
