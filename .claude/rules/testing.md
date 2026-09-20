---
description: GUT testing framework — how to run, where tests live, common pitfalls
paths:
  - "test/**"
  - "addons/gut/**"
  - ".gutconfig.json"
---

# Testing (GUT)

Framework: [GUT](https://github.com/bitwes/Gut) v9.6.0, installed at `addons/gut/` and enabled as an editor plugin.

## Running tests

```
mise run test                                       # all tests in test/unit/
mise run test:one -- res://test/unit/test_foo.gd    # one file
mise run test:dir -- res://test/some/path/          # one directory
mise run test -- -gselect=melee                     # raw GUT flags pass through
```

Config lives in `.gutconfig.json` at repo root (dirs, log level, exit-on-completion).

**`mise run mp:e2e` is the gate for anything under `network/`, `session/` or
`command/`, and GUT cannot replace it.** It is rung 4 of the multiplayer harness
(#754): two headless OS processes drive the shipped lobby over a real socket,
autoplay a whole run, and are compared on winner, turn count, both fingerprints
and the mirror's mid-run divergence count. ~30s. It is a `mise` task rather than
a test because two worlds cannot share one `SceneTree` once turns tick
(`Entity.GROUP` is tree-wide) and because a suite is not where a 30s wall-clock
run belongs. Read the failure, not just the exit code — it names *which* of the
six agreements broke. Its first run was red for a real sync bug it found
(#756: the mirror opened the run's first turn on its own hero, and a decoded
world left its owner mirrors stale); it is green now, at both `--ai-delay 0`
and `0.4`, so **a non-zero divergence count is a regression, not the baseline**.
See `docs/domain/multiplayer-harness.md`, "Rung 4".

The task prints a verdict (counts, each failing test's first assert + line,
pending, parse-error alarms) and **always keeps the full console output at
`.godot/gut-last.log`**, junit XML beside it. A suite or directory run is
**sharded** over half the cores (`GUT_SHARDS_MAX` moves that ceiling; minus
cores another GUT run on the box is already using; clamped by free RAM;
`GUT_SHARDS=N` pins it outright, `1` = single process), each shard's console written **live** to
`.godot/gut-shard-N.log` (`tail -f .godot/gut-shard-*.log` to see which script
every shard is on; a killed run still leaves them) and merged into
`gut-last.log` / `gut-last.xml` at the end — so the merged files, and the
verdict, arrive LAST: an empty summary means "still running", not "broken".
**Background the run; don't sleep-and-poll.** Each shard boots with a fresh
`user://`, so a test may not depend on the developer's real `settings.cfg`.

**Read the verdict with `grep`, never `tail`.** The `✓/✗ N failing · …` line
leads the summary and is followed by each failing test, the pending list, any
native-backend warning, and Godot's always-present exit trailer — so a
`tail -10`/`-20` shows you the RID-leak trailer and *no verdict at all*, which
reads exactly like a clean run. This is not hypothetical: an orchestrator
reported a FAILING suite as green off a `tail` on 2026-09-10, twice in one
session. Use:
```
mise run test 2>&1 | grep -E "failing ·|ERROR task"
``` A full run costs **~45s wall** (507 scripts / 4716 tests over 8 shards,
2026-09-20; ~32s on all 16, ~380s single-process) — a gate, **run at most once per unit of
work**, at final green; iterate on `check` → `test:one` → `test:dir`. When the
summary elided something, grep the log — `grep -F '[Failed]'`, with `-F`, since a
bare `[Failed]` is a bracket expression matching nearly every line.

**Budget a wait in wall-clock seconds, never in ticks.** The GUT pre-run hook
drops headless godot's idle frame sleep to 1000 µs (~1.5 ms/frame instead of
~12.7 ms), so `await process_frame` is cheap — but it means a loop like
`for _i in 900: await get_tree().process_frame` is now a 1.4 s budget, not 15 s,
and a tween that eases on delta moves a tenth as far in 120 frames. Wait on the
condition with a seconds cap: `await wait_until(func(): return not
_bs.is_launching, 15.0)`, or `Time.get_ticks_msec()` against a deadline when
you want the elapsed time back. Timers, tweens and physics ticks are unchanged.

## Layout

- Two tiers, split by **what a test drives, never by speed** (#360): `test/unit/` is the fast tier (hand-built fixtures, no composed scene, no wall clock) and `test/integration/` drives a composed level/menu scene (`game_root.tscn`, `level.tscn`, a sandbox, `meta_root.tscn`) or the real clock — 15 s budget per script. Subdir names mirror `test/unit/`'s. `mise run test` runs both; `mise run test:unit` the fast tier alone; `test:dir -- res://test/integration/` the other. Which tier an assert belongs in — the formula, a composed scene or the real clock, two processes (`mp:e2e`) — is decided by `docs/domain/testing-tiers.md`; its §7/§8 are why a test fires the signal and never writes another unit's `_field`.
- `test/unit/test_*.gd` — unit tests. Filename must start with `test_`; functions must start with `test_`.
- Class extends `GutTest`. Common asserts: `assert_eq`, `assert_ne`, `assert_null`, `assert_not_null`, `assert_true`, `assert_almost_eq`. Lifecycle: `before_all`, `before_each`, `after_each`, `after_all`.

**GUT options are `-gopt=value`; a valueless flag is ignored and the whole suite
runs instead, reported as success** — and `-gtest=<path>` alone doesn't override
the config `dirs`, which is why `.mise/tasks/test` also emits `-gdir=`. Adding a
flag there? Verify the `scripts` count actually drops.

## Gotchas

- **`wait_frames` is `wait_physics_frames`** (~16.7 ms per tick, immune to the 1000 µs idle-frame hook) and `wait_until` polls in `_physics_process` too, so any GUT wait costs ≥1 physics tick. **Why:** #978 found 23 s of tooltip tests that were nothing but frame budgets. **How to apply:** `await` the unit's own coroutine (`await tt.show_for()`) for the exact condition; a `wait_until` is for a condition you cannot await.
- **A test whose setup writes ANOTHER unit's internals has found a seam, not a fixture.** `blade.state.pivot_index`, `preview._live_swing`, `addon._phase = …`, a visual's `modulate.a` — poked from a test that is not about that class — means the fact belongs to that class and the production code mirrors the same reach-in. Make the owner expose it (a marker, a signal, an entry point, a stored sample) and test against that; if that is out of scope, file it and say so in the test's comment. Tests of the class under test reaching its own `_private` state are fine; it is the *cross-unit* write that is the tell.

- **Class-cache miss, not your test: "GUT class_names have not been imported", or a `Scripts`/`Tests` count that dropped after a rebase / is low in a fresh worktree.** A new worktree starts with no `.godot/` class cache, and a rebase (or any new `class_name`, or a GUT update) leaves the existing one stale; scripts referencing the unknown type fail to parse and GUT skips them silently (see below). One fix covers all of it: **`mise run refresh`**, then re-run. Don't audit your test file first.
- **Autoloads are available in tests** (`StatRegistry`, `Events`, etc.) — GUT boots the project normally.
- **Scene/node tests** must `add_child(node)` and usually `await get_tree().process_frame` before assertions; remember `queue_free()` in `after_each` (or use GUT's `autofree(node)`).
- **`@tool` scripts** (SkillNode, Entity, Graph) run in-editor; their tests should still operate on runtime instances, not editor-loaded resources, unless that's specifically what you're testing.
- **A lambda captures locals BY VALUE — a `var n := 0` counter inside a signal handler never moves.** `sig.connect(func(): n += 1)` increments the closure's own copy; the outer `n` stays 0 and the assert fails with no hint that the signal *did* fire. It reads exactly like "the signal never emitted" — the wrong thing to go debug. Count into a reference type: `var seen: Array[int] = []` + `seen.append(1)`, or a script member var. (Arrays/Dictionaries *do* work — same object — which makes it confusing.)
- **A parse error makes GUT *silently skip the whole file* — the suite still reports "all passed".** GUT catches the failed load and logs `Ignoring script … because it does not extend GutTest`, then moves on; the totals just don't include that file. So a green run with an *unchanged* test count after you added tests means your new file didn't run. **Always confirm the `Scripts`/`Tests` totals went UP**, not just that it says passed (the task surfaces the `Ignoring script` line under `run health:`, but the totals are still yours to check). Classic trigger: `var x := autofree(SomeType.new())` — `autofree()` returns untyped, so `:=` can't infer the type and the file fails to parse. Use `var x := SomeType.new()` then `autofree(x)` (or annotate explicitly: `var x: SomeType = autofree(...)`). Second trigger: **`Array[StringName]([&"a"])` is `.tres` serialization syntax, not GDScript** — in a script it parses as *"Cannot call on an expression"*. Declare the typed local instead: `var xs: Array[StringName] = [&"a"]`. Third: `:=` on a Variant-returning call (see `test_tag_channel.gd`). The `Ignoring script` line is the only signal; `mise run test` reprints it under `run health:`.
- **The theory-free version of that check: the tracked test-file count and GUT's `scripts` count must be EQUAL.** Reading "did the total go UP" needs a remembered baseline, which goes stale the moment master moves under you. This doesn't:
  ```
  git ls-files 'test/unit/**/test_*.gd' 'test/unit/test_*.gd' 'test/integration/**/test_*.gd' 'test/integration/test_*.gd' | sort -u | wc -l
  grep -oE '[0-9]+ scripts' .godot/gut-last.log | awk '{s+=$1} END {print s}'   # sharded: one count per shard, summed
  ```
  `.gutconfig.json` scans `res://test/unit/` and `res://test/integration/` with `include_subdirs` and GUT collects `test_*.gd` only, so those two numbers are the same number counted twice (after `mise run test:unit`, compare against the two `test/unit/` globs alone). **Any shortfall means a file was skipped** — parse error, stale class cache, a breaking rename landed underneath you — without needing a theory of *why* first. Two traps: bare `git ls-files 'test/**/*.gd'` gives a much larger count (non-`test_` helpers and fixtures — not a problem, don't chase it), and the glob must stay pinned to the two `dirs` entries because that is all GUT scans; a `test_*.gd` added under `test/perf/` would inflate the git side and read as a false skip. Verified on 424/424, 2026-09-08; 508/508 with the integration tier, 2026-09-20.
- **A missing `.gd.uid` sidecar is NOT a cause of a skipped file.** Plausible, repeated, and false: a new test file was collected and run by both `test:one` and the directory sweep with no sidecar committed (#802, 2026-09-08). If the counts above disagree, diagnose collection — don't reach for `mise run refresh` on the theory that the `.uid` is missing.
- **Asserting scene WIRING? `instantiate()` without adding to the tree resolves `@export` NodePaths without paying a level's `_ready` — but discard it with `queue_free()`, NEVER `free()`.** A bare `free()` on a level-sized un-parented instance poisons the rest of the run: later scripts fail to *load* (`Ignoring script … does not extend GutTest`), `hud_root.tscn` instantiates as null, nothing is attributed to the test that did it, and every one of them passes in isolation. See `test_link_mount.gd::_discard`.
- **A fixture asserting exact combat damage must zero `crit_chance`.** The default board has a 5 % baseline, all three modes roll it per hit since #507, and `BattleSystem` stamps a random seed per launch — so an exact-HP assert behind `launch_attack()` flakes a few runs in a hundred. One line: `board.get_stat(&"crit_chance").base_value = 0.0`. Hand-built `DamageInstance`s and unstamped `plan.resolve()` are unaffected.
- **Driving a `CommandApplier` and the test ends with the queue still draining → Godot ABORTS (exit -6, "freed while a signal is being emitted"), it does not fail.** `command_applied` fires *inside* the applier's guard, so anything that resumes on it — `BattleSystem.launch_attack`, a sandbox panel's submit helper — returns while `_drain` is still unwinding; GUT's autofree then deletes your nodes out from under it. The backtrace names the applier and the VFX coordinator, not your test. One line after each await: `while applier.is_applying: await applier.applying_changed`.
- **Leaf visual components have no `class_name` — a test must `preload` the script to reach their enums/constants.** `RimRing`, `CoreHalos`, `InnerDisk` etc. deliberately declare none (only the base classes do — see `.claude/rules/skill-node-visuals.md`), so `RimRing.HeightPreset.MESA` in a test is a **parse error**, and per the gotcha above GUT then *skips the whole file while still reporting green*. Use `const _RIM_RING := preload("res://skill_node/visuals/rim_ring.gd")` and go through that. Same reason a `var x: RimRing = ...` annotation won't compile — type the local as `Node`.
- **A test that pushes a REAL mouse event must run in its own `SubViewport` — GUT's own UI is over the window.** `add_child_autofree()` parents under the GUT runner, so the click lands on GUT's panels and never reaches your scene, failing exactly like the dispatch bug such a test exists to catch. Host it: a `SubViewport` with `handle_input_locally = true`, then `push_input()` at `get_global_transform_with_canvas() * (size * 0.5)` (viewport-local, already carries any `Camera2D`). Worth it only for the one test per feature that proves *dispatch* — drive the seam directly for the rest. Worked example: `test_frontmatter_navigation.gd::test_a_real_click_reaches_a_menu_node_through_the_whole_shell`.
- **A `MultiMesh` push-then-read-back test asserts NOTHING under headless.** `get_instance_transform_2d()` returns identity from the dummy driver, so the assert passes against an all-zero transform — the blind spot that hid #413's invisible edges. Assert the pushed value as a pure function instead. See `docs/domain/godot-workflow.md`.
- **A leaked `get_tree().paused` is caught by a suite-level guard (#737), not by hunting the leaking test.** `ui/pause_menu.gd`'s `_toggle` is the only writer of that flag in the repo, and it is sticky SceneTree state GUT never resets between scripts — a `Tween` (`create_tween()`, default `TWEEN_PAUSE_BOUND`) silently STOPS while paused, while a `SceneTreeTimer` (`process_always = true` by default) keeps firing, so a tween-sampling test fails downstream reading like a bug in the code under test. `test/gut_hooks/pause_leak_pre_run_hook.gd` (wired as `.gutconfig.json`'s `pre_run_script`) fails the just-finished script's last real test and resets the flag whenever it catches one leaked — see `PauseStateGuard` (`test/gut_hooks/pause_state_guard.gd`) and `test/unit/test_pause_state_guard.gd`. The guard is a safety net, not a license to sample tweens: **prefer asserting on the pure function a tween drives** (`transform_at`/`charge_pose` style, per `FrontmatterCamera`) **over sampling the tween itself** — it doesn't depend on suite ordering to pass.
- **A parse error in a `pre_run_script`/`post_run_script` hook doesn't fail the run — it makes `godot` spin forever printing `Project FPS:` lines, which reads exactly like a hang, and `mise run check`'s editor pass does not catch it** (the file isn't referenced by any scene, so nothing pulls it into that pass — same gap `.claude/rules/godot-workflow.md` names for `--check-only --script`, just via a different door). Cause: GUT's `_validate_hook_script` fails to `load()` the broken script, `_init_run` aborts before anything calls `quit()`, and the process just idles. `var x := gut.get_tree()` is the concrete trigger in `pause_leak_pre_run_hook.gd` — `gut` is untyped, so `:=` can't infer a type from the call (same family as the `:=`-on-Variant gotcha above). Diagnose with `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=<any file> -gdir= -glog=3` run directly (not through the python wrapper, which buffers all output until exit) — the `SCRIPT ERROR: Parse Error` prints immediately, before the spin.
- **A narrow `test:dir` green does not mean a change is contained — and the author is the last person who can tell.** A drone verified #840 (lobby AI default core flipped, every core made pickable by every slot) with `test:dir -- res://test/unit/ui/` and was green and honest; three tests in `test/unit/session/` were asserting exactly the behaviour the issue existed to remove, and only the full suite found them. The tell is behavioural, not structural: a change to a **default, a constant, or a pickability/eligibility rule** is read by tests that never import the file you edited. Before trusting a narrow run, `grep -rn` the *old* value across `test/` — `grep -rn "basic_enemy_core" test/` would have found all three in one call. When such a change lands, expect stale **characterization** tests, and re-point them onto the new invariant rather than deleting them: two of those three had lost their subject entirely (there is no "player-only core" left once every core is `pickable_in = 3`), so deleting would have silently dropped the coverage.
