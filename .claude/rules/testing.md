---
description: GUT testing framework — how to run, where tests live, common pitfalls
paths:
  - "test/**"
  - "addons/gut/**"
  - ".gutconfig.json"
---

# Testing (GUT)

GUT v9.6.0; `.gutconfig.json` scans `test/unit/` + `test/integration/` (tiers: `docs/domain/testing-tiers.md`).

```
mise run test                                       # both tiers, sharded, ~45 s
mise run test:one -- res://test/unit/test_foo.gd    # one file
mise run test:dir -- res://test/some/path/          # one directory
```

- **`mise run mp:e2e` gates `network/`, `session/`, `command/`** (GUT cannot): read
  which of the six agreements failed; a non-zero divergence count is a regression
  (`docs/domain/multiplayer-harness.md`, "Rung 4").
- The suite is a gate: once at final green, backgrounded, no polling. Full log
  `.godot/gut-last.log`; shard consoles `.godot/gut-shard-N.log`, so an empty
  summary means "still running".
- **Read the verdict with `grep`, never `tail`**: `mise run test 2>&1 | grep -E "failing ·|ERROR task"`.
  The exit trailer follows the verdict; a `tail` shows none and reads as clean.
  Grep the log with `grep -F '[Failed]'`.

## Gotchas

- **GUT options are `-gopt=value`**; a valueless flag is ignored and the whole suite runs, reported as success. Adding a flag? Verify the `scripts` count drops.
- **A parse error silently skips the whole file while the suite reports green** (`Ignoring script … does not extend GutTest`). Tracked vs run count: `git ls-files 'test/unit/**/test_*.gd' 'test/unit/test_*.gd' 'test/integration/**/test_*.gd' 'test/integration/test_*.gd' | sort -u | wc -l` against `grep -oE '[0-9]+ scripts' .godot/gut-last.log | awk '{s+=$1} END {print s}'`; a shortfall is a skipped file. A missing `.gd.uid` is not a cause.
- **Parse-error triggers**: `var x := autofree(T.new())` (use `var x: T = autofree(...)`); `Array[StringName]([&"a"])` is `.tres` syntax (use `var xs: Array[StringName] = [&"a"]`); `:=` on a Variant return.
- **Skipped file or "class_names have not been imported"**: the run refreshes the class cache itself; check `run health:`, then `godot --check-only --script` on the file (`docs/domain/godot-workflow.md`).
- **A parse error in a `pre_run_script` hook makes `godot` spin printing `Project FPS:`** (looks like a hang; `check` misses it). Run `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=<file> -gdir= -glog=3` to see it.
- **Waits are seconds, never ticks** (idle sleep is 1000 µs, so 900 frames is ~1.4 s). `wait_frames`/`wait_until` cost >=1 physics tick: `await` the unit's coroutine, or `wait_until(cond, 15.0)`.
- **`instantiate()` without adding to the tree** resolves `@export` NodePaths cheaply; discard with `queue_free()`, NEVER `free()` (poisons later scripts: they fail to load).
- **Exact combat damage: zero `crit_chance`** — `board.get_stat(&"crit_chance").base_value = 0.0`.
- **A `CommandApplier` still draining at test end aborts Godot (exit -6)**; after each await: `while applier.is_applying: await applier.applying_changed`.
- **Leaf visuals (`RimRing`, `CoreHalos`) have no `class_name`**: `preload` the script, type the local `Node`.
- **A real mouse event needs its own `SubViewport`** (`handle_input_locally = true`, `push_input()`); GUT's UI covers the window. Example: `test_frontmatter_navigation.gd`.
- **A `MultiMesh` read-back asserts nothing headless**; assert the pushed value as a pure function.
- **A leaked `get_tree().paused`** is caught by `test/gut_hooks/pause_state_guard.gd`; prefer asserting the pure function a tween drives.
- **A narrow `test:dir` green does not contain a change to a default, constant or eligibility rule** (#840 broke three tests elsewhere). `grep -rn` the old value across `test/`; re-point characterization tests, don't delete them.
