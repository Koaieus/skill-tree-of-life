---
description: GDScript silent failures — freed-object reads, undisconnectable lambdas, setter overrides, @onready in subclasses, typed-array ternaries
paths:
  - "**/*.gd"
---

# GDScript pitfalls

Only silent, repo-wide failures here; the rest: `docs/domain/godot-workflow.md`.

- **A freed Object `== null`**, so a latch holding one re-latches. Latch
  `get_instance_id()`, not the reference or `Entity.entity_id` (0 until in the tree).
- **An inline `set(v):` cannot be overridden** — the subclass hook never runs.
  Use `set = _set_x` plus a named method (`Stat`/`PoolStat`).
- **A subclass's `@onready` is null in the BASE's `_ready`** unless it defines
  `_ready()` and calls `super()` first (`SplashRootView`, #734).
- **A lambda or `unbind()` you did not keep cannot be disconnected** (silent
  no-op); record the Callable — `BindScope` (`ui/bind_scope.gd`) is the one.
- **A lambda captures locals BY VALUE**: writes never escape. Use a member var or
  one-element `Array`/`Dictionary`, or a named method.
- **`var xs: Array[T] = [] if a == null else a.typed()` errors at runtime**
  (untyped Array) though `check` passes; assign inside an `if`.
- **`global_position` before `add_child` silently writes `position`**: `add_child`
  first (`AllocationVFX`'s spike doubled in the menu).
- **`if Engine.is_editor_hint(): return` atop `_ready` strands every subscription
  below it** in a live sandbox tab; gate OS-facing lines individually
  (`docs/domain/sandbox-framework.md`).
- **`Resource.duplicate(true)` shares typed `Array[Resource]` elements** and drops
  `resource_path` (#726).
- Deferred call with a freed Object arg: [entity-death.md](entity-death.md).
