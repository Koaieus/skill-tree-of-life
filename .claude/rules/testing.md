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
```

Config lives in `.gutconfig.json` at repo root (dirs, log level, exit-on-completion).

## Layout

- `test/unit/test_*.gd` — unit tests. Filename must start with `test_`; functions must start with `test_`.
- Class extends `GutTest`. Common asserts: `assert_eq`, `assert_ne`, `assert_null`, `assert_not_null`, `assert_true`, `assert_almost_eq`. Lifecycle: `before_all`, `before_each`, `after_each`, `after_all`.

**`test:one` / `test:dir` silently ran the WHOLE suite until 2026-08-01.** Both
tasks passed the bare flag (`-gtest`, `-gdir`) with the path as a separate
positional. GUT's cmdln options are `-gopt=value`, so a valueless option is
ignored and GUT falls back to `.gutconfig.json`'s `dirs` — 146 scripts, ~28s,
reported as success. `-gtest=<path>` alone is *still* not enough: it doesn't
override the config dirs, so `test:one` also passes `-gdir=` to clear them.

**Why it matters beyond the 28s:** an agent iterating on one file sees failures
and warnings from 145 unrelated scripts and can't tell which are its own. If you
ever add a GUT flag to these tasks, verify the `Scripts` total actually drops.

## Gotchas

- **`class_name` cache miss → "GUT class_names have not been imported".** After fresh install, after pulling GUT updates, or after any new `class_name` introduction, run **`mise run refresh`** once to rebuild `.godot/global_script_class_cache.cfg`. It runs the pass and reports what it changed, so you don't hand-diff it.
- **Autoloads are available in tests** (`StatRegistry`, `Events`, etc.) — GUT boots the project normally.
- **Scene/node tests** must `add_child(node)` and usually `await get_tree().process_frame` before assertions; remember `queue_free()` in `after_each` (or use GUT's `autofree(node)`).
- **`@tool` scripts** (SkillNode, Entity, Graph) run in-editor; their tests should still operate on runtime instances, not editor-loaded resources, unless that's specifically what you're testing.
- **A lambda captures locals BY VALUE — a `var n := 0` counter inside a signal handler never moves.** `sig.connect(func(): n += 1)` increments the closure's own copy; the outer `n` stays 0 and the assert fails with no hint that the signal *did* fire. It reads exactly like "the signal never emitted" or "`call_deferred` is broken", which is the wrong thing to go debug. Count into a reference type: `var seen: Array[int] = []` + `seen.append(1)`, or a script member var. (Arrays/Dictionaries captured the same way *do* work — same object — which is what makes the inconsistency confusing.)
- **A parse error makes GUT *silently skip the whole file* — the suite still reports "all passed".** GUT catches the failed load and logs `Ignoring script … because it does not extend GutTest`, then moves on; the totals just don't include that file. So a green run with an *unchanged* test count after you added tests means your new file didn't run. **Always confirm the `Scripts`/`Tests` totals went UP**, not just that it says passed. Classic trigger: `var x := autofree(SomeType.new())` — `autofree()` returns untyped, so `:=` can't infer the type and the file fails to parse. Use `var x := SomeType.new()` then `autofree(x)` (or annotate explicitly: `var x: SomeType = autofree(...)`). Second trigger: **`Array[StringName]([&"a"])` is `.tres` serialization syntax, not GDScript** — in a script it parses as *"Cannot call on an expression"*. Declare the typed local instead: `var xs: Array[StringName] = [&"a"]`. Third: `:=` on a Variant-returning call (see `test_tag_channel.gd`). Grep the run output for `Ignoring script` — that's the only signal.
- **Leaf visual components have no `class_name` — a test must `preload` the script to reach their enums/constants.** `RimRing`, `CoreHalos`, `InnerDisk` etc. deliberately declare none (only the base classes do — see `.claude/rules/skill-node-visuals.md`), so `RimRing.HeightPreset.MESA` in a test is a **parse error**, and per the gotcha above GUT then *skips the whole file while still reporting green*. Use `const _RIM_RING := preload("res://skill_node/visuals/rim_ring.gd")` and go through that. Same reason a `var x: RimRing = ...` annotation won't compile — type the local as `Node`.
