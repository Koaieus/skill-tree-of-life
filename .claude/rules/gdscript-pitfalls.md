---
description: GDScript silent failures — freed-object reads, undisconnectable lambdas, @tool placeholder instances
paths:
  - "**/*.gd"
---

# GDScript pitfalls

Fires on every `.gd` read, so: add here only if it fails *silently* and applies
repo-wide — otherwise `docs/domain/godot-workflow.md`.

## Reading a freed Object

- **A deferred call with a freed Object argument is silently dropped.** No error.
  Do the work synchronously, or order the free after it. See
  [entity-death.md](entity-death.md).
- **A freed Object compares EQUAL to `null`** — so a latch holding one reads back
  as "nothing latched yet" and silently re-latches. Latch `get_instance_id()` (an
  int, never reused); not the reference, and not `Entity.entity_id`, which is 0
  until the entity enters `entities_container`.
- **A typed variable crashes before `is_instance_valid` can save you** —
  `var t: FooType = dict.get(key)` crashes at the *assignment*. Read untyped first:

```gdscript
var stored = dict.get(key)
var t: MyType = stored if is_instance_valid(stored) else null
```

## You cannot disconnect a lambda or an `unbind()` you did not keep

A lambda's `Callable.get_object()` is the **GDScript**, not the node, and
`foo.unbind(1)` mints a fresh Callable per call — so `disconnect()` never
matches, failing as a silent no-op. Record the Callable when you connect:
`BindScope` (`ui/bind_scope.gd`) is the one such bookkeeper; don't add a second.

## `@tool` (on `SkillNode`, `Entity`, `Graph`, most of `procgen/` + `ui/`)

- **Never touch a signal/method on a non-`@tool` node.** In a non-playing editor
  load that node is a **placeholder instance** exposing only its `@export`s, so
  `other.sig.connect(...)` throws *"Invalid access to property or key"* naming the
  **node** (`Node (Foo)`), pointing at the wrong file. `mise run test` stays green;
  only `mise run check` goes red. Guard in the **method**, not just `_ready()` —
  `@export` setters fire during deserialization, first.
- **Declare an exported bound ABOVE the value that clamps against it** — exports
  restore in declaration order, so a later-declared bound clamps every
  scene-authored value against its *default*, silently (`fill_max` above
  `fill_current`; two live cases in `skill_node/visuals/rim_ring.gd`).
- Guarding `_ready()` and never writing a derived value back into an `@export`:
  **`docs/domain/godot-workflow.md`**, which also holds the rest of these.
