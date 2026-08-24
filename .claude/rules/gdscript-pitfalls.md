---
description: GDScript + .tres silent failures — freed-object reads, undisconnectable lambdas, @tool placeholder instances, dropped .tres properties
paths:
  - "**/*.gd"
  - "**/*.tres"
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

## An inline `set(v):` block cannot be overridden — `set = _method` can

A subclass can only hook a parent's property write if the parent declared the
setter as a **named function**. There is no error either way: with an inline
block there is simply no method to override, so the subclass hook never runs and
the write silently does the base thing.

```gdscript
# Stat — overridable, and load-bearing (#555)
@export var base_value: float = 0.0:
	set = _set_base_value

func _set_base_value(v: float) -> void:
	base_value = v          # does NOT recurse
	_emit_value_changed()

# PoolStat — this override is why a plain `pool.base_value = v` runs the cap policy
func _set_base_value(v: float) -> void:
	var old_max := float(get_value())
	super(v)
	_apply_max_change(old_max)
```

Verified by probe (2026-08-24): the override fires **through a base-typed
reference** too, and `base_value = v` inside the setter still does not re-enter
it when reached via `super()` from the override. Don't conclude the pattern is
impossible from the inline form — that mistake costs a design.

**How to apply:** don't "tidy" a `set = _method` declaration back into an inline
block; you'd silently unhook every subclass. `test_skill_point_stat.gd`'s
`sp.base_value = ...; assert_eq(sp.current, ...)` is what catches it for `Stat`.

## You cannot disconnect a lambda or an `unbind()` you did not keep

A lambda's `Callable.get_object()` is the **GDScript**, not the node, and
`foo.unbind(1)` mints a fresh Callable per call — so `disconnect()` never
matches, failing as a silent no-op. Record the Callable when you connect:
`BindScope` (`ui/bind_scope.gd`) is the one such bookkeeper; don't add a second.

## `@tool` (on `SkillNode`, `Entity`, `Graph`, most of `procgen/` + `ui/`)

- **What the ENGINE loads from a `.tscn`/`.tres` becomes a placeholder instance**
  when its script isn't `@tool` — only `@export`s readable, every method/signal
  touch throws: *"Invalid access to property or key"* naming the **node**
  (`Node (Foo)`, the wrong file), or *"placeholder instance"* naming the resource.
  `Foo.new()` from a `@tool` caller is exempt — real instance, `_ready` and
  methods run (how `sandbox_world` mounts non-`@tool` systems in a live tab). So
  **everything reachable from a `.tres` an editor panel loads must be `@tool`**:
  exports read back fine, so the panel shows the resource in full and throws on
  the first question it asks. `check` catches only the node case; GUT neither.
  Guard in the **method**, not just `_ready()`: `@export` setters fire during
  deserialization, first.
- **Declare an exported bound ABOVE the value that clamps against it** — exports
  restore in declaration order, so a later-declared bound silently clamps every
  scene-authored value against its *default*.
- **In a `.tres`, a property authored ABOVE its `script = ExtResource(...)` line
  is silently dropped** — it lands on a bare `Resource` that has no such
  property. No error; the field just reads as its default. Hand-editing a
  `[resource]` block, insert *after* the script line. (`.tres` has no comment
  syntax either — a `;` trailer is a parse error, not a note.)
- **`if Engine.is_editor_hint(): return` at the top of `_ready` is a trap for any
  script a live sandbox tab instantiates** — the hint is true there, so the object
  runs but every subscription below the guard is silently absent, and GUT (hint
  false) can never see it. Guard the OS-facing lines individually:
  `docs/domain/sandbox-framework.md`.
- Guarding `_ready()`, never writing a derived value back into an `@export`, and
  the rest: **`docs/domain/godot-workflow.md`**.
