# Node subtypes

A node carries two identities: its **archetype** (one of the six) and its
**subtype** — `regular`, `blight` or `bless`
(`procgen/subtypes/node_subtype.gd`, carried on `SkillNode.subtype`).
**Archetype picks the status family, subtype picks the pole**: blighted is the
family's offence, blessed its defence. Which pools each archetype × subtype
cell holds is authored in `procgen/pools/*.tres` and summarised in
[procgen-v4.md](procgen-v4.md) § Pack homes; open threads are in
[../design/node_subtypes.md](../design/node_subtypes.md). Opened from #1025,
built in #1056 and #1059–#1061, #1093–#1095.

## The school table (#1249)

The six primaries are the schools; an aspect sits in the school whose verb it
performs (a loose, geographic coupling — ADR 0059, no free scaling). The pack
carries the school's blighted **potency** (`<aspect>_stacks_per_hit`) where the
aspect has one, and every aspect's **supply** (`<aspect>_aspect`, regular +
blight) in its own pack.

| School | Aspects | Potency in pack | Supply in pack |
|---|---|---|---|
| STR | Bleeding, Weakness | none yet | `bleeding_aspect`, `weakness_aspect` |
| DEX | Poison, Explosive, Mark | poison | `poison_aspect`, `explosive_aspect`, `mark_aspect` |
| INT | Curse, Hex | curse | `curse_aspect`, `hex_aspect` |
| CON | Wither, Sunder | wither | `wither_aspect`, `sunder_aspect` |
| PER | Scout, Blindness | blindness | `scout_aspect`, `blindness_aspect` |
| WIS | Corruption, Greed | corruption (+ `dot_stacks_per_hit`, a different stat) | `corruption_aspect`, `greed_aspect` |

Resistances did not move: `corruption_resistance` stays blessed STR's.

## The authoring law

**A subtype replaces, never adds.** Every subtype is a sidegrade: blighted DEX
gains the poison offence and gives up crit chance. A subtype that only added
would be strictly better and make `regular` filler, so a gated pool always
trades against something the other poles keep.

What a subtype may draw and what it gives up are one fact, stated per pool by
`StatPool.subtypes` (`[]` = every subtype). Three authoring rows:

| want | author | copies |
|---|---|---|
| the same for every subtype (the attribute ladder) | `subtypes = []` | none |
| present for some, absent for others, identical where present | `subtypes = [regular, bless]` | none |
| present for several at different values or weights | one pool per value, each gated | yes |

**Leave the shared ladder at `[]` and gate only the flavour** (decision 16).
This is discipline, not a validated invariant: copy a pool to
`[regular, bless]`, forget `blight`, and blighted nodes silently lose that
content — the demotion below does not catch it. A coverage warning was
considered and declined; revisit if row 3 is ever authored.

## Placement

One weighted roll per archetype-bearing node, off its own salted stream: each
weighted `NodeSubtype` carries a `base_chance`, the default subtype takes the
remainder (`GraphProcgenContent.subtypes`, `default_subtype`). A rolled
subtype **demotes to the default** unless some pool reachable from that
archetype names it (`GraphProcgen._build_subtype_drawability`), so the grid may
be ragged anywhere without a node looking blighted and playing regular.

## Drawing

The subtype tint composes into the node's existing `modulate` chain and
`bless` takes an emissive tier; see `NodeSubtype.tint` / `emissive_tier`.
`rim_ring.gdshader` has no `TIME` on purpose — an animated subtype stripe
would need a per-node phase, which is another instance-uniform slot.

## Roll passes (#1697)

A node's draw is the **budget pass** (the spend-until-broke loop) plus any
**extra passes** its subtype names in `NodeSubtype.extra_passes`, each a
`RollPass { id, chance }`. A pool joins passes through `StatPool.passes`:
**`[]` = the budget pass only** (every pool that predates passes); otherwise it
rolls in the budget loop iff the list holds `&"budget"`
(`StatPool.BUDGET_PASS`) and in extra pass X iff it holds X
(`StatPool.admits_pass`, the third key of `ModifierPoolSet.flatten_for_node`
beside archetype and subtype).

An extra pass runs after the budget loop, on the same seeded rng, in array
order (a replay input): `randf() < chance`, then **one** weighted pick through
`_v4_weighted_pick` with cost ignored. It spends no budget, the subtype and
archetype gates still apply, a pass with nothing eligible rolls nothing, and a
stat rolled in both passes stacks through the aggregator.

Shipped: `blight` carries `supply` at chance 1.0, and the twelve
`<aspect>_aspect` entries list `[&"budget", &"supply"]` — supply stays in the
budget draw and blight adds one roll of it on top. This is the one deliberate
**add** beside the authoring law's replace: the owner wanted blighted ground to
be where supply comes from (2026-10-19). Drawability (D13) is judged on the
budget pass only. Tuning: #1529.

## Decision numbers cited elsewhere

Code, rules and docs cite the owner's 2026-09-22/23 subtype decisions by
number. The full log is `docs/design/node_subtypes.md` at `179054c`; each
number still cited resolves to where it is embodied now:

| # | Settled in / embodied by |
|---|---|
| 5 | #1095; `procgen/pools/perception.tres` |
| 8 | ADR 0028 |
| 11 | #1093; `procgen/pools/wisdom.tres` |
| 12 | `StatPool.subtypes`; § The authoring law |
| 13 | § Placement; `GraphProcgen._build_subtype_drawability` |
| 14 | `NodeSubtype.regular()`, `GraphProcgenContent.default_subtype` |
| 16 | § The authoring law |
| 17 | #1094; `procgen/pools/wisdom.tres` |
| 18 | #1093; `procgen/pools/wisdom.tres` |
| 20 | `effects/status/blindness.gd` |
