# Handoff: SkillNode central-emblem model → issue actions (#167 / #207 / #131 / #132 / #168)

## PROGRESS (branch `feat/skillnode-emblem`)

**DONE — the protocol foundation (additive, no live-file edits, 589/589 GUT green):**
- `skill_node/visuals/emblem/emblem_spec.gd` — `EmblemSpec` (Register CARVE/BLOOM, priority
  ladder KEYSTONE>LOOT>SPELL>ARCHETYPE, polygon/texture/sigil payloads, factory ctors).
- `skill_node/visuals/emblem/emblem_resolver.gd` — pure resolver → `{carve, carve_ties, blooms}`.
- `skill_node/visuals/emblem/archetype_shape.gd` — archetype owns its sides; contributes the
  fallback CARVE. SkillNode never learns the side count.
- `test/unit/test_emblem_resolver.gd` — priority ladder, register split, empty-dome, ties, nulls.

Cross-refs use `preload` (not bare `class_name`) so it runs before an editor class-cache refresh —
the editor was open during authoring. **Add a refresh + tighten to bare types once the editor is
free** (nice-to-have, not required).

**TODO — integration (touches live-loaded files; do when the editor is closed):**
1. `SkillNode.get_emblem_contributions() -> Array` — union of own(archetype via `ArchetypeShape`,
   keystone, effects) + each addon's `get_emblem()`. Mirrors `get_node_effects()`.
2. `NodeAddon.get_emblem() -> EmblemSpec` virtual (default null); `SkillDustAddon` overrides →
   `texture_carve(loot_glyph, PRIORITY_LOOT, &"loot")`. Node stays ignorant of loot.
3. Spell-grant `Effect` → contributes `texture_carve(spell.icon, PRIORITY_SPELL, &"spell")`.
4. `InnerDisk`: consume the resolved CARVE (retire `show_weld`/`show_diamond` bools); read
   `ArchetypeShape.SIDES` instead of its local `ARCH_SIDES` dup. **Contract-tested — mind
   `test_node_visuals_contract.gd`.**
5. **BLOOM render** — ✅ COMPONENT BUILT: `skill_node/visuals/emblem/core_sigil_bloom.{gd,tscn}`
   (`CoreSigilBloom extends SkillNodeVisual`) draws a `Sigil` as an additive, entity-tinted, pulsing
   glow; shared add-blend material; tested (`test/unit/test_core_sigil_bloom.gd`). **REMAINING (needs
   editor closed):** instance it in `node_visuals_composite.tscn`, feed it the owner
   `entity.core_class.sigil` + `entity_tint`, and gate its visibility on `node.is_core()` via the
   composite's `_sync_*`. Draw values (glow_layers/spread/whiteness/pulse) are first-guesses — tune
   live in the Node Visuals sandbox tab. Additive, so it doesn't disturb the carve.
6. Bake substrate (later, gated on a slots-per-node spike): carve = shared `sampler2DArray` of
   baked normals indexed by a cheap instance-uniform; bloom = shared additive glow texture,
   `modulate`-tinted. Not fps — the #172 instance-uniform slot ceiling is the real driver.

---


**Temp file — delete once the issue actions below are applied.** GitHub GraphQL was rate-limited
when this was written (see `TOOLTIP_V2_ISSUE_HANDOFF.md` for the reset check). A fresh agent should,
**after confirming the GraphQL budget reset**, create the new issue(s) and post the comments below.
These are settled design decisions from a working session — post them close to verbatim; the user
can refine on the threads.

## The locked model (context for every action below)

A SkillNode's identity is **several dimensions that can be true at once** (an INT node can host a
core AND grant a spell AND be a keystone). So they're assigned to independent **visual registers**,
not competing for one slot:

- **Register 1 — gem body (dome + rim):** archetype (rim tint) + ownership (disk `entity_tint`,
  lit/dark by allocation). Unchanged.
