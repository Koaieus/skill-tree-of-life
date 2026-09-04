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
`.godot/gut-last.log`**, junit XML beside it. That log is written **live**
(`tail -f` it to see which script GUT is on, and a killed run still leaves it),
while the verdict is the LAST thing printed — an empty summary means "still
running", not "broken". **Background the run; don't sleep-and-poll.** A full run costs **~215s** (409 scripts / 3807 tests, 2026-09-04) — a gate,
**run at most once per unit of work**, at final green; iterate on `check` →
`test:one` → `test:dir`. When the
summary elided something, grep the log — `grep -F '[Failed]'`, with `-F`, since a
bare `[Failed]` is a bracket expression matching nearly every line.

## Layout

- `test/unit/test_*.gd` — unit tests. Filename must start with `test_`; functions must start with `test_`.
- Class extends `GutTest`. Common asserts: `assert_eq`, `assert_ne`, `assert_null`, `assert_not_null`, `assert_true`, `assert_almost_eq`. Lifecycle: `before_all`, `before_each`, `after_each`, `after_all`.

**GUT options are `-gopt=value`; a valueless flag is ignored and the whole suite
runs instead, reported as success** — and `-gtest=<path>` alone doesn't override
the config `dirs`, which is why `.mise/tasks/test` also emits `-gdir=`. Adding a
flag there? Verify the `scripts` count actually drops.

## Gotchas

