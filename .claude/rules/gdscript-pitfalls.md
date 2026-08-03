---
description: GDScript silent failures — @tool serialization, freed-object reads, @export on static var
paths:
  - "**/*.gd"
---

# GDScript pitfalls

Deliberately tiny: this fires on every `.gd` read, so it earns its place only by
staying short. Add here only if it fails *silently* and applies repo-wide.

## `@tool` scripts

`@tool` is on `SkillNode`, `Entity` and `Graph` (plus most of `procgen/` and
`systems/`) — so both of these are live constraints on core classes.

- **Guard `_ready()` with `Engine.is_editor_hint()`** whenever it writes
  `modulate`, shader params, or child `@export`s. Unguarded, the write dirties the
  scene on every editor load and Godot serializes it back into the `.tscn`.
- **Never write a DERIVED value back into an `@export`.** The editor serializes
  the *computed* value, and the next load computes again from there — compounding
  on every save. Export the authored input; expose the derived value as a plain
  `var` with a getter only.

## `@export` cannot be applied to a `static var`

Parse error, not a silent failure — but the design answer matters: a class-level
fact is a `const`. `@export` serializes *per instance*, so an exported
"class constant" would put an editable copy on every node.

## Reading a freed Object

- **A deferred call with a freed Object argument is silently dropped.** No error.
  Bit us in entity-death cleanup, where a deferred `deallocate_all_owned(entity)`
  raced `queue_free(entity)` and orphaned nodes. Do the work synchronously, or
  guarantee the free is ordered after it. See
  [entity-death.md](entity-death.md).
- **A typed variable crashes before `is_instance_valid` can save you.**
  `var t: FooType = dict.get(key)` on a freed instance crashes at the *assignment*.
  Read into an untyped var first:

```gdscript
var stored = dict.get(key)
var t: MyType = stored if is_instance_valid(stored) else null
```

More Godot authoring gotchas: **`docs/domain/godot-workflow.md`**.
