---
paths:
  - "attack/melee/sim/**"
  - "native/**"
---

# The blade solver's C++ backend (#798)

The repo's only GDExtension source. Full context:
`docs/domain/melee-blade-sim.md` → "Two backends, one meaning".

## Never name a GDExtension class as a bare identifier in GDScript

`BladeSolverNative.simulate(...)` is a **parse-time** "identifier not declared"
on any machine where the binary wasn't built — so `blade_sim.gd` fails to load
entirely, taking the GDScript fallback down with it. The fallback then protects
nothing, and `mise run check` passes or fails depending on which machine ran it.

**How to apply:** go through `ClassDB` and call dynamically.

```gdscript
static var _native: Object = (ClassDB.instantiate(&"BladeSolverNative")
        if ClassDB.class_exists(&"BladeSolverNative") else null)
# ...
var out: Dictionary = _native.call(&"simulate", ...)
```

`.call()` rather than `_native.simulate(...)` because a statically-typed
`Object` has no such method at parse time either. Resolve it eagerly in a static
var: `AiBladeRollout` calls `simulate()` from `WorkerThreadPool` tasks, and a
lazy init would race. One shared instance is fine — the method is pure.

## The two backends must stay BIT-identical, and can

Not "within tolerance": `BladeHitScan` turns solver positions into a hit *set*,
so a last-ulp drift near a shape boundary is a different attack, not a smaller
one. Exactness is achievable because GDScript and godot-cpp run the same
`real_t` operators over the same libm, so a transliteration that preserves
**evaluation order** and the **float32/double split** agrees exactly — verified,
not hoped: `test_blade_native_parity.gd` asserts `==` on whole
`PackedVector2Array`s.

**How to apply:** in the C++, `Vector2 * <double>` narrows the scalar to
`real_t` first, so `(delta * diff) * k` is two float32 multiplies, not one
double multiply — write the parens the GDScript's left-to-right order implies.
`PackedFloat32Array` reads become `double` the moment GDScript stores them in a
`var`. `int(x)` truncates toward zero. Pass authored scalars as
`PackedFloat64Array`/`PackedVector2Array`, never packed into float32. And never
add `-ffast-math` / `-march=native` / anything enabling FMA contraction.

## A cached `ptrw()` aliases every snapshot you pushed

Packed arrays are copy-on-write. Taking `ptrw()` once (for speed) and later
`push_back`ing that same array into a result raises its refcount, and subsequent
writes through the cached pointer **retroactively rewrite the stored copy** — so
every trajectory sample ends up equal to the last one. No error.

**How to apply:** push an explicit fresh copy (`resize` + `memcpy`), never the
live buffer.

## `build_profile` is a SCons Variable, not an Import

Passing it in `SConscript("godot-cpp/SConstruct", {...})` is **silently
ignored** — godot-cpp's SConstruct only `Import()`s `api_version`,
`binding_hooks` and `customs` — and you get all ~1000 engine classes generated
and compiled (2072 files, ~10 min) instead of 28 (~1 min).

**How to apply:** `ARGUMENTS.setdefault("build_profile", "build_profile.json")`
before the `SConscript` call. The profile must list the classes **godot-cpp's
own `src/`** includes (`Engine`, `OS`, `SceneTree`, `EditorPlugin`) as well as
yours; base classes come along automatically, siblings do not. Omitting one
fails as a missing `godot_cpp/classes/*.hpp`, which reads like nothing to do
with the blade.

## mise's `pipx:` backend needs `pipx` listed too

`"pipx:scons"` alone makes **every** mise task abort with "pipx is required but
was not found", not just the build. List `pipx = "latest"` in `[tools]` beside
it.
