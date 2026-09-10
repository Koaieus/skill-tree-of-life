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

## Golden trajectories are the solver's determinism contract (#846)

Parity-with-GDScript is **retired** as the contract: `test_blade_goldens.gd`
replays twenty recorded worlds (`test/unit/attack/fixtures/blade_goldens/`) on
the native backend and fails on the first differing line — a one-ulp drift
anywhere is red. It is what catches an FMA contraction slipping back in, a
compiler or flag change, or a "harmless" refactor of the loop once #847 has
deleted the GDScript reference; it is **not** a cross-machine or multiplayer
pin (owner correction on #846 — peers replay the recorded `AttackRecord`).

**How to apply:** when the solver's output is *supposed* to change, re-record
with **`mise run native:goldens`** — the only regeneration path, never
automatic, never a side effect of a red run — review the fixture diff (rows are
6-decimal for reading; the `DIGEST <section>` lines are the bit-exact SHA-256
of the raw float bytes, so a diff touching only DIGEST lines is sub-1e-6
drift), and say WHY in the commit. When `simulate_range`'s signature or a
`BladeState` output gains an axis, add a case to `_CASES` in the same commit;
`_Sink.row()` renders and hashes in one walk, so a value can't reach the text
and miss the digest. A missing binary is a **failure** in `before_each`, never
`pending()`; `mise run native:fetch` cures it.

## The two backends must stay BIT-identical, and can

> Until #847 deletes the GDScript solver. The parity test below is the
> reference-agreement proof for the goldens above; the goldens outlive it.


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
it only happens to be harmless today because both platforms this extension
targets — linux and windows x86_64, the whole matrix as of #844 — have no FMA
in their SSE2 baseline. The pin still matters as insurance against a future
compiler or flag change on either one.

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
a GDScript callback there would eat most of what the backend buys. The clock and
the field are transliterated instead and their state crosses as plain values —
`native_state()` / `bank_from_native()` / `apply_native_state()` are `capture()`
/ `restore()` in Dictionary clothing, so change those and the C++ `FieldCtx`
together. Four traps the plain solver does not have (worked through, with the
decline list and the bench numbers, in `docs/domain/melee-blade-sim.md`):

- **`_strain` is float32 storage with double arithmetic** — the store narrows,
  and `< SHATTER_DISTANCE` compares the narrowed value, so a double accumulator
  "for accuracy" is a different solver. `_edge_residual`'s values are doubles.
- **The contact dictionaries iterate in INSERTION order, and that is a
  summation order** — a key-sorted map is not equivalent.
- **Two sqrt precisions in one function** — `Vector2::length()` is float32,
  `sqrt(d2)` is double; call the godot-cpp methods, never hand-expand.
- **The pushout mutates `positions` mid-loop** — batching the pushes is a
  different solver.

## A stale binary is no binary

A `.so` built before #803 loads fine and has no `simulate_range`; `Object.call()`
on a missing method returns null without an error, so the crash would be
`out["samples"]` a line later on every swing. `_acquire_native` therefore
requires `has_method(&"simulate_range")` and otherwise warns and returns null —
the GDScript fallback, at GDScript cost. **After pulling a change to
`native/src/`, rebuild** (`mise run native:build`); the warning in the log is the
tell that you did not.

## No native binary means PENDING, not pass

> Parity file only. `test_blade_goldens.gd` FAILS without the binary (#846) —
> under #816 it is mandatory and `mise run native:fetch` is the one-line cure.


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

## Two build-config traps, both silent

`build_profile` is a SCons **Variable**, not one of the three names godot-cpp's
SConstruct `Import()`s — pass it in the exports dict and it is ignored, and you
compile ~1000 engine classes (10 min) instead of 28 (1 min). And mise's `pipx:`
backend needs `pipx` listed in `[tools]` beside `pipx:scons`, or **every** mise
task aborts. Both worked through in
`docs/domain/melee-blade-sim.md` → "Building it".

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
report **28 passed, 0 pending**, not 28 pending.

`mise run native:fetch` (#845) runs this same `mise run refresh` itself after
it actually writes a binary — measured, not assumed: a totally fresh checkout
with no `.godot/` at all picks the extension up on its very first headless
pass with no refresh needed (there is no stale cache to be wrong), but an
*existing* checkout gaining a binary later hits exactly this gotcha, so
`native:fetch` refreshes unconditionally on the "wrote something new" path
and is a no-op cost-wise on the steady-state "already present" path.

## `git worktree remove` fails on any worktree that inited the submodule

Since `native/godot-cpp` exists, git refuses with *"working trees containing
submodules cannot be moved or removed"*, and `--force` does not help. It bites
TEARDOWN, so it surfaces with the branch already merged. **Verify the branch is
merged first** — a worktree directory is unrecoverable, and unstaged work inside
it doubly so — then `rm -rf <worktree-dir> && git -C <repo> worktree prune &&
git -C <repo> branch -d <branch>`. Longer version, including what counts as a
merge receipt, in `docs/domain/melee-blade-sim.md` → "Building it".
