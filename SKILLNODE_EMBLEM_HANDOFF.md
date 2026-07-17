# Handoff: SkillNode central-emblem model — implementation pickup

Crash-recovery breadcrumb. The **issue-actions are DONE** (2026-07-17); what
remains is the *implementation* of the emblem registers. The durable engineering
contract lives in **`docs/domain/skillnode-emblem.md`** — read that first; this
file is just the task ledger.

## DONE — protocol foundation + BLOOM component (committed, 589/589 GUT green)
- `skill_node/visuals/emblem/emblem_spec.gd` — `EmblemSpec` (Register CARVE/BLOOM,
  priority ladder KEYSTONE>LOOT>SPELL>ARCHETYPE, polygon/texture/sigil payloads).
- `emblem_resolver.gd` — pure resolver → `{carve, carve_ties, blooms}`.
- `archetype_shape.gd` — archetype owns its sides; contributes fallback CARVE.
- `core_sigil_bloom.{gd,tscn}` — BLOOM component (built, **not yet** in composite).
- Tests: `test_emblem_resolver.gd`, `test_core_sigil_bloom.gd`.

## DONE — issue-actions (all applied)
- **#237** — created: emblem tracking epic "register/priority resolver"
  (design/visuals, SkillNode-visuals-v2, board backlog/L/p1).
- **#238** — created: "prune stacked encoders" (design/visuals, sibling to #215,
  board backlog/M/p2). Not parented (sibling, not child).
- **#128** — pulled in as Register-3 (BLOOM) integration + core-presence travel;
  re-parented under #237; board → Ready. Two comments posted: the model tie-in +
  the `CorePresence` refactor decision.
- Decision comments posted on **#167 / #207 / #131 / #132 / #168** (close to the
  verbatim design notes; user can refine on-thread).

## TODO — implementation (touches live-loaded files; do with the editor closed)
Children of epic **#237**:
1. `SkillNode.get_emblem_contributions()` — union of own(archetype via
   `ArchetypeShape`, keystone, effects) + each addon's `get_emblem()`. Mirrors
   `get_node_effects()`.
2. `NodeAddon.get_emblem() -> EmblemSpec` virtual (default null); `SkillDustAddon`
   overrides → `texture_carve(loot_glyph, PRIORITY_LOOT, &"loot")`.
3. Spell-grant `Effect` → `texture_carve(spell.icon, PRIORITY_SPELL, &"spell")`.
4. `InnerDisk` consumes the resolved CARVE; retire `show_weld`/`show_diamond`
   bools + local `ARCH_SIDES` dup (read `ArchetypeShape.SIDES`). **Contract-tested
   — mind `test_node_visuals_contract.gd`.**
5. **#128 — Register-3 + core-presence travel.** Group `CoreSigilBloom` + the
   existing `CoreHalos` into one **`CorePresence`** node **nested under
   `NodeVisualsComposite/ShaderStack`** (where `CoreHalos` already is), gated on
   `is_core`; move it by tweening its local `position` — retarget the `CoreMarker`
   glide (`skill_node.gd`) onto it; drag-ghost reuses it; **delete `CoreMarker` +
   its star `Label`**. Nesting under `ShaderStack` gives sensed-hide for free (no
   own gate) and keeps the composite's `%`-name `entity_tint` fan-out (add
   `%CoreSigilBloom` to `_children`). Mind `GimbalBack` relative-z (wrapper at
   rel-z 0) + compute the glide offset in the composite's local frame. Full
   rationale + rejected per-entity-follower: the "Core-presence movement" section
   of `docs/domain/skillnode-emblem.md`.
6. Bake substrate (later, gated on the #172 instance-uniform slot spike): CARVE =
   shared `sampler2DArray` of baked normals; BLOOM = shared additive glow texture,
   `modulate`-tinted. Payoff = slot ceiling + authorability + arbitrary art, NOT fps.

## Note
Cross-refs in the emblem code use `preload` (not bare `class_name`) so they parse
before an editor class-cache refresh. Tighten to bare types after a deliberate
`godot --headless --editor --quit` once the editor is free (nice-to-have).

**Delete this file** once the #237 children + #128 land.
