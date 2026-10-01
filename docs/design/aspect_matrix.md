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
beats five per row. #1317 is the arrow pass for every statused concept;
#1318 is the per-concept addon + spell design pass that then files the
addon and spell column units.

## The Matrix

| Concept | Stat | Ranged (arrow) | Addon (map / temp) | Magic (infusion) | Notes |
|---|---|---|---|---|---|
| Poison | `poison_aspect` | shipped (each reload mints `poison_aspect` poison arrows, #1248) | `toxin_addon.tscn` (on shared `dot_addon.gd`) — a stub, **redone in #1318** to the SpikeRing standard (look: #1271) | spells `venom`, `bruiser`; infusion #1250 | spread signature undecided (#1204) |
| Corruption | `corruption_aspect` | #1317 | #1318 | #1250 | spreads as a sandpile by nature (#1202); health bar shows blips per stack, extra-mean when critical (#1092) |
| Curse | `curse_aspect` | #1317 | #1318 (spell `hex` shipped) | #1250 | raises `min_damage_taken`; spills to surviving direct neighbours on death AND dealloc (#1204) |
| Wither | `wither_aspect` | #1317 | #1318 | #1250 | drives healing received negative |
| Blindness | `blindness_aspect` | #1317 | #1318 (spell `dazzle` shipped) | candidate: **Throw Sand** spell (owner, 2026-09-30) — row: #1253; infusion #1250 | count stacks, effect reads as a % via a saturating curve |
| Scout (a reveal, #949) | `scout_aspect` | scouting arrow (shipped) | watchtower addon (shipped); temp: lit blade node pushing back fog (owner pitch, perf-sensitive: one moving mark per blade, never a second vision path) | TBD (#1254) | `effects/status/scouted.tres` is live (VisionSystem's decay rule); first-class concept (owner, 2026-09-30) |
| Armor break | `armor_break_aspect` | #1317 | #1318 (spell `sunder` shipped) | #1250 (#395 holds the design) | flat −1 armor per stack, uncapped, can go below zero (#1203, owner 2026-09-30) |
| Explosive | `explosive_aspect` | explosive arrow (#1211) | explosive addon, procgen at low rate; detonation kills the blade node, reuses spike-pop plumbing (#1211) | stub (#1211) | euclidean hitscan radius from `SkillNode.radius`; barrels / friendly fire open (#1211) |

## Contenders

Not yet promoted into the Matrix proper — fill cells when a good idea shows up.

| Concept | Stat | Ranged (arrow) | Addon | Magic (infusion) | Notes |
|---|---|---|---|---|---|
| Spikes | `spike_aspect` (if promoted) | TBD | `spike_ring_addon.tscn` (×1.5 local `blade_damage` + stake-scaled `spikes`) | TBD | owner estimate ~×4.5 damage at 3/3 allocation, unmeasured |
| Blunting | `blunting_aspect` (if promoted) | TBD | today only a spiked node's +1 | TBD | — |

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
