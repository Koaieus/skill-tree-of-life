# SkillNode central emblem — the register model

How a SkillNode's central identity glyph is decided and drawn. The throughline:
**a node's identity is several dimensions that can be true at once** (an INT node
can host a core *and* grant a spell *and* be a keystone), so they're assigned to
independent **visual registers** rather than fighting over one slot.

Code: `skill_node/visuals/emblem/` — `emblem_spec.gd`, `emblem_resolver.gd`,
`carve_shape.gd` + `polygon_carve_shape.gd` / `gem_carve_shape.gd` /
`texture_carve_shape.gd`, `carve_atlas.gd`, `shapes/*.tres`,
`core_sigil_bloom.{gd,tscn}`; an archetype's fallback shape is
`Archetype.carve_shape` (`archetypes/archetype.gd`). Tests:
`test/unit/test_emblem_resolver.gd`, `test/unit/test_core_sigil_bloom.gd`.

## The four registers

Independent channels, all potentially lit on one node:

1. **Gem body (dome + rim)** — archetype (rim tint) + ownership (disk
   `entity_tint`, lit/dark by allocation). The existing InnerDisk/RimRing stack;
   See [skillnode-visuals.md](skillnode-visuals.md).
2. **The CARVE slot** — one height-field dent in the dome, the node's intrinsic
   payload identity. **Single winner, chosen by priority.**
3. **The BLOOM overlay** — additive, animated, entity-tinted glow layered *over*
   the carve. **Many may coexist; they never compete for the carve.** Core
   presence lives here: the core-class `Sigil` rendered as a glowing emblem.
4. **Rim/badge pips** — the stake dial (RimRing's `fill_current`/`fill_max`) +
   optional count pip (e.g. "2" for a multi-grant node). Not part of the emblem
   protocol.

Registers 2 and 3 are what `EmblemSpec` / `EmblemResolver` arbitrate.

## CARVE vs BLOOM — the core distinction

`EmblemSpec.Register` is the whole reason the model works:

- **CARVE** = the single height-field dent. Sources contend; the highest
  `priority` wins. This is where "what payload does this node carry" is read.
- **BLOOM** = additive entity-tinted glow, drawn on top. No contention — every
  BLOOM draws. This is how core presence rides *alongside* a carved spell/loot
  glyph on the same node without conflict (core + spell = sigil-bloom haloing a
  spell carve).

The CARVE priority ladder (`EmblemSpec.Priority.*`, higher wins):

```
KEYSTONE (40)  >  LOOT (30)  >  SPELL (20)  >  ARCHETYPE (10)  >  (empty dome)
```

- **KEYSTONE** — bespoke, most specific.
- **LOOT** — a consumed one-off; outranks spell so a looted node shows the loot
  glyph until allocation consumes it, then falls back.
- **SPELL** — a granted spell's icon.
- **ARCHETYPE** — the fallback shape, read from `SkillNode.archetype`
  (an [Archetype] resource — `archetype.carve_shape.carve()`). Lowest
  priority and **toggleable by simply declining to contribute it**: a null
  `archetype` contributes nothing, so archetype identity otherwise lives in the
  rim hue.
- **empty dome = an ordinary node.** A carve means "this node has a payload worth
  noticing." That default is the design intent, not an accident.

BLOOM carries no meaningful priority (they're additive, order-independent).

## The coordination architecture — SkillNode stays ignorant

The point of the protocol is **dependency inversion**: sources contribute emblem
candidates; a resolver in the visual layer picks. `SkillNode` never references
loot, SkillDust, spells, or keystones — it just aggregates specs. This mirrors
the existing `get_node_effects()` / `get_addon_tooltip_sections()` aggregation.

```
each source        -> EmblemSpec (register + priority + the CarveShape itself)
SkillNode          -> get_emblem_contributions() = own(archetype/effects) + addons' get_emblem()
EmblemResolver     -> Resolution { carve, carve_ties, blooms }   # pure, scene-free
renderer           -> draws the one carve + every bloom
```

- `EmblemResolver.resolve(contributions)` is **pure** — give it specs, get a
  `Resolution`. It picks the max-priority CARVE, collects CARVEs tied at that
  priority into `carve_ties`, and appends every BLOOM. It does **not** know how
  to combine ties — a multi-spell node's cross-fade/split strategy is the
  *renderer's* job, not the resolver's. Keep it that way.
- **A CARVE spec holds the `CarveShape` itself, not a copy of its fields.** There
  is one CARVE ctor, `EmblemSpec.carve(shape, priority, source)`, reached through
  `CarveShape.carve(priority, source)`, so a new parameter on a shape family is one
  edit on that shape. `sigil` is its own field: a `Sigil` is a BLOOM, not a
  `CarveShape`, and `sigil_bloom` sets the register + tint defaults for it.
- **`InnerDisk.CarveKind` (`NONE`/`POLYGON`/`GEM`/`TEXTURE`) is the shader's int
  branch selector**, needed for the batched instance uniform. The renderer
  dispatches on the shape's own type (`if shape is PolygonCarveShape`) and maps to
  its `CarveKind` locally. `skill_node/visuals/emblem/` knows nothing about
  `InnerDisk`: no `shader_kind()`, no `apply_to(disk)`.
- **A null `shape` is not "no contribution."** A keystone or spell grant with no
  `carve_shape` authored still contributes at its rung, carrying a null shape,
  and renders as an empty dome. Contributing nothing instead would let the
  archetype fallback win and dress a keystone node up as a plain territory node.
- **`priority` and `source_kind` are two independent fields**, and the ladder
  (`EmblemSpec.Priority`) is not 1:1 with the source: a rung is
  shareable (`node_visuals_composite.gd` contributes `&"authored"` at
  `Priority.ARCHETYPE`, and `carve_ties` exists precisely to model ties).
  `source_kind` is purely descriptive — tie-break debugging, tooltip copy.


## BLOOM rendering — CoreSigilBloom

`CoreSigilBloom extends SkillNodeVisual` draws a `Sigil` as an additive,
entity-tinted, pulsing glow — "this node is the entity's core, right here." It
reads `entity_tint` (ownership) and uses a **shared** `CanvasItemMaterial`
(`BLEND_MODE_ADD`) built lazily in a `static var`, mirroring the family's
shared-material convention; the base class's `_validate_property` keeps
`material` out of the saved scene. Glow = stacked outward polylines at falling alpha
(additive summation reads as bloom); core = near-white-but-entity-tinted fill.

**LOD split:** the on-graph node draws this glowing silhouette; the hero
card/tooltip draws the fully shaded sigil. Same sigil, two fidelities — never
absent. The on-graph sigil is a shared additive glow, not a per-instance
arbitrary carve, which keeps batching intact.

Core presence — the `CorePresence` slot that holds the bloom and the owner's core
look, and how it glides on a core move — is in
[skillnode-visuals.md](skillnode-visuals.md) (Core presence).

## The `preload`-not-`class_name` gotcha

Emblem cross-references use `const Foo = preload("res://…/foo.gd")`, not the bare
`class_name`, so the code parses before the editor rebuilds its global class cache
(see [godot-workflow.md](../../.claude/rules/godot-workflow.md)). Tighten to bare
`class_name` types only after a deliberate `mise run refresh`.

## Bake substrate

Arbitrary art (spell icons) reaches the CARVE slot as a baked LUT packed into a
shared `sampler2DArray` and indexed by an instance-uniform slice: see
[emblem-bake.md](emblem-bake.md).
