# Aspect spirits

A **spirit** is a neutral landmark node carrying a one-round skill-dust relic
whose only offer is `+1 <aspect>_aspect`. The first entity to allocate it
absorbs the grant into its core register (persistent, lootable on its death);
the relic then frees itself, so a later allocator gets nothing.

| Piece | Owns |
|---|---|
| `skill_node/keystone/spirit_node.gd` (`SpiritNode`) | which aspect, the tint, filling the relic's offer |
| `skill_node/addons/defs/skill_dust_addon.tscn` (child of the spirit scene) | the offer and the claim — the ordinary relic path |
| `procgen/modules/first_level/content.tres` (`sp_spirit`, `sp_mystery_spirit`) | where, how many, min hops from starters |

## Faced and mystery

- `spirit_node.tscn` — the dust wears the aspect's `Identity.tint`
  (`gold_color`, `victim_tint_mix` 0).
- `mystery_spirit_node.tscn` inherits it with `reveal_on_claim = true`: the dust
  is `mystery_color` (gray) and `SkillDustAddon.conceal_offer` empties its
  tooltip. The offer itself is the same; it shows when the grant lands.

## The aspect is a function of position

`SpiritNode.aspect` is `fixed_aspect` if authored, else a pick from `aspects`
(the 12 aspect identities) seeded by the node's whole-pixel position. A join
rebuilds the node from `GraphSnapshot` by scene path and position by value, so
the joiner rolls the same aspect with nothing extra on the wire. A claimed
spirit crosses without its relic (`_reconcile_addons` compares addon scene
paths). The rolled offer is derived in `_ready` and never in the editor, so it
cannot serialize back into the scene.

## Adoption

A dropped relic is adopted by `LootSystem` when it drops; a hand-placed one has
no drop. The spirit scene authors its dust child into the
`SkillDustAddon.HAND_PLACED_GROUP` group, and `LootSystem` adopts members of it
already in the tree at `_ready` and as they enter (`SceneTree.node_added`).
`adopt_relic` is idempotent.

## Placement

Ordinary `ScenePlacement`s, listed after every other landmark so the extra
`scene_rng` draws shift nothing before them. Dormant Core footprints never
grow onto an authored-scene node, so a spirit is never inside one.

Knobs (tentative): `sp_spirit` 3-6 at `min_hops_from_starter` 3,
`sp_mystery_spirit` 0-2 at 4; `SpiritNode.aspect_count` 1,
`SpiritNode.mystery_color`.
