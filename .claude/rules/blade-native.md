---
paths:
  - "attack/melee/sim/**"
  - "native/**"
---

# The blade solver's C++ backend — the only backend

The binary is mandatory (`mise run native:build`, run by `mise install`'s
postinstall); a checkout without it gets a `push_error` naming that command at
simulate time, never at parse time. Contract, goldens, decline list and build
notes: `docs/domain/blade-native.md`. Behaviour: `docs/domain/melee-blade-sim.md`.

## Never name a GDExtension class as a bare identifier in GDScript

`BladeSolverNative.simulate(...)` is a parse-time "identifier not declared" where the
binary is missing, so `blade_sim.gd` fails to load and `check` goes red with a name
error instead of the message that names the fix. **How to apply:** go through
`ClassDB` and `.call()`, resolved eagerly in a static var (`AiBladeRollout` calls it
from `WorkerThreadPool` tasks; a lazy init would race; the method is pure).

## A missing binary returns null, and no caller may guard it

`simulate_range` returns `null` after its `push_error`, never an empty trajectory (a
zero-step swing reads GREEN to every "nothing severed" test). **How to apply:** never
add an `if traj == null` fallback; a test needing a solver-side hook re-points onto
what crosses the boundary (`BladeTrajectory`, `speed_history`, `clock.history` /
`field.history`, `_length_factor`).

## Goldens are the determinism contract

`test_blade_goldens.gd` replays recorded worlds; a one-ulp drift is red. Re-record an
intentional change with **`mise run native:goldens`**, review the fixture diff, justify
it in the commit; a new axis gets a `_CASES` entry in the same commit. No binary is a
**failure** in `before_each`, never `pending()`.

## Float semantics, boundary values and the defender half

The C++ is a frozen transliteration: `Vector2 * <double>` narrows first,
`PackedFloat32Array` reads widen, `int()` truncates, authored scalars cross as
float64; any "cleanup" is a different solver (`-ffp-contract=off` is pinned; never
`-ffast-math` / `-march=native`). Every `simulate()` parameter and output must cross
the boundary: a missing key (`speed_history`) or ignored parameter (`substeps`) is
not an error, just different physics under green tests. The defender half crosses as
DATA, never a callback; change `native_state()` / `bank_from_native()` /
`apply_native_state()` and the C++ `FieldCtx` together. Summation-order and
precision traps (`_strain` float32 store, insertion-ordered contact dictionaries,
float32 `length()` vs double `sqrt`, in-loop pushout): `docs/domain/blade-native.md`.

## Stale binary, stale cache

`_acquire_native` requires both `simulate_range` and `simulate_range_field`, so after
pulling a change to `native/src/`, rebuild (`mise run native:build`). A built `.so` is
not a loaded extension: Godot's `.godot/extension_list.cfg` cache can predate
`native/blade_sim.gdextension`, so after the first build in an existing checkout (or a
fresh worktree; `worktree:new` does it) run `mise run refresh` and confirm the entry.
Verify: `mise run test:one -- res://test/unit/attack/test_blade_goldens.gd`, 0 pending.

## A cached `ptrw()` aliases every snapshot you pushed

Writes through a cached `ptrw()` after `push_back`ing that packed array retroactively
rewrite the stored copy (copy-on-write refcount), so every trajectory sample equals the
last. Push a fresh copy (`resize` + `memcpy`), never the live buffer.

## Build-config traps

`build_profile` is a SCons Variable (in the `Import` dict it is silently ignored: ~10
min build instead of ~1); mise's `pipx:` backend needs `pipx` in `[tools]` or every
mise task aborts. Worktree teardown with the submodule inited:
`docs/domain/git-gotchas.md`.
