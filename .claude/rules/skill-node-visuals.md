---
description: SkillNode visuals
paths:
  - "skill_node/visuals/**"
---
# SkillNode visuals — gotchas

The component family, identity contract, carve glyph, ring band table and hover
glow: [docs/domain/skillnode-visuals.md](../../docs/domain/skillnode-visuals.md).
The central emblem registers: [skillnode-emblem.md](../../docs/domain/skillnode-emblem.md).
The 3D core look: [gimbal-3d.md](../../docs/domain/gimbal-3d.md).

## Identity

- **Never collapse `entity_tint` and `archetype_tint`.** "Mine" and "what I am" are
  different reads; a rim stays legible on an unowned node only because of the
  second.
- **The composite is the sole authority and loop-sets identity over `_children`.**
  Never poke named properties on named children: an unwired tint export fails
  silently, rendering its default forever.
- **Don't write a derived value into an `@export`** (`@tool` scripts bake it into
  the scene on an editor save). Use getter-only `effective_*`.
- **`PolygonCarveShape.well_depth` is NEGATIVE for "inherit".** It must never reach
  `set_instance_shader_parameter`: the `hint_range(0, 1)` uniform clamps it to
  `0.0`, flattening every inheriting shape.
- **Don't gate `InnerDisk.visible` on `allocated` or early-return `SN_NEUTRAL_DARK`**
  in the shader; both amputate the lit-dark branch that gives the free
  allocation lerp.

## Clock and tree

- **The anim clock gates in `NOTIFICATION_READY` via `_notification`, not
  `_enter_tree`/`_ready`.** A base `_process` auto-enables processing on every
  subclass after `_enter_tree`; a subclass `_ready` shadows the base's.
- **Resolve `ShaderStack` by direct child path, not a `%`-name**, in `_apply_sensed`:
  the setter runs before the node is in the tree, and a `%`-name is null there.
- **The CorePresence rig lives outside the ShaderStack**: `process_mode` does not
  cross into the GimbalWorld, so gate on `is_visible_in_tree()` and mirror it onto
  the rig's `visible`.
- **No `TIME` in `rim_ring.gdshader`**; the stake dial is static.

## Shaders and materials

- **Godot's front face is clockwise as seen from the camera.** A CCW-wound quad is
  culled under `cull_back`. Verify empirically (`SurfaceTool` + `cull_back` +
  sample a pixel).
- **The scene must NOT bake `material` or `instance_shader_parameters/*`**, and
  `_sync_material()` must gate on `is_visible_in_tree()`. Each baked or bound
  instance-uniform item claims a slot in the global buffer (cap 4096) visible or
  not. Don't re-add a `material =` line to `inner_disk.tscn` / `rim_ring.tscn`.
- **A Resource built in `_ready` and assigned to an `@export` bakes into the scene
  on an editor save**, shared by reference across instances. Mark it
  `resource_local_to_scene`, or hoist it to a `static var` and vary through
  instance uniforms.
- **To get a new rim profile, add a preset function; never author a Curve.** New
  presets append AFTER `CUSTOM` (index 4): scenes and the shader's LUT branch key
  on that number.
- **A sampler that varies per instance forces a duplicate material**; one shared by
  all instances (gem LUT, carve atlas) is a plain uniform and keeps batching.
- **Bake and decode constants are two halves of one encoding** (`GEM_*` /
  `SN_GEM_*`, `TextureCarveShape` / `SN_TEXTURE_*`); change them together.

## Resources

- **`GlowStyle` fields emit `changed` in their setters**; a custom Resource does
  not on assignment. Copy the pattern for any shared style resource.
