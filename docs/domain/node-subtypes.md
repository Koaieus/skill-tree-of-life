# Node subtypes

A node carries two identities: its **archetype** (one of the six) and its
**subtype** — `regular`, `blight` or `bless`
(`procgen/subtypes/node_subtype.gd`, carried on `SkillNode.subtype`).
**Archetype picks the status family, subtype picks the pole**: blighted is the
family's offence, blessed its defence. Which pools each archetype × subtype
cell holds is authored in `procgen/pools/*.tres` and tabulated in
[procgen-v4.md](procgen-v4.md) § Seed table; open threads are in
[../design/node_subtypes.md](../design/node_subtypes.md). Opened from #1025,
built in #1056 and #1059–#1061, #1093–#1095.

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

## Decision numbers cited elsewhere

Code, rules and docs cite the owner's 2026-09-22/23 subtype decisions by
number. The ones still cited:

| # | Decision |
|---|---|
| 5 | PER's family is blindness; `scout_arrows_per_reload` stays shared by all three PER poles. |
| 8 | The subtype gate stays on `StatPool` after the archetype gate moved to `StatPack`: a pack is one archetype, but holds mixed subtypes (ADR 0028). |
| 11 | Blessed WIS gets a pool-shaped answer, never a budget multiplier — replace-not-add holds. |
| 13 | A rolled subtype with no drawable content demotes to the default. |
| 14 | `regular` is the global default (`NodeSubtype.regular()`, a lazy accessor); a preset may override it via `default_subtype`. |
| 16 | Partial coverage is authoring discipline, not a validated invariant (above). |
| 17 | Blighted WIS is the archive: `dot_stacks_per_hit`, the one cross-family umbrella; it gives up the small `xp_per_turn` pool. |
| 18 | Blessed WIS is the XP engine plus recovery (`wound_heal_per_turn`, a fatter `xp_per_turn`), replacing the small `xp_per_turn +%` pool. |
| 20 | Blindness potency is depth and commutative: one saturating curve on total power. |
