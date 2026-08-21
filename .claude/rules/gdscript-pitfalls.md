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
- **A `@tool` script must not touch a signal/method on a non-`@tool` node.** In a
  non-playing editor load that node gets a **placeholder instance** exposing only
  its `@export`s — no signals, no methods — so `other.sig.connect(...)` throws
  *"Invalid access to property or key"* naming the **node**, not the class
  (`Node (Foo)`), pointing at the wrong file. `mise run test` stays green (tests
  get real instances); only `mise run check` (`--editor`) goes red. Guard with
  `Engine.is_editor_hint()` in the **method**, not just `_ready()` — `@export`
  setters fire during deserialization, before `_ready()`.

## `@export` cannot be applied to a `static var`

Parse error, not a silent failure — but the design answer matters: a class-level
fact is a `const`. `@export` serializes *per instance*, so an exported
"class constant" would put an editable copy on every node.

## Interdependent `@export`s load in declaration order

**Declare the bound ABOVE the value that clamps against it.** A setter that
clamps one exported property against another (`fill_current` clamped to
`fill_max`) reads that property's *default* if it is declared later — so every
scene-authored value is clamped against the default at load, and nothing errors.

**Why:** Godot serializes and restores exports in declaration order.
**How to apply:** `fill_max` above `fill_current`. Two live cases sit in
`skill_node/visuals/rim_ring.gd`; both were found by seeing wrong values in a
scene, not by reading the code.

## `Rect2.has_point` is half-open; a zero-size Rect2 contains nothing

It excludes the bottom/right edges, so `position + size` is *outside* — and a
zero-size rect contains not even its own origin. Fails as a wrong answer, never
an error (two test failures in `VisionCircles`' bounds early-out).

**How to apply:** for an inclusive region, keep `lo`/`hi` vectors and compare
explicitly. `Rect2` is for layout/culling, not "is this inside?" predicates.

## You cannot disconnect a lambda or an `unbind()` you did not keep

A lambda's `Callable.get_object()` is the **GDScript**, not the node — so a
connection's owner is unidentifiable from the outside — and `foo.unbind(1)`
mints a fresh Callable per call, so `disconnect(foo.unbind(1))` never matches.
Both fail as a silent no-op. Record the Callable when you connect it:
`BindScope` (`ui/bind_scope.gd`) is the one such bookkeeper — don't add a second.

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
