---
paths:
  - "attack/melee/sim/**"
  - "native/**"
---

# The blade solver's C++ backend (#798, the ONLY backend since #847)

The repo's only GDExtension source, and the only blade solver: the GDScript
mirror is deleted, the binary is mandatory (`mise run native:fetch` /
`native:build`), and a checkout without it gets a `push_error` naming that
command — at simulate time, never at parse time. Full context:
`docs/domain/melee-blade-sim.md` → "One backend, a mandatory binary".

## Never name a GDExtension class as a bare identifier in GDScript

`BladeSolverNative.simulate(...)` is a **parse-time** "identifier not declared"
on any machine where the binary is missing — so `blade_sim.gd` fails to load
entirely and `mise run check` goes red with a name-resolution error instead of
the message that names the fix. That is the whole reason the dynamic call
survived #847's cleanup: the error surface is `BladeSim.simulate_range`'s
`push_error("... run \`mise run native:fetch\` ...")` followed by a `null`
return, and `check` stays clean with or without a binary.

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

## A missing binary returns null, and no caller may guard it

`simulate_range` returns `null` after its `push_error` — for a missing binary
AND for every `_simulate_native` decline (a constraint/driver/field subclass,
a custom ease, `BladeObstacleField.trace`, an array that does not parallel
`positions`). Not an empty trajectory: a zero-step swing hits nothing, which
reads GREEN to every "nothing severed" test — the #823 failure (26 cases
reviewed as verified off a fallback) that #816 exists to kill. The callers
(`MeleeAttackPlan.resolve_against`, `AiBladeRollout`, `SkillBlade`) deref it
on the next line and stop there, with the push_error as the cause.

**How to apply:** never add an `if traj == null` fallback at a call site — a
guard is a fallback wearing a hat. A test that needs a solver-side hook (a
counting constraint, a recording driver) cannot have one any more; re-point it
onto what crosses the boundary: `BladeTrajectory`, `state.speed_history`,
`clock.history` / `field.history` banks (per sample), or `_length_factor`.

## Golden trajectories are the solver's determinism contract (#846)

Parity-with-GDScript is **retired**: `test_blade_goldens.gd` replays twenty
recorded worlds (`test/unit/attack/fixtures/blade_goldens/`) on the native
backend, and a one-ulp drift anywhere is red. Not a cross-machine pin — it
catches an *unintended* solver change (FMA, flags, a refactor), which nothing
else can now that #847 has deleted the GDScript reference. Full contract: `docs/domain/melee-blade-sim.md` →
"Golden trajectories".

**How to apply:** an intentional output change is re-recorded with
**`mise run native:goldens`** — the only regeneration path — reviewed as a
fixture diff (6-decimal rows; the `DIGEST` lines are the bit-exact SHA-256, so
a DIGEST-only diff is sub-1e-6 drift) and justified in the commit. A new
`simulate_range` axis gets a `_CASES` entry in the same commit. No binary is a
**failure** in `before_each`, never `pending()`.

## Float semantics in the C++ are the goldens' semantics — do not "improve" them

The C++ is a transliteration of the GDScript solver it replaced, and the
goldens (#846) were recorded from it while both existed and verified equal.
So `Vector2 * <double>` narrows the scalar to `real_t` first and
`(delta * diff) * k` is two float32 multiplies, not one double multiply;
`PackedFloat32Array` reads widen to `double` where a GDScript `var` did;
`int(x)` truncates toward zero; `round()` is half-away-from-zero (`std::round`,
not `rint`); authored scalars cross as `PackedFloat64Array` /
`PackedVector2Array`, never packed into float32. Any of these "cleaned up" is
a different solver, and the goldens go red for it — which is the point.

`native/SConstruct` **pins `-ffp-contract=off`** for golden stability across
compilers and flags: GCC and Clang default to `-ffp-contract=fast`, and it only
happens to be harmless today because linux and windows x86_64 — the whole
matrix as of #844 — have no FMA in their SSE2 baseline. Never add
`-ffast-math` / `-march=native` / anything enabling contraction.

## Every value simulate() produces must cross the boundary — not just positions

The native `simulate()` returns a Dictionary, and a *missing* key is not an
error anywhere: `speed_history` (#779, what speed-scaled damage reads) once
simply wasn't returned, which would have zeroed blade damage on every swing while
every behavioural test stayed green. Likewise every
`simulate()` PARAMETER: `substeps` and `enable_length_scaling` (#790) are
budget-shaping knobs, and a native path that ignores them runs different physics
rather than failing.

**How to apply:** when `BladeSim.simulate`'s signature or its `BladeState`
outputs change, `test_blade_goldens.gd` gains a `_CASES` entry for the new axis
in the same commit — its serialisation covers `speed_history`, `prev_samples`
and the clock/field banks, and its cases already span `substeps` 1 / 4 / 8,
length scaling on and off, and a blade past `LENGTH_ECC_CEILING`. Cheap parts that run once per resolve (the pivot-eccentricity
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

A `.so` built before #803 loads fine and has no `simulate_range`; one built
before #813 has no `simulate_range_field`. `Object.call()` on a missing method
returns null without an error, so the crash would be `out["samples"]` a line
later on every swing. `_acquire_native` therefore requires **both** methods and
otherwise `push_error`s "stale (built before #813) — run `mise run
native:fetch`" and returns null — the same broken-checkout state as no binary.
**After pulling a change to `native/src/`, rebuild** (`mise run native:build`).

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
after #798 landed: the `.so` was on disk and every native test still reported
*"no native binary in this checkout"*.

**How to apply:** after the first `native:build` in any checkout (and after a
fresh `git worktree`), run `mise run refresh`, then confirm
`res://native/blade_sim.gdextension` is in `.godot/extension_list.cfg`. The
gotcha is invisible without it, which is why `test_blade_goldens.gd`'s
`before_each` FAILS on `BladeSim.backend() != &"native"` rather than skipping
— **never soften that to `pending()`.** Verify with a one-liner:
`mise run test:one -- res://test/unit/attack/test_blade_goldens.gd` must
report every case passed, 0 pending.

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
