---
description: Hand-editing a .tscn — script before exports, local-to-scene sub-resources, initialize() not _ready()
paths:
  - "**/*.tscn"
---

# Authoring a `.tscn`

Three silent-failure gotchas. None error; all produce wrong behaviour.

## `script = ExtResource(...)` MUST precede any `@export` override on the root

Godot deserializes properties in file order, so a `script` line *after* an
override reinitialises that var to the GDScript default and discards the scene
value. Only bites the scene's own root node; children are unaffected.

```
[node name="Foo" type="MarginContainer"]
script = ExtResource("1_script")             # FIRST
mode_color = Color(0.945, 0.269, 0.245, 1)   # then overrides
```

## Inline sub-resources are SHARED across every `instantiate()`

A `SubResource` declared in a `.tscn` (a `Gradient`, a `ShaderMaterial`) is
loaded once and reused by every instance — it is *not* duplicated. If a script
mutates it per-instance, last writer wins and every instance renders identically.
Symptom: "my per-instance tweak has no effect", no error.

**Fix:** set `resource_local_to_scene = true` on the sub-resource (inspector:
resource → Local To Scene). Concrete case: `skill_node/addons/*_addon.tscn`'s
granted `StatModifier`s all set this (#377) — without it, one carrier's
value-mutation would leak into every other instantiation of that addon. That
claim went false silently once (#406 added a second Spikes modifier without the
flag), so it is now pinned by
`test_authored_node_content.gd::test_addon_scenes_never_share_a_modifier_instance_between_carriers`,
which walks every scene in the directory.

## Scene-node systems wire injected deps in `initialize()`, not `_ready()`

A system living in the scene tree has `_ready()` fire *during instantiation* —
before the composer can inject its dependency fields. Signal hookups or resolves
that read injected deps must go in a public `initialize()` the composer calls
after assigning them, or they run with null deps and silently no-op. Group
membership in `_enter_tree` is fine. Systems wired purely off autoloads can keep
their hookup in `_ready`.

## A free-floating Control + an autowrap Label sizes itself to the viewport

An autowrap `Label` measures its height by wrapping at its **current** width, so
the first layout (width 0) wraps one word per line; and a Control outside a
Container never *shrinks* when its minimum drops, so that height is permanent.
`SpellTooltip` sat at 4762px until it was made to fit itself.

**How to apply:** a floating panel (tooltip, popup card) that autowraps must fit
itself — `size = Vector2(width, 0.0)` on every populate and per frame while
visible (`set_size()` clamps up against the combined minimum; it converges in ~2
frames). Fit while **visible** — a hidden Control skips layout, so its Labels
never re-shape and the fit never converges; fade in from `modulate.a = 0` rather
than staying hidden. Worked example: `ui/spell_tooltip/`.

`remove_theme_*_override()` also drops the **scene-authored** override, not just
your runtime one — re-assert the captured value instead.

Full set of Godot authoring gotchas: **`docs/domain/godot-workflow.md`**.
