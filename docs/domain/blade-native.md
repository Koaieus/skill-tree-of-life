# The blade solver's C++ backend

The repo's only GDExtension source and the only blade solver. The GDScript
mirror is deleted; the binary is mandatory. The gotchas that bite while editing
live in `.claude/rules/blade-native.md`; this is the contract behind them. The
solver's behaviour (what the maths does) is `docs/domain/melee-blade-sim.md`;
its cost is `docs/domain/blade-perf.md`.

## One backend, a mandatory binary

The stepping loop lives in `native/src/blade_solver_native.cpp`, reached from
`blade_sim.gd` through a `ClassDB` dynamic call (the class is never named as an
identifier, so a missing extension is not a parse error and `mise run check`
stays clean). Staying in GDScript: `BladeState`, drivers and constraints as
descriptors, the pop/gate loop, the `_length_factor` BFS (computed once per
resolve and passed in, so the length axis has one definition), and the dispatch
site.

`mise run native:build` (run by `mise install`'s postinstall hook) puts the
binary in `native/bin/`; `mise run refresh` lists it; `BladeSim.backend()`
reports `&"native"`. Without it:

- the first simulated swing `push_error`s *"no native blade solver in this
  checkout — run `mise run native:build`, then `mise run refresh`"* and
  `simulate_range` returns **`null`**, never a zero-step trajectory (a swing
  that hits nothing reads green to every "nothing severed" test). The callers
  (`MeleeAttackPlan.resolve_against`, `AiBladeRollout`, `SkillBlade`) deref it
  on the next line; none guards it, because a guard is a fallback wearing a hat.
- `test_blade_native_binary.gd` **fails** in `before_each`, never `pending()`.
- A binary lacking `simulate_range` or `simulate_range_field` is "stale" and
  treated as no binary, with the same cure (`_acquire_native` requires both).
- The exporter hard-fails on a `.gdextension` key whose file is absent, so
  `mise run build` refuses up front ([exporting.md](exporting.md)). The library
  ships beside the executable, not inside the pck.

## No golden trajectories

Owner, 2026-10-16: no goldens until most of the game has shipped. The recorded
trajectory replays and their `native:goldens` task are retired; a solver change
is checked by the behaviour tests, and a drift too small to change any outcome is
accepted until the owner revives goldens.

## Float semantics are frozen

The C++ reads like the transliteration it is: same expressions, same evaluation
order, same float32 (`real_t`) vs `double` split. `BladeHitScan` turns
positions into a hit *set*, so a 1e-7 drift next to a shape boundary is a
different attack; a "cleanup" that moves a trajectory one ulp is a solver change.
`native/SConstruct` pins **`-ffp-contract=off`** (GCC/Clang default to `fast`;
the solver stays reproducible today because the x86_64 SSE2 baseline has no FMA, so the flag
is insurance). Never add `-ffast-math` / `-march=native`.

**Everything `simulate()` takes and produces must cross the boundary.** A
missing returned key (`speed_history`) or an ignored parameter (`substeps`,
`enable_length_scaling`) is a silent failure, not an error: different physics,
every behavioural test green. `length_factor` is the one deliberate exception:
it crosses precomputed.

**Solver-side test hooks do not exist.** The native solver refuses constraint /
driver subclasses by exact `get_script()` check (an overridden `project()` /
`apply()` would otherwise be ignored silently). A test observes what crosses the
boundary: the trajectory, `state.speed_history`, the `clock.history` /
`field.history` banks, `_length_factor`.

## The defender half crosses as DATA, never as a callback

`simulate_range_field` is the second entry point: the same loop (`run_range`
takes a `FieldCtx *`, null for a fieldless swing) with a `BladeSwingClock`
and/or `BladeObstacleField`. A per-iteration callback was rejected on cost:
`project()` runs in the innermost loop, millions of crossings a swing. State
crosses instead: `native_inputs()` (the immutable half: zones as four parallel
arrays, live edges, `vertex_radii`, and `vertex_restitution` (optional key:
absent or all-zero → null, the loop untouched), driven particles, `prepare()`'s incidence flattened to a
CSR, and `CONTACT_SLOP` / `CONTACT_HYSTERESIS` / `SHATTER_DISTANCE` /
`EDGE_RADIUS` **passed, not restated in C++**), `native_state()` in, and
`clock_state` / `field_state` / `clock_history` / `field_history` back.
`native_state()` / `bank_from_native()` / `apply_native_state()` are `capture()`
/ `restore()` in Dictionary clothing; change those and the C++ `FieldCtx`
together.

Four traps the plain solver lacks:

- **`_strain` is float32 storage with double arithmetic.** The read widens, the
  add and `maxf` run in double, the **store narrows**, and `< SHATTER_DISTANCE`
  compares the narrowed value. `_edge_residual`'s values are plain doubles.
- **The contact dictionaries iterate in INSERTION order, and that is a
  summation order.** A particle pushed by zone 3 then zone 7 keeps zone 7's
  value at zone 3's position. The C++ uses godot `Dictionary`s for exactly this;
  `test_a_multi_zone_cluster_matches_bit_for_bit` pins it.
- **Two sqrt precisions in one function.** `Vector2::length()` is float32,
  `sqrt(d2)` is double. Call the godot-cpp `Vector2` methods; never hand-expand.
- **The pushout mutates `positions` mid-loop.** Zone z+1 sees zone z's
  correction. Batching the pushes is a different solver.

`simulate_range` transliteration details only the continuation cases catch:
damping multiplies `v` BEFORE the speed is read (so `speed_history` sees the
damped velocity), and `t0` is `(double)(offset + step) * dt` (integers added,
then widened).

**`BladeHitScan` is not ported.** It calls `intersect_shape()` against the
physics server, which is neither freely thread-safe nor a numeric loop. Solver
cost is `samples x substeps x constraints`, hit-scan cost is `samples x edges`;
only the first got cheap.

## The decline list

Every entry is a `push_error` naming the check, then `null` from
`simulate_range` — a call-site programming error, never a supported state:

- a constraint or driver outside the subset (exact `get_script()`), including a
  `BladeArcDriver` with a custom ease (a new ease is a C++ change);
- a `BladeObstacleField` **subclass**;
- `field.trace` on (the diagnostic rows have no native producer);
- `prev_positions`, `damping` or `radii` arrays that do not parallel `positions`;
- an empty Dictionary back from the C++, which already printed its `ERR_FAIL`.

No authored scene, resource or spawn path builds any of these; they exist only
in tests and benches.

## Building it

- `mise run native:build`; append `-- template_release` for exports and a
  platform after that (`-- template_release windows`) to cross-compile on the
  llvm-mingw toolchain `mise.toml` pins. godot-cpp is a submodule at
  `native/godot-cpp` (a fresh clone needs a recursive init). `native/bin/` is
  gitignored.
- **Compiled locally, always.** There is no CI. `mise install`'s postinstall
  runs `native:build`; nothing is fetched or published, so a fresh checkout can
  never pick up a stale binary. A new worktree gets `native/bin/` copied in
  from `.worktreeinclude` — by Claude Code for agent worktrees, by `mise run
  worktree:new` otherwise (which builds in the new worktree if there is
  nothing to copy). A copied binary can still predate the sources: `mise run
  land` runs `native:build` in the rebased tree (initing the submodule) whenever
  `native/` inputs differ between the branch point and the rebased tip.
- **The supported matrix is what is declared and built:** `blade_sim.gdextension`
  declares four keys (linux and windows x86_64, debug and release). Declare
  nothing you do not build; add a target in the same change as its binary.
- **`build_profile` is a SCons Variable, not an Import.** Passing it in
  `SConscript("godot-cpp/SConstruct", {...})` is silently ignored and compiles
  ~1000 engine classes (~10 min) instead of 28 (~1 min). Use
  `ARGUMENTS.setdefault("build_profile", "build_profile.json")` before the
  `SConscript` call. The profile must list the classes godot-cpp's own `src/`
  includes (`Engine`, `OS`, `SceneTree`, `EditorPlugin`) as well as yours; an
  omission fails as a missing `godot_cpp/classes/*.hpp`.
- **mise's `pipx:` backend needs `pipx` listed too:** `"pipx:scons"` alone makes
  every mise task abort with "pipx is required but was not found". List
  `pipx = "latest"` in `[tools]` beside it.
- **Worktree teardown** with the submodule inited: see `docs/domain/git-gotchas.md`.
