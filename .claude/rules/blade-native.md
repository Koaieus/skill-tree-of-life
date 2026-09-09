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
`var`. `int(x)` truncates toward zero. `round()` is half-away-from-zero
(`std::round`, not `rint`). Pass authored scalars as
`PackedFloat64Array`/`PackedVector2Array`, never packed into float32. And never
add `-ffast-math` / `-march=native` / anything enabling FMA contraction.

`native/SConstruct` **pins `-ffp-contract=off`** for exactly that last reason.
Do not drop it as redundant: GCC and Clang default to `-ffp-contract=fast`, and
it only happens to be harmless today because the baseline x86_64 target has no
FMA. `blade_sim.gdextension` already lists `linux.arm64` and macOS, where FMA
*is* baseline — there the default silently fuses `a * b + c` and the solver
drifts on one platform only.

## Every value simulate() produces must cross the boundary — not just positions

The native `simulate()` returns a Dictionary, and a *missing* key is not an
error anywhere: `speed_history` (#779, what speed-scaled damage reads) once
simply wasn't returned, which would have zeroed blade damage on every machine
with a built binary while a GDScript-only CI stayed green. Likewise every
`simulate()` PARAMETER: `substeps` and `enable_length_scaling` (#790) are
budget-shaping knobs, and a native path that ignores them runs different physics
rather than failing.

**How to apply:** when `BladeSim.simulate`'s signature or its `BladeState`
outputs change, the parity test gains a case for the new axis in the same
commit. `test_blade_native_parity.gd` compares `speed_history` elementwise and
runs cases at `substeps` 1 / 4 / 8, length scaling on and off, and a blade past
`LENGTH_ECC_CEILING` — a parity test that only checked `samples` would have
caught none of it. Cheap parts that run once per resolve (the pivot-eccentricity
BFS behind `length_factor`) stay in GDScript and are passed in precomputed: one
definition of the rule, not two. Since #803 the C++ entry point is
`simulate_range` (continued `prev_positions`, integer `step_offset`, per-particle
`damping` in; `prev_samples` out), and since #813 a second one,
`simulate_range_field`, for a swing that has a `BladeSwingClock` and/or a
`BladeObstacleField` — which since #811 is every swing near ANY defender, wall
or plate, i.e. most of them. Two transliteration details that only the
continuation cases catch: damping multiplies `v` BEFORE the speed is read (so
`speed_history` sees the damped velocity), and `t0` is `(double)(offset + step)
* dt` — integers added, then widened, never a float origin carried across chunks.

## The defender half crosses as DATA, never as a callback (#813)

`BladeObstacleField.project()` runs once per constraint-projection iteration, so
a callback into GDScript there would have eaten most of what the backend buys
(k=100, solver only: native 27 ms braced / 16 ms whip vs GDScript 597 / 251).
The clock and the field are transliterated instead, and their state crosses as
plain values — `native_inputs()` (immutable: zones, live edges, driven
particles, `prepare()`'s incidence as a CSR, and the four tuning constants,
**passed rather than restated in C++**), `native_state()` in,
`clock_state` / `field_state` / `clock_history` / `field_history` back.

**How to apply:** `native_state()` / `bank_from_native()` / `apply_native_state()`
are `capture()` / `restore()` in Dictionary clothing — change those, and the C++
`FieldCtx`, together. Four traps the plain solver never hits:

- **`_strain` is float32 storage with double arithmetic** — read widens, add and
  `maxf` in double, the **store narrows**, and `< SHATTER_DISTANCE` compares the
  narrowed value. A double accumulator "for accuracy" is a different solver.
  `_edge_residual`'s values are the opposite: plain GDScript floats, i.e. doubles.
- **`_contact_particles` / `_contact_edges` / `_contact_normals` iterate in
  INSERTION order, and that is a summation order** — several particles bank onto
  one edge per substep, and a particle touched by zone 3 then zone 7 keeps zone
  7's *value* at zone 3's *position*. A key-sorted map is not equivalent; they
  are godot `Dictionary`s in the C++ for that reason (Variant cost is per
  contact, not per iteration).
- **Two sqrt precisions in one function** — `delta.length()` is the engine's
  float32 `Vector2::length()`, `var d := sqrt(d2)` is GDScript's double sqrt.
  Call the godot-cpp `Vector2` methods, never hand-expand either.
- **The pushout mutates `positions` mid-loop** — zone z+1 sees zone z's
  correction. Batching the pushes is a different solver.

Declines (falling back, never approximating): a binary predating #813 — a
SECOND capability flag, `BladeSim._native_field`, because a #803 binary must
keep its plain-swing native path — a `BladeObstacleField` subclass,
`field.trace` on, and a `radii` array not parallel to `positions`.

## A stale binary is no binary

A `.so` built before #803 loads fine and has no `simulate_range`; `Object.call()`
on a missing method returns null without an error, so the crash would be
`out["samples"]` a line later on every swing. `_acquire_native` therefore
requires `has_method(&"simulate_range")` and otherwise warns and returns null —
the GDScript fallback, at GDScript cost. **After pulling a change to
`native/src/`, rebuild** (`mise run native:build`); the warning in the log is the
tell that you did not.

## No native binary means PENDING, not pass

The GDScript fallback is a supported state, so the parity file cannot fail
there — but it must not report *green* either, or "parity verified" means
nothing on the machines that never ran `scons`. `pending()`, and the suite
verdict shows it.

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

## A built `.so` is not a loaded extension — refresh after the first build

`mise run native:build` succeeding does **not** mean `BladeSim.native_available()`
is true. Godot caches its extension roster in `.godot/extension_list.cfg`, and a
checkout whose cache predates `native/blade_sim.gdextension` never loads the
binary no matter how many times you rebuild it. Observed on master immediately
after #798 landed: the `.so` was on disk and all 13 parity cases still reported
*"no native binary in this checkout"*.

**How to apply:** after the first `native:build` in any checkout (and after a
fresh `git worktree`), run `mise run refresh`, then confirm
`res://native/blade_sim.gdextension` is in `.godot/extension_list.cfg`. The
gotcha is invisible without it, which is why the parity test's no-binary arm is
`pending()` and not `pass_test()` — **never soften that back to a pass.** Its
`test_the_native_path_actually_ran` guard exists for the same reason: without it,
every parity case passes vacuously the moment `_simulate_native` declines a
fixture, comparing GDScript to GDScript. Verify with a one-liner:
`mise run test:one -- res://test/unit/attack/test_blade_native_parity.gd` must
report **26 passed, 0 pending**, not 26 pending.

## `git worktree remove` now fails on any worktree that inited the submodule

Since `native/godot-cpp` exists, a worktree where someone ran
`git submodule update --init` cannot be torn down the normal way — git refuses
with *"working trees containing submodules cannot be moved or removed"*, and
`--force` does not help. This bites teardown, not setup, so it surfaces at the
end of a unit when the branch is already merged.

**How to apply:** confirm the branch is merged first (`git -C <repo> log
--oneline master..<branch>` prints nothing, or you have a diffstat receipt that
its content landed rebased), then delete the worktree directory and let git
notice: `rm -rf <worktree-dir> && git -C <repo> worktree prune && git -C <repo>
branch -d <branch>`. Verify the branch is merged **before** the delete — a
worktree directory is unrecoverable, and unstaged work inside it doubly so.
