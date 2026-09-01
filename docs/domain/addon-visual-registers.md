# Addon visual registers — plan, elevation, or elsewhere

Where a `SkillNodeAddon`'s visual goes, and why "put the icon on the node" is
the wrong answer three times running. Companion to
[skillnode-emblem.md](skillnode-emblem.md) (which owns the *central* registers)
and `.claude/rules/skill-node-addons.md` (which carries the short version).

## The centre is not available

The middle of the disk is the **CARVE** slot — a single-winner register where
`KEYSTONE(40)` / `LOOT(30)` / `SPELL(20)` all outrank anything an addon could
contribute. An addon routing its visual through `get_emblem()` as a CARVE is
therefore invisible on exactly the loaded nodes worth caring about: bunker a
spell node and the bunker disappears. BLOOM is available (additive, no
contention) but is an entity-tinted *glow*, which suits presence and payload,
not armour.

So addons draw their own geometry outboard of the emblem. That is what SpikeRing
always did, and as of 2026-09-01 what Bunker, Fortification and Watchtower do.

## Why the sprite keeps coming back

The tooltip icon is right there on the addon (`SkillNodeAddon.icon`), so pasting
it into a `Sprite2D` at the origin looks like the cheap correct move — all three
of the above shipped that way. Two faults, not one:

1. **Register clash** — it sits on the busiest, most contended pixels on the node.
2. **Projection clash** — the icons (`mapping.txt`: `bunker-assault`,
   `defensive-wall`, `watchtower`) are *buildings in elevation*: ground line,
   vertical axis, read from the side. The gem is a dome lit from above. A
   side-view building laid flat over it reads as a UI sticker, not an object.

## Which register — decided by what the addon does

**Shell** (changes what the node is made of) -> **plan**, a concentric band past
the rim. Bunker's `armor` + `min_damage_taken` floor, Fortification's
`node_health`.

**Structure** (built on the territory, projects outward) -> **elevation**,
standing on the rim on a bearing. Watchtower's `vision_range` / `range`.

**Neither** is legitimate — Clamp draws nothing on the carrier and thickens its
incident `Edge`s instead (`graph/edge.gd`'s `_clamp_code`).

The split is a rule, not a compromise between two looks: it is the difference
between "this node is armoured" and "this node has a building on it", and it
tracks the mechanics (local defensive stats vs. outward projection).

## The plan-view band budget

Bands stack — a node can carry all of these at once — so each claims a radius
range as a fraction of `SkillNode.radius` and documents it:

| Addon | Band | Elements | Hue |
|---|---|---|---|
| Bunker | `[0.90, 1.12]` (overlaps the rim) | 4 chamfered plates | dark cool body, bright bevel |
| Fortification | `[1.14, 1.36]` | 12 merlons over a dark curtain | cool chrome |
| SpikeRing | `[1.00, 1.45]` | 12 radial spikes | owner colour |

**Separate neighbours by tone as well as by geometry.** Element count is
unreadable at zoom; two mid-grey bands at adjacent radii read as one crust
however different their silhouettes are up close. Bunker/Fortification separate
by *value* — dark plate bodies over the rim, bright teeth outboard of it.

**A band that overlaps the rim must be judged against BOTH rim states.**
`rim_ring.gd` blends a bronze `BASE_COLOR` toward `archetype_tint` when the node
is allocated and dims to silver when it isn't. Bunker's first cut was warm
gunmetal: it separated cleanly from the dim silver rim in every preview shot and
then vanished into the bronze one. Since procgen puts addons on content nodes
and players fortify their own territory, **allocated is the primary case**, and
an unallocated-only preview cannot show the failure. The fix is hue or radius,
never brightness — brightening re-breaks the non-emissive intent below.

Shared polygon builders (`annular_sector` with an outer chamfer, the shadow
translate, the house light direction) live in `skill_node/addons/addon_geometry.gd`.
They are statics on their own class rather than on `SkillNodeVisual` because
addons are **not** part of the `node_visuals_composite` family — they hang off
the `SkillNode` directly and are driven by `configure_visual`, not by the
composite's identity fan-out, so borrowing that base class's statics would imply
a membership that doesn't exist.

## Elevation: straight up is taken

`skill_node.tscn` parks `HealthBar` at y −59..−46 and `CoreHealthBar` at
y −44..−28, both spanning x ±35, and `FloatAnchor` at (0, −50). Watchtower's
default `stand_bearing_deg = 45` puts its whole silhouette below y ≈ −21. Check
this before moving a structure upward.

An elevation piece needs a **contact shadow** at its footing, and should plant
just inside the rim (`_STAND_RADIUS = 0.94`) — without both it reads as pasted
over the node rather than standing on it.

Note the positioning contract still holds: the addon's own transform stays
identity. The bearing offset is baked into the drawn geometry, not into the root.

## Judge it at three zooms, on a dark unallocated node

Both defensive addons passed at 3x and failed at distance on the first cut:

- Bunker at `[1.00, 1.10]` was a ~3px band of dark steel abutting the node's own
  dark rim — it rendered as very nearly nothing. Fixed by widening it *over* the
  rim and warming/brightening the lit end.
- Fortification at 16 merlons collapsed into a dotted line. Fixed with 12 chunkier
  merlons and a much darker curtain, so the teeth have something to contrast with.

Bold closed fills survive minification; thin many-part detail fragments (the same
point `.claude/rules/icon-assets.md` makes about baked icons). Build the shape out
of fills, and let the fine detail — Watchtower's X-bracing, Bunker's firing slits
— be what fades.

**Preview surface:** the sandbox host's **Node Visuals** tab
(`skill_node/visuals/panel/node_visuals_panel.tscn`) carries one slot per
structure addon plus an all-four crowding check. A headless `mise run check`
cannot validate any of this — it needs a real frame.

## Deliberately non-emissive

Bunker keeps every colour under 1.0 so it never enters the bloom pass
(`.claude/rules/hdr-color.md`). On a board where payload and identity announce
themselves with light, armour is the thing that absorbs it — and it should not be
the brightest object on its own node.

## Not yet built

Fortification's `node_health` is a resource that gets *consumed*, so the wall
could chip and lose merlons as the node takes damage. Deferred: it needs a
health-change hook on the addon and a redraw path. Worth doing — a shelled wall
is a better object than a static one.
