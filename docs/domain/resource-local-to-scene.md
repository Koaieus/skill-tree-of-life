# `resource_local_to_scene` — the fix for shared inline sub-resources

## The gotcha

An inline `SubResource` in a `.tscn` is cached by Godot: every
`PackedScene.instantiate()` of that scene hands back the **same** Resource
instance, not a fresh copy. If that sub-resource is later mutated in place at
runtime, the mutation leaks across every instantiation of the scene that's
still alive — silently, with no error, because nothing about the mutation
looks wrong from the mutating call site's point of view.

Concretely, in this repo: `skill_node/addons/bunker_addon.tscn` declares its
granted `StatModifier` as an inline `sub_resource` (`Resource_vxeh7`,
`stat_id = &"armor"`, `value = 5.0`). Every `BunkerAddon.tscn.instantiate()`
returns the same `Resource_vxeh7`. The local-scale mutator (#376) writes
`m.value` directly on the canonical modifier instance a `SkillNode` holds — if
that instance were the shared scene sub-resource, one node's bunker addon
scaling from 5→15 would bake `value == 15` into every *other* node's "fresh"
bunker addon too.

## The fix

Set `resource_local_to_scene = true` on the sub-resource block in the `.tscn`:

```
[sub_resource type="Resource" id="Resource_vxeh7"]
resource_local_to_scene = true
script = ExtResource("2_efkvd")
stat_id = &"armor"
operation = 3
value = 5.0
```

With the flag set, Godot gives every `instantiate()` call its own private copy
of that sub-resource automatically — no manual `.duplicate(true)` and no
ledger tracking which clone belongs to which instance needed on the
consuming side. See `.claude/rules/skill-node-addons.md` for how SkillNode
attach/detach used to work around this manually (the `_addon_local_clones` /
`_addon_entity_clones` ledgers, retired once the addons carrying
`StatModifier` sub-resources — `bunker_addon.tscn`, `fortification_addon.tscn`,
`spike_ring_addon.tscn` — set this flag) and `.claude/rules/stats-system.md`
for the modifier-sharing rules this interacts with.

## When to reach for it

Any `.tscn` that (a) is instantiated more than once at runtime, and (b) owns
an inline sub-resource some downstream system mutates in place (not just
reads) is a candidate. If the sub-resource is only ever read, sharing is
harmless and the flag buys nothing but overhead — don't cargo-cult it onto
every sub-resource in sight. The tell is a mutation site writing a field
directly on a `Resource` obtained from a scene-authored `@export`, without
having explicitly duplicated it first.