- **Class-cache miss, not your test: "GUT class_names have not been imported", or a `Scripts`/`Tests` count that dropped after a rebase / is low in a fresh worktree.** A new worktree starts with no `.godot/` class cache, and a rebase (or any new `class_name`, or a GUT update) leaves the existing one stale; scripts referencing the unknown type fail to parse and GUT skips them silently (see below). One fix covers all of it: **`mise run refresh`**, then re-run. Don't audit your test file first.
- **Autoloads are available in tests** (`StatRegistry`, `Events`, etc.) — GUT boots the project normally.
- **Scene/node tests** must `add_child(node)` and usually `await get_tree().process_frame` before assertions; remember `queue_free()` in `after_each` (or use GUT's `autofree(node)`).
- **`@tool` scripts** (SkillNode, Entity, Graph) run in-editor; their tests should still operate on runtime instances, not editor-loaded resources, unless that's specifically what you're testing.
- **A lambda captures locals BY VALUE — a `var n := 0` counter inside a signal handler never moves.** `sig.connect(func(): n += 1)` increments the closure's own copy; the outer `n` stays 0 and the assert fails with no hint that the signal *did* fire. It reads exactly like "the signal never emitted" — the wrong thing to go debug. Count into a reference type: `var seen: Array[int] = []` + `seen.append(1)`, or a script member var. (Arrays/Dictionaries *do* work — same object — which makes it confusing.)
- **A parse error makes GUT *silently skip the whole file* — the suite still reports "all passed".** GUT catches the failed load and logs `Ignoring script … because it does not extend GutTest`, then moves on; the totals just don't include that file. So a green run with an *unchanged* test count after you added tests means your new file didn't run. **Always confirm the `Scripts`/`Tests` totals went UP**, not just that it says passed (the task surfaces the `Ignoring script` line under `run health:`, but the totals are still yours to check). Classic trigger: `var x := autofree(SomeType.new())` — `autofree()` returns untyped, so `:=` can't infer the type and the file fails to parse. Use `var x := SomeType.new()` then `autofree(x)` (or annotate explicitly: `var x: SomeType = autofree(...)`). Second trigger: **`Array[StringName]([&"a"])` is `.tres` serialization syntax, not GDScript** — in a script it parses as *"Cannot call on an expression"*. Declare the typed local instead: `var xs: Array[StringName] = [&"a"]`. Third: `:=` on a Variant-returning call (see `test_tag_channel.gd`). The `Ignoring script` line is the only signal; `mise run test` reprints it under `run health:`.
- **Asserting scene WIRING? `instantiate()` without adding to the tree resolves `@export` NodePaths without paying a level's `_ready` — but discard it with `queue_free()`, NEVER `free()`.** A bare `free()` on a level-sized un-parented instance poisons the rest of the run: later scripts fail to *load* (`Ignoring script … does not extend GutTest`), `hud_root.tscn` instantiates as null, nothing is attributed to the test that did it, and every one of them passes in isolation. See `test_link_mount.gd::_discard`.
- **A fixture asserting exact combat damage must zero `crit_chance`.** The default board has a 5 % baseline, all three modes roll it per hit since #507, and `BattleSystem` stamps a random seed per launch — so an exact-HP assert behind `launch_attack()` flakes a few runs in a hundred. One line: `board.get_stat(&"crit_chance").base_value = 0.0`. Hand-built `DamageInstance`s and unstamped `plan.resolve()` are unaffected.
- **Driving a `CommandApplier` and the test ends with the queue still draining → Godot ABORTS (exit -6, "freed while a signal is being emitted"), it does not fail.** `command_applied` fires *inside* the applier's guard, so anything that resumes on it — `BattleSystem.launch_attack`, a sandbox panel's submit helper — returns while `_drain` is still unwinding; GUT's autofree then deletes your nodes out from under it. The backtrace names the applier and the VFX coordinator, not your test. One line after each await: `while applier.is_applying: await applier.applying_changed`.
- **Leaf visual components have no `class_name` — a test must `preload` the script to reach their enums/constants.** `RimRing`, `CoreHalos`, `InnerDisk` etc. deliberately declare none (only the base classes do — see `.claude/rules/skill-node-visuals.md`), so `RimRing.HeightPreset.MESA` in a test is a **parse error**, and per the gotcha above GUT then *skips the whole file while still reporting green*. Use `const _RIM_RING := preload("res://skill_node/visuals/rim_ring.gd")` and go through that. Same reason a `var x: RimRing = ...` annotation won't compile — type the local as `Node`.
- **A test that pushes a REAL mouse event must run in its own `SubViewport` — GUT's own UI is over the window.** `add_child_autofree()` parents under the GUT runner, so the click lands on GUT's panels and never reaches your scene, failing exactly like the dispatch bug such a test exists to catch. Host it: a `SubViewport` with `handle_input_locally = true`, then `push_input()` at `get_global_transform_with_canvas() * (size * 0.5)` (viewport-local, already carries any `Camera2D`). Worth it only for the one test per feature that proves *dispatch* — drive the seam directly for the rest. Worked example: `test_frontmatter_navigation.gd::test_a_real_click_reaches_a_menu_node_through_the_whole_shell`.
- **A `MultiMesh` push-then-read-back test asserts NOTHING under headless.** `get_instance_transform_2d()` returns identity from the dummy driver, so the assert passes against an all-zero transform — the blind spot that hid #413's invisible edges. Assert the pushed value as a pure function instead. See `docs/domain/godot-workflow.md`.
- **A leaked `get_tree().paused` is caught by a suite-level guard (#737), not by hunting the leaking test.** `ui/pause_menu.gd`'s `_toggle` is the only writer of that flag in the repo, and it is sticky SceneTree state GUT never resets between scripts — a `Tween` (`create_tween()`, default `TWEEN_PAUSE_BOUND`) silently STOPS while paused, while a `SceneTreeTimer` (`process_always = true` by default) keeps firing, so a tween-sampling test fails downstream reading like a bug in the code under test. `test/gut_hooks/pause_leak_pre_run_hook.gd` (wired as `.gutconfig.json`'s `pre_run_script`) fails the just-finished script's last real test and resets the flag whenever it catches one leaked — see `PauseStateGuard` (`test/gut_hooks/pause_state_guard.gd`) and `test/unit/test_pause_state_guard.gd`. The guard is a safety net, not a license to sample tweens: **prefer asserting on the pure function a tween drives** (`transform_at`/`charge_pose` style, per `FrontmatterCamera`) **over sampling the tween itself** — it doesn't depend on suite ordering to pass.
- **A parse error in a `pre_run_script`/`post_run_script` hook doesn't fail the run — it makes `godot` spin forever printing `Project FPS:` lines, which reads exactly like a hang, and `mise run check`'s editor pass does not catch it** (the file isn't referenced by any scene, so nothing pulls it into that pass — same gap `.claude/rules/godot-workflow.md` names for `--check-only --script`, just via a different door). Cause: GUT's `_validate_hook_script` fails to `load()` the broken script, `_init_run` aborts before anything calls `quit()`, and the process just idles. `var x := gut.get_tree()` is the concrete trigger in `pause_leak_pre_run_hook.gd` — `gut` is untyped, so `:=` can't infer a type from the call (same family as the `:=`-on-Variant gotcha above). Diagnose with `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=<any file> -gdir= -glog=3` run directly (not through the python wrapper, which buffers all output until exit) — the `SCRIPT ERROR: Parse Error` prints immediately, before the spin.
