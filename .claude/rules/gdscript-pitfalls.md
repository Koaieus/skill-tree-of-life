---
description: GDScript silent failures — freed-object reads, undisconnectable lambdas, @tool placeholder instances
paths:
  - "**/*.gd"
---

# GDScript pitfalls

Fires on every `.gd` read: add here only if it fails *silently* and applies
repo-wide — otherwise `docs/domain/godot-workflow.md`.

## Reading a freed Object

- **A deferred call with a freed Object argument is silently dropped**, no error.
  Do the work synchronously, or order the free after it — [entity-death.md](entity-death.md).
- **A freed Object compares EQUAL to `null`** — so a latch holding one reads back
  as "nothing latched yet" and silently re-latches. Latch `get_instance_id()` (an
  int, never reused); not the reference, and not `Entity.entity_id`, which is 0
  until the entity enters `entities_container`.
- **A typed variable crashes before `is_instance_valid` can save you** —
  `var t: FooType = dict.get(key)` crashes at the *assignment*. Read into an
  untyped var, `is_instance_valid` that, and only then assign the typed one.

## You cannot disconnect a lambda or an `unbind()` you did not keep

A lambda's `Callable.get_object()` is the **GDScript**, not the node, and
`foo.unbind(1)` mints a fresh Callable per call — so `disconnect()` never
matches, failing as a silent no-op. Record the Callable when you connect:
`BindScope` (`ui/bind_scope.gd`) is the one such bookkeeper; don't add a second.

## `@tool` (on `SkillNode`, `Entity`, `Graph`, most of `procgen/` + `ui/`)

- **Never touch a signal/method on a non-`@tool` node.** In a non-playing editor
  load that node is a **placeholder instance** exposing only its `@export`s, so
  `other.sig.connect(...)` throws *"Invalid access to property or key"* naming the
  **node** (`Node (Foo)`), pointing at the wrong file — and `mise run test` stays
  green, only `check` goes red. Guard in the **method**, not just `_ready()`:
  `@export` setters fire during deserialization, first.
- **Declare an exported bound ABOVE the value that clamps against it** — exports
  restore in declaration order, so a later-declared bound silently clamps every
  scene-authored value against its *default*.
- **`if Engine.is_editor_hint(): return` at the top of `_ready` is a trap for any
  script a live sandbox tab instantiates** — the hint is true there, so the object
  runs but every subscription below the guard is silently absent, and GUT (hint
  false) can never see it. Guard the OS-facing lines individually:
  `docs/domain/sandbox-framework.md`.
- Guarding `_ready()`, never writing a derived value back into an `@export`, and
  the rest: **`docs/domain/godot-workflow.md`**.
