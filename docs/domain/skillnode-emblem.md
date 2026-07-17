# SkillNode central emblem — the register model

How a SkillNode's central identity glyph is decided and drawn. The throughline:
**a node's identity is several dimensions that can be true at once** (an INT node
can host a core *and* grant a spell *and* be a keystone), so they're assigned to
independent **visual registers** rather than fighting over one slot.

This is the durable contract. It was hashed out in a working session and first
captured in `SKILLNODE_EMBLEM_HANDOFF.md` — a **temp file slated for deletion**
once its issue-actions are applied, which is exactly why the contract lives here
instead. Design rationale + open issue-actions stay in the handoff while it
exists; the code-facing model lives here.

Code: `skill_node/visuals/emblem/` — `emblem_spec.gd`, `emblem_resolver.gd`,
`archetype_shape.gd`, `core_sigil_bloom.{gd,tscn}`. Tests:
`test/unit/test_emblem_resolver.gd`, `test/unit/test_core_sigil_bloom.gd`.

## The four registers

Independent channels, all potentially lit on one node:

1. **Gem body (dome + rim)** — archetype (rim tint) + ownership (disk
   `entity_tint`, lit/dark by allocation). The existing InnerDisk/RimRing stack;
   unchanged by the emblem work. See [skill-node-visuals.md](../../.claude/rules/skill-node-visuals.md).
2. **The CARVE slot** — one height-field dent in the dome, the node's intrinsic
   payload identity. **Single winner, chosen by priority.**
3. **The BLOOM overlay** — additive, animated, entity-tinted glow layered *over*
   the carve. **Many may coexist; they never compete for the carve.** Core
   presence lives here: the core-class `Sigil` rendered as a glowing emblem.
4. **Rim/badge pips** — stake dial (exists: RimBonuses) + optional count pip
   (e.g. "2" for a multi-grant node). Not part of the emblem protocol.

Registers 2 and 3 are what `EmblemSpec` / `EmblemResolver` arbitrate.

## CARVE vs BLOOM — the core distinction

`EmblemSpec.Register` is the whole reason the model works:

- **CARVE** = the single height-field dent. Sources contend; the highest
  `priority` wins. This is where "what payload does this node carry" is read.
- **BLOOM** = additive entity-tinted glow, drawn on top. No contention — every
  BLOOM draws. This is how core presence rides *alongside* a carved spell/loot
  glyph on the same node without conflict (core + spell = sigil-bloom haloing a
  spell carve).

The CARVE priority ladder (`EmblemSpec.PRIORITY_*`, higher wins):

```
KEYSTONE (40)  >  LOOT (30)  >  SPELL (20)  >  ARCHETYPE (10)  >  (empty dome)
```

- **KEYSTONE** — bespoke, most specific.
- **LOOT** — a consumed one-off; outranks spell so a looted node shows the loot
  glyph until allocation consumes it, then falls back.
- **SPELL** — a granted spell's icon.
- **ARCHETYPE** — the fallback shape (regular polygon per archetype, see
  `ArchetypeShape.SIDES`). Lowest priority and **toggleable by simply declining
  to contribute it** — archetype identity otherwise lives in the rim hue.
- **empty dome = an ordinary node.** A carve means "this node has a payload worth
  noticing." That default is the design intent, not an accident.