- **Register 2 — the carve slot (one height-field dent):** the node's intrinsic payload identity.
  Single winner, chosen by priority: **`KEYSTONE > LOOT > SPELL > ARCHETYPE > (empty)`**.
- **Register 3 — bloom overlay (additive, animated, entity-tinted):** **core presence** — the
  core-class **sigil rendered as a glowing emblem** (the sigil silhouette IS the bloom shape), lit
  near-white and tinted to the entity color, pulsing — "the core is HERE." NOT a carve, so it
  coexists with any Register-2 carve (core + spell = sigil-bloom haloing a spell carve). LOD split
  (#167): on-graph = glowing sigil silhouette (one additive sprite, `modulate`-tinted); hero
  card/tooltip = the fully shaded/beveled sigil. Same sigil, two fidelities — never absent on the node.
- **Register 4 — rim/badge pips:** stake dial (exists) + optional count pip (e.g. "2" for
  multi-grant).

Design intent: **empty dome = ordinary node; a carve = "this node has a payload worth noticing."**
Archetype recognizability stays in the rim hue. Archetype *shape* is kept for now as the lowest-
priority carve contributor, toggleable by commenting out that one contributor.

## The coordination architecture (keeps SkillNode ignorant of loot/skilldust/spells)

Invert the dependency — sources contribute emblem candidates; a resolver in the visual layer picks.
Mirrors the existing `get_addon_tooltip_sections()` / `get_node_effects()` aggregation pattern.

```
EmblemSpec { register: CARVE|BLOOM, priority: int, visual: <atlas id | sigil ref>, tint_mode }

NodeAddon.get_emblem() -> EmblemSpec        # SkillDustAddon overrides → {CARVE, prio=LOOT, loot glyph}
Effect/spell grant   -> {CARVE, prio=SPELL, spell icon}
Keystone             -> {CARVE, prio=KEYSTONE, bespoke}
archetype default    -> {CARVE, prio=ARCHETYPE, shape}   # lowest, toggleable
core presence        -> {BLOOM, entity sigil}            # separate register

SkillNode.get_emblem_contributions() = own(archetype, keystone, effects) + addons' get_emblem()

resolver (visual layer, NOT SkillNode):
  CARVE = max(register==CARVE, key=priority)   # ties (multi-spell) → combine strategy
  BLOOM = all(register==BLOOM)                 # additive
```

- `SkillNode` never references loot/SkillDust — `SkillDustAddon` implements `get_emblem()` and
  declares its own priority. Dependency points addon→emblem, node→nothing.
- Retires `InnerDisk.show_weld`/`show_diamond` mutually-exclusive shader bools (the current "hacky
  show over") — they become two arbitrated `EmblemSpec`s instead of two exclusive flags.
- Multi-spell combine (cross-fade alternation default; static split / N pie-slices as options;
  morph = deferred R&D) lives in the resolver's tie-handling; sources stay dumb. Alternation is
  nearly free in the bake model — animate the `sampler2DArray` instance-uniform index.

Bake/perf substrate (from the same session): carve = shared `sampler2DArray` of baked normal/height
maps indexed per node by a cheap instance-uniform; bloom = one shared additive glow texture,
`modulate`-tinted to entity color. Perf framing: the node shaders are ALREADY batched (~1–2 draw
calls) — draw calls aren't the 2000-node bottleneck; the **#172 instance-uniform slot ceiling
(~4096)** is, and `modulate` is the slot-free tint channel. Baking's payoff is the slot ceiling +
authorability + arbitrary art, NOT fps. Full dome/rim bake = a later refactor gated on a
slots-per-node spike; the emblem sprite/carve layer is the low-risk first step.

---

## ISSUE ACTIONS (apply after GraphQL reset)

### NEW ISSUE — "SkillNode central emblem: register/priority resolver"
Labels: `design`, `visuals`. Milestone: (ask user; likely the node-visuals milestone `#16`-family
or VFX & juice). Parent: consider making it the tracking epic for the emblem work, or child of a
node-visuals prune epic (below).
Body: the "locked model" + "coordination architecture" sections above, framed as the implementation
target. Acceptance: `EmblemSpec` + `get_emblem()`/`get_emblem_contributions()` + a visual-layer
resolver rendering CARVE (with priority `KEYSTONE>LOOT>SPELL>ARCHETYPE`) and BLOOM (core) registers;
`SkillNode` carries no concrete-source knowledge; `show_weld`/`show_diamond` bools retired.

### NEW ISSUE — "SkillNode visuals: prune stacked encoders" (sibling to #215)
Labels: `design`, `visuals`. Body: the composite (`node_visuals_composite`) stacks 6 identity
encoders (InnerDisk weld+diamond, RimRing, RimBonuses diamonds, CoreHalos, RuneRing, SensedOutline)
that the design labs authored as ALTERNATE looks, not simultaneous layers (see #131, #132). Go
layer-by-layer KEEP/MERGE/CUT; fold the central-glyph zoo into the single Emblem resolver above;
force the #132 decision (rune ring vs rim diamonds — pick one). Mirror #215's prune framing.

### COMMENT on #167 (Unify entity Sigil with inner-disk weld glyph)
Decision: the entity **core** reads via **Register 3 (bloom overlay)** — the core-class **sigil
rendered as a glowing emblem** (the sigil silhouette IS the bloom), entity-tinted and animated, NOT
a carve. The sigil is present on the node (as a glowing silhouette LOD) and renders in full detail on
the hero card / tooltip — same sigil, two fidelities. This resolves the batching tension in #167:
the on-graph sigil is a shared additive glow tinted by `modulate`, not a per-instance arbitrary
carve. Sigil-as-carve is superseded by sigil-as-bloom (glow), not dropped.

### COMMENT on #207 (visualize spell grant on skillnode)
Decision: spell grant = **Register 2 (carve)** at priority `SPELL`, contributed via the emblem
protocol (Effect/grant supplies an `EmblemSpec`; a spell-granting `NodeAddon` may instead supply it
via `get_emblem()`). Spell icons already exist as monochrome masks (`assets/icons/spells/`, `mise
run icons:update`) → bake to carve normals or use flat, atlas-shared. Multiple grants: default
cross-fade alternation (free via animated `sampler2DArray` index); static split / N pie-slices as
options; morph deferred. A rim count pip disambiguates N>1; the fan tooltip enumerates all.
Superseded: the "change InnerDisk cutout shape per spell via a shader flag" sketch — goes through the
resolver, not a bespoke bool.

### COMMENT on #131 (weld full-disk placeholder contradicts empty-center default)
Decision confirmed and generalized: **empty dome is the default read** (ordinary node), a carve
means "this node has a payload." Archetype *shape* is kept for now but demoted to the LOWEST-priority
carve contributor (`ARCHETYPE`), toggleable by disabling that one contributor — so it never
dominates and is trivially switchable. Archetype identity otherwise lives in the rim hue.

### COMMENT on #132 (rune_ring invisible, crowded by rim diamonds)
Decision: fold into the "prune stacked encoders" issue above — rune ring vs rim diamonds are
alternate encodings and must not co-render; pick one in the prune. Not a standalone tuning fix.

### COMMENT on #168 (SkillDust loot relic / diamond crown)
Decision: the loot glyph becomes a **CARVE `EmblemSpec` at priority `LOOT`**, contributed by
`SkillDustAddon.get_emblem()` (the addon owns the knowledge; `SkillNode` stays ignorant). `LOOT`
outranks `SPELL` (it's a consumed one-off), so a looted node shows the loot glyph until allocation
consumes it, then falls back to spell/archetype. Retires the `InnerDisk.show_diamond` shader bool.

## When done
Post the number→title for each created issue + a note that comments landed, then delete this file.
