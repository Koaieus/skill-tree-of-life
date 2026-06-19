---
description: GUT testing framework — how to run, where tests live, common pitfalls
globs: test/**, addons/gut/**, .gutconfig.json
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

## Gotchas

- **`class_name` cache miss → "GUT class_names have not been imported".** After fresh install, after pulling GUT updates, or after any new `class_name` introduction, run `godot --headless --editor --quit-after 200` once to rebuild `.godot/global_script_class_cache.cfg`. See `.claude/rules/godot-workflow.md` — and `git diff` afterwards, the editor pass can mutate scenes/.tres.
- **Autoloads are available in tests** (`StatRegistry`, `Events`, etc.) — GUT boots the project normally.
- **Scene/node tests** must `add_child(node)` and usually `await get_tree().process_frame` before assertions; remember `queue_free()` in `after_each` (or use GUT's `autofree(node)`).
- **`@tool` scripts** (SkillNode, Entity, Graph) run in-editor; their tests should still operate on runtime instances, not editor-loaded resources, unless that's specifically what you're testing.
