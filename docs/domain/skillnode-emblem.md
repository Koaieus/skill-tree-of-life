# SkillNode central emblem — the register model

How a SkillNode's central identity glyph is decided and drawn. The throughline:
**a node's identity is several dimensions that can be true at once** (an INT node
can host a core *and* grant a spell *and* be a keystone), so they're assigned to
independent **visual registers** rather than fighting over one slot.

This is the durable contract. It was hashed out in a working session, first
captured in a temporary root-level handoff file; that file's issue-actions have
all been applied and it has been deleted, which is exactly why the contract
lives here instead.

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
- **ARCHETYPE** — the fallback shape, read from `SkillNode.archetype`
  (an [Archetype] resource — `archetype.carve_shape.carve()`; see #312). Lowest
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
SkillNode          -> get_emblem_contributions() = own(archetype/keystone/effects) + addons' get_emblem()
EmblemResolver     -> Resolution { carve, carve_ties, blooms }   # pure, scene-free
renderer           -> draws the one carve + every bloom
```

- `EmblemResolver.resolve(contributions)` is **pure** — give it specs, get a
  `Resolution`. It picks the max-priority CARVE, collects CARVEs tied at that
  priority into `carve_ties`, and appends every BLOOM. It does **not** know how
  to combine ties — a multi-spell node's cross-fade/split strategy is the
  *renderer's* job, not the resolver's. Keep it that way.
- **A CARVE spec holds the `CarveShape` itself, not a copy of its fields**
  (#315). There used to be a union payload — `polygon_sides` / `polygon_squish`
  / `texture` — plus a `CarveStyle` enum naming which of them was live, plus
  per-style factories to fill each combination. That was the shape described
  three times: once by the subclass, once by the enum, once again by
  `InnerDisk.CarveKind`. Now there is **one** CARVE ctor,
  `EmblemSpec.carve(shape, priority, source)`, reached through
  `CarveShape.carve(priority, source)` — so adding a parameter to a shape family
  is one edit on that shape, not a payload field plus a factory arg plus a copy
  hop. `sigil` stays its own field: a `Sigil` is a BLOOM, not a `CarveShape`,
  and `sigil_bloom` still sets the register + tint defaults for it.
- **`InnerDisk.CarveKind` survives, deliberately.** It is the *shader's* int
  branch selector and has to exist for the batched instance uniform. The
  renderer dispatches on the shape's own type (`if shape is PolygonCarveShape`)
  and maps to its own `CarveKind` locally. `skill_node/visuals/emblem/` knows
  nothing about `InnerDisk` — no `shader_kind()`, no `apply_to(disk)`; inverting
  that dependency is what #302 rejected.
- **A null `shape` is not "no contribution."** A keystone or spell grant with no
  `carve_shape` authored still contributes at its rung, carrying a null shape,
  and renders as an empty dome. Contributing nothing instead would let the
  archetype fallback win and dress a keystone node up as a plain territory node.
- **`priority` and `source_kind` are two independent fields**, and the ladder
  (`EmblemSpec.Priority`) is deliberately not 1:1 with the source: a rung is
  shareable (`node_visuals_composite.gd` contributes `&"authored"` at
  `Priority.ARCHETYPE`, and `carve_ties` exists precisely to model ties).
  `source_kind` is purely descriptive — tie-break debugging, tooltip copy.

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

### Core-presence movement — the BLOOM replaces the star, and travels (#128)

The BLOOM (+ `CoreHalos` gimbal) **replaces the old "star emoji" core marker**
(`skill_node/core_marker.gd`, a `$Visuals/CoreMarker` Node2D holding a star
`Label`). That marker already fakes travel: on a core move, `core_location`
flips to the new node, the new node's `CoreMarker` becomes visible and is
**offset to start at the old node's relative position, then tweened to
`Vector2.ZERO`** — it "glides into place" (`skill_node.gd`). This per-node
offset-glide is the seam to ride, not to replace.

The clean mechanism (decided, #128): the core-only visuals now number several
(BLOOM sigil + gimbal halos), so group them under **one `CorePresence` mover**
gated visible by `is_core`, and **retarget the existing glide tween** from the
lone `CoreMarker` onto that group — all core visuals glide together. The
core-move **drag ghost** reuses the same group (a `modulate`-alpha'd copy at the
hovered target). `CoreMarker` + its star `Label` are then deleted.

**Compose `CorePresence` *inside* the visual family — under
`NodeVisualsComposite/ShaderStack`, where `CoreHalos` already lives — and move it
as a whole by tweening its local `position`.** A subtree glides at any nesting
depth (`position` is parent-local), so nesting costs nothing for the move, and it
buys two things for free:

- **Sensed-hide comes free.** `_apply_sensed()` hides the whole `ShaderStack`
  node, so core visuals nested there vanish on a fogged/enemy node with **no
  separate sensed gate**. (This is why nesting beats a Visuals-level group or a
  decoupled follower — those would each need their own fog gate.)
- **`entity_tint` fan-out survives the reparent.** The composite loop-sets
  `entity_tint` over its `%`-unique-named `_children`; unique names resolve
  anywhere in the owner's tree, so wrapping `%CoreHalos` (+ adding
  `%CoreSigilBloom`) under `CorePresence` keeps the fan-out intact.

So `CorePresence` is a *consolidating refactor*, not new machinery: fold the
star-era `CoreMarker` role and the already-in-family `CoreHalos` into one nested,
`is_core`-gated, position-tweenable group. Mind only the `GimbalBack` relative-z
(keep the wrapper at relative z 0) and compute the glide offset in the composite's
local frame. Rejected as heavier: a single per-entity CorePresence *follower*
decoupled from nodes — cleaner "one thing moves" but duplicates the render path,
diverges from the per-node visual family, and re-introduces the fog gate nesting
gives for free.

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
4. **Landed** — `InnerDisk.set_carve()` consumes the resolved CARVE, having
   retired the old mutually-exclusive weld/diamond boolean shader pair and
   its local sides-per-archetype duplicate in favour of the one `carve_kind`
   (`CarveKind.NONE`/`POLYGON`/`GEM`) selector; archetype shapes now come
   from `ArchetypeShape.shape_for()`/`carve()`. See
   `.claude/rules/skill-node-visuals.md`.
5. Register-3 integration + core-presence travel (**#128**, child of the emblem
   epic **#237**): the `CorePresence` group (BLOOM + halos), `is_core` gate,
   glide-tween retarget, drag ghost, and `CoreMarker` deletion — see the
   core-presence movement section above. Draw values are first-guesses — tune in
   the Node Visuals sandbox tab.
6. Bake substrate (later, gated on a slots-per-node spike): CARVE = shared
   `sampler2DArray` of baked normals indexed by a cheap instance-uniform; BLOOM =
   shared additive glow texture, `modulate`-tinted. The payoff is the #172
   instance-uniform slot ceiling + authorability + arbitrary art, **not fps**
   (node shaders already batch to ~1–2 draw calls).

## Related issues

- **#237** — the emblem tracking epic (register/priority resolver). Parent of #128.
- **#238** — "prune stacked encoders" (sibling to #215): folds the central-glyph
  zoo into this one resolver; forces the #132 rune-vs-diamond decision.
- **#128** — Register-3 (BLOOM) integration + core-presence travel (see the
  movement section above). Child of #237.

Design decisions were recorded against #167 (sigil-as-bloom, not sigil-as-carve),
#207 (spell grant = SPELL carve), #131 (empty-dome default, archetype demoted to
fallback), #132 (rune ring vs rim diamonds — fold into the prune), #168 (loot
glyph = LOOT carve via `SkillDustAddon.get_emblem()`). 
The protocol foundation and the BLOOM / CorePresence work landed under #237 and
#128 (both closed). The archetype→shape mapping and retiring the old
mutually-exclusive weld/diamond boolean pair in favour of one uniform
`carve_kind` selector have since landed too; what's left toward one uniform
SDF vocabulary is tracked in **#285**.