BLOOM carries no meaningful priority (they're additive, order-independent).

## The coordination architecture — SkillNode stays ignorant

The point of the protocol is **dependency inversion**: sources contribute emblem
candidates; a resolver in the visual layer picks. `SkillNode` never references
loot, SkillDust, spells, or keystones — it just aggregates specs. This mirrors
the existing `get_node_effects()` / `get_addon_tooltip_sections()` aggregation.

```
each source        -> EmblemSpec (register + priority + payload)
SkillNode          -> get_emblem_contributions() = own(archetype/keystone/effects) + addons' get_emblem()
EmblemResolver     -> Resolution { carve, carve_ties, blooms }   # pure, scene-free
renderer           -> draws the one carve + every bloom
```

- `EmblemResolver.resolve(contributions)` is **pure** — give it specs, get a
  `Resolution`. It picks the max-priority CARVE, collects CARVEs tied at that
  priority into `carve_ties`, and appends every BLOOM. It does **not** know how
  to combine ties — a multi-spell node's cross-fade/split strategy is the
  *renderer's* job, not the resolver's. Keep it that way.
- Payload is polymorphic per kind: `polygon_sides` (archetype), `texture`
  (spell/loot/keystone art), or `sigil` (the core bloom). Factory ctors
  (`polygon_carve` / `texture_carve` / `sigil_bloom`) set the right register +
  tint defaults so callers can't mismatch them.

## BLOOM rendering — CoreSigilBloom (implemented)

`CoreSigilBloom extends SkillNodeVisual` draws a `Sigil` as an additive,
entity-tinted, pulsing glow — "this node is the entity's core, right here." It
reads `entity_tint` (ownership) and uses a **shared** `CanvasItemMaterial`
(`BLEND_MODE_ADD`) built lazily in a `static var`, mirroring the family's
shared-material convention; the base class's `_validate_property` keeps
`material` out of the saved scene so assigning it in code never bakes a
per-instance material. Glow = stacked outward polylines at falling alpha
(additive summation reads as bloom); core = near-white-but-entity-tinted fill.

**LOD split (#167):** the on-graph node draws this glowing silhouette; the hero
card/tooltip draws the fully shaded sigil. Same sigil, two fidelities — never
absent. This is what resolved the batching tension in #167: the on-graph sigil
is a shared additive glow, not a per-instance arbitrary carve.

## The `preload`-not-`class_name` gotcha

Emblem cross-references use `const Foo = preload("res://…/foo.gd")`, **not** the
bare `class_name`, so the code parses before the editor rebuilds its global
class cache (the editor was open during authoring — see
[godot-workflow.md](../../.claude/rules/godot-workflow.md) on the class-cache
refresh). Tighten to bare `class_name` types only after a deliberate
`godot --headless --editor --quit` refresh.

## Implementation status (2026-07-17)

**Done** — the protocol foundation + BLOOM component (589/589 GUT green, additive,
no live-file edits):
- `EmblemSpec`, `EmblemResolver`, `ArchetypeShape` (archetype owns its sides).
- `CoreSigilBloom` component + its test. **Not yet instanced in the composite.**

**Planned** — integration (touches live-loaded files; the handoff wanted these
done with the editor closed):
1. `SkillNode.get_emblem_contributions()` — aggregate own + addon specs.
2. `NodeAddon.get_emblem()` virtual; `SkillDustAddon` → loot CARVE.
3. Spell-grant `Effect` → spell CARVE.
4. `InnerDisk` consumes the resolved CARVE, retiring the `show_weld` /
   `show_diamond` mutually-exclusive shader bools and its local `ARCH_SIDES`
   duplicate (read `ArchetypeShape.SIDES`). **Contract-tested — mind
   `test_node_visuals_contract.gd`.**
5. Instance `CoreSigilBloom` in `node_visuals_composite.tscn`, feed it
   `entity.core_class.sigil` + `entity_tint`, gate visibility on `node.is_core()`
   via the composite's `_sync_*`. Draw values are first-guesses — tune in the
   Node Visuals sandbox tab.
6. Bake substrate (later, gated on a slots-per-node spike): CARVE = shared
   `sampler2DArray` of baked normals indexed by a cheap instance-uniform; BLOOM =
   shared additive glow texture, `modulate`-tinted. The payoff is the #172
   instance-uniform slot ceiling + authorability + arbitrary art, **not fps**
   (node shaders already batch to ~1–2 draw calls).

## Related issues

Design decisions recorded against #167 (sigil-as-bloom, not sigil-as-carve),
#207 (spell grant = SPELL carve), #131 (empty-dome default, archetype demoted to
fallback), #132 (rune ring vs rim diamonds — fold into the encoder prune), #168
(loot glyph = LOOT carve via `SkillDustAddon.get_emblem()`). A "prune stacked
encoders" issue (sibling to #215) folds the central-glyph zoo into this one
resolver. See `SKILLNODE_EMBLEM_HANDOFF.md` for the full framing while it exists.
