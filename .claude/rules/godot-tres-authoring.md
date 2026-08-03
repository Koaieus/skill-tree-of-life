---
description: Hand-authoring a .tres — UID mismatch nulls the field; array-literal parser rules
paths:
  - "**/*.tres"
---

# Hand-authoring a `.tres`

## A UID mismatch silently nulls the field

`[ext_resource type="Script" uid="uid://..." path="res://foo/bar.gd" id="x"]` —
if `uid` doesn't match the real `.uid` for `path`, Godot does **not** error. The
entry fails to resolve, any `SubResource` declaring `script = ExtResource("x")`
instantiates as a bare `Resource` with no script, and any field referencing it
ends up `null`. Tests that don't probe the field never notice.

**Fix:** omit `uid=` entirely (Godot resolves by `path=`, and the editor backfills
it safely on next save), or verify each against `cat <script>.gd.uid`. Never trust
a copy-pasted uid.

## Two parser gotchas

- **Array literals must be single-line.** `Array[T]([a, b, c])` works; a newline
  after `[` gives *"Parse Error: Expected string."* Author wide, don't pretty-print.
- **`PackedStringArray` takes positional args, not a bracketed list.**
  `PackedStringArray("a", "b")` — correct. `PackedStringArray(["a", "b"])` parses
  as one nested-array element and breaks reads. `Array[T]` *does* take `[...]`.
  Don't conflate them.

## Never write a DERIVED value back into an `@export`

In a `@tool` script, if `@export var x` is both the authored knob and where a
computed value lands, the editor serializes the *computed* value into the file
and the next load computes again from there — compounding on every save. Export
the authored input; expose the derived value as a plain `var` with a getter only.

An editor pass re-serializes `.tres` files it touches. Nearly always that's
default-elision (semantically identical); occasionally a non-default value goes
missing. It's all in `git diff` — glance, restore if needed, move on. See
**`docs/domain/godot-workflow.md`**.
